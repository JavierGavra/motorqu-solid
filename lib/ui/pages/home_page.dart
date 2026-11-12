import 'package:flutter/material.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/services/database_service.dart';
import 'package:motorqu_solid/ui/widgets/empty_state.dart';
import 'package:motorqu_solid/ui/widgets/filter_chip.dart';
import 'package:motorqu_solid/ui/widgets/motor_card.dart';
import 'package:motorqu_solid/ui/widgets/stat_item.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomePage> {
  String _filter = 'all'; // 'all', 'private', 'group'
  final _db = DatabaseService();
  List<Motorcycle> _motorcycles = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMotorcycles();
  }

  Future<void> _loadMotorcycles() async {
    try {
      final motorcycles = await _db.getMotorcycles();
      if (mounted) {
        setState(() => _motorcycles = motorcycles);
      }
    } catch (e) {
      debugPrint('Error loading motorcycles: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayName = 'Pengguna Demo';
    final firstName = displayName.split(' ').first;
    final allMotos = _motorcycles;

    // Hitung ringkasan oli
    int dueCount = 0;
    int safeCount = 0;
    for (final m in allMotos) {
      final isDue = _checkIsDue(m);
      if (isDue) {
        dueCount++;
      } else {
        safeCount++;
      }
    }

    // Terapkan filter
    List<Motorcycle> filteredMotos = allMotos;
    if (_filter == 'private') {
      filteredMotos = allMotos.where((m) => !m.isGroupMotor).toList();
    } else if (_filter == 'group') {
      filteredMotos = allMotos.where((m) => m.isGroupMotor).toList();
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadMotorcycles,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Modern Header
            SliverAppBar(
              floating: true,
              pinned: true,
              expandedHeight: 120,
              elevation: 0,
              backgroundColor: isDark
                  ? const Color(0xFF0B1120)
                  : const Color(0xFFF8FAFC),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        isDark
                            ? const Color(0xFF1E293B).withValues(alpha: 0.5)
                            : Colors.blue.shade50,
                        isDark
                            ? const Color(0xFF0B1120)
                            : const Color(0xFFF8FAFC),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 48, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Halo, $firstName! ',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: isDark
                                      ? const Color(0xFF94A3B8)
                                      : Colors.black54,
                                ),
                              ),
                              const Text('👋', style: TextStyle(fontSize: 15)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'MotorQu',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.5,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: const Color(0xFFE3F2FD),
                        backgroundImage: null,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Content
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (allMotos.isNotEmpty) ...[
                      // Status Overview Card (60-30-10 Brand Gradient)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1976D2), Color(0xFF1565C0)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1976D2)
                                  .withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            StatItem(
                              key: const ValueKey('total-motor-stat'),
                              value: '${allMotos.length}',
                              label: 'Total Motor',
                              icon: Icons.two_wheeler_rounded,
                              color: Colors.white,
                            ),
                            Container(
                              width: 1,
                              height: 38,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            StatItem(
                              value: '$safeCount',
                              label: 'Oli Aman',
                              icon: Icons.check_circle_rounded,
                              color: const Color(0xFF81C784),
                            ),
                            Container(
                              width: 1,
                              height: 38,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            StatItem(
                              value: '$dueCount',
                              label: 'Perlu Dicek',
                              icon: Icons.warning_amber_rounded,
                              color: dueCount > 0
                                  ? const Color(0xFFFFB74D)
                                  : Colors.white70,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            MotorFilterChip(
                              value: 'all',
                              label: 'Semua (${allMotos.length})',
                              isDark: isDark,
                              isSelected: _filter == 'all',
                              onSelected: (value) =>
                                  setState(() => _filter = value),
                            ),
                            const SizedBox(width: 8),
                            MotorFilterChip(
                              value: 'private',
                              label:
                                  'Pribadi (${allMotos.where((m) => !m.isGroupMotor).length})',
                              isDark: isDark,
                              isSelected: _filter == 'private',
                              onSelected: (value) =>
                                  setState(() => _filter = value),
                            ),
                            const SizedBox(width: 8),
                            MotorFilterChip(
                              value: 'group',
                              label:
                                  'Grup (${allMotos.where((m) => m.isGroupMotor).length})',
                              isDark: isDark,
                              isSelected: _filter == 'group',
                              onSelected: (value) =>
                                  setState(() => _filter = value),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),

            // Daftar Motor / Empty State (Dengan Extra Bottom Padding untuk Floating Dock)
            isLoading
                ? SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                : filteredMotos.isEmpty
                ? SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      isTotalEmpty: allMotos.isEmpty,
                      isDark: isDark,
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final moto = filteredMotos[index];
                        return MotorCard(moto: moto, isDark: isDark);
                      }, childCount: filteredMotos.length),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
