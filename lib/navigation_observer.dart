import 'package:flutter/material.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// Tab aktif di layar utama (0 = Motor, 1 = Profil). Dipakai halaman di dalam
/// IndexedStack untuk tahu apakah sedang terlihat.
final ValueNotifier<int> mainTabIndex = ValueNotifier<int>(0);
