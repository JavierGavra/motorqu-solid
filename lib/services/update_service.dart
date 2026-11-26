import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateService {
  static const List<String> _metaUrls = [
    'https://github.com/JavierGavra/motorqu-solid/releases/latest/download/latest.json',
  ];
  static const String _apkUrl =
      'https://github.com/JavierGavra/motorqu-solid/releases/latest/download/app-release.apk';

  /// Ambil metadata versi terbaru dari GitHub Release.
  /// Mengembalikan Map JSON atau null jika gagal/offline.
  Future<Map<String, dynamic>?> checkForUpdate() async {
    for (final url in _metaUrls) {
      try {
        final resp = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final decoded = jsonDecode(resp.body);
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
        }
      } catch (_) {
        // Coba sumber berikutnya.
      }
    }
    return null;
  }

  /// Bandingkan versionCode server dengan buildNumber APK terpasang.
  Future<bool> hasUpdate(Map<String, dynamic> meta) async {
    final info = await PackageInfo.fromPlatform();
    final serverCode = int.tryParse(meta['versionCode'].toString()) ?? 0;
    final localCode = int.tryParse(info.buildNumber) ?? 0;
    return serverCode > localCode;
  }

  /// Unduh APK dengan kemampuan resume (HTTP Range 206) dan retry otomatis,
  /// lalu buka installer sistem Android via OpenFilex.
  Future<String?> downloadAndInstall({
    String? targetVersionCode,
    void Function(int received, int total, String status)? onProgress,
  }) async {
    final dir = await _downloadDir();
    if (!dir.existsSync()) {
      try {
        await dir.create(recursive: true);
      } catch (_) {}
    }

    final filename = targetVersionCode != null
        ? 'motorqu_solid_update_$targetVersionCode.apk'
        : 'motorqu_solid_update.apk';
    final target = File('${dir.path}/$filename');

    try {
      for (final entity in dir.listSync()) {
        if (entity is File &&
            entity.path.contains('motorqu_solid_update') &&
            entity.path != target.path) {
          try {
            entity.deleteSync();
          } catch (_) {}
        }
      }
    } catch (_) {}

    var totalBytes = 0;
    const maxRetries = 8;
    String? lastError;

    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      var downloaded = 0;
      if (target.existsSync()) {
        downloaded = target.lengthSync();
      }

      if (totalBytes > 0 && downloaded >= totalBytes) {
        lastError = null;
        break;
      }

      final client = http.Client();
      IOSink? sink;

      try {
        final request = http.Request('GET', Uri.parse(_apkUrl));
        request.headers['Connection'] = 'keep-alive';
        request.headers['User-Agent'] = 'MotorQu-Solid-Android-App';

        if (downloaded > 0) {
          request.headers['Range'] = 'bytes=$downloaded-';
          if (onProgress != null) {
            final dlMb = (downloaded / (1024 * 1024)).toStringAsFixed(1);
            onProgress(
              downloaded,
              totalBytes,
              'Melanjutkan unduhan ($dlMb MB tersimpan)...',
            );
          }
        } else {
          onProgress?.call(0, totalBytes, 'Menghubungkan ke server...');
        }

        final streamed = await client
            .send(request)
            .timeout(const Duration(seconds: 45));

        if (streamed.statusCode == 206) {
          final cr = streamed.headers['content-range'];
          if (cr != null && cr.contains('/')) {
            final totalStr = cr.split('/').last.trim();
            totalBytes = int.tryParse(totalStr) ?? totalBytes;
          } else if (streamed.contentLength != null) {
            totalBytes = downloaded + streamed.contentLength!;
          }
          sink = target.openWrite(mode: FileMode.append);
        } else if (streamed.statusCode == 200) {
          downloaded = 0;
          totalBytes = streamed.contentLength ?? 0;
          sink = target.openWrite(mode: FileMode.write);
        } else if (streamed.statusCode == 416) {
          if (target.existsSync() && target.lengthSync() > 10000000) {
            lastError = null;
            break;
          }
          try {
            target.deleteSync();
          } catch (_) {}
          continue;
        } else {
          lastError = 'Server HTTP ${streamed.statusCode}';
          await Future<void>.delayed(const Duration(seconds: 2));
          continue;
        }

        var received = downloaded;
        await for (final chunk in streamed.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (onProgress != null) {
            final p = totalBytes > 0 ? (received / totalBytes) : 0.0;
            final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
            final totMb = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
            final pct = (p * 100).toInt();
            onProgress(
              received,
              totalBytes,
              '$recMb MB / $totMb MB ($pct%)',
            );
          }
        }

        await sink.flush();
        await sink.close();
        sink = null;

        final finalLen = target.existsSync() ? target.lengthSync() : 0;
        if (totalBytes > 0 && finalLen >= totalBytes) {
          lastError = null;
          break;
        }
      } catch (e) {
        lastError = e.toString();
        await Future<void>.delayed(const Duration(seconds: 2));
      } finally {
        if (sink != null) {
          try {
            await sink.close();
          } catch (_) {}
        }
        client.close();
      }
    }

    if (lastError != null &&
        (!target.existsSync() ||
            (totalBytes > 0 && target.lengthSync() < totalBytes))) {
      return 'Gagal mengunduh: $lastError';
    }

    if (!target.existsSync() || target.lengthSync() < 1000) {
      return 'File APK tidak lengkap saat diunduh.';
    }

    final result = await OpenFilex.open(
      target.path,
      type: 'application/vnd.android.package-archive',
    );
    if (result.type != ResultType.done) {
      return result.message;
    }
    return null;
  }

  Future<Directory> _downloadDir() async {
    try {
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
    } catch (_) {}
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {}
    try {
      return await getApplicationDocumentsDirectory();
    } catch (_) {}
    return Directory.systemTemp;
  }
}
