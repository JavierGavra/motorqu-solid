import 'package:flutter_test/flutter_test.dart';
import 'package:motorqu_solid/services/oil_service.dart';

void main() {
  group('OilService.isNewerOrSameRecord', () {
    bool check(DateTime rec, int km, DateTime? last, int lastKm) =>
        OilService.isNewerOrSameRecord(
          recordAt: rec,
          recordOdometer: km,
          lastServiceAt: last,
          lastOdometer: lastKm,
        );

    test('belum pernah servis: selalu diperbarui', () {
      expect(check(DateTime(2026, 1, 1), 100, null, 0), isTrue);
    });

    test('hari setelahnya: diperbarui', () {
      expect(
        check(DateTime(2026, 5, 2), 1000, DateTime(2026, 5, 1, 15), 2000),
        isTrue,
      );
    });

    test('catatan susulan (hari sebelumnya): tidak memundurkan KM', () {
      expect(
        check(DateTime(2026, 4, 30), 9000, DateTime(2026, 5, 1), 2000),
        isFalse,
      );
    });

    test('hari sama, tanggal dari picker (00:00) dengan KM lebih besar', () {
      // Picker mengembalikan jam 00:00, padahal catatan sebelumnya jam 15:00.
      expect(
        check(DateTime(2026, 5, 1), 2500, DateTime(2026, 5, 1, 15), 2000),
        isTrue,
      );
    });

    test('hari sama dengan KM lebih kecil: tidak diperbarui', () {
      expect(
        check(DateTime(2026, 5, 1, 18), 1500, DateTime(2026, 5, 1, 8), 2000),
        isFalse,
      );
    });
  });
}
