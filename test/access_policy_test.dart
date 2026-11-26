import 'package:flutter_test/flutter_test.dart';
import 'package:motorqu_solid/models/family_group.dart';
import 'package:motorqu_solid/models/join_request.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/services/access_policy.dart';
import 'package:motorqu_solid/services/pod_utils.dart';
import 'package:solidpod/solidpod.dart'
    show AccessMode, ResourceNotExistException, genAclTurtle;

const _alice = 'https://alice.pod/profile/card#me';
const _bob = 'https://bob.pod/profile/card#me';
const _carol = 'https://carol.pod/profile/card#me';
const _groupUrl = 'https://alice.pod/motorqu-solid/data/groups/g1.ttl';

FamilyGroup _group({
  List<String> members = const [_alice, _bob],
  String? code,
  DateTime? expires,
}) => FamilyGroup(
  id: 'g1',
  name: 'Keluarga',
  ownerId: _alice,
  ownerIds: const [_alice],
  memberUids: members,
  groupResourceUrl: _groupUrl,
  activeInviteCode: code,
  inviteExpiresAt: expires,
  createdAt: DateTime.utc(2026),
);

Motorcycle _motor({String groupId = 'private', bool shared = false}) =>
    Motorcycle(
      id: 'm1',
      name: 'Beat',
      brand: 'Honda',
      model: 'BeAT',
      groupId: groupId,
      isGroupMotor: shared,
      createdBy: _alice,
      createdAt: DateTime.utc(2026),
    );

JoinRequest _req({String code = 'ABC123', String member = _carol}) =>
    JoinRequest(
      groupId: 'g1',
      memberWebId: member,
      code: code,
      requestedAt: DateTime.utc(2026, 5, 1),
    );

void main() {
  group('AccessPolicy.agents', () {
    test('membuang pemilik, string kosong, dan WebID tidak valid', () {
      final a = AccessPolicy.agents(
        [_alice, _bob, '', 'bukan-url', _carol],
        _alice,
        AccessPolicy.groupFilePerms,
      );
      expect(a.keys, [_bob, _carol]);
    });

    test('urutan input tidak memengaruhi hasil', () {
      final a = AccessPolicy.agents([_carol, _bob], _alice, {AccessMode.read});
      final b = AccessPolicy.agents([_bob, _carol], _alice, {AccessMode.read});
      expect(a.keys.toList(), b.keys.toList());
    });
  });

  group('AccessPolicy.motorAgents', () {
    test('motor pribadi: tanpa agen', () {
      final a = AccessPolicy.motorAgents(
        motor: _motor(),
        ownerWebId: _alice,
        knownGroups: {'g1': _group()},
        isDir: true,
      );
      expect(a, isEmpty);
    });

    test('motor grup: semua anggota kecuali pemilik, folder dapat Append', () {
      final a = AccessPolicy.motorAgents(
        motor: _motor(groupId: 'g1', shared: true),
        ownerWebId: _alice,
        knownGroups: {'g1': _group(members: [_alice, _bob, _carol])},
        isDir: true,
      )!;
      expect(a.keys, [_bob, _carol]);
      expect(a[_bob], contains(AccessMode.append));
    });

    test('file motor: tanpa Append', () {
      final a = AccessPolicy.motorAgents(
        motor: _motor(groupId: 'g1', shared: true),
        ownerWebId: _alice,
        knownGroups: {'g1': _group()},
        isDir: false,
      )!;
      expect(a[_bob], {AccessMode.read, AccessMode.write});
    });

    test('grup tidak dikenal: null (jangan ubah ACL)', () {
      final a = AccessPolicy.motorAgents(
        motor: _motor(groupId: 'gX', shared: true),
        ownerWebId: _alice,
        knownGroups: {'g1': _group()},
        isDir: true,
      );
      expect(a, isNull);
    });
  });

  group('AccessPolicy.decideJoin', () {
    final future = DateTime.utc(2026, 6, 1);
    final now = DateTime.utc(2026, 5, 2);

    test('kode benar & belum kedaluwarsa: diterima', () {
      expect(
        AccessPolicy.decideJoin(
          _group(code: 'ABC123', expires: future),
          _req(),
          now: now,
        ),
        JoinDecision.accept,
      );
    });

    test('kode salah / sudah dipakai / kedaluwarsa: ditolak', () {
      expect(
        AccessPolicy.decideJoin(_group(code: 'ZZZ999'), _req(), now: now),
        JoinDecision.reject,
      );
      expect(
        AccessPolicy.decideJoin(_group(), _req(), now: now),
        JoinDecision.reject,
      );
      expect(
        AccessPolicy.decideJoin(
          _group(code: 'ABC123', expires: DateTime.utc(2026, 5, 1)),
          _req(),
          now: now,
        ),
        JoinDecision.reject,
      );
    });

    test('sudah anggota: alreadyMember (permintaan cukup dihapus)', () {
      expect(
        AccessPolicy.decideJoin(
          _group(code: 'ABC123'),
          _req(member: _bob),
          now: now,
        ),
        JoinDecision.alreadyMember,
      );
    });

    test('WebID tidak valid: ditolak', () {
      expect(
        AccessPolicy.decideJoin(
          _group(code: 'ABC123'),
          _req(member: 'javascript:alert(1)'),
          now: now,
        ),
        JoinDecision.reject,
      );
    });
  });

  group('AccessPolicy.decidePointer', () {
    final now = DateTime.utc(2026, 5, 20);

    test('404: hapus', () {
      expect(
        AccessPolicy.decidePointer(
          status: GroupReadStatus.notFound,
          isMember: false,
          now: now,
        ),
        PointerAction.remove,
      );
    });

    test('terbaca: anggota tetap, bukan anggota dihapus', () {
      expect(
        AccessPolicy.decidePointer(
          status: GroupReadStatus.readable,
          isMember: true,
        ),
        PointerAction.keep,
      );
      expect(
        AccessPolicy.decidePointer(
          status: GroupReadStatus.readable,
          isMember: false,
        ),
        PointerAction.remove,
      );
    });

    test('terbaca tapi belum anggota saat menunggu persetujuan: tunggu', () {
      expect(
        AccessPolicy.decidePointer(
          status: GroupReadStatus.readable,
          isMember: false,
          requestedAt: now.subtract(const Duration(hours: 1)),
          now: now,
        ),
        PointerAction.hide,
      );
      expect(
        AccessPolicy.decidePointer(
          status: GroupReadStatus.readable,
          isMember: false,
          requestedAt: now.subtract(const Duration(days: 8)),
          now: now,
        ),
        PointerAction.remove,
      );
    });

    test('403 pertama: catat, jangan hapus', () {
      expect(
        AccessPolicy.decidePointer(
          status: GroupReadStatus.forbidden,
          isMember: false,
          now: now,
        ),
        PointerAction.markDenied,
      );
    });

    test('403 dalam masa tenggang: sembunyikan; lewat 7 hari: hapus', () {
      expect(
        AccessPolicy.decidePointer(
          status: GroupReadStatus.forbidden,
          isMember: false,
          deniedSince: now.subtract(const Duration(days: 2)),
          now: now,
        ),
        PointerAction.hide,
      );
      expect(
        AccessPolicy.decidePointer(
          status: GroupReadStatus.forbidden,
          isMember: false,
          requestedAt: now.subtract(const Duration(days: 8)),
          now: now,
        ),
        PointerAction.remove,
      );
    });

    test('galat jaringan: hanya disembunyikan', () {
      expect(
        AccessPolicy.decidePointer(
          status: GroupReadStatus.error,
          isMember: false,
          deniedSince: now.subtract(const Duration(days: 30)),
          now: now,
        ),
        PointerAction.hide,
      );
    });
  });

  group('PodUtils.isDefinitelyNotFound', () {
    test('hanya ResourceNotExistException, bukan teks "404" di URL', () {
      expect(
        PodUtils.isDefinitelyNotFound(ResourceNotExistException('x')),
        isTrue,
      );
      final server500 = Exception(
        'Gagal membaca https://budi404.pod/data/groups/a404b.ttl (HTTP 500)',
      );
      expect(PodUtils.isDefinitelyNotFound(server500), isFalse);
      expect(PodUtils.isNotFound(server500), isTrue,
          reason: 'versi longgar memang tertipu; jangan dipakai untuk hapus');
    });
  });

  group('AccessPolicy.isMotorUrlOwnedBy', () {
    const bob = 'https://solidcommunity.au/bob/profile/card#me';
    const bobUrl =
        'https://solidcommunity.au/bob/motorqu-solid/data/motorcycles/m1/motorcycle.ttl';
    const bobbyUrl =
        'https://solidcommunity.au/bobby/motorqu-solid/data/motorcycles/m2/motorcycle.ttl';

    test('motor di Pod sendiri: ya', () {
      expect(AccessPolicy.isMotorUrlOwnedBy(bobUrl, bob), isTrue);
    });

    test('Pod dengan awalan nama sama (bob vs bobby): tidak', () {
      expect(AccessPolicy.isMotorUrlOwnedBy(bobbyUrl, bob), isFalse);
    });

    test('WebID subdomain (https://bob.pod/profile/card#me)', () {
      expect(
        AccessPolicy.isMotorUrlOwnedBy(
          'https://bob.pod/motorqu-solid/data/motorcycles/m1/motorcycle.ttl',
          _bob,
        ),
        isTrue,
      );
      expect(
        AccessPolicy.isMotorUrlOwnedBy(
          'https://bob.pod.evil/motorqu-solid/data/motorcycles/m1/motorcycle.ttl',
          _bob,
        ),
        isFalse,
      );
    });
  });

  group('URL', () {
    test('requestsUrlFor menurunkan container dari URL grup', () {
      expect(
        AccessPolicy.requestsUrlFor(_groupUrl, 'g1'),
        'https://alice.pod/motorqu-solid/data/group_requests/g1/',
      );
      expect(
        () => AccessPolicy.requestsUrlFor('https://x/other.ttl', 'g1'),
        throwsFormatException,
      );
    });

    test('aclUrlFor sesuai konvensi solidpod', () {
      expect(AccessPolicy.aclUrlFor('https://p/a.ttl', isFile: true),
          'https://p/a.ttl.acl');
      expect(AccessPolicy.aclUrlFor('https://p/dir/', isFile: false),
          'https://p/dir/.acl');
      expect(AccessPolicy.aclUrlFor('https://p/dir', isFile: false),
          'https://p/dir/.acl');
    });
  });

  group('JoinRequest', () {
    test('toTurtle -> tryParse bolak-balik', () {
      final parsed = JoinRequest.tryParse(_req(code: 'abc123').toTurtle())!;
      expect(parsed.groupId, 'g1');
      expect(parsed.memberWebId, _carol);
      expect(parsed.code, 'ABC123');
      expect(parsed.requestedAt, DateTime.utc(2026, 5, 1));
    });

    test('isi sembarang (spam): null', () {
      expect(JoinRequest.tryParse('halo'), isNull);
    });
  });

  group('genAclTurtle + AccessPolicy.agents', () {
    test('hasil stabil walau urutan anggota berbeda', () async {
      Future<String> gen(List<String> members) => genAclTurtle(
        'https://alice.pod/motorqu-solid/data/motorcycles/m1/',
        externalWebId: _alice,
        isFile: false,
        thirdPartyAccess: AccessPolicy.agents(
          members,
          _alice,
          AccessPolicy.motorDirPerms,
        ),
      );

      final a = await gen([_alice, _carol, _bob]);
      final b = await gen([_bob, _alice, _carol]);
      expect(a, b);
      expect(a, contains('bob.pod'));
      expect(a, contains('carol.pod'));
      expect(a, contains('Append'));
      expect(a, contains('default'));
    });

    test('container permintaan: authUser hanya Append', () async {
      final acl = await genAclTurtle(
        'https://alice.pod/motorqu-solid/data/group_requests/g1/',
        externalWebId: _alice,
        isFile: false,
        thirdPartyAccess: const {},
        authUserAccess: AccessPolicy.joinRequestAuthUserPerms,
      );
      expect(acl, contains('AuthenticatedAgent'));
      // Satu-satunya otorisasi untuk authUser adalah Append.
      final authBlock = acl
          .split(RegExp(r'\.\s*\n'))
          .firstWhere((b) => b.contains('AuthenticatedAgent'));
      expect(authBlock, contains('Append'));
      expect(authBlock, isNot(contains('Read')));
      expect(authBlock, isNot(contains('Write')));
    });
  });
}
