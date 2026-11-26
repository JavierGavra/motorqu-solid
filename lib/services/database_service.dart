import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:motorqu_solid/models/family_group.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/services/group_service.dart';
import 'package:motorqu_solid/services/motorcycle_service.dart';
import 'package:motorqu_solid/services/oil_service.dart';

class DatabaseService {
  static DatabaseService? _instance;

  DatabaseService._(this.webId);

  DatabaseService.init(this.webId) {
    _instance = DatabaseService._(webId);
  }

  static bool get isInitialized => _instance != null;

  static void reset() {
    _instance = null;
  }

  factory DatabaseService() => _instance!;

  String webId;

  MotorcycleService get motorcycle => MotorcycleService(webId);

  OilService get oil => OilService(webId);

  GroupService get group => GroupService(webId);

  /// Mengambil seluruh motor yang dapat diakses user (motor pribadi + motor grup).
  Future<List<Motorcycle>> getAllAccessibleMotorcycles() async {
    final motoService = motorcycle;
    final groupService = group;

    final ownMotorsFuture = motoService.getMotorcycles();
    final groupsFuture = groupService.getUserGroupsList().catchError((Object e) {
      debugPrint('Gagal memuat daftar grup untuk motor: $e');
      return const <FamilyGroup>[];
    });

    final ownMotors = await ownMotorsFuture;
    final groups = await groupsFuture;

    final byId = <String, Motorcycle>{
      for (final m in ownMotors) m.id: m,
    };

    if (groups.isNotEmpty) {
      final groupMotorLists = await Future.wait(
        groups.map((g) async {
          try {
            return await groupService.getGroupMotorcycles(g.id);
          } catch (e) {
            debugPrint('Gagal memuat motor grup ${g.id}: $e');
            return const <Motorcycle>[];
          }
        }),
      );

      for (final list in groupMotorLists) {
        for (final gm in list) {
          byId[gm.id] = gm;
        }
      }
    }

    final merged = byId.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Latar belakang, single-flight, tidak pernah melempar error:
    // - permintaan bergabung dari kode undangan (setiap beranda dimuat,
    //   hanya grup yang di-host & undangannya masih aktif);
    // - rekonsiliasi akses penuh (dibatasi 10 menit).
    unawaited(groupService.processPendingJoins(groups));
    unawaited(groupService.syncAccess());

    return merged;
  }
}
