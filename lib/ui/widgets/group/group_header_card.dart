import 'package:flutter/material.dart';
import 'package:motorqu_solid/models/family_group.dart';
import 'package:motorqu_solid/ui/widgets/group/group_common.dart';

/// Kartu banner grup: nama, peran pengguna, dan tombol undang anggota.
class GroupHeaderCard extends StatelessWidget {
  const GroupHeaderCard({
    super.key,
    required this.group,
    required this.isOwner,
    required this.onEditName,
    required this.onInvite,
  });

  final FamilyGroup group;
  final bool isOwner;
  final VoidCallback onEditName;
  final VoidCallback onInvite;

  @override
  Widget build(BuildContext context) {
    final p = GroupPalette.of(context);

    return Container(
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: p.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: p.isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: GroupPalette.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.diversity_3_rounded,
                  color: p.successText,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            group.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: p.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: onEditName,
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 16,
                              color: GroupPalette.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _RoleBadge(isOwner: isOwner),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onInvite,
              icon: const Icon(Icons.qr_code_rounded, size: 18),
              label: const Text('Undang Anggota'),
              style: FilledButton.styleFrom(
                backgroundColor: GroupPalette.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.isOwner});

  final bool isOwner;

  @override
  Widget build(BuildContext context) {
    final p = GroupPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isOwner
            ? GroupPalette.primary.withValues(alpha: 0.15)
            : (p.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isOwner ? '👑 Anda adalah Owner/Admin' : 'Anggota Keluarga',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isOwner
              ? (p.isDark ? const Color(0xFF60A5FA) : const Color(0xFF1565C0))
              : p.textSecondary,
        ),
      ),
    );
  }
}
