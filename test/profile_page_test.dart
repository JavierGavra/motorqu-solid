import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motorqu_solid/services/notification_service.dart';
import 'package:motorqu_solid/ui/pages/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    NotificationService().resetForTest();
  });

  testWidgets('ProfilePage toggles notification preference and opens reminder dialog', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'notifications_enabled': true});

    await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
    await tester.pumpAndSettle();

    expect(find.text('Pengingat Ganti Oli'), findsOneWidget);
    expect(find.text('Aktif berkala setiap 30 hari'), findsOneWidget);

    await tester.scrollUntilVisible(find.byType(SwitchListTile), 200);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(NotificationService().isEnabled, isFalse);
    expect(find.text('Nonaktif (alarm oli dimatikan)'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('notifications_enabled'), isFalse);

    await tester.scrollUntilVisible(
      find.text('Informasi & Tes Notifikasi'),
      200,
    );
    await tester.tap(find.text('Informasi & Tes Notifikasi'));
    await tester.pumpAndSettle();

    expect(find.text('Kirim Tes'), findsOneWidget);
    await tester.tap(find.text('Kirim Tes'));
    await tester.pumpAndSettle();

    expect(
      find.text('Notifikasi uji coba dikirim! Periksa panel notifikasi HP.'),
      findsOneWidget,
    );
  });
}
