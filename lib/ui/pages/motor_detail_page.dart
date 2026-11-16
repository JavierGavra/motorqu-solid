// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import 'package:motorqu_solid/models/motorcycle.dart';
// import 'package:motorqu_solid/models/oil_record.dart';
// import 'package:motorqu_solid/services/database_service.dart';
// import 'package:motorqu_solid/ui/pages/add_motor_page.dart';

// class MotorDetailScreen extends StatefulWidget {
//   final Motorcycle motorcycle;
//   const MotorDetailScreen({super.key, required this.motorcycle});

//   @override
//   State<MotorDetailScreen> createState() => _MotorDetailScreenState();
// }

// class _MotorDetailScreenState extends State<MotorDetailScreen> {
//   final DatabaseService _db = DatabaseService();

//   Future<void> _deleteOilRecord(OilRecord r) async {
//     final ok = await showDialog<bool>(
//       context: context,
//       builder: (ctx) => AlertDialog(
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
//         title: const Row(
//           children: [
//             Icon(Icons.delete_outline_rounded, color: Colors.red),
//             SizedBox(width: 8),
//             Text('Hapus Catatan Oli'),
//           ],
//         ),
//         content: Text(
//           'Hapus catatan oli pada ${NumberFormat('#,###').format(r.odometer)} KM '
//           '(${DateFormat('dd MMM yyyy').format(r.performedAt)})?',
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(ctx, false),
//             child: const Text('Batal'),
//           ),
//           FilledButton(
//             onPressed: () => Navigator.pop(ctx, true),
//             style: FilledButton.styleFrom(
//               backgroundColor: const Color(0xFFDC2626),
//               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//             ),
//             child: const Text('Hapus'),
//           ),
//         ],
//       ),
//     );
//     if (ok != true) return;
//     try {
//       await _db.deleteOilRecord(widget.motorcycle.id, r.id);
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Catatan oli berhasil dihapus'),
//             backgroundColor: Color(0xFF1976D2),
//           ),
//         );
//       }
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Gagal menghapus: $e')),
//         );
//       }
//     }
//   }

//   Future<void> _deleteMotor(Motorcycle moto) async {
//     final ok = await showDialog<bool>(
//       context: context,
//       builder: (ctx) => AlertDialog(
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
//         title: const Row(
//           children: [
//             Icon(Icons.warning_amber_rounded, color: Colors.red),
//             SizedBox(width: 8),
//             Text('Hapus Motor Permanen'),
//           ],
//         ),
//         content: Text(
//           'Yakin hapus motor "${moto.name}" beserta semua riwayat olinya secara permanen? Tindakan ini tidak dapat dibatalkan.',
//           style: const TextStyle(height: 1.4),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(ctx, false),
//             child: const Text('Batal'),
//           ),
//           FilledButton(
//             onPressed: () => Navigator.pop(ctx, true),
//             style: FilledButton.styleFrom(
//               backgroundColor: const Color(0xFFDC2626),
//               shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//             ),
//             child: const Text('Hapus Permanen'),
//           ),
//         ],
//       ),
//     );
//     if (ok != true) return;
//     await _db.deleteMotorcycle(moto.id);
//     if (mounted) Navigator.pop(context);
//   }

//   @override
//   Widget build(BuildContext context) {
//     final isDark = Theme.of(context).brightness == Brightness.dark;
//     final textPrimary = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
//     final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

//     final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';

//     return StreamBuilder<Motorcycle?>(
//       stream: _db.getMotorcycleStream(widget.motorcycle.id),
//       builder: (context, motoSnap) {
//         final moto = motoSnap.data ?? widget.motorcycle;
//         final isCreator = moto.createdBy == myUid;

//         // Perhitungan Status Oli & Hari
//         final serviceDate = moto.lastServiceAt;
//         final daysSince = serviceDate != null
//             ? DateTime.now().difference(serviceDate).inDays
//             : DateTime.now().difference(moto.createdAt).inDays;
//         final daysRemaining = 30 - daysSince;
//         final isDue = daysSince >= 30;
//         final isWarning = !isDue && daysSince >= 24;

//         return Scaffold(
//           backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
//           appBar: AppBar(
//             backgroundColor: Colors.transparent,
//             elevation: 0,
//             leading: IconButton(
//               icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
//               onPressed: () => Navigator.pop(context),
//             ),
//             title: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   moto.name,
//                   style: TextStyle(
//                     fontSize: 18,
//                     fontWeight: FontWeight.bold,
//                     letterSpacing: -0.3,
//                     color: textPrimary,
//                   ),
//                 ),
//                 Text(
//                   '${moto.brand} ${moto.model}${moto.plate != null && moto.plate!.isNotEmpty ? " • ${moto.plate}" : ""}',
//                   style: TextStyle(
//                     fontSize: 12,
//                     fontWeight: FontWeight.normal,
//                     color: textSecondary,
//                   ),
//                 ),
//               ],
//             ),
//             actions: [
//               IconButton(
//                 icon: Container(
//                   padding: const EdgeInsets.all(6),
//                   decoration: BoxDecoration(
//                     color: const Color(0xFF1976D2).withValues(alpha: 0.15),
//                     borderRadius: BorderRadius.circular(8),
//                   ),
//                   child: const Icon(Icons.edit_rounded, size: 18, color: Color(0xFF1976D2)),
//                 ),
//                 tooltip: 'Edit Motor',
//                 onPressed: () {
//                   Navigator.push(
//                     context,
//                     MaterialPageRoute(builder: (_) => AddMotorPage(moto: moto)),
//                   );
//                 },
//               ),
//               const SizedBox(width: 8),
//             ],
//           ),
//           body: StreamBuilder<List<OilRecord>>(
//             stream: _db.getOilRecordsStream(moto.id),
//             builder: (context, snapshot) {
//               final records = snapshot.data ?? [];

//               return ListView(
//                 padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
//                 children: [
//                   // 1. HERO CARD: ODOMETER & OIL HEALTH PROGRESS (Rivian & BMW style)
//                   _buildOilHealthCard(moto, daysSince, daysRemaining, isDue, isWarning, isDark),

//                   const SizedBox(height: 16),

//                   // 2. PRIMARY CTA BUTTON: CATAT GANTI OLI
//                   _buildAddOilButton(moto.id),

//                   const SizedBox(height: 24),

//                   // 3. RIWAYAT OLI TIMELINE DENGAN DELTA KM (Mercedes-Benz & NRC style)
//                   _buildTimelineSection(records, isDark),

//                   const SizedBox(height: 24),

//                   // 4. SPESIFIKASI KENDARAAN (Modern Specs Grid)
//                   _buildVehicleSpecsCard(moto, isDark),

//                   // 5. TOMBOL HAPUS MOTOR (Hanya untuk Creator)
//                   if (isCreator) ...[
//                     const SizedBox(height: 32),
//                     OutlinedButton.icon(
//                       onPressed: () => _deleteMotor(moto),
//                       icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFDC2626)),
//                       label: const Text(
//                         'Hapus Motor Permanen',
//                         style: TextStyle(
//                           color: Color(0xFFDC2626),
//                           fontWeight: FontWeight.w600,
//                           fontSize: 14,
//                         ),
//                       ),
//                       style: OutlinedButton.styleFrom(
//                         side: BorderSide(color: const Color(0xFFDC2626).withValues(alpha: 0.4)),
//                         backgroundColor: const Color(0xFFDC2626).withValues(alpha: 0.06),
//                         minimumSize: const Size(double.infinity, 46),
//                         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//                       ),
//                     ),
//                   ],
//                 ],
//               );
//             },
//           ),
//         );
//       },
//     );
//   }

//   /// 1. Hero Card: Status Kesehatan Oli & Milestone Progress Bar
//   Widget _buildOilHealthCard(
//     Motorcycle moto,
//     int daysSince,
//     int daysRemaining,
//     bool isDue,
//     bool isWarning,
//     bool isDark,
//   ) {
//     final progress = (daysSince / 30.0).clamp(0.05, 1.0);
//     final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
//     final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
//     final textPrimary = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
//     final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

//     Color statusColor;
//     Color statusBgColor;
//     String statusTitle;
//     IconData statusIcon;

//     if (isDue) {
//       statusColor = const Color(0xFFDC2626);
//       statusBgColor = isDark
//           ? const Color(0xFF7F1D1D).withValues(alpha: 0.3)
//           : const Color(0xFFFEE2E2);
//       statusTitle = 'Perlu Servis Segera';
//       statusIcon = Icons.error_rounded;
//     } else if (isWarning) {
//       statusColor = const Color(0xFFD97706);
//       statusBgColor = isDark
//           ? const Color(0xFF78350F).withValues(alpha: 0.3)
//           : const Color(0xFFFEF3C7);
//       statusTitle = 'Mendekati Waktu Servis';
//       statusIcon = Icons.warning_amber_rounded;
//     } else {
//       statusColor = isDark ? const Color(0xFF4ADE80) : const Color(0xFF2E7D32);
//       statusBgColor = isDark
//           ? const Color(0xFF14532D).withValues(alpha: 0.3)
//           : const Color(0xFFE8F5E9);
//       statusTitle = 'Kondisi Oli Prima';
//       statusIcon = Icons.check_circle_rounded;
//     }

//     String lastServiceDateStr = 'Belum dicatat';
//     if (moto.lastServiceAt != null) {
//       lastServiceDateStr = DateFormat('dd MMM yyyy').format(moto.lastServiceAt!);
//     }

//     return Container(
//       decoration: BoxDecoration(
//         color: cardBg,
//         borderRadius: BorderRadius.circular(20),
//         border: Border.all(color: borderColor),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
//             blurRadius: 16,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       padding: const EdgeInsets.all(18),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           // Header Row: Status Badge & Ownership Chip
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
//                 decoration: BoxDecoration(
//                   color: statusBgColor,
//                   borderRadius: BorderRadius.circular(20),
//                 ),
//                 child: Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Icon(statusIcon, size: 14, color: statusColor),
//                     const SizedBox(width: 6),
//                     Text(
//                       statusTitle,
//                       style: TextStyle(
//                         fontSize: 12,
//                         fontWeight: FontWeight.bold,
//                         color: statusColor,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                 decoration: BoxDecoration(
//                   color: moto.isGroupMotor
//                       ? const Color(0xFF2E7D32).withValues(alpha: 0.15)
//                       : const Color(0xFF1976D2).withValues(alpha: 0.15),
//                   borderRadius: BorderRadius.circular(8),
//                 ),
//                 child: Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Icon(
//                       moto.isGroupMotor ? Icons.group_rounded : Icons.person_rounded,
//                       size: 13,
//                       color: moto.isGroupMotor
//                           ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF2E7D32))
//                           : (isDark ? const Color(0xFF60A5FA) : const Color(0xFF1976D2)),
//                     ),
//                     const SizedBox(width: 4),
//                     Text(
//                       moto.isGroupMotor ? 'Grup Keluarga' : 'Pribadi',
//                       style: TextStyle(
//                         fontSize: 11,
//                         fontWeight: FontWeight.bold,
//                         color: moto.isGroupMotor
//                             ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF2E7D32))
//                             : (isDark ? const Color(0xFF60A5FA) : const Color(0xFF1976D2)),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),

//           const SizedBox(height: 18),

//           // Big Odometer Milestone Target Display
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.baseline,
//             textBaseline: TextBaseline.alphabetic,
//             children: [
//               Text(
//                 NumberFormat('#,###').format(moto.nextDueKm),
//                 style: TextStyle(
//                   fontSize: 32,
//                   fontWeight: FontWeight.w800,
//                   letterSpacing: -1,
//                   color: textPrimary,
//                 ),
//               ),
//               const SizedBox(width: 6),
//               Text(
//                 'KM',
//                 style: TextStyle(
//                   fontSize: 15,
//                   fontWeight: FontWeight.bold,
//                   color: textSecondary,
//                 ),
//               ),
//             ],
//           ),
//           const SizedBox(height: 2),
//           Text(
//             'Target Servis Berikutnya (+${NumberFormat('#,###').format(moto.reminderIntervalKm)} KM interval)',
//             style: TextStyle(
//               fontSize: 12,
//               color: textSecondary,
//             ),
//           ),

//           const SizedBox(height: 18),

//           // Milestone Progress Bar
//           ClipRRect(
//             borderRadius: BorderRadius.circular(8),
//             child: LinearProgressIndicator(
//               value: progress,
//               minHeight: 8,
//               backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
//               valueColor: AlwaysStoppedAnimation<Color>(statusColor),
//             ),
//           ),

//           const SizedBox(height: 10),

//           // Milestone Checkpoint Labels (Last Odo vs Target Odo)
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(
//                     'Servis Terakhir ($lastServiceDateStr)',
//                     style: TextStyle(fontSize: 10, color: textSecondary),
//                   ),
//                   const SizedBox(height: 2),
//                   Text(
//                     '${NumberFormat('#,###').format(moto.lastOdometer)} KM',
//                     style: TextStyle(
//                       fontSize: 13,
//                       fontWeight: FontWeight.bold,
//                       color: textPrimary,
//                     ),
//                   ),
//                 ],
//               ),
//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.end,
//                 children: [
//                   Text(
//                     'Target Checkpoint',
//                     style: TextStyle(fontSize: 10, color: textSecondary),
//                   ),
//                   const SizedBox(height: 2),
//                   Text(
//                     '${NumberFormat('#,###').format(moto.nextDueKm)} KM',
//                     style: TextStyle(
//                       fontSize: 13,
//                       fontWeight: FontWeight.bold,
//                       color: isDue ? const Color(0xFFDC2626) : textPrimary,
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),

//           const SizedBox(height: 14),
//           Divider(height: 1, color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
//           const SizedBox(height: 12),

//           // Dynamic Service Notice Pill
//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//             decoration: BoxDecoration(
//               color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
//               borderRadius: BorderRadius.circular(10),
//               border: Border.all(color: borderColor),
//             ),
//             child: Row(
//               children: [
//                 Icon(
//                   isDue ? Icons.schedule_rounded : Icons.info_outline_rounded,
//                   size: 16,
//                   color: isDue ? const Color(0xFFDC2626) : const Color(0xFF1976D2),
//                 ),
//                 const SizedBox(width: 8),
//                 Expanded(
//                   child: Text(
//                     isDue
//                         ? 'Sudah $daysSince hari sejak ganti oli. Segera lakukan pengecekan!'
//                         : 'Jadwal cek oli berikutnya berkala: ${daysRemaining > 0 ? "$daysRemaining hari lagi" : "hari ini"}',
//                     style: TextStyle(
//                       fontSize: 12,
//                       fontWeight: FontWeight.w500,
//                       color: isDue ? const Color(0xFFF87171) : textPrimary,
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   /// 2. Primary CTA Button: Catat Ganti Oli
//   Widget _buildAddOilButton(String motorId) {
//     return Container(
//       decoration: BoxDecoration(
//         borderRadius: BorderRadius.circular(16),
//         gradient: const LinearGradient(
//           colors: [Color(0xFF1976D2), Color(0xFF1565C0)],
//           begin: Alignment.centerLeft,
//           end: Alignment.centerRight,
//         ),
//         boxShadow: [
//           BoxShadow(
//             color: const Color(0xFF1976D2).withValues(alpha: 0.3),
//             blurRadius: 12,
//             offset: const Offset(0, 4),
//           ),
//         ],
//       ),
//       child: Material(
//         color: Colors.transparent,
//         child: InkWell(
//           borderRadius: BorderRadius.circular(16),
//           onTap: () {
//             // Navigator.push(
//             //   context,
//             //   MaterialPageRoute(builder: (_) => AddOilScreen(preselectMotorId: motorId)),
//             // );
//           },
//           child: const Padding(
//             padding: EdgeInsets.symmetric(vertical: 14, horizontal: 20),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Icon(Icons.build_circle_rounded, color: Colors.white, size: 22),
//                 SizedBox(width: 10),
//                 Text(
//                   'Catat Ganti Oli',
//                   style: TextStyle(
//                     color: Colors.white,
//                     fontSize: 15,
//                     fontWeight: FontWeight.bold,
//                     letterSpacing: 0.2,
//                   ),
//                 ),
//                 SizedBox(width: 8),
//                 Icon(Icons.arrow_forward_rounded, color: Colors.white70, size: 18),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   /// 3. Timeline Riwayat Oli dengan Delta KM
//   Widget _buildTimelineSection(List<OilRecord> records, bool isDark) {
//     final textPrimary = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
//     final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
//     final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
//     final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Row(
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             Text(
//               'Riwayat Servis & Ganti Oli',
//               style: TextStyle(
//                 fontSize: 16,
//                 fontWeight: FontWeight.bold,
//                 color: textPrimary,
//               ),
//             ),
//             Container(
//               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
//               decoration: BoxDecoration(
//                 color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
//                 borderRadius: BorderRadius.circular(12),
//               ),
//               child: Text(
//                 '${records.length} Catatan',
//                 style: TextStyle(
//                   fontSize: 11,
//                   fontWeight: FontWeight.w600,
//                   color: textSecondary,
//                 ),
//               ),
//             ),
//           ],
//         ),
//         const SizedBox(height: 12),
//         if (records.isEmpty)
//           Container(
//             padding: const EdgeInsets.all(24),
//             decoration: BoxDecoration(
//               color: cardBg,
//               borderRadius: BorderRadius.circular(16),
//               border: Border.all(color: borderColor),
//             ),
//             child: Center(
//               child: Column(
//                 children: [
//                   Icon(Icons.history_rounded, size: 40, color: textSecondary),
//                   const SizedBox(height: 8),
//                   Text(
//                     'Belum ada catatan ganti oli',
//                     style: TextStyle(
//                       fontSize: 14,
//                       fontWeight: FontWeight.w600,
//                       color: textPrimary,
//                     ),
//                   ),
//                   const SizedBox(height: 4),
//                   Text(
//                     'Tekan "Catat Ganti Oli" untuk mulai mencatat.',
//                     style: TextStyle(fontSize: 12, color: textSecondary),
//                   ),
//                 ],
//               ),
//             ),
//           )
//         else
//           Column(
//             children: List.generate(records.length, (i) {
//               final r = records[i];
//               final isLast = i == records.length - 1;

//               int? deltaKm;
//               if (i < records.length - 1) {
//                 deltaKm = r.odometer - records[i + 1].odometer;
//               }

//               return IntrinsicHeight(
//                 child: Row(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     // Node Indikator & Garis Vertikal
//                     Column(
//                       children: [
//                         Container(
//                           width: 24,
//                           height: 24,
//                           decoration: BoxDecoration(
//                             color: i == 0 ? const Color(0xFF1976D2) : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
//                             shape: BoxShape.circle,
//                           ),
//                           child: Icon(
//                             Icons.check_rounded,
//                             size: 14,
//                             color: i == 0 ? Colors.white : textSecondary,
//                           ),
//                         ),
//                         if (!isLast)
//                           Expanded(
//                             child: Container(
//                               width: 2,
//                               margin: const EdgeInsets.symmetric(vertical: 4),
//                               color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
//                             ),
//                           ),
//                       ],
//                     ),

//                     const SizedBox(width: 12),

//                     // Kartu Catatan Odometer & Delta
//                     Expanded(
//                       child: Padding(
//                         padding: const EdgeInsets.only(bottom: 12),
//                         child: Container(
//                           decoration: BoxDecoration(
//                             color: cardBg,
//                             borderRadius: BorderRadius.circular(16),
//                             border: Border.all(
//                               color: i == 0
//                                   ? const Color(0xFF1976D2).withValues(alpha: 0.3)
//                                   : borderColor,
//                             ),
//                             boxShadow: [
//                               BoxShadow(
//                                 color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
//                                 blurRadius: 8,
//                                 offset: const Offset(0, 2),
//                               ),
//                             ],
//                           ),
//                           padding: const EdgeInsets.all(14),
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               // Baris Odometer & Tombol Hapus
//                               Row(
//                                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                                 children: [
//                                   Row(
//                                     children: [
//                                       Text(
//                                         '${NumberFormat('#,###').format(r.odometer)} KM',
//                                         style: TextStyle(
//                                           fontSize: 16,
//                                           fontWeight: FontWeight.bold,
//                                           color: textPrimary,
//                                         ),
//                                       ),
//                                       const SizedBox(width: 8),
//                                       if (deltaKm != null && deltaKm > 0)
//                                         Container(
//                                           padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//                                           decoration: BoxDecoration(
//                                             color: const Color(0xFF1976D2).withValues(alpha: 0.15),
//                                             borderRadius: BorderRadius.circular(6),
//                                           ),
//                                           child: Text(
//                                             '+${NumberFormat('#,###').format(deltaKm)} KM',
//                                             style: TextStyle(
//                                               fontSize: 11,
//                                               fontWeight: FontWeight.bold,
//                                               color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1565C0),
//                                             ),
//                                           ),
//                                         )
//                                       else if (isLast)
//                                         Container(
//                                           padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//                                           decoration: BoxDecoration(
//                                             color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
//                                             borderRadius: BorderRadius.circular(6),
//                                           ),
//                                           child: Text(
//                                             'Catatan Awal',
//                                             style: TextStyle(
//                                               fontSize: 10,
//                                               fontWeight: FontWeight.w600,
//                                               color: textSecondary,
//                                             ),
//                                           ),
//                                         ),
//                                     ],
//                                   ),
//                                   InkWell(
//                                     onTap: () => _deleteOilRecord(r),
//                                     borderRadius: BorderRadius.circular(8),
//                                     child: Padding(
//                                       padding: const EdgeInsets.all(4),
//                                       child: Icon(
//                                         Icons.delete_outline_rounded,
//                                         size: 18,
//                                         color: textSecondary,
//                                       ),
//                                     ),
//                                   ),
//                                 ],
//                               ),

//                               const SizedBox(height: 8),

//                               // Info Tanggal & Pencatat
//                               Row(
//                                 children: [
//                                   Icon(Icons.calendar_today_rounded, size: 12, color: textSecondary),
//                                   const SizedBox(width: 4),
//                                   Text(
//                                     DateFormat('dd MMMM yyyy').format(r.performedAt),
//                                     style: TextStyle(fontSize: 12, color: textSecondary),
//                                   ),
//                                   const SizedBox(width: 12),
//                                   Icon(Icons.person_outline_rounded, size: 13, color: textSecondary),
//                                   const SizedBox(width: 4),
//                                   Flexible(
//                                     child: Text(
//                                       r.performedByName?.isNotEmpty == true ? r.performedByName! : 'Pengguna',
//                                       style: TextStyle(
//                                         fontSize: 12,
//                                         color: textPrimary,
//                                         fontWeight: FontWeight.w500,
//                                       ),
//                                       overflow: TextOverflow.ellipsis,
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               );
//             }),
//           ),
//       ],
//     );
//   }

//   /// 4. Spesifikasi Kendaraan (Modern Specs Grid)
//   Widget _buildVehicleSpecsCard(Motorcycle moto, bool isDark) {
//     final textPrimary = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
//     final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
//     final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
//     final dividerColor = isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           'Spesifikasi Kendaraan',
//           style: TextStyle(
//             fontSize: 16,
//             fontWeight: FontWeight.bold,
//             color: textPrimary,
//           ),
//         ),
//         const SizedBox(height: 12),
//         Container(
//           decoration: BoxDecoration(
//             color: cardBg,
//             borderRadius: BorderRadius.circular(20),
//             border: Border.all(color: borderColor),
//             boxShadow: [
//               BoxShadow(
//                 color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
//                 blurRadius: 10,
//                 offset: const Offset(0, 2),
//               ),
//             ],
//           ),
//           padding: const EdgeInsets.all(16),
//           child: Column(
//             children: [
//               Row(
//                 children: [
//                   Expanded(
//                     child: _buildSpecItem(
//                       icon: Icons.two_wheeler_rounded,
//                       label: 'Merk & Tipe',
//                       value: '${moto.brand} ${moto.model}',
//                       isDark: isDark,
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: _buildSpecItem(
//                       icon: Icons.pin_rounded,
//                       label: 'Plat Nomor',
//                       value: moto.plate != null && moto.plate!.isNotEmpty ? moto.plate! : 'Tidak ada',
//                       isDark: isDark,
//                     ),
//                   ),
//                 ],
//               ),
//               Padding(
//                 padding: const EdgeInsets.symmetric(vertical: 12),
//                 child: Divider(height: 1, color: dividerColor),
//               ),
//               Row(
//                 children: [
//                   Expanded(
//                     child: _buildSpecItem(
//                       icon: Icons.calendar_month_rounded,
//                       label: 'Tahun Pembuatan',
//                       value: moto.year != null && moto.year!.isNotEmpty ? moto.year! : '-',
//                       isDark: isDark,
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: _buildSpecItem(
//                       icon: Icons.palette_outlined,
//                       label: 'Warna Motor',
//                       value: moto.color != null && moto.color!.isNotEmpty ? moto.color! : '-',
//                       isDark: isDark,
//                     ),
//                   ),
//                 ],
//               ),
//               Padding(
//                 padding: const EdgeInsets.symmetric(vertical: 12),
//                 child: Divider(height: 1, color: dividerColor),
//               ),
//               Row(
//                 children: [
//                   Expanded(
//                     child: _buildSpecItem(
//                       icon: Icons.speed_rounded,
//                       label: 'Interval Pengingat',
//                       value: 'Setiap ${NumberFormat('#,###').format(moto.reminderIntervalKm)} KM',
//                       isDark: isDark,
//                     ),
//                   ),
//                   const SizedBox(width: 12),
//                   Expanded(
//                     child: _buildSpecItem(
//                       icon: moto.isGroupMotor ? Icons.group_rounded : Icons.person_rounded,
//                       label: 'Status Akses',
//                       value: moto.isGroupMotor ? 'Grup Keluarga' : 'Pribadi',
//                       isDark: isDark,
//                     ),
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildSpecItem({
//     required IconData icon,
//     required String label,
//     required String value,
//     required bool isDark,
//   }) {
//     final textPrimary = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
//     final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
//     final iconBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

//     return Row(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Container(
//           padding: const EdgeInsets.all(7),
//           decoration: BoxDecoration(
//             color: iconBg,
//             borderRadius: BorderRadius.circular(8),
//           ),
//           child: Icon(icon, size: 16, color: const Color(0xFF1976D2)),
//         ),
//         const SizedBox(width: 10),
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 label,
//                 style: TextStyle(
//                   fontSize: 11,
//                   color: textSecondary,
//                 ),
//               ),
//               const SizedBox(height: 2),
//               Text(
//                 value,
//                 style: TextStyle(
//                   fontSize: 13,
//                   fontWeight: FontWeight.w600,
//                   color: textPrimary,
//                 ),
//                 maxLines: 2,
//                 overflow: TextOverflow.ellipsis,
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }
