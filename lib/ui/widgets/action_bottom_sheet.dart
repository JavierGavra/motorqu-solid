import 'package:flutter/material.dart';
import 'package:motorqu_solid/ui/widgets/action_card.dart';

void openActionSheet(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final surfaceColor = isDark ? const Color(0xFF1E293B) : Colors.white;
  final borderColor = isDark
      ? const Color(0xFF334155)
      : const Color(0xFFE2E8F0);

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF475569)
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Aksi Cepat',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark
                    ? const Color(0xFFF8FAFC)
                    : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Pilih tindakan yang ingin langsung kamu lakukan',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 20),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ActionCard(
                      icon: Icons.build_circle_rounded,
                      color: const Color(0xFF1976D2),
                      title: 'Catat Oli',
                      subtitle: 'Update KM & riwayat oli',
                      isDark: isDark,
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, '/addOil');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ActionCard(
                      icon: Icons.two_wheeler_rounded,
                      color: const Color(0xFF1976D2),
                      title: 'Tambah Motor',
                      subtitle: 'Daftarkan motor baru',
                      isDark: isDark,
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, '/addMotor');
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ActionCard(
                      icon: Icons.group_add_rounded,
                      color: const Color(0xFF1976D2),
                      title: 'Buat Grup',
                      subtitle: 'Bikin garasi grup baru',
                      isDark: isDark,
                      onTap: () {
                        Navigator.pop(ctx);
                        _showCreateGroupDialog(context);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ActionCard(
                      icon: Icons.login_rounded,
                      color: const Color(0xFF1976D2),
                      title: 'Masuk Grup',
                      subtitle: 'Gabung pakai kode 6 digit',
                      isDark: isDark,
                      onTap: () {
                        Navigator.pop(ctx);
                        _showJoinGroupDialog(context);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showCreateGroupDialog(BuildContext context) async {
  final ctrl = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.group_add_rounded, color: Color(0xFF2E7D32)),
          SizedBox(width: 8),
          Text('Buat Garasi Grup'),
        ],
      ),
      content: TextField(
        controller: ctrl,
        decoration: const InputDecoration(
          labelText: 'Nama Grup',
          hintText: 'contoh: Keluarga Ridlo, Motor Kantor',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1976D2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Buat Grup'),
        ),
      ],
    ),
  );

  if (name == null || name.isEmpty) return;
  debugPrint('Buat grup dengan nama: $name');
}

Future<void> _showJoinGroupDialog(BuildContext context) async {
  final ctrl = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.login_rounded, color: Color(0xFF1976D2)),
          SizedBox(width: 8),
          Text('Masuk ke Grup'),
        ],
      ),
      content: TextField(
        controller: ctrl,
        textCapitalization: TextCapitalization.characters,
        maxLength: 6,
        decoration: const InputDecoration(
          labelText: 'Kode Undangan (6 Karakter)',
          hintText: 'contoh: ABC123',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim().toUpperCase()),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1976D2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Gabung'),
        ),
      ],
    ),
  );

  if (code == null || code.isEmpty) return;
  debugPrint('Gabung grup dengan kode: $code');
}
