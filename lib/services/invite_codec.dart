import 'dart:convert';

/// Kode undangan grup dalam bentuk teks, supaya bisa dikirim lewat chat
/// (WhatsApp, Telegram, SMS) untuk anggota yang tidak sedang berada di dekat
/// HP pembuat grup.
///
/// Isi kode = payload JSON yang sama dengan QR undangan (v2), di-encode
/// base64url dengan awalan `MQ1-`. Kode sekali pakai & berlaku 7 hari; yang
/// memvalidasi tetap host grup (lihat GroupService.processJoinRequests).
class InviteCodec {
  InviteCodec._();

  static const prefix = 'MQ1-';

  static final _tokenRe = RegExp(r'MQ1-([A-Za-z0-9_-]{16,})');

  /// Payload JSON -> kode `MQ1-...`.
  static String encode(String payloadJson) =>
      prefix +
      base64Url.encode(utf8.encode(payloadJson)).replaceAll('=', '');

  /// Ambil payload JSON dari teks apa pun yang ditempel: pesan chat utuh,
  /// kode `MQ1-...` saja, atau isi QR (JSON mentah). `null` bila tidak ada
  /// undangan yang valid.
  static String? decode(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;

    if (trimmed.startsWith('{')) {
      return _isInvitePayload(trimmed) ? trimmed : null;
    }

    final match = _tokenRe.firstMatch(trimmed);
    if (match == null) return null;
    try {
      final raw = match.group(1)!;
      final padded = raw.padRight((raw.length + 3) ~/ 4 * 4, '=');
      final json = utf8.decode(base64Url.decode(padded));
      return _isInvitePayload(json) ? json : null;
    } catch (_) {
      return null;
    }
  }

  static bool _isInvitePayload(String json) {
    try {
      final map = jsonDecode(json);
      return map is Map &&
          map['groupId'] is String &&
          map['groupUrl'] is String &&
          map['code'] is String;
    } catch (_) {
      return false;
    }
  }

  /// Pesan siap kirim ke chat.
  static String shareMessage({
    required String groupName,
    required String payloadJson,
  }) =>
      'Yuk gabung ke garasi grup "$groupName" di MotorQu!\n\n'
      'Buka MotorQu > tombol + > Masuk Grup > "Tempel Kode Undangan", '
      'lalu tempel pesan ini.\n\n'
      '${encode(payloadJson)}\n\n'
      'Kode hanya untuk 1 orang & berlaku 7 hari.';
}
