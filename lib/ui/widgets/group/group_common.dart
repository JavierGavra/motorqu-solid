import 'package:flutter/material.dart';

/// Warna tema Garasi Grup, mengikuti mode gelap/terang.
class GroupPalette {
  const GroupPalette._(this.isDark);

  factory GroupPalette.of(BuildContext context) =>
      GroupPalette._(Theme.of(context).brightness == Brightness.dark);

  final bool isDark;

  static const Color primary = Color(0xFF1976D2);
  static const Color success = Color(0xFF2E7D32);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);

  Color get background =>
      isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC);
  Color get cardBg => isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get border =>
      isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get textPrimary =>
      isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
  Color get textSecondary =>
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get successText => isDark ? const Color(0xFF4ADE80) : success;
}

/// Gaya tombol FilledButton yang dipakai di seluruh dialog grup.
ButtonStyle groupFilledStyle(Color color, {double radius = 10}) {
  return FilledButton.styleFrom(
    backgroundColor: color,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
  );
}

/// Indikator loading kecil untuk bagian di dalam ListView.
class InlineLoading extends StatelessWidget {
  const InlineLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ),
    );
  }
}
