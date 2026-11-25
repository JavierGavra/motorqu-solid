import 'package:flutter/material.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/ui/widgets/group/group_common.dart';

/// Bottom sheet pemilih motor pribadi untuk dimasukkan ke grup.
/// Mengembalikan motor yang dipilih, atau null kalau ditutup tanpa memilih.
Future<Motorcycle?> showPickMotorSheet(
  BuildContext context, {
  required String groupName,
  required List<Motorcycle> motorcycles,
}) {
  return showModalBottomSheet<Motorcycle>(
    context: context,
    backgroundColor: Theme.of(context).cardTheme.color ?? Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final p = GroupPalette.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: p.isDark
                        ? const Color(0xFF475569)
                        : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Pilih Motor untuk Masuk ke "$groupName"',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: p.border),
              ...motorcycles.map(
                (m) => ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 4,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: GroupPalette.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.two_wheeler_rounded,
                      color: GroupPalette.primary,
                    ),
                  ),
                  title: Text(
                    m.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${m.brand} ${m.model} ${m.plate != null ? "• ${m.plate}" : ""}',
                  ),
                  trailing: const Icon(
                    Icons.add_circle_rounded,
                    color: GroupPalette.success,
                  ),
                  onTap: () => Navigator.pop(ctx, m),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    },
  );
}
