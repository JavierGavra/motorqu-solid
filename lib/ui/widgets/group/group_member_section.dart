import 'package:flutter/material.dart';
import 'package:motorqu_solid/models/family_group.dart';
import 'package:motorqu_solid/ui/widgets/group/group_common.dart';
import 'package:motorqu_solid/ui/widgets/group_member_card.dart';

/// Seksi "Anggota Garasi": judul + daftar anggota dengan aksi
/// jadikan owner / turunkan / keluarkan.
class GroupMemberSection extends StatelessWidget {
  const GroupMemberSection({
    super.key,
    required this.group,
    required this.membersFuture,
    required this.currentUserId,
    required this.onPromote,
    required this.onDemote,
    required this.onKick,
  });

  final FamilyGroup group;
  final Future<List<Map<String, dynamic>>> membersFuture;
  final String currentUserId;
  final ValueChanged<Map<String, dynamic>> onPromote;
  final ValueChanged<Map<String, dynamic>> onDemote;
  final ValueChanged<Map<String, dynamic>> onKick;

  @override
  Widget build(BuildContext context) {
    final p = GroupPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Anggota Garasi (${group.memberUids.length})',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: p.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: membersFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const InlineLoading();
            }
            final members = snap.data ?? [];
            return Container(
              decoration: BoxDecoration(
                color: p.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: p.border),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: members.length,
                separatorBuilder: (ctx, i) => Divider(height: 1, color: p.border),
                itemBuilder: (ctx, index) => GroupMemberCard(
                  member: members[index],
                  group: group,
                  currentUserId: currentUserId,
                  onPromote: onPromote,
                  onDemote: onDemote,
                  onKick: onKick,
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
