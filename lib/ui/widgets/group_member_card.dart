import 'package:flutter/material.dart';
import 'package:motorqu_solid/models/family_group.dart';

class GroupMemberCard extends StatelessWidget {
  const GroupMemberCard({
    required this.member,
    required this.group,
    required this.currentUserId,
    required this.onPromote,
    required this.onDemote,
    required this.onKick,
    super.key,
  });

  final Map<String, dynamic> member;
  final FamilyGroup group;
  final String currentUserId;
  final ValueChanged<Map<String, dynamic>> onPromote;
  final ValueChanged<Map<String, dynamic>> onDemote;
  final ValueChanged<Map<String, dynamic>> onKick;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF0F172A);
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final memberUid = member['uid'] as String;
    final isMe = memberUid == currentUserId;
    final isOwner = group.isOwner(currentUserId);
    final isMemberOwner = group.isOwner(memberUid);
    final isGroupCreator = memberUid == group.ownerId;
    final photo = member['photoUrl'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFF1976D2).withValues(alpha: 0.15),
            backgroundImage: photo != null && photo.trim().isNotEmpty
                ? NetworkImage(photo)
                : null,
            child: photo == null || photo.trim().isEmpty
                ? const Icon(
                    Icons.person_rounded,
                    size: 20,
                    color: Color(0xFF1976D2),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member['displayName'] ?? 'Pengguna',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: isMe ? FontWeight.bold : FontWeight.w600,
                    fontSize: 14,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  member['email'] ?? '',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
                const SizedBox(height: 8),
                if (isMe)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isMemberOwner) _ownerBadge(isGroupCreator, isDark),
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF0F172A)
                              : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Anda',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: textSecondary,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isMemberOwner) _ownerBadge(isGroupCreator, isDark),
                      if (isOwner)
                        _memberActions(textPrimary, textSecondary, isDark),
                    ],
                  ),
              ],
            ),
          ),
          // const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _ownerBadge(bool isGroupCreator, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF1976D2).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isGroupCreator ? 'Owner Utama' : 'Owner',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1565C0),
        ),
      ),
    );
  }

  Widget _memberActions(Color textPrimary, Color textSecondary, bool isDark) {
    final memberUid = member['uid'] as String;
    final isGroupCreator = memberUid == group.ownerId;
    final isMemberOwner = group.isOwner(memberUid);

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, size: 20, color: textSecondary),
      tooltip: 'Kelola Anggota',
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      onSelected: (value) {
        switch (value) {
          case 'promote':
            onPromote(member);
          case 'demote':
            onDemote(member);
          case 'kick':
            onKick(member);
        }
      },
      itemBuilder: (context) => [
        if (!isMemberOwner)
          PopupMenuItem(
            value: 'promote',
            child: Row(
              children: [
                const Icon(
                  Icons.military_tech_rounded,
                  color: Color(0xFF1976D2),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Jadikan Owner / Admin',
                  style: TextStyle(color: textPrimary),
                ),
              ],
            ),
          )
        else if (!isGroupCreator)
          PopupMenuItem(
            value: 'demote',
            child: Row(
              children: [
                const Icon(
                  Icons.remove_moderator_rounded,
                  color: Color(0xFFD97706),
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Turunkan dari Owner',
                  style: TextStyle(color: textPrimary),
                ),
              ],
            ),
          ),
        if (!isGroupCreator)
          const PopupMenuItem(
            value: 'kick',
            child: Row(
              children: [
                Icon(
                  Icons.person_remove_rounded,
                  color: Color(0xFFDC2626),
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(
                  'Keluarkan dari Grup',
                  style: TextStyle(color: Color(0xFFDC2626)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
