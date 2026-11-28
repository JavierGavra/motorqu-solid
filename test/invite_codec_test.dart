import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:motorqu_solid/services/invite_codec.dart';

final _payload = jsonEncode({
  'v': 2,
  'groupId': '3f2a1c9e-0000-4000-8000-1234567890ab',
  'groupUrl': 'https://alice.pod/motorqu-solid/data/groups/3f2a1c9e-0000-4000-8000-1234567890ab.ttl',
  'requestsUrl': 'https://alice.pod/motorqu-solid/data/group_requests/3f2a1c9e-0000-4000-8000-1234567890ab/',
  'code': 'ABC123',
});

void main() {
  group('InviteCode (kode pendek)', () {
    const defaultRoot = 'https://pods.solidcommunity.au/ridlofw/';

    test('server bawaan: cukup nama akun + 6 karakter', () {
      const c = InviteCode(podRoot: defaultRoot, code: 'K7M2QX');
      expect(c.text, 'ridlofw-K7M2QX');
      expect(
        c.indexUrl,
        'https://pods.solidcommunity.au/ridlofw/motorqu-solid/data/invites/K7M2QX.ttl',
      );
      final parsed = InviteCode.parse('ridlofw-K7M2QX')!;
      expect(parsed.podRoot, defaultRoot);
      expect(parsed.code, 'K7M2QX');
    });

    test('server lain (subdomain & path) bolak-balik', () {
      for (final root in [
        'https://alice.solidcommunity.net/',
        'https://solidweb.org/alice/',
        'https://pods.solidcommunity.au/ridlo.fw/',
        'http://localhost:3000/bob/',
      ]) {
        final c = InviteCode(podRoot: root, code: 'ABCDEF');
        final parsed = InviteCode.parse(c.text);
        expect(parsed?.podRoot, root, reason: c.text);
        expect(parsed?.code, 'ABCDEF');
      }
      expect(
        const InviteCode(
          podRoot: 'https://alice.solidcommunity.net/',
          code: 'ABCDEF',
        ).text,
        'alice.solidcommunity.net-ABCDEF',
      );
    });

    test('huruf kecil, spasi, & nama akun bertanda hubung', () {
      final a = InviteCode.parse('  ridlofw-k7m2qx \n')!;
      expect(a.code, 'K7M2QX');
      final b = InviteCode.parse('ridlo-fw-K7M2QX')!;
      expect(b.podRoot, 'https://pods.solidcommunity.au/ridlo-fw/');
      expect(b.code, 'K7M2QX');
    });

    test('pesan chat utuh, juga bila baris barunya hilang saat ditempel', () {
      final msg = InviteCode.shareMessage(
        groupName: 'Keluarga Ridlo',
        code: 'ridlofw-K7M2QX',
        expiresAt: DateTime.utc(2026, 12, 5),
      );
      expect(msg, contains('Keluarga Ridlo'));
      for (final text in [
        msg,
        msg.replaceAll('\n', ''),
        'Diteruskan:\n$msg',
        '*ridlofw-K7M2QX*',
        // Nama grup yang mirip kode tidak boleh terambil.
        InviteCode.shareMessage(
          groupName: 'Motor-AYAHKU',
          code: 'ridlofw-K7M2QX',
          expiresAt: DateTime.utc(2026, 12, 5),
        ),
        InviteCode.shareMessage(
          groupName: 'Motor-AYAHKU',
          code: 'ridlofw-K7M2QX',
          expiresAt: DateTime.utc(2026, 12, 5),
        ).replaceAll('\n', ''),
      ]) {
        final parsed = InviteCode.parse(text);
        expect(parsed?.text, 'ridlofw-K7M2QX', reason: text);
      }
    });

    test('teks tanpa kode valid: null', () {
      expect(InviteCode.parse(''), isNull);
      expect(InviteCode.parse('Yuk gabung ke grup'), isNull);
      expect(InviteCode.parse('K7M2QX'), isNull, reason: 'tanpa alamat');
      expect(InviteCode.parse('ridlofw-K7M2Q'), isNull, reason: '5 karakter');
      // I, O, 0, 1 tidak dipakai agar tidak tertukar saat diketik.
      expect(InviteCode.parse('ridlofw-ABCDE1'), isNull);
      expect(InviteCode.looksLikeBareCode('k7m2qx'), isTrue);
      expect(InviteCode.looksLikeBareCode('ridlofw'), isFalse);
    });

    test('root Pod dari URL folder data aplikasi', () {
      expect(
        InviteCode.podRootFromDataUrl(
          'https://pods.solidcommunity.au/ridlofw/motorqu-solid/data/',
        ),
        defaultRoot,
      );
      expect(
        InviteCode.podRootFromDataUrl(
          'https://alice.solidcommunity.net/motorqu-solid/data',
        ),
        'https://alice.solidcommunity.net/',
      );
    });
  });

  group('GroupInvite', () {
    test('toTurtle -> tryParse bolak-balik', () {
      final invite = GroupInvite(
        groupId: 'g1',
        groupName: 'Keluarga "Ridlo"',
        groupUrl: 'https://alice.pod/motorqu-solid/data/groups/g1.ttl',
        requestsUrl: 'https://alice.pod/motorqu-solid/data/group_requests/g1/',
        code: 'K7M2QX',
        expiresAt: DateTime.utc(2026, 12, 5, 10),
      );
      final parsed = GroupInvite.tryParse(invite.toTurtle())!;
      expect(parsed.groupId, 'g1');
      expect(parsed.groupName, 'Keluarga "Ridlo"');
      expect(parsed.groupUrl, invite.groupUrl);
      expect(parsed.requestsUrl, invite.requestsUrl);
      expect(parsed.code, 'K7M2QX');
      expect(parsed.expiresAt, invite.expiresAt);
      expect(parsed.isExpired(DateTime.utc(2026, 12, 1)), isFalse);
      expect(parsed.isExpired(DateTime.utc(2026, 12, 6)), isTrue);
      expect(parsed.toJoinPayload()['code'], 'K7M2QX');
    });

    test('isi rusak: null', () {
      expect(GroupInvite.tryParse(''), isNull);
      expect(GroupInvite.tryParse('<#invite> a grp:GroupInvite .'), isNull);
    });
  });

  group('InviteCodec (format lama)', () {
    test('encode -> decode bolak-balik', () {
      final code = InviteCodec.encode(_payload);
      expect(code, startsWith('MQ1-'));
      expect(InviteCodec.decode(code), _payload);
      expect(InviteCodec.decode('Diteruskan:\n\n  $code  '), _payload);
    });

    test('isi QR lama (JSON mentah) diterima apa adanya', () {
      expect(InviteCodec.decode(_payload), _payload);
    });

    test('teks sembarang, kode pendek baru, atau JSON lain: null', () {
      final code = InviteCodec.encode(_payload);
      expect(InviteCodec.decode(''), isNull);
      expect(InviteCodec.decode('halo apa kabar'), isNull);
      expect(InviteCodec.decode('ridlofw-K7M2QX'), isNull);
      expect(InviteCodec.decode('MQ1-abc'), isNull);
      expect(InviteCodec.decode(code.substring(0, code.length ~/ 2)), isNull);
      expect(InviteCodec.decode('{"foo": 1}'), isNull);
    });
  });
}
