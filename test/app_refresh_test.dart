import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motorqu_solid/services/app_refresh.dart';

class _Probe extends StatefulWidget {
  const _Probe({required this.visible, required this.onRefresh});

  final ValueNotifier<bool> visible;
  final Future<void> Function() onRefresh;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with AutoRefreshMixin<_Probe> {
  @override
  Duration get autoRefreshMaxAge => const Duration(minutes: 2);

  @override
  bool get isAutoRefreshVisible => widget.visible.value;

  @override
  Future<void> autoRefresh() => widget.onRefresh();

  @override
  void initState() {
    super.initState();
    markLoaded(); // seolah data baru saja dimuat saat halaman dibuka
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  group('AppRefresh.shouldRefresh', () {
    final now = DateTime(2026, 11, 26, 12);
    const maxAge = Duration(minutes: 2);

    test('belum pernah dimuat: selalu refresh', () {
      expect(
        AppRefresh.shouldRefresh(
          reason: RefreshReason.periodic,
          lastLoadedAt: null,
          now: now,
          maxAge: maxAge,
        ),
        isTrue,
      );
    });

    test('periodic: hanya bila lebih tua dari maxAge halaman', () {
      bool check(Duration age) => AppRefresh.shouldRefresh(
        reason: RefreshReason.periodic,
        lastLoadedAt: now.subtract(age),
        now: now,
        maxAge: maxAge,
      );
      expect(check(const Duration(seconds: 30)), isFalse);
      expect(check(const Duration(minutes: 2)), isTrue);
    });

    test('resumed: ambang lebih pendek (15 detik)', () {
      bool check(Duration age) => AppRefresh.shouldRefresh(
        reason: RefreshReason.resumed,
        lastLoadedAt: now.subtract(age),
        now: now,
        maxAge: maxAge,
      );
      expect(check(const Duration(seconds: 5)), isFalse);
      expect(check(const Duration(seconds: 20)), isTrue);
    });
  });

  group('AppRefresh lifecycle', () {
    testWidgets('timer berhenti di background, jalan lagi saat kembali',
        (tester) async {
      final refresh = AppRefresh(tickInterval: const Duration(seconds: 1));
      final events = <RefreshReason>[];
      final sub = refresh.events.listen(events.add);
      // Pastikan timer berhenti walau ada expect yang gagal.
      addTearDown(() async {
        refresh.stop();
        await sub.cancel();
      });

      refresh.start();
      expect(refresh.isTimerRunning, isTrue);

      await tester.pump(const Duration(seconds: 1));
      expect(events, [RefreshReason.periodic]);

      // Urutan asli engine (Flutter >= 3.13) saat ke background.
      for (final s in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        refresh.didChangeAppLifecycleState(s);
      }
      expect(refresh.isTimerRunning, isFalse);
      await tester.pump();
      events.clear();
      await tester.pump(const Duration(seconds: 3));
      expect(events, isEmpty, reason: 'tidak ada detak saat di background');

      // Urutan asli saat kembali: state sebelum resumed adalah inactive.
      for (final s in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        refresh.didChangeAppLifecycleState(s);
      }
      await tester.pump(); // event broadcast dikirim asinkron
      expect(events, [RefreshReason.resumed], reason: 'tepat satu kali');
      expect(refresh.isTimerRunning, isTrue);

      refresh.stop();
      expect(refresh.isTimerRunning, isFalse);
    });

    testWidgets('resumed -> inactive -> resumed (tarik notifikasi) tidak memicu',
        (tester) async {
      final refresh = AppRefresh(tickInterval: const Duration(hours: 1));
      final events = <RefreshReason>[];
      final sub = refresh.events.listen(events.add);
      addTearDown(() async {
        refresh.stop();
        await sub.cancel();
      });
      refresh.start();

      refresh.didChangeAppLifecycleState(AppLifecycleState.resumed);
      refresh.didChangeAppLifecycleState(AppLifecycleState.inactive);
      refresh.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(events, isEmpty);
      expect(refresh.isTimerRunning, isTrue, reason: 'timer tetap jalan');
      refresh.stop();
    });
  });

  group('AutoRefreshMixin', () {
    testWidgets('tidak memuat ulang data yang masih baru atau saat tersembunyi',
        (tester) async {
      var calls = 0;
      final visible = ValueNotifier<bool>(false);
      await tester.pumpWidget(
        MaterialApp(
          home: _Probe(
            visible: visible,
            onRefresh: () async => calls++,
          ),
        ),
      );

      // Data baru dimuat: detak berkala diabaikan.
      visible.value = true;
      AppRefresh.instance.debugEmit(RefreshReason.periodic);
      await tester.pump();
      expect(calls, 0);

      // Tersembunyi (mis. tab lain): resumed pun diabaikan.
      visible.value = false;
      AppRefresh.instance.debugEmit(RefreshReason.resumed);
      await tester.pump();
      expect(calls, 0);
    });

    testWidgets('pemuatan bersamaan digabung (single-flight)', (tester) async {
      var calls = 0;
      final gate = Completer<void>();
      final visible = ValueNotifier<bool>(true);
      await tester.pumpWidget(
        MaterialApp(
          home: _Probe(
            visible: visible,
            onRefresh: () {
              calls++;
              return gate.future;
            },
          ),
        ),
      );
      final state = tester.state<_ProbeState>(find.byType(_Probe));
      // Paksa data dianggap lama.
      state.markLoadedForTest(DateTime(2000));

      AppRefresh.instance.debugEmit(RefreshReason.resumed);
      await tester.pump();
      AppRefresh.instance.debugEmit(RefreshReason.resumed);
      await tester.pump();
      expect(calls, 1);

      gate.complete();
      await tester.pump();
    });
  });
}
