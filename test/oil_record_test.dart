import 'package:flutter_test/flutter_test.dart';
import 'package:motorqu_solid/models/oil_record.dart';

void main() {
  group('OilRecord Turtle Serialization', () {
    test('toTurtle and fromTurtle match correctly', () {
      final now = DateTime.utc(2026, 10, 1, 8, 30);
      final record = OilRecord(
        id: 'rec-12345',
        motorcycleId: 'moto-67890',
        performedAt: now,
        odometer: 15400,
        performedBy: 'https://solidcommunity.au/user/profile/card#me',
        performedByName: 'Ridlo Firmansyah',
        createdAt: now,
      );

      final turtleFile = record.toTurtleFile();
      expect(turtleFile, contains('<#record-rec-12345>'));
      expect(turtleFile, contains('moto:motorcycleId "moto-67890"'));
      expect(turtleFile, contains('moto:odometer 15400'));
      expect(turtleFile, contains('Ridlo Firmansyah'));

      final parsed = OilRecord.fromTurtle(turtleFile);
      expect(parsed.id, equals(record.id));
      expect(parsed.motorcycleId, equals(record.motorcycleId));
      expect(parsed.odometer, equals(15400));
      expect(parsed.performedBy, equals(record.performedBy));
      expect(parsed.performedByName, equals('Ridlo Firmansyah'));
      expect(parsed.performedAt.toIso8601String(), equals(now.toIso8601String()));
    });
  });
}
