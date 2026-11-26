import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/motorcycle.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const String prefsKeyEnabled = 'notifications_enabled';
  static const int testNotificationId = 999;

  static const String _channelId = 'motorqu_reminder';
  static const String _channelName = 'Pengingat Ganti Oli';
  static const String _channelDesc = 'Notifikasi cek oli tiap 30 hari';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _enabled = true;
  DateTime? _lastSyncTime;
  String? _pendingMotorId;
  void Function(String motorId)? _onNotificationTap;

  bool get isEnabled => _enabled;

  /// Menghasilkan ID integer 31-bit positif yang deterministik lintas sesi
  /// (berbeda dengan `String.hashCode` yang bisa berubah antar restart VM).
  static int notificationIdFor(String motorId) {
    var hash = 0x811c9dc5;
    for (final unit in motorId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash == testNotificationId ? testNotificationId + 1 : hash;
  }

  /// Menghitung jadwal pengingat berikutnya (30 hari sejak servis/dibuat,
  /// atau +1 jam jika sudah jatuh tempo).
  static DateTime computeScheduledTimeForDate(
    DateTime baseDate, {
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final dueDate = baseDate.toLocal().add(const Duration(days: 30));
    if (dueDate.isAfter(current)) {
      return dueDate;
    }
    return current.add(const Duration(hours: 1));
  }

  static DateTime computeNextReminderTime(Motorcycle moto, {DateTime? now}) {
    final baseDate = moto.lastServiceAt ?? moto.createdAt;
    return computeScheduledTimeForDate(baseDate, now: now);
  }

  Future<void> init({void Function(String motorId)? onNotificationTap}) async {
    if (onNotificationTap != null) {
      _onNotificationTap = onNotificationTap;
    }
    if (_initialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(prefsKeyEnabled) ?? true;
    } catch (_) {}

    try {
      tzdata.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
      } catch (_) {
        // Fallback ke lokasi default bila zona waktu tidak dikenal.
      }

      const initSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            _handleTap(payload);
          }
        },
      );

      // Tangani kasus aplikasi dibuka dari ketukan notifikasi saat terminated.
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      final launchPayload = launchDetails?.notificationResponse?.payload;
      if (launchDetails?.didNotificationLaunchApp == true &&
          launchPayload != null &&
          launchPayload.isNotEmpty) {
        _pendingMotorId = launchPayload;
        _onNotificationTap?.call(launchPayload);
      }

      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidImpl?.requestNotificationsPermission();

      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );
      await androidImpl?.createNotificationChannel(channel);

      _initialized = true;
    } catch (_) {
      // Jangan gagalkan startup aplikasi bila environment tidak mendukung plugin.
    }
  }

  void _handleTap(String payload) {
    _pendingMotorId = payload;
    _onNotificationTap?.call(payload);
  }

  void setPendingMotorId(String? motorId) {
    _pendingMotorId = (motorId == null || motorId.isEmpty) ? null : motorId;
  }

  String? consumePendingMotorId() {
    final pending = _pendingMotorId;
    _pendingMotorId = null;
    return pending;
  }

  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
      _lastSyncTime = null;
    }
  }

  void resetSyncThrottle() {
    _lastSyncTime = null;
  }

  @visibleForTesting
  void resetForTest() {
    _initialized = false;
    _enabled = true;
    _lastSyncTime = null;
    _pendingMotorId = null;
    _onNotificationTap = null;
  }

  Future<bool> requestPermission() async {
    try {
      if (!_initialized) await init();
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      return granted ?? true;
    } catch (_) {
      return true;
    }
  }

  NotificationDetails _notificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    return const NotificationDetails(android: androidDetails);
  }

  Future<void> showTestNotification() async {
    try {
      if (!_initialized) await init();
      await _plugin.show(
        testNotificationId,
        'Pengingat Ganti Oli MotorQu',
        'Notifikasi pengingat berfungsi dengan baik!',
        _notificationDetails(),
      );
    } catch (_) {}
  }

  /// Sinkronisasi jadwal pengingat untuk seluruh motor (pribadi dan grup).
  Future<void> syncReminders(
    List<Motorcycle> motorcycles, {
    bool force = false,
  }) async {
    if (!_enabled) return;
    final now = DateTime.now();
    if (!force &&
        _lastSyncTime != null &&
        now.difference(_lastSyncTime!).inMinutes < 15) {
      return;
    }
    _lastSyncTime = now;

    try {
      if (!_initialized) await init();

      final details = _notificationDetails();

      for (final moto in motorcycles) {
        final scheduledLocal = computeNextReminderTime(moto, now: now);
        final scheduledTz = tz.TZDateTime.from(scheduledLocal, tz.local);
        final targetFormatted = NumberFormat('#,###').format(moto.nextDueKm);

        await _plugin.zonedSchedule(
          notificationIdFor(moto.id),
          'Cek oli ${moto.name}',
          'Jika KM motor ${moto.name} sudah lebih dari ${targetFormatted}KM, jangan lupa ganti oli yaa',
          scheduledTz,
          details,
          payload: moto.id,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (_) {}
  }

  Future<void> scheduleOilReminder({
    required String motorId,
    required String title,
    required String body,
    DateTime? performedAt,
  }) async {
    if (!_enabled) return;
    try {
      if (!_initialized) await init();

      final scheduledLocal = computeScheduledTimeForDate(
        performedAt ?? DateTime.now(),
      );
      final when = tz.TZDateTime.from(scheduledLocal, tz.local);

      await _plugin.zonedSchedule(
        notificationIdFor(motorId),
        title,
        body,
        when,
        _notificationDetails(),
        payload: motorId,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Notifikasi lokal tidak boleh menggagalkan proses penyimpanan data.
    }
  }

  Future<void> cancelForMotor(String motorId) =>
      cancel(notificationIdFor(motorId));

  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id & 0x7FFFFFFF);
    } catch (_) {}
  }

  Future<void> cancelAll() async {
    _lastSyncTime = null;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
