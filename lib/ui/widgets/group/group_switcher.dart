import 'package:flutter/material.dart';
import 'package:motorqu_solid/models/family_group.dart';
import 'package:motorqu_solid/ui/widgets/group/group_common.dart';

/// Dropdown pemilih "Garasi Aktif" saat pengguna punya lebih dari satu grup.
class GroupSwitcher extends StatelessWidget {
  const GroupSwitcher({
    super.key,
    required this.groups,
    required this.activeId,
    required this.onChanged,
  });

  final List<FamilyGroup> groups;
  final String activeId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = GroupPalette.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.swap_horiz_rounded,
            color: GroupPalette.primary,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Garasi Aktif:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: p.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: activeId,
                isExpanded: true,
                dropdownColor: p.cardBg,
                borderRadius: BorderRadius.circular(16),
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: GroupPalette.primary,
                ),
                items: groups
                    .map(
                      (g) => DropdownMenuItem<String>(
                        value: g.id,
                        child: Text(
                          g.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: p.textPrimary,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (id) {
                  if (id != null) onChanged(id);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
