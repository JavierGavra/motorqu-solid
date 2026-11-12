import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/services/database_service.dart';

/// Form Tambah / Edit Motor Modern (Sectioned Card & Segmented Ownership).
class AddMotorPage extends StatefulWidget {
  final Motorcycle? moto;
  const AddMotorPage({super.key, this.moto});

  @override
  State<AddMotorPage> createState() => _AddMotorPageState();
}

class _AddMotorPageState extends State<AddMotorPage> {
  final _db = DatabaseService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late TextEditingController _name;
  late TextEditingController _brand;
  late TextEditingController _model;
  late TextEditingController _plate;
  late TextEditingController _year;
  late TextEditingController _color;
  late TextEditingController _kmInterval;
  late TextEditingController _initialKm;

  bool _isGroup = false;
  List<dynamic> _userGroups = [];
  String? _selectedGroupId;
  bool _loadingGroup = false;
  bool _saving = false;

  bool get _isEdit => widget.moto != null;

  @override
  void initState() {
    super.initState();
    final m = widget.moto;
    _name = TextEditingController(text: m?.name ?? '');
    _brand = TextEditingController(text: m?.brand ?? '');
    _model = TextEditingController(text: m?.model ?? '');
    _plate = TextEditingController(text: m?.plate ?? '');
    _year = TextEditingController(text: m?.year ?? '');
    _color = TextEditingController(text: m?.color ?? '');
    _kmInterval = TextEditingController(
      text: (m?.reminderIntervalKm ?? 2000).toString(),
    );
    _initialKm = TextEditingController(text: (m?.lastOdometer ?? 0).toString());
    _isGroup = m?.isGroupMotor ?? false;
    _loadGroup();
  }

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _model.dispose();
    _plate.dispose();
    _year.dispose();
    _color.dispose();
    _kmInterval.dispose();
    _initialKm.dispose();
    super.dispose();
  }

  Future<void> _loadGroup() async {
    // final uid = FirebaseAuth.instance.currentUser!.uid;
    // final groups = await _db.getUserGroupsList(uid);
    // if (mounted) {
    setState(() {
      //     _userGroups = groups;
      _loadingGroup = false;
      //     if (_isEdit && widget.moto!.isGroupMotor && groups.any((g) => g.id == widget.moto!.groupId)) {
      //       _isGroup = true;
      //       _selectedGroupId = widget.moto!.groupId;
      //     } else if (groups.isNotEmpty) {
      //       _selectedGroupId = groups.first.id;
      //     } else {
      //       _isGroup = false;
      //       _selectedGroupId = null;
      //     }
    });
    // }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final interval = int.tryParse(_kmInterval.text.trim()) ?? 2000;
      final initialKm = int.tryParse(_initialKm.text.trim()) ?? 0;

      String targetGroupId;
      if (_isGroup && _selectedGroupId != null) {
        targetGroupId = _selectedGroupId!;
      } else {
        targetGroupId = 'private';
      }

      if (_isEdit) {
        // final plateText = _plate.text.trim();
        // final yearText = _year.text.trim();
        // final colorText = _color.text.trim();

        // await _db.updateMotorcycleFields(
        //   widget.moto!.id,
        //   name: _name.text.trim(),
        //   brand: _brand.text.trim(),
        //   model: _model.text.trim(),
        //   plate: plateText.isEmpty ? null : plateText,
        //   year: yearText.isEmpty ? null : yearText,
        //   color: colorText.isEmpty ? null : colorText,
        //   clearPlate: plateText.isEmpty,
        //   clearYear: yearText.isEmpty,
        //   clearColor: colorText.isEmpty,
        //   reminderIntervalKm: interval,
        //   groupId: targetGroupId,
        //   isGroupMotor: _isGroup,
        // );
      } else {
        final moto = Motorcycle(
          id: '',
          name: _name.text.trim(),
          brand: _brand.text.trim(),
          model: _model.text.trim(),
          plate: _plate.text.trim().isEmpty ? null : _plate.text.trim(),
          year: _year.text.trim().isEmpty ? null : _year.text.trim(),
          color: _color.text.trim().isEmpty ? null : _color.text.trim(),
          groupId: targetGroupId,
          isGroupMotor: _isGroup,
          reminderIntervalKm: interval,
          lastOdometer: initialKm,
          createdBy: _db.webId,
          createdAt: DateTime.now(),
        );
        await _db.motorcycleService.addMotorcycle(moto);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEdit
                  ? 'Motor berhasil diperbarui'
                  : 'Motor baru berhasil ditambahkan',
            ),
            backgroundColor: const Color(0xFF1976D2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal menyimpan: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? const Color(0xFFF8FAFC)
        : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0B1120)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEdit ? 'Edit Motor' : 'Tambah Motor Baru',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
            color: textPrimary,
          ),
        ),
      ),
      body: _loadingGroup
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // 1. KARTU SEKSI: IDENTITAS KENDARAAN
                  _buildSectionHeader(
                    'Identitas Kendaraan',
                    Icons.two_wheeler_rounded,
                    isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildIdentityCard(isDark),

                  const SizedBox(height: 20),

                  // 2. KARTU SEKSI: ODOMETER & INTERVAL PENGINGAT
                  _buildSectionHeader(
                    'Odometer & Interval Servis',
                    Icons.speed_rounded,
                    isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildOdometerCard(isDark),

                  const SizedBox(height: 20),

                  // 3. KARTU SEKSI: KEPEMILIKAN & HAK AKSES
                  _buildSectionHeader(
                    'Kepemilikan Motor',
                    Icons.shield_outlined,
                    isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildOwnershipCard(isDark),

                  const SizedBox(height: 28),

                  // 4. TOMBOL SIMPAN
                  _buildSaveButton(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF1976D2)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
          ),
        ),
      ],
    );
  }

  Widget _buildIdentityCard(bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          TextFormField(
            controller: _name,
            decoration: _inputDecoration(
              label: 'Nama Panggilan Motor *',
              hint: 'contoh: Beat Merah, Vario Hitam',
              icon: Icons.bookmark_outline_rounded,
              isDark: isDark,
            ),
            validator: (v) => v == null || v.trim().isEmpty
                ? 'Nama panggilan wajib diisi'
                : null,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _brand,
                  decoration: _inputDecoration(
                    label: 'Merk *',
                    hint: 'Honda, Yamaha, dll',
                    isDark: isDark,
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Merk wajib diisi' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _model,
                  decoration: _inputDecoration(
                    label: 'Model / Tipe *',
                    hint: 'Beat CBS, NMax',
                    isDark: isDark,
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Model wajib diisi'
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _plate,
            textCapitalization: TextCapitalization.characters,
            decoration: _inputDecoration(
              label: 'Plat Nomor (opsional)',
              hint: 'B 1234 ABC',
              icon: Icons.pin_rounded,
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: _inputDecoration(
                    label: 'Tahun (opsional)',
                    hint: '2022',
                    isDark: isDark,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _color,
                  decoration: _inputDecoration(
                    label: 'Warna (opsional)',
                    hint: 'Hitam Glossy',
                    isDark: isDark,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOdometerCard(bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isEdit) ...[
            TextFormField(
              controller: _initialKm,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _inputDecoration(
                label: 'KM Odometer Saat Ini *',
                hint: '0',
                suffixText: 'KM',
                icon: Icons.speed_rounded,
                isDark: isDark,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'KM wajib diisi';
                final n = int.tryParse(v.trim());
                if (n == null || n < 0) return 'KM tidak valid';
                return null;
              },
            ),
            const SizedBox(height: 14),
          ],
          TextFormField(
            controller: _kmInterval,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _inputDecoration(
              label: 'Interval Pengingat Ganti Oli (KM) *',
              hint: '2000',
              suffixText: 'KM',
              icon: Icons.update_rounded,
              isDark: isDark,
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Interval wajib diisi';
              final n = int.tryParse(v.trim());
              if (n == null || n <= 0) return 'Interval harus > 0';
              return null;
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Pintasan Interval Cepat:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildIntervalChip('1.500 KM', 1500, isDark),
                const SizedBox(width: 8),
                _buildIntervalChip('⭐ 2.000 KM (Matic)', 2000, isDark),
                const SizedBox(width: 8),
                _buildIntervalChip('2.500 KM', 2500, isDark),
                const SizedBox(width: 8),
                _buildIntervalChip('3.000 KM (Bebek/Sport)', 3000, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntervalChip(String label, int val, bool isDark) {
    final currentVal = int.tryParse(_kmInterval.text.trim()) ?? 0;
    final isSelected = currentVal == val;

    final chipBg = isSelected
        ? const Color(0xFF1976D2).withValues(alpha: 0.15)
        : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9));
    final chipBorder = isSelected
        ? const Color(0xFF1976D2)
        : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1));

    return InkWell(
      onTap: () {
        setState(() {
          _kmInterval.text = val.toString();
        });
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: chipBorder, width: isSelected ? 1.4 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? (isDark ? const Color(0xFF60A5FA) : const Color(0xFF1565C0))
                : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
          ),
        ),
      ),
    );
  }

  Widget _buildOwnershipCard(bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final unselectedBg = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFF8FAFC);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Segmented Option 1: Motor Pribadi
          InkWell(
            onTap: () => setState(() => _isGroup = false),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: !_isGroup
                    ? const Color(0xFF1976D2).withValues(alpha: 0.12)
                    : unselectedBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: !_isGroup ? const Color(0xFF1976D2) : borderColor,
                  width: !_isGroup ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: !_isGroup ? const Color(0xFF1976D2) : borderColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      size: 18,
                      color: !_isGroup ? Colors.white : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Motor Pribadi',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hanya terlihat dan dipantau di akun Anda sendiri',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isGroup)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF1976D2),
                      size: 20,
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),

          // Segmented Option 2: Garasi Grup Keluarga
          InkWell(
            onTap: _userGroups.isEmpty
                ? null
                : () => setState(() => _isGroup = true),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _isGroup
                    ? const Color(0xFF2E7D32).withValues(alpha: 0.12)
                    : unselectedBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isGroup ? const Color(0xFF2E7D32) : borderColor,
                  width: _isGroup ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isGroup ? const Color(0xFF2E7D32) : borderColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.diversity_3_rounded,
                      size: 18,
                      color: _isGroup ? Colors.white : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userGroups.isEmpty
                              ? 'Bagikan ke Grup Keluarga (Belum Ada)'
                              : 'Bagikan ke Grup Keluarga',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _userGroups.isEmpty
                              ? 'Buat atau gabung grup dulu lewat tab Profil'
                              : 'Terlihat dan bisa dicatat olinya oleh seluruh anggota grup',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark
                                ? const Color(0xFF94A3B8)
                                : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isGroup)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF2E7D32),
                      size: 20,
                    ),
                ],
              ),
            ),
          ),

          if (_isGroup && _userGroups.isNotEmpty) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _selectedGroupId,
              dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF1976D2),
              ),
              decoration: _inputDecoration(
                label: 'Pilih Garasi Grup Tujuan *',
                icon: Icons.group_rounded,
                isDark: isDark,
              ),
              items: _userGroups.map((g) {
                return DropdownMenuItem<String>(
                  value: g.id,
                  child: Text(
                    g.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedGroupId = val);
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF1976D2), Color(0xFF1565C0)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _saving ? null : _save,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_saving) ...[
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Menyimpan Data...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ] else ...[
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _isEdit ? 'Simpan Perubahan' : 'Daftarkan Motor',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    String? suffixText,
    IconData? icon,
    required bool isDark,
  }) {
    final borderColor = isDark
        ? const Color(0xFF334155)
        : const Color(0xFFE2E8F0);
    final fillBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final labelColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffixText,
      prefixIcon: icon != null ? Icon(icon, size: 18, color: labelColor) : null,
      filled: true,
      fillColor: fillBg,
      labelStyle: TextStyle(fontSize: 13, color: labelColor),
      hintStyle: TextStyle(
        fontSize: 13,
        color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFF1976D2), width: 1.5),
      ),
    );
  }
}
