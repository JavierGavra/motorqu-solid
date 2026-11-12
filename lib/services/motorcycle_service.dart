import 'package:flutter/rendering.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:solidpod/solidpod.dart';
import 'package:uuid/uuid.dart';

class MotorcycleService {
  MotorcycleService(this.webId);

  final String webId;
  static const _path = 'motorcycles/motorcycles.ttl';

  Future<void> _queue = Future.value();

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<Motorcycle>> _load() async {
    final dynamic content;
    try {
      content = await readPod(_path);
    } catch (e) {
      if (e.runtimeType.toString() == 'ResourceNotExistException') return [];
      rethrow;
    }
    if (content is String) {
      return content.trim().isEmpty ? [] : Motorcycle.listFromTurtle(content);
    }
    throw StateError('readPod mengembalikan ${content.runtimeType}: $content');
  }

  Future<void> _save(List<Motorcycle> list) async {
    await writePod(
      _path,
      Motorcycle.listToTurtle(list),
      encrypted: false,
      overwrite: true,
    );
  }

  Future<List<Motorcycle>> getMotorcycles() => _load();

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

      final list = await _load();
      list.add(data);
      await _save(list);
      return id;
    } catch (e) {
      debugPrint('Error adding motorcycle: $e');
      rethrow;
    }
  }

  Future<void> updateMotorcycle(Motorcycle updated) => _synchronized(() async {
    final list = await _load();
    final i = list.indexWhere((m) => m.id == updated.id);
    if (i == -1) {
      throw StateError('Motor dengan id ${updated.id} tidak ditemukan');
    }
    list[i] = updated;
    await _save(list);
  });

  Future<void> deleteMotorcycle(String id) async {
    final list = await _load();
    list.removeWhere((m) => m.id == id);
    await _save(list);
  }
}
