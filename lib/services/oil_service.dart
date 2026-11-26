import 'package:flutter/foundation.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/models/oil_record.dart';
import 'package:motorqu_solid/services/pod_atomic.dart';
import 'package:motorqu_solid/services/pod_utils.dart';
import 'package:solidpod/solidpod.dart';
import 'package:uuid/uuid.dart';

/// Penyimpanan riwayat oli di Pod Solid.
///
/// Struktur (relatif terhadap `pod/appDirName/data/`):
///   `motorcycles/<motorId>/motorcycle.ttl`
///   `motorcycles/<motorId>/records/<recordId>.ttl`
class OilService {
  OilService(this.webId);

  final String webId;

  static const _root = 'motorcycles';

  static String _motorFile(String id) => '$_root/$id/motorcycle.ttl';
  static String _recordsDir(String id) => '$_root/$id/records';
  static String _recordFile(String motorId, String recordId) =>
      '${_recordsDir(motorId)}/$recordId.ttl';

  /// Semua operasi tulis memakai antrean bersama (reentrant) lintas service.
  static Future<T> _sync<T>(Future<T> Function() action) =>
      PodWriteQueue.run(action);

  String _motorDirUrlFromFileUrl(String motorFileUrl) {
    final idx = motorFileUrl.lastIndexOf('/');
    return idx >= 0 ? motorFileUrl.substring(0, idx + 1) : '$motorFileUrl/';
  }

  /// URL penuh motorcycle.ttl (Pod sendiri bila [motorResourceUrl] kosong).
  Future<String> _motorUrl(String motorId, String? motorResourceUrl) async =>
      (motorResourceUrl != null && motorResourceUrl.isNotEmpty)
      ? motorResourceUrl
      : '${await PodUtils.ownDataRootPrefix()}${_motorFile(motorId)}';

  Future<({List<String> files, List<String> subDirs})> _listContainerUrl(
    String containerUrl,
  ) async {
    try {
      final res = await getResourcesInContainer(containerUrl);
      return res;
    } catch (e) {
      const empty = (files: <String>[], subDirs: <String>[]);
      if (PodUtils.isNotFound(e)) return empty;
      try {
        final status = await checkResourceStatus(containerUrl, isFile: false);
        if (status.name.toLowerCase().contains('not')) return empty;
      } catch (_) {}
      rethrow;
    }
  }

  Future<({List<String> files, List<String> subDirs})> _list(String dir) async {
    try {
      final url = await getDirUrl("motorqu-solid/data/$dir");
      final res = await getResourcesInContainer(url);
      return res;
    } catch (e) {
      const empty = (files: <String>[], subDirs: <String>[]);
      if (PodUtils.isNotFound(e)) return empty;

      // Container yang belum pernah dibuat bisa muncul sebagai
      // AccessFailedException, bukan ResourceNotExistException. Periksa
      // statusnya dulu supaya 401/403 yang asli tetap dilempar.
      debugPrint('LIST $dir gagal: ${e.runtimeType}: $e');
      try {
        final url = await getDirUrl("motorqu-solid/data/$dir");
        final status = await checkResourceStatus(url, isFile: false);
        if (status.name.toLowerCase().contains('not')) return empty;
      } catch (e2) {
        debugPrint('Cek status $dir juga gagal: ${e2.runtimeType}: $e2');
      }
      rethrow;
    }
  }

  Future<Motorcycle?> _readMotor(String id, {String? motorResourceUrl}) async {
    try {
      final isExt = await PodUtils.isExternalUrl(motorResourceUrl);
      final content = (isExt && motorResourceUrl != null)
          ? await readExternalPod(motorResourceUrl)
          : await readPod(_motorFile(id));
      if (content.trim().isEmpty) return null;
      return Motorcycle.fromTurtle(
        content,
      ).copyWith(resourceUrl: motorResourceUrl);
    } catch (e) {
      if (PodUtils.isNotFound(e)) return null;
      rethrow;
    }
  }

  /// Ubah metadata motor secara atomik (ETag + If-Match).
  Future<void> _updateMotor(
    String motorId,
    String? motorResourceUrl,
    Future<Motorcycle?> Function(Motorcycle current) change,
  ) async {
    final url = await _motorUrl(motorId, motorResourceUrl);
    await PodAtomicWriter.instance.update(url, (content) async {
      if (content.trim().isEmpty) return null;
      final next = await change(Motorcycle.fromTurtle(content));
      return next == null ? null : Motorcycle.turtlePrefixes + next.toTurtle();
    }, ownerWebId: PodUtils.resolveOwnerWebId(url, fallback: webId));
  }

  Future<List<OilRecord>> _loadRecords(
    String motorId, {
    String? motorResourceUrl,
  }) async {
    final isExt = await PodUtils.isExternalUrl(motorResourceUrl);
    if (isExt && motorResourceUrl != null) {
      final recordsDirUrl =
          '${_motorDirUrlFromFileUrl(motorResourceUrl)}records/';
      final res = await _listContainerUrl(recordsDirUrl);
      final names = res.files
          .map(PodUtils.lastSegment)
          .where((n) => n.endsWith('.ttl'));
      final records = await Future.wait(
        names.map((n) async {
          try {
            final content = await readExternalPod('$recordsDirUrl$n');
            return OilRecord.fromTurtle(content);
          } catch (e) {
            if (PodUtils.isNotFound(e)) return null;
            rethrow;
          }
        }),
      );
      return records.whereType<OilRecord>().toList()
        ..sort((a, b) => b.performedAt.compareTo(a.performedAt));
    }

    final res = await _list(_recordsDir(motorId));
    final names = res.files
        .map(PodUtils.lastSegment)
        .where((n) => n.endsWith('.ttl'));

    final records = await Future.wait(
      names.map((n) async {
        try {
          final content = await readPod('${_recordsDir(motorId)}/$n');
          return OilRecord.fromTurtle(content);
        } catch (e) {
          if (PodUtils.isNotFound(e)) return null;
          rethrow;
        }
      }),
    );
    return records.whereType<OilRecord>().toList()
      ..sort((a, b) => b.performedAt.compareTo(a.performedAt));
  }

  /// Apakah record baru boleh memperbarui `lastOdometer`/`lastServiceAt`.
  ///
  /// Dibandingkan per HARI kalender (date picker mengembalikan jam 00:00,
  /// sedangkan default form memakai jam sekarang). Pada hari yang sama,
  /// record dianggap terbaru bila KM-nya tidak lebih kecil.
  @visibleForTesting
  static bool isNewerOrSameRecord({
    required DateTime recordAt,
    required int recordOdometer,
    required DateTime? lastServiceAt,
    required int lastOdometer,
  }) {
    if (lastServiceAt == null) return true;
    DateTime day(DateTime d) {
      final l = d.toLocal();
      return DateTime(l.year, l.month, l.day);
    }

    final recDay = day(recordAt);
    final lastDay = day(lastServiceAt);
    if (recDay.isAfter(lastDay)) return true;
    if (recDay.isBefore(lastDay)) return false;
    return recordOdometer >= lastOdometer;
  }

  /// Pembacaan murni: tidak lewat antrean tulis.
  Future<List<OilRecord>> getOilRecords(
    String motorId, {
    String? motorResourceUrl,
  }) => _loadRecords(motorId, motorResourceUrl: motorResourceUrl);

  Future<void> addOilRecord(
    String motorId,
    OilRecord record, {
    String? motorResourceUrl,
  }) => _sync(() async {
    final motor = await _readMotor(motorId, motorResourceUrl: motorResourceUrl);
    if (motor == null) {
      throw StateError('Motor dengan id $motorId tidak ditemukan');
    }

    final rec = record.copyWith(id: const Uuid().v4(), motorcycleId: motorId);
    final isExt = await PodUtils.isExternalUrl(motorResourceUrl);

    // Record selalu file baru dengan UUID unik, jadi tidak bisa bentrok.
    if (isExt && motorResourceUrl != null) {
      final recordsDirUrl =
          '${_motorDirUrlFromFileUrl(motorResourceUrl)}records/';
      final ownerWebId = PodUtils.resolveOwnerWebId(
        motorResourceUrl,
        fallback: motor.createdBy.isNotEmpty ? motor.createdBy : webId,
      );
      await writeExternalPod(
        '$recordsDirUrl${rec.id}.ttl',
        rec.toTurtleFile(),
        ownerWebId,
        encrypted: false,
        overwrite: true,
      );
    } else {
      await writePod(
        _recordFile(motorId, rec.id),
        rec.toTurtleFile(),
        encrypted: false,
        // Jangan buat ACL terpisah per record agar tetap mewarisi ACL folder motor saat motor di-share ke grup.
        createAcl: false,
      );
    }

    // Metadata di motor (agar cepat di-load di dashboard), atomik.
    // Hanya diperbarui bila record ini yang paling baru, supaya catatan
    // susulan (tanggal lampau) tidak memundurkan lastOdometer.
    // Catatan: record & metadata tetap dua langkah terpisah (tidak atomik
    // bersama). Bila langkah ini gagal, hapus/tambah record berikutnya akan
    // menghitung ulang metadata.
    await _updateMotor(motorId, motorResourceUrl, (current) async {
      if (!isNewerOrSameRecord(
        recordAt: rec.performedAt,
        recordOdometer: rec.odometer,
        lastServiceAt: current.lastServiceAt,
        lastOdometer: current.lastOdometer,
      )) {
        return null;
      }
      return current.copyWith(
        lastOdometer: rec.odometer,
        lastServiceAt: rec.performedAt,
      );
    });
  });

  Future<void> deleteOilRecord(
    String motorId,
    String recordId, {
    String? motorResourceUrl,
  }) => _sync(() async {
    final isExt = await PodUtils.isExternalUrl(motorResourceUrl);
    final motor = await _readMotor(motorId, motorResourceUrl: motorResourceUrl);

    if (isExt && motorResourceUrl != null) {
      final recordsDirUrl =
          '${_motorDirUrlFromFileUrl(motorResourceUrl)}records/';
      final ownerWebId = PodUtils.resolveOwnerWebId(
        motorResourceUrl,
        fallback: (motor?.createdBy.isNotEmpty ?? false)
            ? motor!.createdBy
            : webId,
      );
      await deleteFile(
        fileUrl: '$recordsDirUrl$recordId.ttl',
        ownerWebId: ownerWebId,
      );
    } else {
      await deleteFile(
        fileUrl: await getFileUrl(
          "motorqu-solid/data/${_recordFile(motorId, recordId)}",
        ),
      );
    }

    if (motor == null) return;

    // Hitung ulang dari record yang tersisa DI DALAM transformasi, sehingga
    // saat retry (konflik) daftar record juga dibaca ulang.
    await _updateMotor(motorId, motorResourceUrl, (current) async {
      final remaining = await _loadRecords(
        motorId,
        motorResourceUrl: motorResourceUrl,
      );
      return remaining.isNotEmpty
          ? current.copyWith(
              lastOdometer: remaining.first.odometer,
              lastServiceAt: remaining.first.performedAt,
            )
          : current.copyWith(clearLastServiceAt: true);
    });
  });
}
