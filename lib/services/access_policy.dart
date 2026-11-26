import 'dart:collection';

import 'package:motorqu_solid/models/family_group.dart';
import 'package:motorqu_solid/models/join_request.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:solidpod/solidpod.dart' show AccessMode;

/// Aturan akses (fungsi murni, tanpa I/O) untuk grup & motor di Solid Pod.
///
/// Prinsip: setiap pemilik resource menulis ACL UTUH sesuai keadaan grup saat
/// ini. Pencabutan akses (kick, keluar, motor dijadikan pribadi) terjadi
/// otomatis karena anggota yang tidak lagi berhak tidak ikut ditulis.
class AccessPolicy {
  AccessPolicy._();

  static const groupFilePerms = {AccessMode.read, AccessMode.write};
  static const motorFilePerms = {AccessMode.read, AccessMode.write};

  /// Folder motor: Append wajib eksplisit agar anggota bisa membuat file baru
  /// di `records/` (genAclTurtle tidak menambahkannya sendiri).
  static const motorDirPerms = {
    AccessMode.read,
    AccessMode.write,
    AccessMode.append,
  };

  /// Container permintaan bergabung: user terautentikasi hanya boleh
  /// menambah file, tidak bisa membaca/mengubah permintaan orang lain.
  static const joinRequestAuthUserPerms = {AccessMode.append};

  /// Lama menunggu sebelum pointer grup yang terus ditolak (403) atau
  /// permintaan bergabung yang tak kunjung disetujui dihapus.
  static const accessGracePeriod = Duration(days: 7);

  /// Map agen -> izin, terurut & tanpa pemilik resource, supaya hasil
  /// `genAclTurtle` stabil (bisa dibandingkan untuk melewati tulis ulang).
  static SplayTreeMap<String, Set<AccessMode>> agents(
    Iterable<String> webIds,
    String ownerWebId,
    Set<AccessMode> perms,
  ) {
    final map = SplayTreeMap<String, Set<AccessMode>>();
    for (final id in webIds) {
      final trimmed = id.trim();
      if (trimmed.isEmpty || trimmed == ownerWebId) continue;
      if (!isPlausibleWebId(trimmed)) continue;
      map[trimmed] = perms;
    }
    return map;
  }

  static bool isPlausibleWebId(String s) {
    final uri = Uri.tryParse(s);
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  /// Anggota (selain pemilik) yang boleh mengakses motor milik [ownerWebId].
  ///
  /// - Motor pribadi: tidak ada.
  /// - Motor grup: semua anggota grup tersebut.
  /// - Motor grup yang grupnya tidak dikenal: `null` = JANGAN ubah ACL
  ///   (belum ada bukti pasti, mis. jaringan gagal).
  static Map<String, Set<AccessMode>>? motorAgents({
    required Motorcycle motor,
    required String ownerWebId,
    required Map<String, FamilyGroup> knownGroups,
    required bool isDir,
  }) {
    final perms = isDir ? motorDirPerms : motorFilePerms;
    if (!isSharedMotor(motor)) return agents(const [], ownerWebId, perms);
    final group = knownGroups[motor.groupId];
    if (group == null) return null;
    return agents(group.memberUids, ownerWebId, perms);
  }

  static bool isSharedMotor(Motorcycle m) =>
      m.isGroupMotor && m.groupId.isNotEmpty && m.groupId != 'private';

  /// Validasi permintaan bergabung terhadap data grup TERBARU.
  static JoinDecision decideJoin(
    FamilyGroup group,
    JoinRequest req, {
    DateTime? now,
  }) {
    if (req.groupId != group.id) return JoinDecision.reject;
    if (!isPlausibleWebId(req.memberWebId)) return JoinDecision.reject;
    if (group.memberUids.contains(req.memberWebId)) {
      return JoinDecision.alreadyMember;
    }
    final code = group.activeInviteCode;
    if (code == null || code != req.code) return JoinDecision.reject;
    final exp = group.inviteExpiresAt;
    if (exp != null && (now ?? DateTime.now()).toUtc().isAfter(exp)) {
      return JoinDecision.reject;
    }
    return JoinDecision.accept;
  }

  /// Apa yang dilakukan terhadap pointer grup setelah mencoba membacanya.
  ///
  /// Pointer (dan motor yang merujuk grup itu) hanya dibuang dengan bukti
  /// pasti: file grup tidak ada (404) atau terbaca tapi kita bukan anggota.
  /// 403/401/galat jaringan tidak pernah langsung menghapus apa pun.
  static PointerAction decidePointer({
    required GroupReadStatus status,
    required bool isMember,
    DateTime? deniedSince,
    DateTime? requestedAt,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    switch (status) {
      case GroupReadStatus.notFound:
        return PointerAction.remove;
      case GroupReadStatus.readable:
        if (isMember) return PointerAction.keep;
        // Permintaan bergabung belum diproses host: grup lama masih bisa
        // terbaca (ACL authUser lama) walau kita belum anggota. Tunggu.
        if (requestedAt != null &&
            current.difference(requestedAt) <= accessGracePeriod) {
          return PointerAction.hide;
        }
        return PointerAction.remove;
      case GroupReadStatus.forbidden:
        final since = deniedSince ?? requestedAt;
        if (since == null) return PointerAction.markDenied;
        return current.difference(since) > accessGracePeriod
            ? PointerAction.remove
            : PointerAction.hide;
      case GroupReadStatus.error:
        return PointerAction.hide;
    }
  }

  /// Apakah file motor di [motorUrl] tersimpan di Pod milik [webId].
  ///
  /// Prefix dicocokkan sampai batas segmen (`.../bob/`), supaya
  /// `.../bob` tidak ikut mencocokkan `.../bobby/...`.
  static bool isMotorUrlOwnedBy(String motorUrl, String webId) {
    final marker = motorUrl.indexOf('/motorqu-solid/');
    if (marker != -1 &&
        '${motorUrl.substring(0, marker)}/profile/card#me' == webId) {
      return true;
    }
    final idx = webId.indexOf('/profile/');
    if (idx <= 0) return false;
    return motorUrl.startsWith('${webId.substring(0, idx)}/');
  }

  /// URL container permintaan bergabung, diturunkan dari URL group.ttl:
  /// `.../data/groups/<id>.ttl` -> `.../data/group_requests/<id>/`.
  static String requestsUrlFor(String groupUrl, String groupId) {
    final marker = '/groups/$groupId.ttl';
    final idx = groupUrl.lastIndexOf(marker);
    if (idx < 0) {
      throw FormatException('URL grup tidak dikenali: $groupUrl');
    }
    return '${groupUrl.substring(0, idx)}/group_requests/$groupId/';
  }

  /// Lokasi file ACL (sama dengan `getResAclFile` milik solidpod).
  static String aclUrlFor(String resourceUrl, {required bool isFile}) {
    if (resourceUrl.endsWith('.acl')) return resourceUrl;
    if (isFile) return '$resourceUrl.acl';
    return resourceUrl.endsWith('/') ? '$resourceUrl.acl' : '$resourceUrl/.acl';
  }
}

enum JoinDecision { accept, alreadyMember, reject }

enum GroupReadStatus { readable, notFound, forbidden, error }

enum PointerAction {
  /// Grup tampil normal.
  keep,

  /// Grup disembunyikan sementara, data tidak diubah.
  hide,

  /// Catat waktu pertama ditolak, lalu sembunyikan.
  markDenied,

  /// Hapus pointer; motor milik sendiri di grup itu dikembalikan ke pribadi.
  remove,
}
