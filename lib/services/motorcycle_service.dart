import 'package:flutter/rendering.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/services/group_service.dart';
import 'package:motorqu_solid/services/pod_atomic.dart';
import 'package:motorqu_solid/services/pod_utils.dart';
import 'package:solidpod/solidpod.dart';
import 'package:uuid/uuid.dart';

class MotorcycleService {
  MotorcycleService(this.webId);

  final String webId;
  static const _root = 'motorcycles';

  String _motorPath(String id) => '$_root/$id/motorcycle.ttl';

  /// Semua operasi tulis memakai antrean bersama (reentrant) lintas service.
  Future<T> _sync<T>(Future<T> Function() action) => PodWriteQueue.run(action);

  Future<List<Motorcycle>> _loadMotors() async {
    final ownPrefix = await PodUtils.ownDataRootPrefix();
    final res = await _list(_root);
    final motors = await Future.wait(
      res.subDirs.map(
        (d) => _readMotor(PodUtils.lastSegment(d), ownPrefix: ownPrefix),
      ),
    );
    return motors.whereType<Motorcycle>().toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Hanya untuk membuat file motor BARU. Perubahan motor yang sudah ada
  /// wajib lewat [modifyMotorcycle] agar atomik.
  Future<void> _save(Motorcycle moto, {required bool isNew}) async {
    await writePod(
      _motorPath(moto.id),
      Motorcycle.turtlePrefixes + moto.toTurtle(),
      encrypted: false,
      overwrite: true,
      createAcl: isNew,
    );
  }

  Future<({List<String> files, List<String> subDirs})> _list(String dir) async {
    try {
      final url = await getDirUrl("motorqu-solid/data/$dir");
      final res = await getResourcesInContainer(url);
      return res;
    } catch (e) {
      const empty = (files: <String>[], subDirs: <String>[]);
      if (PodUtils.isNotFound(e)) return empty;
      debugPrint('LIST $dir gagal: ${e.runtimeType}: $e');
      try {
        final url = await getDirUrl(dir);
        final status = await checkResourceStatus(url, isFile: false);
        if (status.name.toLowerCase().contains('not')) return empty;
      } catch (e2) {
        debugPrint('Cek status $dir juga gagal: ${e2.runtimeType}: $e2');
      }
      rethrow;
    }
  }

  Future<Motorcycle?> _readMotor(String id, {String? ownPrefix}) async {
    try {
      final content = await readPod(_motorPath(id));
      if (content.trim().isEmpty) return null;
      final prefix = ownPrefix ?? await PodUtils.ownDataRootPrefix();
      return Motorcycle.fromTurtle(
        content,
      ).copyWith(resourceUrl: '$prefix${_motorPath(id)}');
    } catch (e) {
      if (PodUtils.isNotFound(e)) return null;
      rethrow;
    }
  }

  Future<Motorcycle?> _readMotorByUrl(String resourceUrl) async {
    try {
      final isExt = await PodUtils.isExternalUrl(resourceUrl);
      final ownPrefix = await PodUtils.ownDataRootPrefix();
      final content = isExt
          ? await readExternalPod(resourceUrl)
          : await readPod(resourceUrl.substring(ownPrefix.length));
      if (content.trim().isEmpty) return null;
      return Motorcycle.fromTurtle(content).copyWith(resourceUrl: resourceUrl);
    } catch (e) {
      if (PodUtils.isNotFound(e)) return null;
      rethrow;
    }
  }

  /// Pembacaan murni: tidak lewat antrean tulis.
  Future<List<Motorcycle>> getMotorcycles() => _loadMotors();

  Future<Motorcycle?> getMotorcycle(String id, {String? resourceUrl}) =>
      (resourceUrl != null && resourceUrl.isNotEmpty)
      ? _readMotorByUrl(resourceUrl)
      : _readMotor(id);

  Future<String> addMotorcycle(Motorcycle moto) async {
    try {
      final id = const Uuid().v4();
      final wantsGroup =
          moto.isGroupMotor &&
          moto.groupId.isNotEmpty &&
          moto.groupId != 'private';
      final data = moto.copyWith(
        id: id,
        createdBy: webId,
        createdAt: DateTime.now().toUtc(),
        groupId: 'private',
        isGroupMotor: false,
        memberUids: [webId],
      );

      await _sync(() => _save(data, isNew: false));
      if (wantsGroup) {
        await GroupService(webId).assignMotorcycleToGroup(id, moto.groupId);
      }
      return id;
    } catch (e) {
      debugPrint('Error adding motorcycle: $e');
      rethrow;
    }
  }

  /// Ubah motor secara atomik (ETag + If-Match), baik di Pod sendiri maupun
  /// Pod anggota grup lain. [change] selalu menerima data TERBARU dari server
  /// dan bisa dipanggil ulang bila terjadi konflik.
  Future<void> modifyMotorcycle(
    String id,
    Motorcycle Function(Motorcycle current) change, {
    String? resourceUrl,
  }) => _sync(() async {
    final url = (resourceUrl != null && resourceUrl.isNotEmpty)
        ? resourceUrl
        : '${await PodUtils.ownDataRootPrefix()}${_motorPath(id)}';

    try {
      await PodAtomicWriter.instance.update(url, (content) {
        if (content.trim().isEmpty) {
          throw StateError('Motor dengan id $id tidak ditemukan');
        }
        final current = Motorcycle.fromTurtle(
          content,
        ).copyWith(resourceUrl: url);
        return Motorcycle.turtlePrefixes + change(current).toTurtle();
      }, ownerWebId: PodUtils.resolveOwnerWebId(url, fallback: webId));
    } catch (e) {
      if (PodUtils.isNotFound(e)) {
        throw StateError('Motor dengan id $id tidak ditemukan');
      }
      rethrow;
    }
  });

  /// Simpan hasil form Edit Motor.
  ///
  /// Hanya field yang bisa diedit di form yang disalin ke data terbaru dari
  /// server, supaya `lastOdometer`/`lastServiceAt` yang baru dicatat anggota
  /// lain tidak tertimpa oleh salinan lama di layar edit.
  Future<void> updateMotorcycle(Motorcycle edited) => modifyMotorcycle(
    edited.id,
    (current) => current.copyWith(
      name: edited.name,
      brand: edited.brand,
      model: edited.model,
      plate: edited.plate,
      year: edited.year,
      color: edited.color,
      clearPlate: edited.plate == null,
      clearYear: edited.year == null,
      clearColor: edited.color == null,
      reminderIntervalKm: edited.reminderIntervalKm,
    ),
    resourceUrl: edited.resourceUrl,
  );

  Future<void> deleteMotorcycle(String id) async {
    try {
      final current = await _readMotor(id);
      if (current != null &&
          current.isGroupMotor &&
          current.groupId.isNotEmpty &&
          current.groupId != 'private') {
        await GroupService(webId).removeMotorcycleFromGroup(id);
      }
    } catch (e) {
      debugPrint('Warning cleanup grup saat hapus motor $id: $e');
    }
    await _sync(() => deleteContainer(_root, id));
  }
}
