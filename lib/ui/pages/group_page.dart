import 'package:flutter/material.dart';
import 'package:motorqu_solid/models/family_group.dart';
import 'package:motorqu_solid/services/app_refresh.dart';
import 'package:motorqu_solid/services/database_service.dart';
import 'package:motorqu_solid/services/group_service.dart';
import 'package:motorqu_solid/ui/pages/join_group_scanner_page.dart';
import 'package:motorqu_solid/ui/widgets/group/group_actions_menu.dart';
import 'package:motorqu_solid/ui/widgets/group/group_common.dart';
import 'package:motorqu_solid/ui/widgets/group/group_dialogs.dart';
import 'package:motorqu_solid/ui/widgets/group/group_header_card.dart';
import 'package:motorqu_solid/ui/widgets/group/group_member_section.dart';
import 'package:motorqu_solid/ui/widgets/group/group_motor_section.dart';
import 'package:motorqu_solid/ui/widgets/group/group_switcher.dart';
import 'package:motorqu_solid/ui/widgets/group/leave_group_button.dart';
import 'package:motorqu_solid/ui/widgets/group/no_group_view.dart';
import 'package:motorqu_solid/ui/widgets/group/pending_group_card.dart';
import 'package:motorqu_solid/ui/widgets/group/pick_motor_sheet.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/ui/widgets/invite_qr_dialog.dart';

/// Kelola Grup Keluarga (Referensi Mobbin: Amazon Family & Lyft Family Hub).
///
/// File ini hanya berisi state dan logika. Tampilan dipecah ke
/// `ui/widgets/group/`.
class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage>
    with AutoRefreshMixin<GroupPage> {
  final DatabaseService _db = DatabaseService();
  String get _myUid => _db.webId;

  late Future<({List<FamilyGroup> groups, List<PendingGroup> pending})>
  _groupsFuture;
  String? _selectedGroupId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _db.group.getGroupListing();
    _groupsFuture.then((_) => markLoaded(), onError: (_) {});
  }

  // Anggota baru / motor yang dibagikan anggota lain muncul tanpa
  // pull-to-refresh. Tidak berjalan saat aksi grup sedang diproses.
  @override
  Duration get autoRefreshMaxAge => const Duration(minutes: 2);

  @override
  bool get isAutoRefreshVisible => !_isLoading;

  @override
  Future<void> autoRefresh() => _refreshGroups();

  Future<void> _refreshGroups() async {
    final future = _db.group.getGroupListing();
    if (mounted) {
      setState(() {
        _groupsFuture = future;
      });
    }
    await future;
    markLoaded();
  }

  Future<T> _withLoading<T>(Future<T> Function() action) async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      return await action();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: GroupPalette.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ----------------------------- Aksi grup -----------------------------

  Future<void> _createGroup() async {
    final name = await showCreateGroupDialog(context);
    if (name == null || name.isEmpty) return;
    try {
      await _withLoading(() async {
        final newId = await _db.group.createGroup(name);
        if (mounted) {
          setState(() => _selectedGroupId = newId);
        }
      });
      _toast('Grup "$name" berhasil dibuat');
      await _refreshGroups();
    } catch (e) {
      _toast('Gagal buat grup: $e');
    }
  }

  Future<void> _joinGroup() async {
    final joinedGroupId = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (BuildContext context) {
          return JoinGroupScannerPage(groupService: _db.group);
        },
      ),
    );

    if (joinedGroupId != null && mounted) {
      // Pilih grup yang baru dimasuki (bila sudah aktif) lalu muat ulang.
      setState(() => _selectedGroupId = joinedGroupId);
      await _refreshGroups();
    }
  }

  List<Widget> _pendingCards(List<PendingGroup> pending) => [
    for (final g in pending)
      PendingGroupCard(key: ValueKey('pending-${g.groupId}'), group: g),
  ];

  Future<void> _editGroupName(FamilyGroup group) async {
    final newName = await showEditGroupNameDialog(context, group.name);
    if (newName == null || newName.isEmpty || newName == group.name) return;
    try {
      await _withLoading(() async {
        await _db.group.updateGroupName(group.id, newName);
      });
      _toast('Nama grup diperbarui');
      await _refreshGroups();
    } catch (e) {
      _toast('Gagal ubah nama: $e');
    }
  }

  Future<void> _generateInvite(FamilyGroup group) async {
    try {
      // final code = await _db.group.createInviteCode(group.id);
      await showInviteQrDialog(
        context: context,
        groupService: _db.group,
        groupId: group.id,
        groupName: group.name,
      );
    } catch (e) {
      _toast('Gagal membuat kode: $e');
    }
  }

  Future<void> _leaveGroup(FamilyGroup group) async {
    final isOwner = group.isOwner(_myUid);
    final isCreator = group.ownerId == _myUid;

    final ok = await showConfirmDialog(
      context,
      title: isCreator
          ? 'Hapus/Tinggalkan Grup'
          : (isOwner ? 'Keluar dari Grup (Owner)' : 'Keluar dari Grup'),
      message: isCreator
          ? 'Anda adalah pembuat utama grup "${group.name}" dan data grup tersimpan di Pod Anda. '
                'Anda hanya bisa keluar setelah semua anggota lain dikeluarkan; grup lalu dihapus.'
          : (isOwner
                ? 'Anda adalah salah satu owner di grup "${group.name}". Jika keluar, status owner Anda akan dilepas dan motor Anda otomatis ditarik kembali ke motor pribadi.'
                : 'Motor milik Anda yang dibagikan ke grup "${group.name}" akan otomatis '
                      'ditarik kembali menjadi motor pribadi Anda.'),
      confirmLabel: 'Keluar',
      confirmColor: GroupPalette.danger,
    );
    if (!ok) return;

    try {
      await _withLoading(() async {
        await _db.group.leaveGroup(group.id);
        if (mounted) {
          setState(() => _selectedGroupId = null);
        }
      });
      _toast('Anda telah keluar dari grup "${group.name}"');
      await _refreshGroups();
    } catch (e) {
      _toast('Gagal keluar: $e');
    }
  }

  // ----------------------------- Aksi motor -----------------------------

  Future<void> _addMotorToGroup(FamilyGroup group) async {
    try {
      final myPrivates = await _withLoading(
        _db.group.getUserPrivateMotorcycles,
      );
      if (!mounted) return;

      if (myPrivates.isEmpty) {
        await showNoPrivateMotorDialog(context);
        return;
      }

      final Motorcycle? chosen = await showPickMotorSheet(
        context,
        groupName: group.name,
        motorcycles: myPrivates,
      );
      if (chosen == null) return;

      try {
        await _withLoading(() async {
          await _db.group.assignMotorcycleToGroup(chosen.id, group.id);
        });
        _toast('Motor "${chosen.name}" berhasil dimasukkan ke garasi grup');
        await _refreshGroups();
      } catch (e) {
        _toast('Gagal memasukkan motor: $e');
      }
    } catch (e) {
      _toast('Gagal memuat motor pribadi: $e');
    }
  }

  Future<void> _removeMotorFromGroup(Motorcycle moto) async {
    final ok = await showConfirmDialog(
      context,
      icon: Icons.remove_circle_outline_rounded,
      iconColor: GroupPalette.warning,
      title: 'Keluarkan Motor?',
      message: 'Motor yang dikeluarkan dari grup akan otomatis kembali menjadi motor pribadi dari pemilik yang menambahkannya.',
      confirmLabel: 'Keluarkan',
      confirmColor: GroupPalette.warning,
    );
    if (!ok) return;

    try {
      await _withLoading(() async {
        await _db.group.removeMotorcycleFromGroup(
          moto.id,
          motorResourceUrl: moto.resourceUrl,
        );
      });
      _toast('Motor "${moto.name}" telah dikembalikan ke motor pribadi');
      await _refreshGroups();
    } catch (e) {
      _toast('Gagal mengeluarkan motor: $e');
    }
  }

  // ----------------------------- Aksi anggota -----------------------------

  Future<void> _kickMember(
    FamilyGroup group,
    Map<String, dynamic> member,
  ) async {
    final memberName = member['displayName'] ?? 'Anggota';
    final targetUid = member['uid'] as String;

    final ok = await showConfirmDialog(
      context,
      icon: Icons.person_remove_rounded,
      iconColor: GroupPalette.danger,
      title: 'Keluarkan Anggota?',
      message:
          'Yakin ingin mengeluarkan "$memberName" dari grup "${group.name}"?\n\n'
          'Motor milik "$memberName" yang ada di dalam grup ini akan otomatis ditarik kembali menjadi motor pribadinya.',
      confirmLabel: 'Keluarkan',
      confirmColor: GroupPalette.danger,
    );
    if (!ok) return;

    try {
      await _withLoading(() async {
        await _db.group.kickMember(group.id, targetUid);
      });
      _toast('"$memberName" telah dikeluarkan dari grup');
      await _refreshGroups();
    } catch (e) {
      _toast('Gagal mengeluarkan anggota: $e');
    }
  }

  Future<void> _promoteMemberToOwner(
    FamilyGroup group,
    Map<String, dynamic> member,
  ) async {
    final memberName = member['displayName'] ?? 'Anggota';
    final targetUid = member['uid'] as String;

    final ok = await showConfirmDialog(
      context,
      icon: Icons.military_tech_rounded,
      iconColor: GroupPalette.primary,
      title: 'Jadikan Owner / Admin?',
      message:
          'Angkat "$memberName" sebagai Owner / Admin grup "${group.name}"?\n\n'
          'Grup ini mendukung sistem banyak owner. "$memberName" akan memiliki hak untuk mengelola motor dan anggota grup.',
      confirmLabel: 'Jadikan Owner',
      confirmColor: GroupPalette.primary,
    );
    if (!ok) return;

    try {
      await _withLoading(() async {
        await _db.group.promoteMemberToOwner(group.id, targetUid);
      });
      _toast('"$memberName" sekarang menjadi Owner grup');
      await _refreshGroups();
    } catch (e) {
      _toast('Gagal mengangkat owner: $e');
    }
  }

  Future<void> _demoteOwner(
    FamilyGroup group,
    Map<String, dynamic> member,
  ) async {
    final memberName = member['displayName'] ?? 'Anggota';
    final targetUid = member['uid'] as String;

    final ok = await showConfirmDialog(
      context,
      icon: Icons.remove_moderator_rounded,
      iconColor: GroupPalette.warning,
      title: 'Turunkan Status Owner?',
      message:
          'Turunkan "$memberName" menjadi anggota biasa di grup "${group.name}"?',
      confirmLabel: 'Turunkan',
      confirmColor: GroupPalette.warning,
    );
    if (!ok) return;

    try {
      await _withLoading(() async {
        await _db.group.demoteOwner(group.id, targetUid);
      });
      _toast('Status owner "$memberName" telah dicabut');
      await _refreshGroups();
    } catch (e) {
      _toast('Gagal mencabut status owner: $e');
    }
  }

  // ----------------------------- Tampilan -----------------------------

  @override
  Widget build(BuildContext context) {
    final p = GroupPalette.of(context);

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: _isLoading ? null : () => Navigator.pop(context),
        ),
        title: Text(
          'Kelola Grup Keluarga',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
            color: p.textPrimary,
          ),
        ),
        actions: [
          AbsorbPointer(
            absorbing: _isLoading,
            child: GroupActionsMenu(onCreate: _createGroup, onJoin: _joinGroup),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _refreshGroups,
            child:
                FutureBuilder<
                  ({List<FamilyGroup> groups, List<PendingGroup> pending})
                >(
                  future: _groupsFuture,
                  builder: (context, snapshot) {
                    // Spinner hanya saat belum ada data: auto-refresh tidak berkedip.
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const _RefreshableLoading();
                    }
                    final groups = snapshot.data?.groups ?? const [];
                    final pending = snapshot.data?.pending ?? const [];

                    if (groups.isEmpty && pending.isEmpty) {
                      return NoGroupView(
                        onCreate: _createGroup,
                        onJoin: _joinGroup,
                      );
                    }

                    if (groups.isEmpty) {
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: _pendingCards(pending),
                      );
                    }

                    if (_selectedGroupId == null ||
                        !groups.any((g) => g.id == _selectedGroupId)) {
                      _selectedGroupId = groups.first.id;
                    }

                    final activeGroup = groups.firstWhere(
                      (g) => g.id == _selectedGroupId,
                      orElse: () => groups.first,
                    );

                    return _buildGroupDetail(groups, activeGroup, pending);
                  },
                ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: AbsorbPointer(
                child: ColoredBox(
                  color: const Color(0x66000000),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupDetail(
    List<FamilyGroup> allGroups,
    FamilyGroup active,
    List<PendingGroup> pending,
  ) {
    final isOwner = active.isOwner(_myUid);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ..._pendingCards(pending),
        if (allGroups.length > 1) ...[
          GroupSwitcher(
            groups: allGroups,
            activeId: active.id,
            onChanged: (id) => setState(() => _selectedGroupId = id),
          ),
          const SizedBox(height: 12),
        ],
        GroupHeaderCard(
          group: active,
          isOwner: isOwner,
          onEditName: () => _editGroupName(active),
          onInvite: () => _generateInvite(active),
        ),
        const SizedBox(height: 24),
        GroupMotorSection(
          // Key per grup: ganti grup = state baru (tanpa data grup lama).
          key: ValueKey('motors-${active.id}'),
          motorcyclesFuture: _db.group.getGroupMotorcycles(active.id),
          myUid: _myUid,
          isOwner: isOwner,
          onAddMotor: () => _addMotorToGroup(active),
          onRemoveMotor: _removeMotorFromGroup,
        ),
        const SizedBox(height: 24),
        GroupMemberSection(
          key: ValueKey('members-${active.id}'),
          group: active,
          membersFuture: _db.group.getGroupMembers(active),
          currentUserId: _myUid,
          onPromote: (m) => _promoteMemberToOwner(active, m),
          onDemote: (m) => _demoteOwner(active, m),
          onKick: (m) => _kickMember(active, m),
        ),
        const SizedBox(height: 32),
        LeaveGroupButton(onPressed: () => _leaveGroup(active)),
      ],
    );
  }
}

/// Loading penuh layar yang tetap bisa di-pull-to-refresh.
class _RefreshableLoading extends StatelessWidget {
  const _RefreshableLoading();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}
