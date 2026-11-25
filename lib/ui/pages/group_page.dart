import 'package:flutter/material.dart';
import 'package:motorqu_solid/models/family_group.dart';
import 'package:motorqu_solid/services/database_service.dart';
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

class _GroupPageState extends State<GroupPage> {
  final DatabaseService _db = DatabaseService();
  final String _myUid = "";

  late Future<List<FamilyGroup>> _groupsFuture;
  String? _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _db.group.getUserGroupsList();
  }

  Future<void> _refreshGroups() async {
    final future = _db.group.getUserGroupsList();
    setState(() {
      _groupsFuture = future;
    });
    await future;
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
      final newId = await _db.group.createGroup(name);
      setState(() => _selectedGroupId = newId);
      _toast('Grup "$name" berhasil dibuat');
      _refreshGroups();
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
      // Muat ulang daftar grup atau pilih grup yang baru dimasuki
      await _refreshGroups();
    }
  }

  Future<void> _editGroupName(FamilyGroup group) async {
    final newName = await showEditGroupNameDialog(context, group.name);
    if (newName == null || newName.isEmpty || newName == group.name) return;
    try {
      await _db.group.updateGroupName(group.id, newName);
      _toast('Nama grup diperbarui');
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
          ? 'Anda adalah pembuat utama grup "${group.name}". Jika Anda keluar, '
                'kepemilikan akan dialihkan atau grup akan ditutup jika tidak ada anggota lain.'
          : (isOwner
                ? 'Anda adalah salah satu owner di grup "${group.name}". Jika keluar, status owner Anda akan dilepas dan motor Anda otomatis ditarik kembali ke motor pribadi.'
                : 'Motor milik Anda yang dibagikan ke grup "${group.name}" akan otomatis '
                      'ditarik kembali menjadi motor pribadi Anda.'),
      confirmLabel: 'Keluar',
      confirmColor: GroupPalette.danger,
    );
    if (!ok) return;

    try {
      await _db.group.leaveGroup(group.id);
      _toast('Anda telah keluar dari grup "${group.name}"');
      setState(() => _selectedGroupId = null);
      _refreshGroups();
    } catch (e) {
      _toast('Gagal keluar: $e');
    }
  }

  // ----------------------------- Aksi motor -----------------------------

  Future<void> _addMotorToGroup(FamilyGroup group) async {
    try {
      final myPrivates = await _db.group.getUserPrivateMotorcycles();
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
        await _db.group.assignMotorcycleToGroup(chosen.id, group.id);
        _toast('Motor "${chosen.name}" berhasil dimasukkan ke garasi grup');
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
      await _db.group.removeMotorcycleFromGroup(moto.id);
      _toast('Motor "${moto.name}" telah dikembalikan ke motor pribadi');
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
      await _db.group.kickMember(group.id, targetUid);
      _toast('"$memberName" telah dikeluarkan dari grup');
      setState(() {});
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
      await _db.group.promoteMemberToOwner(group.id, targetUid);
      _toast('"$memberName" sekarang menjadi Owner grup');
      setState(() {});
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
      await _db.group.demoteOwner(group.id, targetUid);
      _toast('Status owner "$memberName" telah dicabut');
      setState(() {});
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
          onPressed: () => Navigator.pop(context),
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
          GroupActionsMenu(onCreate: _createGroup, onJoin: _joinGroup),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshGroups,
        child: FutureBuilder<List<FamilyGroup>>(
          future: _groupsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _RefreshableLoading();
            }
            final groups = snapshot.data ?? [];

            if (groups.isEmpty) {
              return NoGroupView(onCreate: _createGroup, onJoin: _joinGroup);
            }

            if (_selectedGroupId == null ||
                !groups.any((g) => g.id == _selectedGroupId)) {
              _selectedGroupId = groups.first.id;
            }

            final activeGroup = groups.firstWhere(
              (g) => g.id == _selectedGroupId,
              orElse: () => groups.first,
            );

            return _buildGroupDetail(groups, activeGroup);
          },
        ),
      ),
    );
  }

  Widget _buildGroupDetail(List<FamilyGroup> allGroups, FamilyGroup active) {
    final isOwner = active.isOwner(_myUid);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
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
          motorcyclesFuture: _db.group.getGroupMotorcycles(active.id),
          myUid: _myUid,
          isOwner: isOwner,
          onAddMotor: () => _addMotorToGroup(active),
          onRemoveMotor: _removeMotorFromGroup,
        ),
        const SizedBox(height: 24),
        GroupMemberSection(
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
