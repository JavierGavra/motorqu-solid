import 'package:flutter/material.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/navigation_observer.dart';
import 'package:motorqu_solid/services/database_service.dart';
import 'package:motorqu_solid/services/notification_service.dart';
import 'package:motorqu_solid/theme/app_theme.dart';
import 'package:motorqu_solid/ui/pages/add_motor_page.dart';
import 'package:motorqu_solid/ui/pages/add_oil_page.dart';
import 'package:motorqu_solid/ui/pages/bottom_navigation.dart';
import 'package:motorqu_solid/ui/pages/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(
  ThemeMode.system,
);

void _handleNotificationTap(String motorId) {
  if (motorId.isEmpty) return;
  if (DatabaseService.isInitialized && navigatorKey.currentState != null) {
    NotificationService().consumePendingMotorId();
    navigatorKey.currentState?.pushNamed('/addOil', arguments: motorId);
  } else {
    NotificationService().setPendingMotorId(motorId);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString('theme_mode') ?? 'system';
    themeModeNotifier.value = switch (savedTheme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  } catch (_) {}

  await NotificationService().init(onNotificationTap: _handleNotificationTap);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'MotorQu',
          debugShowCheckedModeBanner: false,
          navigatorObservers: [routeObserver],
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeMode,
          home: const LoginPage(),
          routes: {
            '/login': (context) => const LoginPage(),
            '/home': (context) => BottomNavigation(),
            '/addMotor': (context) {
              final moto =
                  ModalRoute.of(context)?.settings.arguments as Motorcycle?;
              return AddMotorPage(moto: moto);
            },
            '/addOil': (context) {
              final id = ModalRoute.of(context)?.settings.arguments as String?;
              return AddOilPage(preselectMotorId: id);
            },
          },
        );
      },
    );
  }
}
