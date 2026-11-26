import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:motorqu_solid/services/pod_utils.dart';
import 'package:solidpod/solidpod.dart'
    show
        AccessForbiddenException,
        ResourceNotExistException,
        getTokensForResource,
        readExternalPod,
        readPod,
        writeExternalPod,
        writePod;

/// Penyedia token DPoP. Token WAJIB dibuat ulang untuk setiap request karena
/// DPoP proof terikat pada method + URL dan hanya sekali pakai.
typedef PodTokenProvider =
    Future<({String accessToken, String dPopToken})> Function(
      String url,
      String method,
    );

/// Jalur cadangan (tanpa ETag) memakai fungsi baca/tulis bawaan solidpod.
typedef PodFallbackRead = Future<String> Function(String url);
typedef PodFallbackWrite =
    Future<void> Function(String url, String content, String ownerWebId);

/// Transformasi isi file. Kembalikan `null` bila tidak ada yang perlu diubah.
///
/// Transformasi BISA dipanggil lebih dari sekali (saat terjadi konflik), jadi
/// harus murni: validasi di dalam, efek samping (ACL, file lain) di luar.
typedef PodTransform = FutureOr<String?> Function(String current);

/// Dilempar bila file terus diubah perangkat lain sampai batas percobaan habis.
class PodUpdateConflictException implements Exception {
  PodUpdateConflictException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Antrean tulis tunggal untuk seluruh service (motor, oli, grup).
///
/// Reentrant: pemanggilan dari dalam antrean langsung dijalankan sehingga
/// tidak mungkin deadlock. Pembacaan murni sebaiknya tidak lewat antrean.
class PodWriteQueue {
  PodWriteQueue._();

  static Future<void> _tail = Future<void>.value();
  static final Object _zoneKey = Object();

  static Future<T> run<T>(Future<T> Function() action) {
    if (Zone.current[_zoneKey] == true) return action();
    final result = _tail.then(
      (_) => runZoned(action, zoneValues: {_zoneKey: true}),
    );
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

/// Read-modify-write atomik untuk file Turtle di Pod (milik sendiri maupun
/// Pod orang lain) memakai `ETag` + `If-Match`.
///
/// Bila dua perangkat mengubah file yang sama bersamaan, PUT yang kalah
/// mendapat HTTP 412, lalu file dibaca ulang dan transformasi diterapkan lagi
/// pada data terbaru, sehingga tidak ada perubahan yang tertimpa.
class PodAtomicWriter {
  PodAtomicWriter({
    http.Client? client,
    PodTokenProvider? tokens,
    PodFallbackRead? fallbackRead,
    PodFallbackWrite? fallbackWrite,
    this.maxAttempts = 5,
    Duration Function(int attempt)? backoff,
  }) : _client = client ?? http.Client(),
       _tokens = tokens ?? getTokensForResource,
       _fallbackRead = fallbackRead ?? _defaultFallbackRead,
       _fallbackWrite = fallbackWrite ?? _defaultFallbackWrite,
       _backoff = backoff ?? _defaultBackoff;

  static PodAtomicWriter instance = PodAtomicWriter();

  final http.Client _client;
  final PodTokenProvider _tokens;
  final PodFallbackRead _fallbackRead;
  final PodFallbackWrite _fallbackWrite;
  final int maxAttempts;
  final Duration Function(int attempt) _backoff;

  static final Set<String> _loggedEtagState = <String>{};
  static final Random _random = Random();

  static Duration _defaultBackoff(int attempt) =>
      Duration(milliseconds: 150 * attempt + _random.nextInt(200));

  /// Terapkan [transform] pada isi file di [url] secara atomik.
  ///
  /// Mengembalikan `true` bila file ditulis, `false` bila tidak ada perubahan.
  /// [ownerWebId] hanya dipakai jalur cadangan untuk menulis ke Pod orang lain.
  ///
  /// [createIfMissing]: bila file belum ada (404), [transform] dipanggil
  /// dengan string kosong lalu file dibuat dengan `If-None-Match: *`.
  ///
  /// [allowFallback]: `false` untuk file sensitif (mis. `.acl`): 401 dilempar
  /// sebagai error, bukan dialihkan ke readPod/writePod.
  Future<bool> update(
    String url,
    PodTransform transform, {
    String? ownerWebId,
    bool createIfMissing = false,
    bool allowFallback = true,
  }) async {
    String? previous412Etag;
    String? previous412Body;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      final get = await _get(url);

      if (get.statusCode == 401) {
        if (!allowFallback) {
          throw Exception('Sesi tidak valid (HTTP 401) saat membaca $url');
        }
        return _updateViaFallback(url, transform, ownerWebId);
      }

      if (get.statusCode == 404 && createIfMissing) {
        final created = await transform('');
        if (created == null) return false;
        final put = await _put(url, created, null, createOnly: true);
        if (_isSuccess(put.statusCode)) return true;
        if (put.statusCode == 412) {
          // Perangkat lain membuat file lebih dulu: ulangi sebagai update.
          await Future<void>.delayed(_backoff(attempt));
          continue;
        }
        _throwForStatus(put.statusCode, url, put.body, 'membuat');
      }
      _throwForStatus(get.statusCode, url, get.body, 'membaca');

      final next = await transform(get.body);
      if (next == null || next == get.body) return false;

      final etag = get.etag;
      _logEtagState(url, etag);

      if (etag == null || etag.startsWith('W/')) {
        // Server tidak menyediakan ETag kuat: If-Match tidak bisa dipakai.
        return _putOrFallback(url, next, null, ownerWebId, allowFallback);
      }

      final put = await _put(url, next, etag);
      if (_isSuccess(put.statusCode)) return true;

      if (put.statusCode == 412) {
        final serverBroken =
            previous412Etag == etag && previous412Body == get.body;
        if (serverBroken) {
          // ETag & isi tidak berubah tapi tetap 412: dukungan kondisional
          // server rusak. Jangan habiskan percobaan, tulis biasa.
          debugPrint('[PodAtomic] If-Match selalu 412 untuk $url, tulis biasa');
          return _putOrFallback(url, next, null, ownerWebId, allowFallback);
        }
        previous412Etag = etag;
        previous412Body = get.body;
        debugPrint('[PodAtomic] Konflik (412) di $url, percobaan $attempt');
        await Future<void>.delayed(_backoff(attempt));
        continue;
      }

      if (put.statusCode == 401 && allowFallback) {
        await _fallbackWrite(url, next, _owner(url, ownerWebId));
        return true;
      }
      _throwForStatus(put.statusCode, url, put.body, 'menyimpan');
    }

    throw PodUpdateConflictException(
      'Gagal menyimpan: data sedang diubah dari perangkat lain. '
      'Silakan coba lagi.',
    );
  }

  /// Membuat resource baru di dalam container (POST + Slug).
  ///
  /// Dipakai untuk permintaan bergabung grup: penerima hanya punya izin
  /// Append pada container, dan PUT ke resource baru bisa ditolak.
  Future<void> post(
    String containerUrl,
    String content, {
    String? slug,
  }) async {
    final t = await _tokens(containerUrl, 'POST');
    final resp = await _client.post(
      Uri.parse(containerUrl),
      headers: {
        'Content-Type': 'text/turtle',
        'Authorization': 'DPoP ${t.accessToken}',
        'DPoP': t.dPopToken,
        'Link': '<http://www.w3.org/ns/ldp#Resource>; rel="type"',
        'Slug': ?slug,
      },
      body: utf8.encode(content),
    );
    _throwForStatus(resp.statusCode, containerUrl, resp.body, 'mengirim ke');
  }

  Future<bool> _putOrFallback(
    String url,
    String content,
    String? etag,
    String? ownerWebId,
    bool allowFallback,
  ) async {
    final put = await _put(url, content, etag);
    if (_isSuccess(put.statusCode)) return true;
    if (put.statusCode == 401 && allowFallback) {
      await _fallbackWrite(url, content, _owner(url, ownerWebId));
      return true;
    }
    _throwForStatus(put.statusCode, url, put.body, 'menyimpan');
    return true;
  }

  Future<bool> _updateViaFallback(
    String url,
    PodTransform transform,
    String? ownerWebId,
  ) async {
    debugPrint('[PodAtomic] 401 di $url, pakai jalur baca/tulis solidpod');
    final current = await _fallbackRead(url);
    final next = await transform(current);
    if (next == null || next == current) return false;
    await _fallbackWrite(url, next, _owner(url, ownerWebId));
    return true;
  }

  String _owner(String url, String? ownerWebId) =>
      ownerWebId ?? PodUtils.resolveOwnerWebId(url, fallback: '');

  void _logEtagState(String url, String? etag) {
    if (_loggedEtagState.add(url)) {
      debugPrint(
        '[PodAtomic] $url -> '
        '${etag == null ? 'TANPA ETag (tulis biasa)' : 'ETag: $etag'}',
      );
    }
  }

  bool _isSuccess(int code) => code >= 200 && code < 300;

  void _throwForStatus(int code, String url, String body, String action) {
    if (_isSuccess(code)) return;
    if (code == 404) {
      throw ResourceNotExistException('Resource $url does not exist (404)');
    }
    if (code == 403) {
      throw AccessForbiddenException(
        'Akses ditolak (HTTP 403) saat $action $url',
      );
    }
    throw Exception('Gagal $action $url (HTTP $code): $body');
  }

  Future<({int statusCode, String body, String? etag})> _get(String url) async {
    final t = await _tokens(url, 'GET');
    final resp = await _client.get(
      Uri.parse(url),
      headers: {
        // Accept harus sama dengan tipe tersimpan agar ETag cocok saat PUT.
        'Accept': 'text/turtle',
        'Authorization': 'DPoP ${t.accessToken}',
        'DPoP': t.dPopToken,
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    );
    return (
      statusCode: resp.statusCode,
      body: utf8.decode(resp.bodyBytes),
      etag: resp.headers['etag'],
    );
  }

  Future<({int statusCode, String body})> _put(
    String url,
    String content,
    String? etag, {
    bool createOnly = false,
  }) async {
    final t = await _tokens(url, 'PUT');
    final bytes = utf8.encode(content);
    final resp = await _client.put(
      Uri.parse(url),
      headers: {
        'Content-Type': 'text/turtle',
        'Authorization': 'DPoP ${t.accessToken}',
        'DPoP': t.dPopToken,
        'If-Match': ?etag,
        if (createOnly) 'If-None-Match': '*',
      },
      body: bytes,
    );
    return (statusCode: resp.statusCode, body: resp.body);
  }

  static Future<String> _defaultFallbackRead(String url) async {
    final ownPrefix = await PodUtils.ownDataRootPrefix();
    return url.startsWith(ownPrefix)
        ? readPod(url.substring(ownPrefix.length))
        : readExternalPod(url);
  }

  static Future<void> _defaultFallbackWrite(
    String url,
    String content,
    String ownerWebId,
  ) async {
    final ownPrefix = await PodUtils.ownDataRootPrefix();
    if (url.startsWith(ownPrefix)) {
      await writePod(
        url.substring(ownPrefix.length),
        content,
        encrypted: false,
        overwrite: true,
        createAcl: false,
      );
    } else {
      await writeExternalPod(
        url,
        content,
        ownerWebId,
        encrypted: false,
        overwrite: true,
      );
    }
  }
}
