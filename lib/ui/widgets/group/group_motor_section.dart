import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/ui/widgets/group/group_common.dart';

/// Seksi "Motor di Garasi Ini": judul + tombol tambah + daftar motor grup.
class GroupMotorSection extends StatelessWidget {
  const GroupMotorSection({
    super.key,
    required this.motorcyclesFuture,
    required this.myUid,
    required this.isOwner,
    required this.onAddMotor,
    required this.onRemoveMotor,
  });

  final Future<List<Motorcycle>> motorcyclesFuture;
  final String myUid;
  final bool isOwner;
  final VoidCallback onAddMotor;
  final ValueChanged<Motorcycle> onRemoveMotor;

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
              'Motor di Garasi Ini',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: p.textPrimary,
              ),
            ),
            TextButton.icon(
              onPressed: onAddMotor,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Tambah Motor'),
              style: TextButton.styleFrom(
                foregroundColor: GroupPalette.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<Motorcycle>>(
          future: motorcyclesFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const InlineLoading();
            }
            final motos = snap.data ?? [];
            if (motos.isEmpty) {
              return _EmptyGroupMotors(onAddMotor: onAddMotor);
            }
            return Column(
              children: motos.map((m) {
                final isMyMotor = m.createdBy == myUid;
                return _GroupMotorTile(
                  motor: m,
                  canRemove: isMyMotor || isOwner,
                  isMyMotor: isMyMotor,
                  onRemove: () => onRemoveMotor(m),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

class _EmptyGroupMotors extends StatelessWidget {
  const _EmptyGroupMotors({required this.onAddMotor});

  final VoidCallback onAddMotor;

  @override
  Widget build(BuildContext context) {
    final p = GroupPalette.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.two_wheeler_rounded, color: p.textSecondary, size: 36),
            const SizedBox(height: 8),
            Text(
              'Belum ada motor di garasi grup ini',
              style: TextStyle(
                fontSize: 13,
                color: p.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAddMotor,
              child: const Text('Masukkan Motor Pribadi ke Sini'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupMotorTile extends StatelessWidget {
  const _GroupMotorTile({
    required this.motor,
    required this.canRemove,
    required this.isMyMotor,
    required this.onRemove,
  });

  final Motorcycle motor;
  final bool canRemove;
  final bool isMyMotor;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = GroupPalette.of(context);
    final fmt = NumberFormat('#,###');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: p.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: GroupPalette.success.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.two_wheeler_rounded,
            color: p.successText,
            size: 22,
          ),
        ),
        title: Text(
          motor.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: p.textPrimary,
          ),
        ),
        subtitle: Text(
          '${motor.brand} ${motor.model} ${motor.plate != null ? "• ${motor.plate}" : ""}\n'
          'Odometer: ${fmt.format(motor.lastOdometer)} KM · Target: ${fmt.format(motor.nextDueKm)} KM',
          style: TextStyle(fontSize: 12, color: p.textSecondary),
        ),
        isThreeLine: true,
        trailing: canRemove
            ? IconButton(
                icon: const Icon(
                  Icons.remove_circle_outline_rounded,
                  color: GroupPalette.warning,
                ),
                tooltip: isMyMotor
                    ? 'Keluarkan Motor Saya dari Grup'
                    : 'Keluarkan Motor Ini dari Grup',
                onPressed: onRemove,
              )
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: GroupPalette.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Grup',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: p.successText,
                  ),
                ),
              ),
      ),
    );
  }
}
