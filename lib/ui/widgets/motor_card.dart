import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:motorqu_solid/models/motorcycle.dart';

class MotorCard extends StatelessWidget {
  final Motorcycle moto;
  final bool isDark;

  const MotorCard({super.key, required this.moto, required this.isDark});

  bool _checkIsDue(Motorcycle moto) {
    final serviceDate = moto.lastServiceAt;
    if (serviceDate != null) {
      final days = DateTime.now().difference(serviceDate).inDays;
      return days >= 30;
    }
    final days = DateTime.now().difference(moto.createdAt).inDays;
    return days >= 30;
  }

  @override
  Widget build(BuildContext context) {
    final isDue = _checkIsDue(moto);
    final serviceDate = moto.lastServiceAt;
    final daysSince = serviceDate != null
        ? DateTime.now().difference(serviceDate).inDays
        : DateTime.now().difference(moto.createdAt).inDays;
    final daysRemaining = 30 - daysSince;
    final isWarning = !isDue && daysSince >= 24;

    final progress = (daysSince / 30.0).clamp(0.05, 1.0);

    Color statusColor;
    Color statusBgColor;
    String statusText;
    IconData statusIcon;

    if (isDue) {
      statusColor = const Color(0xFFDC2626);
      statusBgColor = isDark
          ? const Color(0xFF7F1D1D).withValues(alpha: 0.3)
          : const Color(0xFFFEE2E2);
      statusText = 'Sudah $daysSince hari sejak servis! Segera ganti oli.';
      statusIcon = Icons.error_rounded;
    } else if (isWarning) {
      statusColor = const Color(0xFFD97706);
      statusBgColor = isDark
          ? const Color(0xFF78350F).withValues(alpha: 0.3)
          : const Color(0xFFFEF3C7);
      statusText = 'Mendekati waktu servis (sisa $daysRemaining hari lagi)';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF2E7D32);
      statusBgColor = isDark
          ? const Color(0xFF14532D).withValues(alpha: 0.3)
          : const Color(0xFFE8F5E9);
      statusText =
          'Kondisi oli aman (cek: ${daysRemaining > 0 ? "$daysRemaining hari lagi" : "hari ini"})';
      statusIcon = Icons.check_circle_rounded;
    }

    String dateStr = 'Belum dicatat';
    if (moto.lastServiceAt != null) {
      dateStr = DateFormat('dd MMM yyyy').format(moto.lastServiceAt!);
    }

    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDue
        ? const Color(0xFFDC2626).withValues(alpha: 0.5)
        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: isDue ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            // Navigator.push(
            //   context,
            //   MaterialPageRoute(
            //     builder: (_) => MotorDetailScreen(motorcycle: moto),
            //   ),
            // );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row Atas: Avatar, Nama, Plat, & Badge Akses
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: moto.isGroupMotor
                            ? const Color(0xFF2E7D32).withValues(alpha: 0.15)
                            : const Color(0xFF1976D2).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.two_wheeler_rounded,
                        color: moto.isGroupMotor
                            ? (isDark
                                  ? const Color(0xFF4ADE80)
                                  : const Color(0xFF2E7D32))
                            : (isDark
                                  ? const Color(0xFF60A5FA)
                                  : const Color(0xFF1976D2)),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            moto.name,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? const Color(0xFFF8FAFC)
                                  : const Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${moto.brand} ${moto.model}',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                          if (moto.plate != null && moto.plate!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF334155)
                                      : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Text(
                                moto.plate!,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: isDark
                                      ? const Color(0xFFCBD5E1)
                                      : const Color(0xFF334155),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: moto.isGroupMotor
                            ? const Color(0xFF2E7D32).withValues(alpha: 0.15)
                            : const Color(0xFF1976D2).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            moto.isGroupMotor
                                ? Icons.group_rounded
                                : Icons.person_rounded,
                            size: 12,
                            color: moto.isGroupMotor
                                ? (isDark
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFF2E7D32))
                                : (isDark
                                      ? const Color(0xFF60A5FA)
                                      : const Color(0xFF1976D2)),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            moto.isGroupMotor ? 'Grup' : 'Pribadi',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: moto.isGroupMotor
                                  ? (isDark
                                        ? const Color(0xFF4ADE80)
                                        : const Color(0xFF2E7D32))
                                  : (isDark
                                        ? const Color(0xFF60A5FA)
                                        : const Color(0xFF1976D2)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Divider(
                  height: 1,
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFF1F5F9),
                ),
                const SizedBox(height: 12),

                // Info Odometer Servis & Checkpoint Target
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Oli Terakhir ($dateStr)',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${NumberFormat('#,###').format(moto.lastOdometer)} KM',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? const Color(0xFFF8FAFC)
                                : const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Target Servis',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${NumberFormat('#,###').format(moto.nextDueKm)} KM',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDue
                                ? const Color(0xFFDC2626)
                                : (isDark
                                      ? const Color(0xFFF8FAFC)
                                      : const Color(0xFF0F172A)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Mini Milestone Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF1F5F9),
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                  ),
                ),

                const SizedBox(height: 12),

                // Status Pill Modern
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: statusBgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(statusIcon, size: 14, color: statusColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 12,
                        color: statusColor.withValues(alpha: 0.7),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
