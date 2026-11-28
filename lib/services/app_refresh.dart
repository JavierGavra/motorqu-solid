import 'dart:async';

import 'package:flutter/widgets.dart';

/// Alasan sebuah halaman diminta memuat ulang.
enum RefreshReason {
  /// Aplikasi kembali ke depan (dari background / layar terkunci).
  resumed,

  /// Detak berkala selama aplikasi terbuka di depan.
  periodic,
}

/// Sinkronisasi berkala untuk data di Solid Pod.
///
/// Solid Pod tidak mengirim perubahan ke aplikasi, jadi data dari anggota
/// keluarga lain diambil ulang saat:
/// - aplikasi kembali aktif ([RefreshReason.resumed]), dan
/// - berkala selama aplikasi di depan ([RefreshReason.periodic]).
///
/// Timer berhenti saat aplikasi di background, jadi tidak boros baterai/kuota.
/// Halaman memutuskan sendiri apakah perlu memuat ulang (lihat
/// [AutoRefreshMixin]).
class AppRefresh with WidgetsBindingObserver {
  AppRefresh({this.tickInterval = const Duration(seconds: 30)});

  static final AppRefresh instance = AppRefresh();

  final Duration tickInterval;
  final _controller = StreamController<RefreshReason>.broadcast();
  Timer? _timer;
  bool _started = false;
  bool _wentToBackground = false;

  Stream<RefreshReason> get events => _controller.stream;

  /// Dipanggil setelah login (layar utama tampil).
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _startTimer();
  }

  /// Dipanggil saat layar utama ditutup (logout).
  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    _stopTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;

    // Sejak Flutter 3.13 engine melewati semua state perantara:
    //   ke background : resumed -> inactive -> hidden -> paused
    //   kembali       : paused -> hidden -> inactive -> resumed
    // Jadi state sebelum `resumed` SELALU `inactive`. Pakai flag: emit hanya
    // bila sempat hidden/paused, bukan karena dialog sistem / tarik notifikasi
    // (resumed -> inactive -> resumed).
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _wentToBackground = true;
        _stopTimer();
      case AppLifecycleState.resumed:
        _startTimer();
        if (_wentToBackground) {
          _wentToBackground = false;
          _emit(RefreshReason.resumed);
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _startTimer() {
    _timer ??= Timer.periodic(
      tickInterval,
      (_) => _emit(RefreshReason.periodic),
    );
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _emit(RefreshReason reason) {
    if (!_controller.isClosed) _controller.add(reason);
  }

  @visibleForTesting
  bool get isTimerRunning => _timer != null;

  @visibleForTesting
  void debugEmit(RefreshReason reason) => _emit(reason);

  /// Apakah data yang dimuat pada [lastLoadedAt] perlu dimuat ulang.
  ///
  /// - resumed: muat ulang bila data lebih tua dari [resumeMaxAge].
  /// - periodic: muat ulang bila data lebih tua dari [maxAge] halaman.
  static bool shouldRefresh({
    required RefreshReason reason,
    required DateTime? lastLoadedAt,
    required DateTime now,
    required Duration maxAge,
    Duration resumeMaxAge = const Duration(seconds: 15),
  }) {
    if (lastLoadedAt == null) return true;
    final age = now.difference(lastLoadedAt);
    return age >= (reason == RefreshReason.resumed ? resumeMaxAge : maxAge);
  }
}

/// Mixin untuk halaman yang datanya perlu diperbarui otomatis.
///
/// Memuat ulang hanya bila halaman sedang terlihat (route teratas dan
/// [isAutoRefreshVisible]) dan datanya sudah cukup lama. Pemuatan bersamaan
/// digabung (single-flight).
mixin AutoRefreshMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription<RefreshReason>? _refreshSub;
  DateTime? _lastLoadedAt;
  Future<void>? _autoRefreshInFlight;

  /// Umur maksimum data sebelum dimuat ulang oleh detak berkala.
  Duration get autoRefreshMaxAge;

  /// Muat ulang data halaman. Jangan menampilkan spinner layar penuh.
  Future<void> autoRefresh();

  /// Override bila halaman bisa tersembunyi walau route-nya teratas
  /// (mis. tab yang tidak aktif di IndexedStack).
  bool get isAutoRefreshVisible => true;

  /// Panggil setiap kali data selesai dimuat (manual maupun otomatis).
  void markLoaded() => _lastLoadedAt = DateTime.now();

  @visibleForTesting
  void markLoadedForTest(DateTime at) => _lastLoadedAt = at;

  @override
  void initState() {
    super.initState();
    _refreshSub = AppRefresh.instance.events.listen(_onRefreshEvent);
  }

  @override
  void dispose() {
    _refreshSub?.cancel();
    super.dispose();
  }

  void _onRefreshEvent(RefreshReason reason) {
    if (!mounted || _autoRefreshInFlight != null) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    if (!isAutoRefreshVisible) return;
    if (!AppRefresh.shouldRefresh(
      reason: reason,
      lastLoadedAt: _lastLoadedAt,
      now: DateTime.now(),
      maxAge: autoRefreshMaxAge,
    )) {
      return;
    }

    _autoRefreshInFlight = autoRefresh()
        .catchError((Object e) => debugPrint('[AutoRefresh] gagal: $e'))
        .whenComplete(() {
          _autoRefreshInFlight = null;
          markLoaded();
        });
  }
}
