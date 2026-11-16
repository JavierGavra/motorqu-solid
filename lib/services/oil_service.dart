import 'package:flutter/foundation.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/models/oil_record.dart';
import 'package:solidpod/solidpod.dart';
import 'package:uuid/uuid.dart';

/// Penyimpanan riwayat oli di Pod Solid.
///
/// Struktur (relatif terhadap <pod>/<appDirName>/data/):
///   motorcycles/<motorId>/motor.ttl
///   motorcycles/<motorId>/records/<recordId>.ttl
class OilService {
  OilService(this.webId);

  final String webId;

  static const _root = 'motorcycles';

  static String _motorFile(String id) => '$_root/$id/motor.ttl';
  static String _recordsDir(String id) => '$_root/$id/records';
  static String _recordFile(String motorId, String recordId) =>
      '${_recordsDir(motorId)}/$recordId.ttl';

  // ---------------------------------------------------------------------
  // Antrean (static): semua operasi tulis berjalan satu per satu, apa pun
  // instance MotorcycleService-nya. JANGAN memanggil method publik dari
  // dalam method publik lain (akan deadlock); pakai helper _xxx.
  // ---------------------------------------------------------------------
  static Future<void> _queue = Future.value();

  static Future<T> _sync<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  bool _isNotFound(Object e) {
    final s = e.toString();
    return e.runtimeType.toString() == 'ResourceNotExistException' ||
        s.contains('does not exist') ||
        s.contains('404');
  }

  /// Ambil segmen terakhir dari nama/URL, misalnya ".../abc-123/" -> "abc-123".
  String _lastSegment(String s) =>
      Uri.parse(s).pathSegments.where((e) => e.isNotEmpty).last;

  Future<({List<String> files, List<String> subDirs})> _list(String dir) async {
    try {
      final url = await getDirUrl(dir);
      final res = await getResourcesInContainer(url);
      // SEMENTARA: hapus setelah kamu yakin formatnya.
      debugPrint('LIST $dir -> files=${res.files} subDirs=${res.subDirs}');
      return res;
    } catch (e) {
      const empty = (files: <String>[], subDirs: <String>[]);
      if (_isNotFound(e)) return empty;

      // Container yang belum pernah dibuat bisa muncul sebagai
      // AccessFailedException, bukan ResourceNotExistException. Periksa
      // statusnya dulu supaya 401/403 yang asli tetap dilempar.
      debugPrint('LIST $dir gagal: ${e.runtimeType}: $e');
      try {
        final url = await getDirUrl(dir);
        final status = await checkResourceStatus(url, isFile: false);
        // SEMENTARA: kirim baris ini kalau masih error.
        debugPrint('STATUS $dir ($url) -> $status');
        if (status.name.toLowerCase().contains('not')) return empty;
      } catch (e2) {
        debugPrint('Cek status $dir juga gagal: ${e2.runtimeType}: $e2');
      }
      rethrow;
    }
  }

  Future<Motorcycle?> _readMotor(String id) async {
    try {
      final content = await readPod(_motorFile(id));
      return content.trim().isEmpty ? null : Motorcycle.fromTurtle(content);
    } catch (e) {
      if (_isNotFound(e)) return null;
      rethrow;
    }
  }

  Future<void> _writeMotor(Motorcycle m, {required bool isNew}) => writePod(
    _motorFile(m.id),
    Motorcycle.turtlePrefixes + m.toTurtle(),
    encrypted: false,
    overwrite: true,
    // File ACL hanya dibuat saat motor baru; update tidak menyentuhnya.
    createAcl: isNew,
  );

  Future<List<OilRecord>> _loadRecords(String motorId) async {
    final res = await _list(_recordsDir(motorId));
    final names = res.files.map(_lastSegment).where((n) => n.endsWith('.ttl'));

    final records = await Future.wait(
      names.map((n) async {
        try {
          final content = await readPod('${_recordsDir(motorId)}/$n');
          return OilRecord.fromTurtle(content);
        } catch (e) {
          if (_isNotFound(e)) return null;
          rethrow;
        }
      }),
    );
    return records.whereType<OilRecord>().toList()
      ..sort((a, b) => b.performedAt.compareTo(a.performedAt));
  }

  Future<List<OilRecord>> getOilRecords(String motorId) =>
      _sync(() => _loadRecords(motorId));

  Future<void> addOilRecord(String motorId, OilRecord record) => _sync(
    () async {
      final motor = await _readMotor(motorId);
      if (motor == null) {
        throw StateError('Motor dengan id $motorId tidak ditemukan');
      }

      final rec = record.copyWith(id: const Uuid().v4(), motorcycleId: motorId);
      await writePod(
        _recordFile(motorId, rec.id),
        rec.toTurtleFile(),
        encrypted: false,
      );

      // Metadata di motor (agar cepat di-load di dashboard).
      // Catatan: dua langkah ini TIDAK atomik. Kalau langkah kedua gagal,
      // record tersimpan tapi lastOdometer/lastServiceAt belum ikut berubah.
      await _writeMotor(
        motor.copyWith(
          lastOdometer: rec.odometer,
          lastServiceAt: rec.performedAt,
        ),
        isNew: false,
      );
    },
  );

  Future<void> deleteOilRecord(String motorId, String recordId) =>
      _sync(() async {
        await deleteFile(
          fileUrl: await getFileUrl(_recordFile(motorId, recordId)),
        );

        final motor = await _readMotor(motorId);
        if (motor == null) return;

        final remaining = await _loadRecords(motorId);
        final updated = remaining.isNotEmpty
            ? motor.copyWith(
                lastOdometer: remaining.first.odometer,
                lastServiceAt: remaining.first.performedAt,
              )
            : motor.copyWith(clearLastServiceAt: true);
        await _writeMotor(updated, isNew: false);
      });
}
