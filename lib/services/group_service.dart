import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:motorqu_solid/models/family_group.dart';
import 'package:motorqu_solid/models/join_request.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/services/access_policy.dart';
import 'package:motorqu_solid/services/database_service.dart';
import 'package:motorqu_solid/services/pod_atomic.dart';
import 'package:motorqu_solid/services/pod_utils.dart';
import 'package:solidpod/solidpod.dart';
import 'package:uuid/uuid.dart';

/// Hasil memindai QR undangan.
class JoinOutcome {
  const JoinOutcome({required this.groupId, required this.pending});

  final String groupId;

  /// `true` bila permintaan sudah terkirim tapi belum disetujui host grup
  /// (host belum membuka aplikasi). Grup akan muncul otomatis nanti.
  final bool pending;
}

/// Pointer `joined_groups/<id>.ttl` di Pod user sendiri.
class _GroupPointer {
  const _GroupPointer({
    required this.groupId,
    required this.groupUrl,
    required this.ownerId,
    this.requestedAt,
    this.deniedSince,
  });

  final String groupId;
  final String groupUrl;
  final String ownerId;
  final DateTime? requestedAt;
  final DateTime? deniedSince;
}

/// Hasil membaca group.ttl beserta statusnya.
class _GroupRead {
  const _GroupRead(this.status, [this.group]);
  final GroupReadStatus status;
  final FamilyGroup? group;
}

/// Model akses (Fase 2):
///
/// - Host grup = pemilik Pod tempat `group.ttl` disimpan (pembuat grup).
///   Hanya host yang bisa mengubah ACL file grup, jadi host adalah satu-satunya
///   otoritas: menyetujui permintaan bergabung & menulis ACL anggota.
/// - Setiap pemilik motor menulis ACL motornya sendiri sesuai anggota grup.
/// - ACL ditulis UTUH (bukan ditambah), jadi kick/keluar/motor jadi pribadi
///   otomatis mencabut akses saat aplikasi pemilik resource berjalan.
class GroupService {
  GroupService(this.webId);

  final String webId;
  static const _motorsRoot = 'motorcycles';
  static const _groupsRoot = 'groups';
  static const _joinedGroupsRoot = 'joined_groups';
  static const _requestsRoot = 'group_requests';
  static const _grpNs = 'https://example.org/motorqu-group#';

  // Aksi yang mengubah keanggotaan sudah menulis ACL langsung; sinkronisasi
  // latar ini hanya penyapu (permintaan bergabung, motor basi), jadi jarang.
  static const _syncInterval = Duration(minutes: 10);
  static final Map<String, Future<void>> _syncInFlight = {};
  static final Map<String, DateTime> _lastSync = {};
  static final Set<String> _loggedAclOverwrite = {};

  String _motorPath(String id) => '$_motorsRoot/$id/motorcycle.ttl';
  String _motorDirPath(String id) => '$_motorsRoot/$id/';
  String _ownGroupPath(String groupId) => '$_groupsRoot/$groupId.ttl';
  String _pointerPath(String groupId) => '$_joinedGroupsRoot/$groupId.ttl';

  /// Semua operasi tulis memakai antrean bersama (reentrant) lintas service.
  Future<T> _sync<T>(Future<T> Function() action) => PodWriteQueue.run(action);

  bool _isNotFound(Object e) => PodUtils.isNotFound(e);

  String _lastSegment(String s) => PodUtils.lastSegment(s);

  /// Membentuk URL penuh resource pada Pod user yang sedang login
  Future<String> _buildOwnResourceUrl(String relativeDataPath) async {
    final baseDirUrl = await getDirUrl('motorqu-solid/data');
    final normalizedBase = baseDirUrl.endsWith('/')
        ? baseDirUrl
        : '$baseDirUrl/';
    return '$normalizedBase$relativeDataPath';
  }

  Future<bool> _isOwnUrl(String url) async =>
      url.startsWith(await _buildOwnResourceUrl(''));

  /// Apakah group.ttl grup ini tersimpan di Pod user (user = host).
  Future<bool> isHostOf(String groupId) async {
    final ptr = await _readGroupPointer(groupId);
    return ptr != null && await _isOwnUrl(ptr.groupUrl);
  }

  // ----------------------------- ATOMIC UPDATE -----------------------------

  /// Read-modify-write atomik pada `group.ttl` (ETag + If-Match).
  ///
  /// [change] bisa dipanggil ulang saat konflik, jadi validasi dilakukan di
  /// dalamnya dan efek samping (ACL, pointer) dilakukan setelahnya.
  /// Kembalikan `null` dari [change] bila tidak ada perubahan.
  Future<FamilyGroup> _updateGroup(
    String groupUrl,
    FutureOr<FamilyGroup?> Function(FamilyGroup current) change,
  ) async {
    FamilyGroup? result;
    await PodAtomicWriter.instance.update(groupUrl, (content) async {
      if (content.trim().isEmpty) {
        throw Exception('Data grup kosong atau rusak');
      }
      final current = FamilyGroup.fromTurtle(content, fallbackUrl: groupUrl);
      final next = await change(current);
      if (next == null) {
        result = current.copyWith(groupResourceUrl: groupUrl);
        return null;
      }
      final updated = next.copyWith(groupResourceUrl: groupUrl);
      result = updated;
      return FamilyGroup.turtlePrefixes + updated.toTurtle();
    }, ownerWebId: _resolveFileOwnerWebId(groupUrl, webId));
    return result!;
  }

  /// Read-modify-write atomik pada `motorcycle.ttl` (milik sendiri / eksternal).
  /// Mengembalikan motor sebelum diubah, atau `null` bila file tidak ada.
  Future<Motorcycle?> _updateMotorAtUrl(
    String motorUrl,
    Motorcycle? Function(Motorcycle current) change,
  ) async {
    Motorcycle? before;
    try {
      await PodAtomicWriter.instance.update(motorUrl, (content) {
        if (content.trim().isEmpty) return null;
        final current = Motorcycle.fromTurtle(content);
        before = current;
        final next = change(current);
        if (next == null) return null;
        return Motorcycle.turtlePrefixes + next.toTurtle();
      }, ownerWebId: _resolveFileOwnerWebId(motorUrl, webId));
    } catch (e) {
      if (_isNotFound(e)) return null;
      rethrow;
    }
    return before;
  }

  // ----------------------------- ACL -----------------------------

  /// Tulis ACL UTUH untuk resource di Pod sendiri, hanya bila berbeda.
  ///
  /// [createIfMissing] `false`: bila file ACL belum ada, biarkan (resource
  /// mewarisi ACL folder induk yang privat).
  Future<void> _applyAcl(
    String resourceUrl, {
    required bool isFile,
    required Map<String, Set<AccessMode>> agents,
    Set<AccessMode>? authUser,
    required bool createIfMissing,
  }) async {
    final aclUrl = AccessPolicy.aclUrlFor(resourceUrl, isFile: isFile);
    final desired = await genAclTurtle(
      resourceUrl,
      externalWebId: webId,
      isFile: isFile,
      thirdPartyAccess: agents,
      authUserAccess: authUser,
    );
    try {
      await PodAtomicWriter.instance.update(
        aclUrl,
        (current) {
          if (current == desired) return null;
          if (current.trim().isNotEmpty && _loggedAclOverwrite.add(aclUrl)) {
            // Cadangan manual: isi ACL lama sebelum ditimpa pertama kali.
            debugPrint('[ACL] Menimpa $aclUrl. Isi lama:\n$current');
          }
          return desired;
        },
        createIfMissing: createIfMissing,
        allowFallback: false,
      );
    } catch (e) {
      if (!createIfMissing && _isNotFound(e)) return;
      rethrow;
    }
  }

  /// ACL folder motor (mewarisi ke records/) + file motorcycle.ttl.
  ///
  /// [memberUids] kosong = motor pribadi. File ACL lama dari `grantPermission`
  /// (yang hanya memuat anggota pertama) ditulis ulang bila ada.
  Future<void> _applyMotorAcl(String motoId, List<String> memberUids) async {
    final shared = memberUids.any((m) => m != webId);
    await _applyAcl(
      await _buildOwnResourceUrl(_motorDirPath(motoId)),
      isFile: false,
      agents: AccessPolicy.agents(
        memberUids,
        webId,
        AccessPolicy.motorDirPerms,
      ),
      createIfMissing: shared,
    );
    await _applyAcl(
      await _buildOwnResourceUrl(_motorPath(motoId)),
      isFile: true,
      agents: AccessPolicy.agents(
        memberUids,
        webId,
        AccessPolicy.motorFilePerms,
      ),
      createIfMissing: false,
    );
  }

  /// ACL group.ttl = semua anggota (baca/tulis), TANPA akses authUser.
  /// Hanya bisa dijalankan host.
  Future<void> _reconcileGroupAcl(FamilyGroup group) async {
    await _applyAcl(
      group.groupResourceUrl,
      isFile: true,
      agents: AccessPolicy.agents(
        group.memberUids,
        webId,
        AccessPolicy.groupFilePerms,
      ),
      createIfMissing: true,
    );
  }

  /// Container permintaan bergabung: authUser hanya Append. Hanya host.
  Future<void> _ensureRequestsContainer(String groupId) async {
    final rootUrl = await getDirUrl('motorqu-solid/data/$_requestsRoot');
    final dirUrl = await getDirUrl(
      'motorqu-solid/data/$_requestsRoot/$groupId',
    );
    if (await checkResourceStatus(rootUrl, isFile: false) ==
        ResourceStatus.notExist) {
      await createContainer('', _requestsRoot, createAcl: false);
    }
    if (await checkResourceStatus(dirUrl, isFile: false) ==
        ResourceStatus.notExist) {
      await createContainer(_requestsRoot, groupId, createAcl: false);
    }
    await _applyAcl(
      dirUrl.endsWith('/') ? dirUrl : '$dirUrl/',
      isFile: false,
      agents: const {},
      authUser: AccessPolicy.joinRequestAuthUserPerms,
      createIfMissing: true,
    );
  }

  // ----------------------------- POINTER & GROUP I/O -----------------------------

  Future<void> _saveGroupPointer({
    required String groupId,
    required String groupUrl,
    required String ownerId,
    DateTime? requestedAt,
    DateTime? deniedSince,
  }) async {
    final ttl =
        '${FamilyGroup.turtlePrefixes}'
        '<#ptr-$groupId> a <${_grpNs}GroupPointer> ;\n'
        '    <${_grpNs}groupId> "$groupId" ;\n'
        '    <${_grpNs}groupResourceUrl> "$groupUrl" ;\n'
        '${requestedAt == null ? '' : '    <${_grpNs}requestedAt> "${requestedAt.toUtc().toIso8601String()}" ;\n'}'
        '${deniedSince == null ? '' : '    <${_grpNs}deniedSince> "${deniedSince.toUtc().toIso8601String()}" ;\n'}'
        '    <${_grpNs}ownerId> "$ownerId" .\n';

    await writePod(
      _pointerPath(groupId),
      ttl,
      encrypted: false,
      overwrite: true,
      createAcl: true,
    );
  }

  Future<_GroupPointer?> _readGroupPointer(String groupId) async {
    try {
      final content = await readPod(_pointerPath(groupId));
      String? field(String name) => RegExp(
        '<${RegExp.escape('$_grpNs$name')}>\\s+"([^"]+)"',
      ).firstMatch(content)?.group(1);

      final url = field('groupResourceUrl');
      if (url == null) return null;
      return _GroupPointer(
        groupId: groupId,
        groupUrl: url,
        ownerId: field('ownerId') ?? '',
        requestedAt: DateTime.tryParse(field('requestedAt') ?? ''),
        deniedSince: DateTime.tryParse(field('deniedSince') ?? ''),
      );
    } catch (e) {
      if (_isNotFound(e)) return null;
      rethrow;
    }
  }

  Future<String?> _readGroupPointerUrl(String groupId) async =>
      (await _readGroupPointer(groupId))?.groupUrl;

  Future<void> _deleteGroupPointer(String groupId) async {
    try {
      final pointerUrl = await _buildOwnResourceUrl(_pointerPath(groupId));
      await deleteFile(fileUrl: pointerUrl);
    } catch (e) {
      if (!_isNotFound(e)) debugPrint('Gagal hapus pointer grup: $e');
    }
  }

  Future<FamilyGroup?> _fetchGroupByUrl(String groupUrl) async {
    final read = await _readGroup(groupUrl);
    switch (read.status) {
      case GroupReadStatus.readable:
        return read.group;
      case GroupReadStatus.notFound:
        return null;
      case GroupReadStatus.forbidden:
        throw AccessForbiddenException('Akses ke grup ditolak');
      case GroupReadStatus.error:
        throw Exception('Gagal memuat data grup');
    }
  }

  /// Membaca group.ttl tanpa melempar: status dipakai untuk memutuskan
  /// apakah pointer boleh dihapus (lihat [AccessPolicy.decidePointer]).
  Future<_GroupRead> _readGroup(String groupUrl) async {
    try {
      final content = await _isOwnUrl(groupUrl)
          ? await readPod(
              groupUrl.substring((await _buildOwnResourceUrl('')).length),
            )
          : await readExternalPod(groupUrl);
      if (content.trim().isEmpty) {
        return const _GroupRead(GroupReadStatus.error);
      }
      return _GroupRead(
        GroupReadStatus.readable,
        FamilyGroup.fromTurtle(content, fallbackUrl: groupUrl),
      );
    } catch (e) {
      // Ketat: hanya 404 asli yang boleh berujung pointer dihapus.
      if (PodUtils.isDefinitelyNotFound(e)) {
        return const _GroupRead(GroupReadStatus.notFound);
      }
      if (e is AccessForbiddenException) {
        return const _GroupRead(GroupReadStatus.forbidden);
      }
      debugPrint('Gagal membaca grup $groupUrl: $e');
      return const _GroupRead(GroupReadStatus.error);
    }
  }

  /// URL group.ttl dari pointer; melempar bila grup tidak dikenal.
  Future<String> _requireGroupUrl(String groupId) async {
    final groupUrl = await _readGroupPointerUrl(groupId);
    if (groupUrl == null) throw Exception('Grup tidak ditemukan');
    return groupUrl;
  }

  /// Menentukan WebID pemilik fisik Pod dari URL resource
  String _resolveFileOwnerWebId(String resourceUrl, String fallbackOwnerId) =>
      PodUtils.resolveOwnerWebId(resourceUrl, fallback: fallbackOwnerId);

  /// Hanya untuk membuat file grup BARU. Perubahan grup yang sudah ada wajib
  /// lewat [_updateGroup] agar tidak menimpa perubahan perangkat lain.
  Future<void> _createGroupFile(FamilyGroup group) async {
    final ownPrefix = await _buildOwnResourceUrl('');
    final payload = FamilyGroup.turtlePrefixes + group.toTurtle();
    await writePod(
      group.groupResourceUrl.substring(ownPrefix.length),
      payload,
      encrypted: false,
      overwrite: true,
      createAcl: true,
    );
  }

  /// Listing ketat untuk jalur yang bisa menghapus/mengembalikan data:
  /// kosong HANYA bila container benar-benar tidak ada; galat lain dilempar.
  Future<({List<String> files, List<String> subDirs})> _listDirStrict(
    String dir,
  ) async {
    final url = await getDirUrl('motorqu-solid/data/$dir');
    try {
      return await getResourcesInContainer(url);
    } catch (e) {
      if (await checkResourceStatus(url, isFile: false) ==
          ResourceStatus.notExist) {
        return (files: <String>[], subDirs: <String>[]);
      }
      rethrow;
    }
  }

  /// `false` HANYA bila pointer pasti tidak ada (404 asli).
  Future<bool> _pointerExists(String groupId) async {
    try {
      await readPod(_pointerPath(groupId));
      return true;
    } catch (e) {
      return !PodUtils.isDefinitelyNotFound(e);
    }
  }

  Future<({List<String> files, List<String> subDirs})> _listDir(
    String dir,
  ) async {
    try {
      final url = await getDirUrl('motorqu-solid/data/$dir');
      return await getResourcesInContainer(url);
    } catch (e) {
      if (_isNotFound(e)) return (files: <String>[], subDirs: <String>[]);
      rethrow;
    }
  }

  // ----------------------------- READ -----------------------------

  /// Cari grup pertama di mana user menjadi member (kompatibilitas backward)
  Future<FamilyGroup?> getUserGroup() async {
    final groups = await getUserGroupsList();
    return groups.isEmpty ? null : groups.first;
  }

  /// Mengambil daftar grup yang bisa dibaca & user adalah anggotanya.
  ///
  /// Pointer hanya dihapus dengan bukti pasti (404 / terbaca tapi bukan
  /// anggota). Grup yang menolak akses (403) disembunyikan sementara.
  /// Tidak lewat antrean tulis karena dipanggil di setiap refresh halaman.
  Future<List<FamilyGroup>> getUserGroupsList() async {
    final res = await _listDir(_joinedGroupsRoot);
    final groups = <FamilyGroup>[];

    for (final fileUrl in res.files) {
      final fileName = _lastSegment(fileUrl);
      if (!fileName.endsWith('.ttl')) continue;
      final groupId = fileName.replaceAll('.ttl', '');

      try {
        final ptr = await _readGroupPointer(groupId);
        if (ptr == null) continue;

        final read = await _readGroup(ptr.groupUrl);
        final isMember = read.group?.memberUids.contains(webId) ?? false;
        final action = AccessPolicy.decidePointer(
          status: read.status,
          isMember: isMember,
          deniedSince: ptr.deniedSince,
          requestedAt: ptr.requestedAt,
        );

        switch (action) {
          case PointerAction.keep:
            if (ptr.requestedAt != null || ptr.deniedSince != null) {
              // Permintaan bergabung sudah disetujui / akses pulih.
              await _saveGroupPointer(
                groupId: groupId,
                groupUrl: ptr.groupUrl,
                ownerId: read.group!.ownerId,
              );
            }
            groups.add(read.group!);
          case PointerAction.markDenied:
            await _saveGroupPointer(
              groupId: groupId,
              groupUrl: ptr.groupUrl,
              ownerId: ptr.ownerId,
              deniedSince: DateTime.now().toUtc(),
            );
          case PointerAction.hide:
            break;
          case PointerAction.remove:
            await _deleteGroupPointer(groupId);
        }
      } catch (e) {
        debugPrint('Lewati pointer grup $groupId: $e');
      }
    }

    groups.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return groups;
  }

  Future<List<Motorcycle>> getGroupMotorcycles(String groupId) async {
    final groupUrl = await _readGroupPointerUrl(groupId);
    if (groupUrl == null) return [];

    final read = await _readGroup(groupUrl);
    final group = read.group;
    if (group == null) return [];

    final ownPrefix = await _buildOwnResourceUrl('');
    final futures = group.sharedMotorUrls.map((motorUrl) async {
      try {
        final content = motorUrl.startsWith(ownPrefix)
            ? await readPod(motorUrl.substring(ownPrefix.length))
            : await readExternalPod(motorUrl);

        if (content.trim().isEmpty) return null;
        final moto = Motorcycle.fromTurtle(content);
        return (moto.groupId == groupId && moto.isGroupMotor)
            ? moto.copyWith(resourceUrl: motorUrl)
            : null;
      } catch (e) {
        debugPrint('Lewati motor grup ($motorUrl): $e');
        return null;
      }
    });

    final results = await Future.wait(futures);
    return results.whereType<Motorcycle>().toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Mengambil daftar motor pribadi milik user (groupId == 'private').
  /// Hanya membaca, jadi tidak lewat antrean tulis.
  Future<List<Motorcycle>> getUserPrivateMotorcycles() async {
    final res = await _listDir(_motorsRoot);
    final list = <Motorcycle>[];

    for (final dirUrl in res.subDirs) {
      final id = _lastSegment(dirUrl);
      try {
        final content = await readPod(_motorPath(id));
        if (content.trim().isEmpty) continue;
        final m = Motorcycle.fromTurtle(content);
        if (m.groupId.isEmpty || m.groupId == 'private' || !m.isGroupMotor) {
          list.add(m);
        }
      } catch (e) {
        if (!_isNotFound(e)) rethrow;
      }
    }

    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  // ----------------------------- SINKRONISASI AKSES -----------------------------

  /// Rekonsiliasi akses di latar belakang (single-flight, dibatasi 2 menit):
  ///
  /// 1. Host: proses permintaan bergabung & tulis ACL group.ttl.
  /// 2. Semua user: tulis ACL motor sendiri sesuai anggota grupnya; motor yang
  ///    grupnya sudah pasti hilang (pointer dihapus) dikembalikan ke pribadi.
  ///
  /// Tidak pernah melempar error.
  Future<void> syncAccess({bool force = false}) {
    final running = _syncInFlight[webId];
    if (running != null) return running;
    final last = _lastSync[webId];
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _syncInterval) {
      return Future<void>.value();
    }

    final future = _syncAccessImpl()
        .catchError((Object e) => debugPrint('[AccessSync] gagal: $e'))
        .whenComplete(() {
          _syncInFlight.remove(webId);
          _lastSync[webId] = DateTime.now();
        });
    _syncInFlight[webId] = future;
    return future;
  }

  /// Berhenti bila user sudah logout / berganti akun di tengah sinkronisasi.
  bool get _stillActive =>
      DatabaseService.isInitialized && DatabaseService().webId == webId;

  Future<void> _syncAccessImpl() async {
    // Daftar pointer harus berhasil dibaca; kalau gagal, batalkan semua
    // (jangan sampai motor dikembalikan ke pribadi karena galat jaringan).
    final pointerFiles = await _listDirStrict(_joinedGroupsRoot);
    final pointerIds = <String>{
      for (final f in pointerFiles.files)
        if (_lastSegment(f).endsWith('.ttl'))
          _lastSegment(f).replaceAll('.ttl', ''),
    };

    final knownGroups = <String, FamilyGroup>{};
    for (final group in await getUserGroupsList()) {
      knownGroups[group.id] = group;
    }
    // getUserGroupsList bisa menghapus pointer (bukti pasti); muat ulang.
    final remainingPointers = (await _listDirStrict(_joinedGroupsRoot)).files
        .map(_lastSegment)
        .where((n) => n.endsWith('.ttl'))
        .map((n) => n.replaceAll('.ttl', ''))
        .toSet();
    pointerIds.retainAll(remainingPointers);

    // 1. Grup yang di-host user ini.
    for (final group in knownGroups.values.toList()) {
      if (!_stillActive) return;
      if (!await _isOwnUrl(group.groupResourceUrl)) continue;
      // ACL grup lebih dulu & terpisah: menutup akses authUser lama walaupun
      // pembuatan container permintaan gagal.
      try {
        await _sync(() async {
          final fresh = await _fetchGroupByUrl(group.groupResourceUrl);
          if (fresh != null) {
            knownGroups[group.id] = fresh;
            await _reconcileGroupAcl(fresh);
          }
        });
      } catch (e) {
        debugPrint('[AccessSync] ACL grup ${group.id}: $e');
      }
      try {
        await _sync(() async {
          await _ensureRequestsContainer(group.id);
          await _processJoinRequestsFor(group);
          final fresh = await _fetchGroupByUrl(group.groupResourceUrl);
          if (fresh != null) knownGroups[group.id] = fresh;
        });
      } catch (e) {
        debugPrint('[AccessSync] permintaan bergabung ${group.id}: $e');
      }
    }

    // 2. Motor milik user sendiri.
    final motorDirs = await _listDirStrict(_motorsRoot);
    for (final dirUrl in motorDirs.subDirs) {
      if (!_stillActive) return;
      final motoId = _lastSegment(dirUrl);
      try {
        await _sync(() => _syncMotorAccess(motoId, knownGroups, pointerIds));
      } catch (e) {
        debugPrint('[AccessSync] motor $motoId: $e');
      }
    }
  }

  Future<void> _syncMotorAccess(
    String motoId,
    Map<String, FamilyGroup> knownGroups,
    Set<String> pointerIds,
  ) async {
    final String content;
    try {
      content = await readPod(_motorPath(motoId));
    } catch (e) {
      if (_isNotFound(e)) return;
      rethrow;
    }
    if (content.trim().isEmpty) return;
    final motor = Motorcycle.fromTurtle(content);

    if (AccessPolicy.isSharedMotor(motor) &&
        !knownGroups.containsKey(motor.groupId)) {
      if (pointerIds.contains(motor.groupId)) {
        // Grup sementara tidak bisa dibaca (403/jaringan): jangan diubah.
        return;
      }
      // Cek ulang saat ini juga: user mungkin baru bergabung & membagikan
      // motor setelah snapshot sinkronisasi diambil.
      if (await _pointerExists(motor.groupId)) return;
      // Pointer sudah dihapus dengan bukti pasti (grup hilang / dikeluarkan):
      // kembalikan motor menjadi pribadi.
      await _updateMotorAtUrl(
        await _buildOwnResourceUrl(_motorPath(motoId)),
        (m) => m.groupId == motor.groupId
            ? m.copyWith(
                groupId: 'private',
                isGroupMotor: false,
                memberUids: [webId],
              )
            : null,
      );
      await _applyMotorAcl(motoId, const []);
      return;
    }

    final agents = AccessPolicy.motorAgents(
      motor: motor,
      ownerWebId: webId,
      knownGroups: knownGroups,
      isDir: true,
    );
    if (agents == null) return;
    await _applyMotorAcl(motoId, agents.keys.toList());
  }

  // ----------------------------- PERMINTAAN BERGABUNG -----------------------------

  /// Proses permintaan bergabung untuk grup yang di-host user ini.
  /// Dipanggil berkala oleh dialog QR. Mengembalikan jumlah anggota baru.
  Future<int> processJoinRequests(String groupId) => _sync(() async {
    final ptr = await _readGroupPointer(groupId);
    if (ptr == null || !await _isOwnUrl(ptr.groupUrl)) return 0;
    final group = await _fetchGroupByUrl(ptr.groupUrl);
    if (group == null) return 0;
    return _processJoinRequestsFor(group);
  });

  static final Map<String, Future<void>> _pendingJoinsInFlight = {};

  /// Untuk anggota yang bergabung dari jauh (kode lewat chat): host tidak
  /// sedang membuka dialog QR, jadi permintaan diproses setiap beranda
  /// dimuat. Hanya grup yang di-host user ini & undangannya masih aktif
  /// (setelah dipakai, kode dihapus sehingga tidak ada request tambahan).
  /// Tidak pernah melempar error.
  Future<void> processPendingJoins(List<FamilyGroup> groups) {
    final running = _pendingJoinsInFlight[webId];
    if (running != null) return running;

    final future = () async {
      final ownPrefix = await _buildOwnResourceUrl('');
      final now = DateTime.now().toUtc();
      for (final g in groups) {
        if (!_stillActive) return;
        if (g.activeInviteCode == null) continue;
        if (g.inviteExpiresAt != null && now.isAfter(g.inviteExpiresAt!)) {
          continue;
        }
        if (!g.groupResourceUrl.startsWith(ownPrefix)) continue;
        try {
          await processJoinRequests(g.id);
        } catch (e) {
          debugPrint('[Join] gagal memproses permintaan ${g.id}: $e');
        }
      }
    }().catchError((Object e) => debugPrint('[Join] $e')).whenComplete(
      () => _pendingJoinsInFlight.remove(webId),
    );
    _pendingJoinsInFlight[webId] = future;
    return future;
  }

  Future<int> _processJoinRequestsFor(FamilyGroup group) async {
    final requestsUrl = AccessPolicy.requestsUrlFor(
      group.groupResourceUrl,
      group.id,
    );
    final ({List<String> files, List<String> subDirs}) listing;
    try {
      listing = await getResourcesInContainer(requestsUrl);
    } catch (e) {
      if (_isNotFound(e)) return 0;
      rethrow;
    }

    final ownPrefix = await _buildOwnResourceUrl('');
    var accepted = 0;
    FamilyGroup? latest;
    for (final fileUrl in listing.files) {
      final url = fileUrl.startsWith('http')
          ? fileUrl
          : '$requestsUrl${_lastSegment(fileUrl)}';
      try {
        final req = JoinRequest.tryParse(
          await readPod(url.substring(ownPrefix.length)),
        );

        if (req != null) {
          var added = false;
          // Urutan: tambah anggota (atomik) -> ACL -> hapus permintaan.
          final updated = await _updateGroup(group.groupResourceUrl, (
            current,
          ) {
            if (AccessPolicy.decideJoin(current, req) != JoinDecision.accept) {
              return null;
            }
            added = true;
            return current.copyWith(
              memberUids: [...current.memberUids, req.memberWebId],
              clearInvite: true,
            );
          });
          if (added) {
            accepted++;
            latest = updated;
            await _reconcileGroupAcl(updated);
          }
        }
        await deleteFile(fileUrl: url);
      } catch (e) {
        debugPrint('Gagal memproses permintaan bergabung $url: $e');
      }
    }

    // Anggota baru langsung bisa melihat motor milik host di grup ini.
    // Motor anggota lain terbuka saat aplikasi pemiliknya berjalan.
    if (latest != null) await _applyOwnGroupMotorAcls(latest);
    return accepted;
  }

  /// Tulis ulang ACL semua motor milik user ini yang terdaftar di [group].
  Future<void> _applyOwnGroupMotorAcls(FamilyGroup group) async {
    final ownPrefix = await _buildOwnResourceUrl('');
    for (final motorUrl in group.sharedMotorUrls) {
      if (!motorUrl.startsWith(ownPrefix)) continue;
      final segments = motorUrl.substring(ownPrefix.length).split('/');
      if (segments.length < 2) continue;
      try {
        await _applyMotorAcl(segments[1], group.memberUids);
      } catch (e) {
        debugPrint('Gagal memperbarui akses motor ${segments[1]}: $e');
      }
    }
  }

  // ----------------------------- MOTOR <-> GROUP -----------------------------

  /// Memasukkan motor pribadi milik user ke dalam grup.
  ///
  /// Urutan langkah sengaja dibuat idempoten: ACL -> motorcycle.ttl ->
  /// group.ttl. Bila gagal di tengah, memanggil ulang akan melanjutkan.
  Future<void> assignMotorcycleToGroup(String motoId, String groupId) =>
      _sync(() async {
        final groupUrl = await _requireGroupUrl(groupId);

        final group = await _fetchGroupByUrl(groupUrl);
        if (group == null) throw Exception('Data grup gagal dimuat');
        if (!group.memberUids.contains(webId)) {
          throw Exception('Anda bukan anggota grup ini');
        }

        // 1. Beri izin baca/tulis pada folder motor & file motorcycle.ttl
        await _applyMotorAcl(motoId, group.memberUids);

        // 2. Update motorcycle.ttl di Pod milik user (atomik)
        final ownMotorUrl = await _buildOwnResourceUrl(_motorPath(motoId));
        final before = await _updateMotorAtUrl(
          ownMotorUrl,
          (current) => current.copyWith(
            groupId: groupId,
            isGroupMotor: true,
            memberUids: group.memberUids,
          ),
        );
        if (before == null) throw Exception('Motor tidak ditemukan');

        // 3. Daftarkan URL motor ini ke group.ttl (atomik)
        await _updateGroup(groupUrl, (current) {
          if (current.sharedMotorUrls.contains(ownMotorUrl)) return null;
          return current.copyWith(
            sharedMotorUrls: [...current.sharedMotorUrls, ownMotorUrl],
          );
        });
      });

  /// Melempar bila user bukan owner/admin grup tempat motor [motorUrl]
  /// (milik anggota lain) terdaftar.
  Future<void> _requireGroupAdminForMotor(String motorUrl) async {
    final String content;
    try {
      content = await readExternalPod(motorUrl);
    } catch (e) {
      if (_isNotFound(e)) throw Exception('Motor tidak ditemukan');
      rethrow;
    }
    final motor = Motorcycle.fromTurtle(content);
    final groupUrl = AccessPolicy.isSharedMotor(motor)
        ? await _readGroupPointerUrl(motor.groupId)
        : null;
    final group = groupUrl == null ? null : await _fetchGroupByUrl(groupUrl);
    if (group == null || !group.isOwner(webId)) {
      throw Exception(
        'Hanya pemilik motor atau owner/admin grup yang dapat '
        'mengeluarkan motor ini dari grup',
      );
    }
  }

  /// Mengeluarkan motor dari grup kembali menjadi motor pribadi ('private')
  Future<void> removeMotorcycleFromGroup(
    String motoId, {
    String? motorResourceUrl,
  }) => _sync(() async {
    final ownPrefix = await _buildOwnResourceUrl('');
    final isExternal =
        motorResourceUrl != null &&
        motorResourceUrl.isNotEmpty &&
        !motorResourceUrl.startsWith(ownPrefix);

    final motorUrl = isExternal
        ? motorResourceUrl
        : await _buildOwnResourceUrl(_motorPath(motoId));

    // Motor milik anggota lain hanya boleh dikeluarkan oleh owner/admin grup.
    if (isExternal) {
      await _requireGroupAdminForMotor(motorUrl);
    }

    Motorcycle? before;
    try {
      before = await _updateMotorAtUrl(motorUrl, (current) {
        final ownerWebId = isExternal
            ? (current.createdBy.isNotEmpty
                  ? current.createdBy
                  : _resolveFileOwnerWebId(motorUrl, webId))
            : webId;
        return current.copyWith(
          groupId: 'private',
          isGroupMotor: false,
          memberUids: [ownerWebId],
        );
      });
    } catch (e) {
      if (!isExternal) rethrow;
      debugPrint('Warning update motor eksternal saat remove: $e');
    }

    // Motor sendiri: cabut akses anggota sekarang juga. Motor milik orang
    // lain: ACL-nya dicabut oleh aplikasi pemilik motor saat sinkronisasi.
    if (!isExternal) {
      try {
        await _applyMotorAcl(motoId, const []);
      } catch (e) {
        debugPrint('Gagal mencabut akses motor $motoId: $e');
      }
    }

    // Hapus URL motor dari group.ttl
    final oldGroupId = before?.groupId ?? '';
    if (oldGroupId.isNotEmpty && oldGroupId != 'private') {
      final groupUrl = await _readGroupPointerUrl(oldGroupId);
      if (groupUrl != null) {
        await _updateGroup(groupUrl, (current) {
          final updatedUrls = current.sharedMotorUrls
              .where(
                (u) =>
                    u != motorUrl && !u.endsWith('/$motoId/motorcycle.ttl'),
              )
              .toList();
          if (updatedUrls.length == current.sharedMotorUrls.length) {
            return null;
          }
          return current.copyWith(sharedMotorUrls: updatedUrls);
        });
      }
    }
  });

  // ----------------------------- GROUP LIFECYCLE & QR INVITE -----------------------------

  Future<String> createGroup(String groupName) => _sync(() async {
    final groupId = const Uuid().v4();
    final groupUrl = await _buildOwnResourceUrl(_ownGroupPath(groupId));

    final newGroup = FamilyGroup(
      id: groupId,
      name: groupName.trim(),
      ownerId: webId,
      ownerIds: [webId],
      memberUids: [webId],
      sharedMotorUrls: const [],
      groupResourceUrl: groupUrl,
      createdAt: DateTime.now().toUtc(),
    );

    await _createGroupFile(newGroup);
    await _saveGroupPointer(
      groupId: groupId,
      groupUrl: groupUrl,
      ownerId: webId,
    );
    try {
      await _ensureRequestsContainer(groupId);
    } catch (e) {
      // Akan dicoba lagi oleh syncAccess / saat membuat QR.
      debugPrint('Gagal menyiapkan container permintaan bergabung: $e');
    }

    return groupId;
  });

  /// Membuat payload JSON untuk di-render sebagai QR Code undangan
  /// (berlaku 7 hari, sekali pakai).
  ///
  /// Tidak lagi membuka akses `authUser` ke group.ttl: calon anggota hanya
  /// mengirim permintaan ke container khusus (Append saja), lalu host
  /// memvalidasi kode & menambahkannya.
  Future<String> createInviteQrPayload(String groupId) => _sync(() async {
    final groupUrl = await _requireGroupUrl(groupId);

    // Kode dibuat SEKALI di luar transformasi, supaya kode di QR selalu sama
    // dengan kode yang benar-benar tersimpan walaupun terjadi retry.
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final code = List.generate(
      6,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    final expiresAt = DateTime.now().toUtc().add(const Duration(days: 7));

    final group = await _updateGroup(groupUrl, (current) {
      if (!current.isOwner(webId)) {
        throw Exception(
          'Hanya owner/admin grup yang dapat membuat QR undangan',
        );
      }
      return current.copyWith(
        activeInviteCode: code,
        inviteExpiresAt: expiresAt,
      );
    });

    if (await _isOwnUrl(groupUrl)) {
      // Tutup akses authUser lama (grup dari versi sebelumnya) dulu.
      await _reconcileGroupAcl(group);
      await _ensureRequestsContainer(groupId);
    }

    return jsonEncode({
      'v': 2,
      'groupId': groupId,
      'groupUrl': groupUrl,
      'requestsUrl': AccessPolicy.requestsUrlFor(groupUrl, groupId),
      'code': code,
    });
  });

  /// Bergabung ke grup dengan memindai QR Code undangan.
  ///
  /// Mengirim permintaan ke host lalu menunggu sebentar ([approvalWait])
  /// sampai host menyetujui. Bila host belum membuka aplikasi, hasilnya
  /// `pending` dan grup akan muncul otomatis setelah disetujui.
  ///
  /// Scan QR: host biasanya sedang membuka dialog QR (memproses tiap 3 dtk),
  /// jadi tunggu ±20 dtk. Kode lewat chat: host jarang sedang membuka
  /// aplikasi, jadi cukup cek singkat.
  Future<JoinOutcome> joinGroupWithQr(
    String qrRawData, {
    Duration approvalWait = const Duration(seconds: 20),
  }) async {
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(qrRawData.trim()) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Format QR Code undangan tidak valid');
    }

    final groupId = payload['groupId'] as String? ?? '';
    final groupUrl = payload['groupUrl'] as String? ?? '';
    final requestsUrl = payload['requestsUrl'] as String? ?? '';
    final code = (payload['code'] as String? ?? '').trim().toUpperCase();

    if (groupId.isEmpty || groupUrl.isEmpty || code.length != 6) {
      throw Exception('Data QR Code undangan tidak lengkap');
    }
    if (requestsUrl.isEmpty) {
      throw Exception(
        'QR dibuat oleh versi aplikasi lama. Minta pembuat grup memperbarui '
        'aplikasi lalu membuat QR baru.',
      );
    }

    // Sudah anggota (mis. memindai ulang): cukup pulihkan pointer.
    final existing = await _readGroup(groupUrl);
    if (existing.group?.memberUids.contains(webId) ?? false) {
      await _sync(
        () => _saveGroupPointer(
          groupId: groupId,
          groupUrl: groupUrl,
          ownerId: existing.group!.ownerId,
        ),
      );
      return JoinOutcome(groupId: groupId, pending: false);
    }

    await _sync(() async {
      final request = JoinRequest(
        groupId: groupId,
        memberWebId: webId,
        code: code,
        requestedAt: DateTime.now().toUtc(),
      );
      try {
        await PodAtomicWriter.instance.post(
          requestsUrl,
          request.toTurtle(),
          slug: 'req-${const Uuid().v4()}.ttl',
        );
      } catch (e) {
        if (_isNotFound(e) || e is AccessForbiddenException) {
          throw Exception('Grup tidak ditemukan atau undangan tidak berlaku');
        }
        rethrow;
      }

      await _saveGroupPointer(
        groupId: groupId,
        groupUrl: groupUrl,
        ownerId: '',
        requestedAt: DateTime.now().toUtc(),
      );
    });

    // Tunggu persetujuan host (dialog QR host memproses tiap beberapa detik).
    for (var i = 0; i < approvalWait.inSeconds ~/ 2; i++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      final read = await _readGroup(groupUrl);
      if (read.group?.memberUids.contains(webId) ?? false) {
        await _sync(
          () => _saveGroupPointer(
            groupId: groupId,
            groupUrl: groupUrl,
            ownerId: read.group!.ownerId,
          ),
        );
        return JoinOutcome(groupId: groupId, pending: false);
      }
    }
    return JoinOutcome(groupId: groupId, pending: true);
  }

  /// Mengambil nama profil langsung dari WebID card#me masing-masing anggota
  Future<List<Map<String, dynamic>>> getGroupMembers(FamilyGroup group) async {
    if (group.memberUids.isEmpty) return [];
    final result = <Map<String, dynamic>>[];

    for (final memberWebId in group.memberUids) {
      try {
        final cardContent = await readExternalPod(memberWebId);
        final nameMatch = RegExp(
          r'(?:foaf:name|vcard:fn|schema:name)\s+"([^"]+)"',
        ).firstMatch(cardContent);

        final fallbackHandle = Uri.parse(memberWebId).pathSegments
            .where((s) => s.isNotEmpty && s != 'profile' && s != 'card')
            .firstOrNull;

        result.add({
          'uid': memberWebId,
          'displayName':
              nameMatch?.group(1) ?? fallbackHandle ?? 'Anggota Keluarga',
          'email': memberWebId,
        });
      } catch (_) {
        result.add({
          'uid': memberWebId,
          'displayName': 'Anggota Keluarga',
          'email': memberWebId,
        });
      }
    }
    return result;
  }

  // ----------------------------- MEMBER & ROLE MANAGEMENT -----------------------------

  /// Keluar dari grup.
  ///
  /// Host (data grup ada di Pod-nya) tidak bisa keluar selama masih ada
  /// anggota lain, karena hanya host yang bisa mengatur akses grup. Setelah
  /// semua anggota lain dikeluarkan, keluar = grup dihapus.
  Future<void> leaveGroup(String groupId) => _sync(() async {
    final groupUrl = await _readGroupPointerUrl(groupId);
    if (groupUrl == null) return;

    final isHost = await _isOwnUrl(groupUrl);
    final ownMotorPrefix = await _buildOwnResourceUrl(_motorsRoot);
    var deleteGroupFile = false;

    try {
      await _updateGroup(groupUrl, (current) {
        deleteGroupFile = false;
        final remainingMembers = current.memberUids
            .where((m) => m != webId)
            .toList();

        if (isHost) {
          if (remainingMembers.isNotEmpty) {
            throw Exception(
              'Data grup ini tersimpan di Pod Anda, jadi Anda belum bisa '
              'keluar selama masih ada anggota lain. Keluarkan anggota lain '
              'terlebih dahulu; setelah itu keluar akan menghapus grup.',
            );
          }
          deleteGroupFile = true;
          return null;
        }

        var nextOwnerId = current.ownerId;
        var nextOwnerIds = current.ownerIds
            .where((o) => o != webId)
            .toList();

        if (current.ownerId == webId && remainingMembers.isNotEmpty) {
          nextOwnerId = nextOwnerIds.isNotEmpty
              ? nextOwnerIds.first
              : remainingMembers.first;
          if (!nextOwnerIds.contains(nextOwnerId)) {
            nextOwnerIds = [nextOwnerId, ...nextOwnerIds];
          }
        }

        return current.copyWith(
          ownerId: nextOwnerId,
          ownerIds: nextOwnerIds,
          memberUids: remainingMembers,
          sharedMotorUrls: current.sharedMotorUrls
              .where((u) => !u.startsWith(ownMotorPrefix))
              .toList(),
        );
      });
    } catch (e) {
      // Grup PASTI sudah tidak ada (404 asli): tetap bersihkan data lokal.
      if (!PodUtils.isDefinitelyNotFound(e)) rethrow;
    }

    if (deleteGroupFile) {
      for (final url in [
        await _buildOwnResourceUrl(_ownGroupPath(groupId)),
        await _buildOwnResourceUrl('$_requestsRoot/$groupId/'),
      ]) {
        try {
          await deleteFile(fileUrl: url);
        } catch (e) {
          if (!_isNotFound(e)) debugPrint('Gagal hapus $url: $e');
        }
      }
    }

    // Kembalikan semua motor milik user di grup ini menjadi 'private' dan
    // cabut akses anggota lain.
    final res = await _listDir(_motorsRoot);
    for (final dirUrl in res.subDirs) {
      final motoId = _lastSegment(dirUrl);
      try {
        final before = await _updateMotorAtUrl(
          await _buildOwnResourceUrl(_motorPath(motoId)),
          (moto) => moto.groupId == groupId
              ? moto.copyWith(
                  groupId: 'private',
                  isGroupMotor: false,
                  memberUids: [webId],
                )
              : null,
        );
        if (before?.groupId == groupId) {
          await _applyMotorAcl(motoId, const []);
        }
      } catch (e) {
        debugPrint('Gagal mengembalikan motor $motoId ke pribadi: $e');
      }
    }

    await _deleteGroupPointer(groupId);
  });

  /// Mengeluarkan anggota. Akses file grup dicabut langsung bila yang
  /// mengeluarkan adalah host; bila co-owner, dicabut saat aplikasi host
  /// berjalan. Akses ke motor anggota lain dicabut oleh aplikasi masing-masing
  /// pemilik motor.
  Future<void> kickMember(String groupId, String targetUid) => _sync(() async {
    final groupUrl = await _requireGroupUrl(groupId);

    // Hapus target dari memberUids, ownerIds, dan keluarkan URL motor miliknya
    var removedMotorUrls = <String>[];
    final updatedGroup = await _updateGroup(groupUrl, (current) {
      removedMotorUrls = const [];
      if (!current.isOwner(webId)) {
        throw Exception(
          'Hanya owner/admin grup yang dapat mengeluarkan anggota',
        );
      }
      if (current.ownerId == targetUid) {
        throw Exception('Pembuat grup utama tidak dapat dikeluarkan');
      }
      if (!current.memberUids.contains(targetUid)) return null;

      removedMotorUrls = current.sharedMotorUrls
          .where((u) => AccessPolicy.isMotorUrlOwnedBy(u, targetUid))
          .toList();
      return current.copyWith(
        memberUids: current.memberUids.where((m) => m != targetUid).toList(),
        ownerIds: current.ownerIds.where((o) => o != targetUid).toList(),
        sharedMotorUrls: current.sharedMotorUrls
            .where((u) => !removedMotorUrls.contains(u))
            .toList(),
      );
    });

    if (await _isOwnUrl(groupUrl)) {
      await _reconcileGroupAcl(updatedGroup);
    }

    // Cabut akses target ke motor milik user ini.
    await _applyOwnGroupMotorAcls(updatedGroup);

    // Seperti referensi: motor milik anggota yang dikeluarkan langsung
    // dikembalikan menjadi motor pribadinya (selama izin tulis masih ada).
    // Bila gagal, aplikasi anggota itu sendiri yang mengembalikannya saat
    // akses ke grup sudah pasti hilang.
    for (final url in removedMotorUrls) {
      try {
        await _updateMotorAtUrl(
          url,
          (m) => m.groupId == groupId
              ? m.copyWith(
                  groupId: 'private',
                  isGroupMotor: false,
                  memberUids: [targetUid],
                )
              : null,
        );
      } catch (e) {
        debugPrint('Gagal mengembalikan motor anggota ($url): $e');
      }
    }
  });

  Future<void> promoteMemberToOwner(String groupId, String targetUid) =>
      _sync(() async {
        final groupUrl = await _requireGroupUrl(groupId);
        await _updateGroup(groupUrl, (current) {
          if (!current.isOwner(webId)) {
            throw Exception(
              'Hanya owner/admin grup yang dapat mengangkat owner baru',
            );
          }
          if (current.ownerIds.contains(targetUid)) return null;
          return current.copyWith(ownerIds: [...current.ownerIds, targetUid]);
        });
      });

  Future<void> demoteOwner(String groupId, String targetUid) => _sync(() async {
    final groupUrl = await _requireGroupUrl(groupId);
    await _updateGroup(groupUrl, (current) {
      if (!current.isOwner(webId)) {
        throw Exception(
          'Hanya owner/admin grup yang dapat mengubah status owner',
        );
      }
      if (current.ownerId == targetUid) {
        throw Exception('Pembuat grup utama tidak dapat diturunkan statusnya');
      }
      if (!current.ownerIds.contains(targetUid)) return null;
      return current.copyWith(
        ownerIds: current.ownerIds.where((o) => o != targetUid).toList(),
      );
    });
  });

  /// Memindahkan peran "pembuat utama" (ownerId).
  ///
  /// Catatan: file grup TIDAK berpindah Pod. Host (pemilik Pod) tetap menjadi
  /// otoritas akses; ownerId hanya peran di dalam aplikasi.
  Future<void> transferGroupOwnership(String groupId, String newOwnerUid) =>
      _sync(() async {
        final groupUrl = await _requireGroupUrl(groupId);
        await _updateGroup(groupUrl, (current) {
          if (current.ownerId != webId) {
            throw Exception(
              'Hanya pembuat utama yang dapat memindahkan kepemilikan',
            );
          }
          if (!current.memberUids.contains(newOwnerUid)) {
            throw Exception('Pengguna tujuan bukan anggota grup ini');
          }
          return current.copyWith(
            ownerId: newOwnerUid,
            ownerIds: current.ownerIds.contains(newOwnerUid)
                ? current.ownerIds
                : [...current.ownerIds, newOwnerUid],
          );
        });
      });

  Future<void> updateGroupName(String groupId, String newName) =>
      _sync(() async {
        final groupUrl = await _requireGroupUrl(groupId);
        final trimmed = newName.trim();
        await _updateGroup(
          groupUrl,
          (current) =>
              current.name == trimmed ? null : current.copyWith(name: trimmed),
        );
      });
}
