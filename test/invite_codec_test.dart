import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:motorqu_solid/services/invite_codec.dart';

final _payload = jsonEncode({
  'v': 2,
  'groupId': '3f2a1c9e-0000-4000-8000-1234567890ab',
  'groupUrl':
      'https://alice.pod/motorqu-solid/data/groups/3f2a1c9e-0000-4000-8000-1234567890ab.ttl',
  'requestsUrl':
      'https://alice.pod/motorqu-solid/data/group_requests/3f2a1c9e-0000-4000-8000-1234567890ab/',
  'code': 'ABC123',
});

void main() {
  group('InviteCodec', () {
    test('encode -> decode bolak-balik', () {
      final code = InviteCodec.encode(_payload);
      expect(code, startsWith('MQ1-'));
      expect(code, isNot(contains('=')), reason: 'tanpa padding');
      expect(InviteCodec.decode(code), _payload);
    });

    test('kode hanya memakai karakter aman untuk chat', () {
      final code = InviteCodec.encode(_payload);
      expect(RegExp(r'^MQ1-[A-Za-z0-9_-]+$').hasMatch(code), isTrue);
    });

    test('pesan chat utuh (dengan teks lain) tetap bisa di-decode', () {
      final message = InviteCodec.shareMessage(
        groupName: 'Keluarga Ridlo',
        payloadJson: _payload,
      );
      expect(message, contains('Keluarga Ridlo'));
      expect(InviteCodec.decode(message), _payload);
      // Diteruskan ulang dengan awalan "Diteruskan" / spasi tambahan.
      expect(InviteCodec.decode('Diteruskan:\n\n  $message  '), _payload);
    });

    test('isi QR (JSON mentah) diterima apa adanya', () {
      expect(InviteCodec.decode(_payload), _payload);
    });

    test('teks sembarang, kode terpotong, atau JSON lain: null', () {
      final code = InviteCodec.encode(_payload);
      expect(InviteCodec.decode(''), isNull);
      expect(InviteCodec.decode('halo apa kabar'), isNull);
      expect(InviteCodec.decode('MQ1-abc'), isNull);
      expect(InviteCodec.decode(code.substring(0, code.length ~/ 2)), isNull);
      expect(InviteCodec.decode('{"foo": 1}'), isNull);
      expect(
        InviteCodec.decode('MQ1-${base64Url.encode(utf8.encode('{"a":1}'))}xxxxxxxxxxxxxxxx'),
        isNull,
      );
    });
  });
}
