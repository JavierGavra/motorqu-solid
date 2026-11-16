import 'package:flutter/rendering.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:solidpod/solidpod.dart';
import 'package:uuid/uuid.dart';

class MotorcycleService {
  MotorcycleService(this.webId);

  final String webId;
  static const _root = 'motorcycles';

  String _motorPath(String id) => '$_root/$id/motorcycle.ttl';

  Future<void> _queue = Future.value();

  Future<T> _sync<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  bool _isNotFound(Object e) {
    final s = e.toString();
    return e.runtimeType.toString() == 'ResourceNotExistException' ||
        s.contains('does not exist') ||
        s.contains('404');
  }

  String _lastSegment(String s) =>
      Uri.parse(s).pathSegments.where((e) => e.isNotEmpty).last;

  Future<List<Motorcycle>> _loadMotors() async {
    final res = await _list(_root);
    final motors = await Future.wait(
      res.subDirs.map((d) => _readMotor(_lastSegment(d))),
    );
    return motors.whereType<Motorcycle>().toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

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
      if (_isNotFound(e)) return empty;
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

  Future<Motorcycle?> _readMotor(String id) async {
    try {
      final content = await readPod(_motorPath(id));
      return content.trim().isEmpty ? null : Motorcycle.fromTurtle(content);
    } catch (e) {
      if (_isNotFound(e)) return null;
      rethrow;
    }
  }

  Future<List<Motorcycle>> getMotorcycles() => _sync(_loadMotors);

  Future<Motorcycle?> getMotorcycle(String id) => _sync(() => _readMotor(id));

  Future<String> addMotorcycle(Motorcycle moto) async {
    try {
      final id = const Uuid().v4();
      final data = moto.copyWith(
        id: id,
        createdBy: webId,
        createdAt: DateTime.now().toUtc(),
        groupId: 'private',
        isGroupMotor: false,
        memberUids: [webId],
      );

      await _save(data, isNew: false);
      return id;
    } catch (e) {
      debugPrint('Error adding motorcycle: $e');
      rethrow;
    }
  }

  Future<void> modifyMotorcycle(
    String id,
    Motorcycle Function(Motorcycle current) change,
  ) => _sync(() async {
    final current = await _readMotor(id);
    if (current == null) {
      throw StateError('Motor dengan id $id tidak ditemukan');
    }
    await _save(change(current), isNew: false);
  });

  Future<void> updateMotorcycle(Motorcycle updated) =>
      modifyMotorcycle(updated.id, (_) => updated);

  Future<void> deleteMotorcycle(String id) async {
    await deleteContainer(_root, id);
  }
}
