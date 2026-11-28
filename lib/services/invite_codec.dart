import 'dart:convert';

import 'package:motorqu_solid/models/turtle_utils.dart';

/// Kode undangan grup yang pendek & bisa diketik, mis. `ridlofw-K7M2QX`.
///
/// MotorQu tidak punya server pusat: data grup ada di Solid Pod pembuat
/// kode. Karena itu kode terdiri dari dua bagian:
///
/// - **alamat Pod** pembuat kode. Untuk server bawaan
///   (`pods.solidcommunity.au`) cukup nama akunnya (`ridlofw`); untuk server
///   lain berupa host/path Pod (`alice.solidcommunity.net`,
///   `solidweb.org/alice`), jadi tetap bisa dipakai di server mana pun.
/// - **6 karakter acak** (tanpa I/O/0/1 agar tidak tertukar saat diketik).
///
/// Kode yang sama dipakai untuk QR. Aplikasi pembuat kode menaruh file
/// [GroupInvite] di `<pod>/motorqu-solid/data/invites/<KODE>.ttl` (bisa
/// dibaca user Solid yang sudah login) yang menunjuk ke grup sebenarnya.
class InviteCode {
  const InviteCode({required this.podRoot, required this.code});

  /// URL root Pod pembuat kode, selalu diakhiri `/`.
  final String podRoot;

  /// 6 karakter, huruf besar.
  final String code;

  static const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const codeLength = 6;
  static const defaultServer = 'https://pods.solidcommunity.au/';
  static const appDataPath = 'motorqu-solid/data/';
  static const invitesDir = 'invites';

  /// Lokasi file [GroupInvite] untuk kode ini.
  String get indexUrl => '$podRoot$appDataPath$invitesDir/$code.ttl';

  /// Teks yang dibagikan/diketik pengguna.
  String get text => '${addressOf(podRoot)}-$code';

  @override
  String toString() => text;

  /// Root Pod dari URL folder data aplikasi (`.../motorqu-solid/data/`).
  static String podRootFromDataUrl(String dataUrl) {
    final base = dataUrl.endsWith('/') ? dataUrl : '$dataUrl/';
    if (!base.endsWith(appDataPath)) {
      throw FormatException('URL data aplikasi tidak dikenali: $dataUrl');
    }
    return base.substring(0, base.length - appDataPath.length);
  }

  /// Root Pod -> bagian alamat pada kode.
  static String addressOf(String podRoot) {
    final root = podRoot.endsWith('/')
        ? podRoot.substring(0, podRoot.length - 1)
        : podRoot;
    final defaultBase = defaultServer.substring(0, defaultServer.length - 1);
    if (root.startsWith('$defaultBase/')) {
      final user = root.substring(defaultBase.length + 1);
      if (_isPlainUser(user)) return user;
    }
    if (root.startsWith('https://')) return root.substring('https://'.length);
    return root;
  }

  /// Bagian alamat pada kode -> root Pod. `null` bila tidak masuk akal.
  static String? podRootOf(String address) {
    var a = address.trim();
    while (a.endsWith('/')) {
      a = a.substring(0, a.length - 1);
    }
    if (a.isEmpty) return null;
    final String url;
    if (a.startsWith('https://') || a.startsWith('http://')) {
      url = '$a/';
    } else if (_isPlainUser(a)) {
      url = '$defaultServer$a/';
    } else {
      url = 'https://$a/';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    return url;
  }

  /// Nama akun polos (tanpa titik/garis miring) = akun di server bawaan.
  static bool _isPlainUser(String s) =>
      s.isNotEmpty && !s.contains('.') && !s.contains('/') && !s.contains(':');

  static final _tokenRe = RegExp(
    r'''(?:^|[\s"'*_(\[<:])((?:https?://)?[A-Za-z0-9][A-Za-z0-9._~%/:-]*?)-([A-Za-z0-9]{6})(?=$|[\s"'*_.,!?)\]>])''',
  );

  /// Ambil kode dari teks apa pun: kode saja, pesan chat utuh, atau isi QR.
  /// Huruf kecil diterima (kode dinormalkan ke huruf besar).
  ///
  /// Bila ada beberapa kandidat, yang TERAKHIR dipakai: di [shareMessage]
  /// kode selalu di akhir, sedangkan nama grup di awal pesan bisa saja
  /// berbentuk mirip kode (mis. "Motor-AYAHKU").
  static InviteCode? parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    InviteCode? last;
    for (final m in _tokenRe.allMatches(trimmed)) {
      final code = m.group(2)!.toUpperCase();
      if (!code.split('').every(alphabet.contains)) continue;
      final root = podRootOf(m.group(1)!);
      if (root == null) continue;
      last = InviteCode(podRoot: root, code: code);
    }
    return last;
  }

  /// Apakah teks berisi 6 karakter kode saja (tanpa alamat Pod), untuk
  /// pesan galat yang lebih jelas.
  static bool looksLikeBareCode(String text) {
    final t = text.trim().toUpperCase();
    return t.length == codeLength && t.split('').every(alphabet.contains);
  }

  /// Pesan siap kirim ke chat.
  static String shareMessage({
    required String groupName,
    required String code,
    required DateTime expiresAt,
  }) {
    final local = expiresAt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final until = '${two(local.day)}/${two(local.month)}/${local.year}';
    // Kode sengaja di akhir pesan: bila pesan ditempel ke kolom satu baris
    // (baris baru dibuang), kode tetap terpisah dari teks lain.
    return 'Yuk gabung ke garasi grup "$groupName" di MotorQu!\n\n'
        'Buka MotorQu > Grup > Gabung, lalu ketik atau tempel kode di bawah. '
        'Berlaku sampai $until.\n\n'
        'Kode undangan: $code';
  }
}

/// Isi file `invites/<KODE>.ttl`: penunjuk dari kode ke grup.
class GroupInvite {
  const GroupInvite({
    required this.groupId,
    required this.groupName,
    required this.groupUrl,
    required this.requestsUrl,
    required this.code,
    required this.expiresAt,
  });

  final String groupId;
  final String groupName;
  final String groupUrl;
  final String requestsUrl;
  final String code;
  final DateTime expiresAt;

  bool isExpired([DateTime? now]) =>
      (now ?? DateTime.now()).toUtc().isAfter(expiresAt);

  static const _grpNs = 'https://example.org/motorqu-group#';

  String toTurtle() =>
      '@prefix grp: <$_grpNs> .\n'
      '@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n\n'
      '<#invite> a grp:GroupInvite ;\n'
      '    grp:groupId "${turtleEsc(groupId)}" ;\n'
      '    grp:groupName "${turtleEsc(groupName)}" ;\n'
      '    grp:groupUrl "${turtleEsc(groupUrl)}" ;\n'
      '    grp:requestsUrl "${turtleEsc(requestsUrl)}" ;\n'
      '    grp:code "${turtleEsc(code)}" ;\n'
      '    grp:expiresAt ${turtleDt(expiresAt)} .\n';

  static GroupInvite? tryParse(String turtle) {
    final p = turtleProps(turtle);
    String? one(String k) => p[k]?.first;
    final groupId = one('grp:groupId');
    final groupUrl = one('grp:groupUrl');
    final requestsUrl = one('grp:requestsUrl');
    final code = one('grp:code');
    final expiresAt = DateTime.tryParse(one('grp:expiresAt') ?? '');
    if (groupId == null ||
        groupUrl == null ||
        requestsUrl == null ||
        code == null ||
        expiresAt == null) {
      return null;
    }
    return GroupInvite(
      groupId: groupId,
      groupName: one('grp:groupName') ?? '',
      groupUrl: groupUrl,
      requestsUrl: requestsUrl,
      code: code.trim().toUpperCase(),
      expiresAt: expiresAt.toUtc(),
    );
  }

  /// Payload yang dipakai alur bergabung.
  Map<String, String> toJoinPayload() => {
    'groupId': groupId,
    'groupUrl': groupUrl,
    'requestsUrl': requestsUrl,
    'code': code,
  };
}

/// Format undangan LAMA (`MQ1-<base64>` / JSON mentah di QR v2). Hanya untuk
/// membaca undangan yang sudah terlanjur dibagikan dari versi sebelumnya.
class InviteCodec {
  InviteCodec._();

  static const prefix = 'MQ1-';

  static final _tokenRe = RegExp(r'MQ1-([A-Za-z0-9_-]{16,})');

  /// Payload JSON -> kode `MQ1-...`.
  static String encode(String payloadJson) =>
      prefix + base64Url.encode(utf8.encode(payloadJson)).replaceAll('=', '');

  /// Ambil payload JSON dari kode `MQ1-...` atau JSON mentah. `null` bila
  /// tidak ada undangan format lama yang valid.
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
}
