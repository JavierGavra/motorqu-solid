import 'package:flutter/material.dart';
import 'package:motorqu_solid/services/group_service.dart';
import 'package:motorqu_solid/ui/widgets/group/group_common.dart';

/// Grup yang sudah dimasuki dengan kode, tapi data grupnya belum bisa dibuka
/// karena aplikasi pembuat grup belum berjalan sejak itu.
class PendingGroupCard extends StatelessWidget {
  const PendingGroupCard({super.key, required this.group});

  final PendingGroup group;

  @override
  Widget build(BuildContext context) {
    final p = GroupPalette.of(context);
    final name = group.name.isEmpty ? 'Grup baru' : group.name;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GroupPalette.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: p.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Kamu sudah bergabung. Data grup sedang disinkronkan dan '
            'muncul otomatis saat HP pembuat grup membuka MotorQu.',
            style: TextStyle(fontSize: 13, height: 1.4, color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}
