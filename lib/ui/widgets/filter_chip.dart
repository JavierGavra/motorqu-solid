import 'package:flutter/material.dart';

class MotorFilterChip extends StatelessWidget {
  const MotorFilterChip({
    super.key,
    required this.value,
    required this.label,
    required this.isDark,
    required this.isSelected,
    required this.onSelected,
  });

  final String value;
  final String label;
  final bool isDark;
  final bool isSelected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1976D2);
    final bgColor = isSelected
        ? const Color(0xFF1976D2).withValues(alpha: 0.15)
        : (isDark ? const Color(0xFF1E293B) : Colors.white);
    final borderColor = isSelected
        ? primary
        : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1));

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(value),
      selectedColor: const Color(0xFF1976D2).withValues(alpha: 0.15),
      backgroundColor: bgColor,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected
            ? primary
            : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
      ),
      side: BorderSide(color: borderColor, width: isSelected ? 1.4 : 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }
}
