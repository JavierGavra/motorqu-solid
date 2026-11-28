import 'package:flutter/material.dart';
import 'package:motorqu_solid/ui/widgets/group/group_common.dart';

/// Tampilan kosong saat pengguna belum punya grup.
class NoGroupView extends StatelessWidget {
  const NoGroupView({super.key, required this.onCreate, required this.onJoin});

  final VoidCallback onCreate;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final p = GroupPalette.of(context);

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.diversity_3_rounded,
                      size: 64,
                      color: GroupPalette.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Belum Ada Garasi Grup',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: p.isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Buat grup keluarga atau gabung dengan kode undangan untuk memantau oli motor bersama.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, height: 1.4),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Icons.group_add_rounded),
                    label: const Text('Buat Grup Baru'),
                    style: FilledButton.styleFrom(
                      backgroundColor: GroupPalette.primary,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onJoin,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Gabung Pakai Kode / QR'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(
                        color: p.isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
