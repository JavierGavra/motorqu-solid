import 'package:flutter_test/flutter_test.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/services/database_service.dart';

void main() {
  group('Motorcycle model & DatabaseService lifecycle', () {
    test('Motorcycle roundtrips Turtle and preserves runtime resourceUrl via copyWith', () {
      final created = DateTime.utc(2026, 10, 1, 10, 0);
      final serviceAt = DateTime.utc(2026, 10, 15, 12, 0);
      final moto = Motorcycle(
        id: 'm-100',
        name: 'Beat Merah',
        brand: 'Honda',
        model: 'BeAT',
        plate: 'B 1234 XYZ',
        year: '2022',
        color: 'Merah',
        groupId: 'grp-1',
        isGroupMotor: true,
        reminderIntervalKm: 2500,
        lastOdometer: 15000,
        lastServiceAt: serviceAt,
        memberUids: const ['https://pod.a/profile/card#me'],
        createdBy: 'https://pod.a/profile/card#me',
        createdAt: created,
        resourceUrl:
            'https://pod.a/user/motorqu-solid/data/motorcycles/m-100/motorcycle.ttl',
      );

      expect(moto.nextDueKm, equals(17500));

      final turtle = Motorcycle.turtlePrefixes + moto.toTurtle();
      expect(turtle, isNot(contains('resourceUrl')));

      final parsed = Motorcycle.fromTurtle(turtle).copyWith(
        resourceUrl: moto.resourceUrl,
      );
      expect(parsed.id, equals(moto.id));
      expect(parsed.name, equals(moto.name));
      expect(parsed.groupId, equals('grp-1'));
      expect(parsed.isGroupMotor, isTrue);
      expect(parsed.nextDueKm, equals(17500));
      expect(parsed.resourceUrl, equals(moto.resourceUrl));

      final cleared = parsed.copyWith(clearResourceUrl: true);
      expect(cleared.resourceUrl, isNull);
    });

    test('DatabaseService.isInitialized tracks init and reset state', () {
      DatabaseService.reset();
      expect(DatabaseService.isInitialized, isFalse);

      DatabaseService.init('https://example.pod/alice/profile/card#me');
      expect(DatabaseService.isInitialized, isTrue);
      expect(
        DatabaseService().webId,
        equals('https://example.pod/alice/profile/card#me'),
      );

      DatabaseService.reset();
      expect(DatabaseService.isInitialized, isFalse);
    });
  });
}
