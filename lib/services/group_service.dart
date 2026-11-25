import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:motorqu_solid/models/family_group.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:solidpod/solidpod.dart';
import 'package:uuid/uuid.dart';

class GroupService {
  GroupService(this.webId);

  final String webId;
  static const _motorsRoot = 'motorcycles';
  static const _groupsRoot = 'groups';
  static const _joinedGroupsRoot = 'joined_groups';

  String _motorPath(String id) => '$_motorsRoot/$id/motorcycle.ttl';
  String _ownGroupPath(String groupId) => '$_groupsRoot/$groupId.ttl';
  String _pointerPath(String groupId) => '$_joinedGroupsRoot/$groupId.ttl';

  Future<void> _queue = Future.value();

  Future<T> _sync<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  bool _isNotFound(Object e) {
    final s = e.toString();
    return e.runtimeType.toString() == 'ResourceNotExistException' ||
        s.contains('does not exist') ||
        s.contains('404');
  }

  String _lastSegment(String s) =>
      Uri.parse(s).pathSegments.where((e) => e.isNotEmpty).last;

  /// Membentuk URL penuh resource pada Pod user yang sedang login
  Future<String> _buildOwnResourceUrl(String relativeDataPath) async {
    final baseDirUrl = await getDirUrl('motorqu-solid/data');
    final normalizedBase = baseDirUrl.endsWith('/')
        ? baseDirUrl
        : '$baseDirUrl/';
    return '$normalizedBase$relativeDataPath';
  }

  // ----------------------------- POINTER & GROUP I/O -----------------------------

  /// Menyinkronkan ACL motor milik user saat ini yang terdaftar di grup
  /// agar anggota baru otomatis mendapat akses baca/tulis.
  Future<void> _syncOwnedGroupMotorAcls(FamilyGroup group) async {
    final ownPrefix = await _buildOwnResourceUrl('');
    for (final motorUrl in group.sharedMotorUrls) {
      if (!motorUrl.startsWith(ownPrefix)) continue;

      final relFilePath = motorUrl.substring(ownPrefix.length);
      final segments = relFilePath.split('/');
      if (segments.length < 2) continue;
      final motoId = segments[1];

      // 1. Izin pada folder motor (mencakup subfolder records/)
      await _applyIndividualAcl(
        relativePath: '$_motorsRoot/$motoId',
        isFile: false,
        allowedWebIds: group.memberUids,
        allowWrite: true,
      );

      // 2. Izin eksplisit pada file motorcycle.ttl
      await _applyIndividualAcl(
        relativePath: _motorPath(motoId),
        isFile: true,
        allowedWebIds: group.memberUids,
        allowWrite: true,
      );
    }
  }

  Future<void> _saveGroupPointer({
    required String groupId,
    required String groupUrl,
    required String ownerId,
  }) async {
    final ttl =
        '${FamilyGroup.turtlePrefixes}'
        '<#ptr-$groupId> a <https://example.org/motorqu-group#GroupPointer> ;\n'
        '    <https://example.org/motorqu-group#groupId> "$groupId" ;\n'
        '    <https://example.org/motorqu-group#groupResourceUrl> "$groupUrl" ;\n'
        '    <https://example.org/motorqu-group#ownerId> "$ownerId" .\n';

    await writePod(
      _pointerPath(groupId),
      ttl,
      encrypted: false,
      overwrite: true,
      createAcl: true,
    );
  }

  Future<String?> _readGroupPointerUrl(String groupId) async {
    try {
      final content = await readPod(_pointerPath(groupId));
      final match = RegExp(
        r'<https://example\.org/motorqu-group#groupResourceUrl>\s+"([^"]+)"',
      ).firstMatch(content);
      return match?.group(1);
    } catch (e) {
      if (_isNotFound(e)) return null;
      rethrow;
    }
  }

  Future<void> _deleteGroupPointer(String groupId) async {
    try {
      final pointerUrl = await _buildOwnResourceUrl(_pointerPath(groupId));
      await deleteFile(fileUrl: pointerUrl);
    } catch (e) {
      if (!_isNotFound(e)) debugPrint('Gagal hapus pointer grup: $e');
    }
  }

  Future<FamilyGroup?> _fetchGroupByUrl(String groupUrl) async {
    try {
      final ownPrefix = await _buildOwnResourceUrl('');
      final isLocal = groupUrl.startsWith(ownPrefix);
      final content = isLocal
          ? await readPod(groupUrl.substring(ownPrefix.length))
          : await readExternalPod(groupUrl);

      if (content.trim().isEmpty) return null;
      return FamilyGroup.fromTurtle(content, fallbackUrl: groupUrl);
    } catch (e) {
      if (_isNotFound(e)) return null;
      rethrow;
    }
  }

  /// Menentukan WebID pemilik fisik Pod dari URL resource
  String _resolveFileOwnerWebId(String resourceUrl, String fallbackOwnerId) {
    final markerIndex = resourceUrl.indexOf('/motorqu-solid/');
    if (markerIndex != -1) {
      final podBase = resourceUrl.substring(0, markerIndex);
      return '$podBase/profile/card#me';
    }
    return fallbackOwnerId;
  }

  Future<void> _writeGroupToUrl(FamilyGroup group, {bool isNew = false}) async {
    final ownPrefix = await _buildOwnResourceUrl('');
    final targetUrl = group.groupResourceUrl.isNotEmpty
        ? group.groupResourceUrl
        : await _buildOwnResourceUrl(_ownGroupPath(group.id));

    final updatedGroup = group.copyWith(groupResourceUrl: targetUrl);
    final payload = FamilyGroup.turtlePrefixes + updatedGroup.toTurtle();

    if (targetUrl.startsWith(ownPrefix)) {
      final relPath = targetUrl.substring(ownPrefix.length);
      await writePod(
        relPath,
        payload,
        encrypted: false,
        overwrite: true,
        createAcl: isNew,
      );
    } else {
      final fileOwnerWebId = _resolveFileOwnerWebId(targetUrl, group.ownerId);
      await writeExternalPod(
        targetUrl,
        payload,
        fileOwnerWebId,
        encrypted: false,
        overwrite: true,
      );
    }
  }

  /// Mengatur ACL pada resource di Pod milik user saat ini
  Future<void> _applyIndividualAcl({
    required String relativePath,
    required bool isFile,
    required List<String> allowedWebIds,
    bool allowWrite = true,
    bool allowControl = false,
  }) async {
    try {
      final recipients = allowedWebIds.where((id) => id != webId).toList();
      if (recipients.isEmpty) return;

      final perms = <String>[
        'Read',
        if (allowWrite) 'Write',
        if (allowControl) 'Control',
      ];

      await grantPermission(
        fileName: relativePath,
        isFile: isFile,
        permissionList: perms,
        recipientType: RecipientType.individual,
        recipientWebIdList: recipients,
        ownerWebId: webId,
        granterWebId: webId,
      );
    } catch (e) {
      debugPrint('ACL sync warning ($relativePath): $e');
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

  /// Mengambil daftar semua grup yang diikuti oleh user
  Future<List<FamilyGroup>> getUserGroupsList() => _sync(() async {
    final res = await _listDir(_joinedGroupsRoot);
    final groups = <FamilyGroup>[];

    for (final fileUrl in res.files) {
      final fileName = _lastSegment(fileUrl);
      if (!fileName.endsWith('.ttl')) continue;
      final groupId = fileName.replaceAll('.ttl', '');

      final targetUrl = await _readGroupPointerUrl(groupId);
      if (targetUrl == null) continue;

      final group = await _fetchGroupByUrl(targetUrl);
      if (group == null || !group.memberUids.contains(webId)) {
        await _deleteGroupPointer(groupId);
        continue;
      }

      if (group.ownerId == webId && group.activeInviteCode == null) {
        await _applyIndividualAcl(
          relativePath: _ownGroupPath(group.id),
          isFile: true,
          allowedWebIds: group.memberUids,
          allowWrite: true,
        );
      }

      // Sinkronkan ACL motor milik user ini untuk anggota baru
      await _syncOwnedGroupMotorAcls(group);

      groups.add(group);
    }

    groups.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return groups;
  });

  Future<List<Motorcycle>> getGroupMotorcycles(String groupId) async {
    final groupUrl = await _readGroupPointerUrl(groupId);
    if (groupUrl == null) return [];

    final group = await _fetchGroupByUrl(groupUrl);
    if (group == null) return [];

    // Pastikan motor milik user sendiri di grup ini terbuka ACL-nya untuk semua member
    await _syncOwnedGroupMotorAcls(group);

    final ownPrefix = await _buildOwnResourceUrl('');
    final futures = group.sharedMotorUrls.map((motorUrl) async {
      try {
        final content = motorUrl.startsWith(ownPrefix)
            ? await readPod(motorUrl.substring(ownPrefix.length))
            : await readExternalPod(motorUrl);

        if (content.trim().isEmpty) return null;
        final moto = Motorcycle.fromTurtle(content);
        return (moto.groupId == groupId && moto.isGroupMotor) ? moto : null;
      } catch (e) {
        debugPrint('Lewati motor grup ($motorUrl): $e');
        return null;
      }
    });

    final results = await Future.wait(futures);
    return results.whereType<Motorcycle>().toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Mengambil daftar motor pribadi milik user (groupId == 'private')
  Future<List<Motorcycle>> getUserPrivateMotorcycles() => _sync(() async {
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
  });

  // ----------------------------- MOTOR <-> GROUP -----------------------------

  /// Memasukkan motor pribadi milik user ke dalam grup
  Future<void> assignMotorcycleToGroup(String motoId, String groupId) =>
      _sync(() async {
        final groupUrl = await _readGroupPointerUrl(groupId);
        if (groupUrl == null) throw Exception('Grup tidak ditemukan');

        final group = await _fetchGroupByUrl(groupUrl);
        if (group == null) throw Exception('Data grup gagal dimuat');

        // 1. Update motorcycle.ttl di Pod milik user
        final rawMoto = await readPod(_motorPath(motoId));
        final currentMoto = Motorcycle.fromTurtle(rawMoto);
        final updatedMoto = currentMoto.copyWith(
          groupId: groupId,
          isGroupMotor: true,
          memberUids: group.memberUids,
        );

        await writePod(
          _motorPath(motoId),
          Motorcycle.turtlePrefixes + updatedMoto.toTurtle(),
          encrypted: false,
          overwrite: true,
          createAcl: false,
        );

        // 2. Beri izin baca/tulis pada folder motor & file motorcycle.ttl ke anggota grup
        await _applyIndividualAcl(
          relativePath: '$_motorsRoot/$motoId',
          isFile: false,
          allowedWebIds: group.memberUids,
          allowWrite: true,
        );
        await _applyIndividualAcl(
          relativePath: _motorPath(motoId),
          isFile: true,
          allowedWebIds: group.memberUids,
          allowWrite: true,
        );

        // 3. Daftarkan URL motor ini ke group.ttl
        final ownMotorUrl = await _buildOwnResourceUrl(_motorPath(motoId));
        if (!group.sharedMotorUrls.contains(ownMotorUrl)) {
          final updatedGroup = group.copyWith(
            sharedMotorUrls: [...group.sharedMotorUrls, ownMotorUrl],
          );
          await _writeGroupToUrl(updatedGroup);
        }
      });

  /// Mengeluarkan motor dari grup kembali menjadi motor pribadi ('private')
  Future<void> removeMotorcycleFromGroup(String motoId) => _sync(() async {
    final rawMoto = await readPod(_motorPath(motoId));
    final currentMoto = Motorcycle.fromTurtle(rawMoto);
    final oldGroupId = currentMoto.groupId;

    final updatedMoto = currentMoto.copyWith(
      groupId: 'private',
      isGroupMotor: false,
      memberUids: [webId],
    );

    await writePod(
      _motorPath(motoId),
      Motorcycle.turtlePrefixes + updatedMoto.toTurtle(),
      encrypted: false,
      overwrite: true,
      createAcl: false,
    );

    // Hapus URL motor dari group.ttl
    if (oldGroupId.isNotEmpty && oldGroupId != 'private') {
      final groupUrl = await _readGroupPointerUrl(oldGroupId);
      if (groupUrl != null) {
        final group = await _fetchGroupByUrl(groupUrl);
        if (group != null) {
          final ownMotorUrl = await _buildOwnResourceUrl(_motorPath(motoId));
          final updatedUrls = group.sharedMotorUrls
              .where((u) => u != ownMotorUrl)
              .toList();
          await _writeGroupToUrl(group.copyWith(sharedMotorUrls: updatedUrls));
        }
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

    await _writeGroupToUrl(newGroup, isNew: true);
    await _saveGroupPointer(
      groupId: groupId,
      groupUrl: groupUrl,
      ownerId: webId,
    );

    return groupId;
  });

  /// Membuat payload JSON untuk di-render sebagai QR Code undangan (berlaku 7 hari)
  Future<String> createInviteQrPayload(String groupId) => _sync(() async {
    final groupUrl = await _readGroupPointerUrl(groupId);
    if (groupUrl == null) throw Exception('Grup tidak ditemukan');

    final group = await _fetchGroupByUrl(groupUrl);
    if (group == null) throw Exception('Data grup gagal dimuat');
    if (!group.isOwner(webId)) {
      throw Exception('Hanya owner/admin grup yang dapat membuat QR undangan');
    }

    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final code = List.generate(
      6,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    final expiresAt = DateTime.now().toUtc().add(const Duration(days: 7));

    final updatedGroup = group.copyWith(
      activeInviteCode: code,
      inviteExpiresAt: expiresAt,
    );
    await _writeGroupToUrl(updatedGroup);

    // Buka akses sementara bagi user Solid terautentikasi yang memindai QR
    if (group.ownerId == webId) {
      try {
        await grantPermission(
          fileName: _ownGroupPath(groupId),
          isFile: true,
          permissionList: ['Read', 'Write'],
          recipientType: RecipientType.authUser,
          recipientWebIdList: const [],
          ownerWebId: webId,
          granterWebId: webId,
        );
      } catch (e) {
        debugPrint('Gagal set authUser ACL untuk invite QR: $e');
      }
    }

    return jsonEncode({
      'v': 1,
      'groupId': groupId,
      'groupUrl': groupUrl,
      'code': code,
    });
  });

  /// Bergabung ke grup dengan memindai QR Code undangan
  Future<String> joinGroupWithQr(String qrRawData) => _sync(() async {
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(qrRawData.trim()) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Format QR Code undangan tidak valid');
    }

    final groupId = payload['groupId'] as String? ?? '';
    final groupUrl = payload['groupUrl'] as String? ?? '';
    final code = (payload['code'] as String? ?? '').trim().toUpperCase();

    if (groupId.isEmpty || groupUrl.isEmpty || code.length != 6) {
      throw Exception('Data QR Code undangan tidak lengkap');
    }

    final group = await _fetchGroupByUrl(groupUrl);
    if (group == null) {
      throw Exception('Grup tidak ditemukan atau akses ditolak');
    }

    if (group.activeInviteCode == null || group.activeInviteCode != code) {
      throw Exception('QR undangan sudah dipakai atau tidak valid');
    }

    if (group.inviteExpiresAt != null &&
        DateTime.now().toUtc().isAfter(group.inviteExpiresAt!)) {
      throw Exception('QR undangan sudah kedaluwarsa');
    }

    if (group.memberUids.contains(webId)) {
      await _saveGroupPointer(
        groupId: groupId,
        groupUrl: groupUrl,
        ownerId: group.ownerId,
      );
      return groupId;
    }

    // Tambahkan WebID ke memberUids & hanguskan kode (single-use)
    final updatedGroup = group.copyWith(
      memberUids: [...group.memberUids, webId],
      clearInvite: true,
    );
    await _writeGroupToUrl(updatedGroup);

    // Simpan pointer grup di Pod anggota baru
    await _saveGroupPointer(
      groupId: groupId,
      groupUrl: groupUrl,
      ownerId: group.ownerId,
    );

    return groupId;
  });

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

  Future<void> leaveGroup(String groupId) => _sync(() async {
    final groupUrl = await _readGroupPointerUrl(groupId);
    if (groupUrl == null) return;

    final group = await _fetchGroupByUrl(groupUrl);
    if (group != null) {
      final remainingMembers = group.memberUids
          .where((m) => m != webId)
          .toList();
      final remainingOwners = group.ownerIds.where((o) => o != webId).toList();

      if (remainingMembers.isEmpty && group.ownerId == webId) {
        // Anggota terakhir keluar -> hapus file grup di Pod sendiri
        try {
          await deleteFile(
            fileUrl: await _buildOwnResourceUrl(_ownGroupPath(groupId)),
          );
        } catch (e) {
          if (!_isNotFound(e)) debugPrint('Gagal hapus file grup: $e');
        }
      } else {
        var nextOwnerId = group.ownerId;
        var nextOwnerIds = remainingOwners;

        if (group.ownerId == webId) {
          nextOwnerId = remainingOwners.isNotEmpty
              ? remainingOwners.first
              : remainingMembers.first;
          if (!nextOwnerIds.contains(nextOwnerId)) {
            nextOwnerIds = [nextOwnerId, ...nextOwnerIds];
          }
        }

        final ownMotorPrefix = await _buildOwnResourceUrl(_motorsRoot);
        final remainingSharedMotors = group.sharedMotorUrls
            .where((u) => !u.startsWith(ownMotorPrefix))
            .toList();

        await _writeGroupToUrl(
          group.copyWith(
            ownerId: nextOwnerId,
            ownerIds: nextOwnerIds,
            memberUids: remainingMembers,
            sharedMotorUrls: remainingSharedMotors,
          ),
        );
      }
    }

    // Kembalikan semua motor milik user di grup ini menjadi 'private'
    final res = await _listDir(_motorsRoot);
    for (final dirUrl in res.subDirs) {
      final motoId = _lastSegment(dirUrl);
      try {
        final content = await readPod(_motorPath(motoId));
        if (content.trim().isEmpty) continue;
        final moto = Motorcycle.fromTurtle(content);
        if (moto.groupId == groupId) {
          await writePod(
            _motorPath(motoId),
            Motorcycle.turtlePrefixes +
                moto
                    .copyWith(
                      groupId: 'private',
                      isGroupMotor: false,
                      memberUids: [webId],
                    )
                    .toTurtle(),
            encrypted: false,
            overwrite: true,
            createAcl: false,
          );
        }
      } catch (_) {}
    }

    await _deleteGroupPointer(groupId);
  });

  Future<void> kickMember(String groupId, String targetUid) => _sync(() async {
    final groupUrl = await _readGroupPointerUrl(groupId);
    if (groupUrl == null) throw Exception('Grup tidak ditemukan');

    final group = await _fetchGroupByUrl(groupUrl);
    if (group == null) throw Exception('Data grup gagal dimuat');
    if (!group.isOwner(webId)) {
      throw Exception('Hanya owner/admin grup yang dapat mengeluarkan anggota');
    }
    if (group.ownerId == targetUid) {
      throw Exception('Pembuat grup utama tidak dapat dikeluarkan');
    }

    // Hapus target dari memberUids, ownerIds, dan keluarkan URL motor miliknya
    final targetPodBase = targetUid.split('/profile/').first;
    final updatedMotors = group.sharedMotorUrls
        .where((u) => !u.startsWith(targetPodBase))
        .toList();

    final updatedGroup = group.copyWith(
      memberUids: group.memberUids.where((m) => m != targetUid).toList(),
      ownerIds: group.ownerIds.where((o) => o != targetUid).toList(),
      sharedMotorUrls: updatedMotors,
    );

    await _writeGroupToUrl(updatedGroup);

    if (group.ownerId == webId) {
      await _applyIndividualAcl(
        relativePath: _ownGroupPath(groupId),
        isFile: true,
        allowedWebIds: updatedGroup.memberUids,
        allowWrite: true,
      );
    }
  });

  Future<void> promoteMemberToOwner(String groupId, String targetUid) =>
      _sync(() async {
        final groupUrl = await _readGroupPointerUrl(groupId);
        if (groupUrl == null) throw Exception('Grup tidak ditemukan');

        final group = await _fetchGroupByUrl(groupUrl);
        if (group == null) throw Exception('Data grup gagal dimuat');
        if (!group.isOwner(webId)) {
          throw Exception(
            'Hanya owner/admin grup yang dapat mengangkat owner baru',
          );
        }

        if (!group.ownerIds.contains(targetUid)) {
          await _writeGroupToUrl(
            group.copyWith(ownerIds: [...group.ownerIds, targetUid]),
          );
        }
      });

  Future<void> demoteOwner(String groupId, String targetUid) => _sync(() async {
    final groupUrl = await _readGroupPointerUrl(groupId);
    if (groupUrl == null) throw Exception('Grup tidak ditemukan');

    final group = await _fetchGroupByUrl(groupUrl);
    if (group == null) throw Exception('Data grup gagal dimuat');
    if (!group.isOwner(webId)) {
      throw Exception(
        'Hanya owner/admin grup yang dapat mengubah status owner',
      );
    }
    if (group.ownerId == targetUid) {
      throw Exception('Pembuat grup utama tidak dapat diturunkan statusnya');
    }

    await _writeGroupToUrl(
      group.copyWith(
        ownerIds: group.ownerIds.where((o) => o != targetUid).toList(),
      ),
    );
  });

  Future<void> transferGroupOwnership(String groupId, String newOwnerUid) =>
      _sync(() async {
        final groupUrl = await _readGroupPointerUrl(groupId);
        if (groupUrl == null) throw Exception('Grup tidak ditemukan');

        final group = await _fetchGroupByUrl(groupUrl);
        if (group == null) throw Exception('Data grup gagal dimuat');
        if (group.ownerId != webId) {
          throw Exception(
            'Hanya pembuat utama yang dapat memindahkan kepemilikan',
          );
        }
        if (!group.memberUids.contains(newOwnerUid)) {
          throw Exception('Pengguna tujuan bukan anggota grup ini');
        }

        final nextOwners = group.ownerIds.contains(newOwnerUid)
            ? group.ownerIds
            : [...group.ownerIds, newOwnerUid];

        final updatedGroup = group.copyWith(
          ownerId: newOwnerUid,
          ownerIds: nextOwners,
        );
        await _writeGroupToUrl(updatedGroup);

        // Berikan hak Control pada file group.ttl ke owner utama yang baru
        if (group.ownerId == webId) {
          await _applyIndividualAcl(
            relativePath: _ownGroupPath(groupId),
            isFile: true,
            allowedWebIds: [newOwnerUid],
            allowWrite: true,
            allowControl: true,
          );
        }
      });

  Future<void> updateGroupName(String groupId, String newName) =>
      _sync(() async {
        final groupUrl = await _readGroupPointerUrl(groupId);
        if (groupUrl == null) throw Exception('Grup tidak ditemukan');

        final group = await _fetchGroupByUrl(groupUrl);
        if (group == null) throw Exception('Data grup gagal dimuat');

        await _writeGroupToUrl(group.copyWith(name: newName.trim()));
      });
}
