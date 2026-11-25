import 'package:flutter/material.dart';
import 'package:motorqu_solid/ui/widgets/group/group_common.dart';

/// Menu "+" di AppBar: buat grup baru / gabung pakai kode.
class GroupActionsMenu extends StatelessWidget {
  const GroupActionsMenu({
    super.key,
    required this.onCreate,
    required this.onJoin,
  });

  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final p = GroupPalette.of(context);
    final itemColor = p.isDark ? Colors.white : const Color(0xFF0F172A);

    PopupMenuItem<String> item(String value, IconData icon, String label) {
      return PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, color: GroupPalette.primary, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w600, color: itemColor),
            ),
          ],
        ),
      );
    }

    return PopupMenuButton<String>(
      icon: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: GroupPalette.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(
          Icons.add_rounded,
          size: 20,
          color: GroupPalette.primary,
        ),
      ),
      tooltip: 'Aksi Grup',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: p.cardBg,
      onSelected: (val) {
        if (val == 'create') onCreate();
        if (val == 'join') onJoin();
      },
      itemBuilder: (ctx) => [
        item('create', Icons.group_add_rounded, 'Buat Grup Baru'),
        item('join', Icons.qr_code_scanner_rounded, 'Gabung Pakai Kode'),
      ],
    );
  }
}
