import 'package:flutter_test/flutter_test.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/services/notification_service.dart';

void main() {
  group('NotificationService', () {
    setUp(() {
      NotificationService().resetForTest();
    });

    test('notificationIdFor is deterministic, 31-bit positive, and avoids 999', () {
      const idA = '550e8400-e29b-41d4-a716-446655440000';
      const idB = '550e8400-e29b-41d4-a716-446655440001';

      final hashA1 = NotificationService.notificationIdFor(idA);
      final hashA2 = NotificationService.notificationIdFor(idA);
      final hashB = NotificationService.notificationIdFor(idB);

      expect(hashA1, equals(hashA2));
      expect(hashA1, isNonNegative);
      expect(hashA1, lessThanOrEqualTo(0x7FFFFFFF));
      expect(hashA1, isNot(equals(NotificationService.testNotificationId)));
      expect(hashB, isNot(equals(hashA1)));
    });

    test('computeNextReminderTime schedules +30 days when not yet due', () {
      final now = DateTime(2026, 11, 26, 8, 0);
      final lastService = DateTime(2026, 11, 10, 14, 30);
      final moto = Motorcycle(
        id: 'moto-1',
        name: 'Vario 160',
        brand: 'Honda',
        model: 'Vario',
        groupId: 'private',
        createdBy: 'https://example.pod/u/profile/card#me',
        createdAt: DateTime(2026, 1, 1),
        lastServiceAt: lastService,
      );

      final scheduled = NotificationService.computeNextReminderTime(
        moto,
        now: now,
      );

      expect(scheduled, equals(lastService.add(const Duration(days: 30))));
    });

    test('computeNextReminderTime falls back to createdAt when lastServiceAt is null', () {
      final now = DateTime(2026, 11, 26, 8, 0);
      final createdAt = DateTime(2026, 11, 20, 9, 0);
      final moto = Motorcycle(
        id: 'moto-2',
        name: 'Beat',
        brand: 'Honda',
        model: 'Beat CBS',
        groupId: 'private',
        createdBy: 'https://example.pod/u/profile/card#me',
        createdAt: createdAt,
      );

      final scheduled = NotificationService.computeNextReminderTime(
        moto,
        now: now,
      );

      expect(scheduled, equals(createdAt.add(const Duration(days: 30))));
    });

    test('computeNextReminderTime schedules +1 hour when overdue (>= 30 days)', () {
      final now = DateTime(2026, 11, 26, 8, 0);
      final oldService = DateTime(2026, 10, 1, 8, 0);
      final moto = Motorcycle(
        id: 'moto-3',
        name: 'NMax',
        brand: 'Yamaha',
        model: 'NMax 155',
        groupId: 'private',
        createdBy: 'https://example.pod/u/profile/card#me',
        createdAt: oldService,
        lastServiceAt: oldService,
      );

      final scheduled = NotificationService.computeNextReminderTime(
        moto,
        now: now,
      );

      expect(scheduled, equals(now.add(const Duration(hours: 1))));
    });

    test('pending motorId is consumed once and empty values are ignored', () {
      final notif = NotificationService();
      expect(notif.consumePendingMotorId(), isNull);

      notif.setPendingMotorId('');
      expect(notif.consumePendingMotorId(), isNull);

      notif.setPendingMotorId('moto-xyz');
      expect(notif.consumePendingMotorId(), equals('moto-xyz'));
      expect(notif.consumePendingMotorId(), isNull);
    });

    test('setEnabled toggles enabled state', () {
      final notif = NotificationService();
      expect(notif.isEnabled, isTrue);
      notif.setEnabled(false);
      expect(notif.isEnabled, isFalse);
      notif.setEnabled(true);
      expect(notif.isEnabled, isTrue);
    });
  });
}
