import 'package:flutter/material.dart';
import 'package:motorqu_solid/ui/widgets/group/group_common.dart';

/// Tombol merah "Keluar dari Garasi Grup" di bagian bawah halaman.
class LeaveGroupButton extends StatelessWidget {
  const LeaveGroupButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(
        Icons.logout_rounded,
        size: 18,
        color: GroupPalette.danger,
      ),
      label: const Text(
        'Keluar dari Garasi Grup',
        style: TextStyle(
          color: GroupPalette.danger,
          fontWeight: FontWeight.bold,
        ),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: GroupPalette.danger.withValues(alpha: 0.4)),
        backgroundColor: GroupPalette.danger.withValues(alpha: 0.06),
        minimumSize: const Size(double.infinity, 46),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
