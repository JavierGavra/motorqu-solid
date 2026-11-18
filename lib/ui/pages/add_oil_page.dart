import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:motorqu_solid/models/motorcycle.dart';
import 'package:motorqu_solid/models/oil_record.dart';
import 'package:motorqu_solid/services/auth_service.dart';
import 'package:motorqu_solid/services/database_service.dart';
import 'package:motorqu_solid/ui/pages/add_motor_page.dart';

/// Form pencatatan ganti oli modern berbasis Solid Pod.
class AddOilPage extends StatefulWidget {
  final String? preselectMotorId;
  const AddOilPage({super.key, this.preselectMotorId});

  @override
  State<AddOilPage> createState() => _AddOilPageState();
}

class _AddOilPageState extends State<AddOilPage> {
  final DatabaseService _db = DatabaseService();
  final AuthService _auth = AuthService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _km = TextEditingController();

  List<Motorcycle> _motos = [];
  bool _loadingMotos = true;
  String? _selectedMotorId;
  DateTime _tanggal = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadMotos();
  }

  @override
  void dispose() {
    _km.dispose();
    super.dispose();
  }

  Future<void> _loadMotos() async {
    try {
      final motos = await _db.motorcycle.getMotorcycles();
      if (mounted) {
        setState(() {
          _motos = motos;
          _loadingMotos = false;

          if (motos.isNotEmpty) {
            final wanted = widget.preselectMotorId;
            if (wanted != null && motos.any((m) => m.id == wanted)) {
              _selectedMotorId = wanted;
            } else {
              _selectedMotorId = motos.first.id;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Gagal memuat daftar motor: $e');
      if (mounted) {
        setState(() => _loadingMotos = false);
      }
    }
  }

  Future<void> _pickDate() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final picked = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1976D2),
              brightness: isDark ? Brightness.dark : Brightness.light,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _tanggal = picked);
  }

  Future<void> _save() async {
    final moto = _motos.cast<Motorcycle?>().firstWhere(
          (m) => m?.id == _selectedMotorId,
          orElse: () => null,
        );
    if (moto == null) {
      _toast('Pilih motor terlebih dahulu');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final webId = _db.webId;
      final profile = await _auth.loadPodProfile();
      final performedByName = profile?.displayName ?? 'Pengguna';
      final km = int.parse(_km.text.trim());

      final record = OilRecord(
        id: '',
        motorcycleId: moto.id,
        performedAt: _tanggal,
        odometer: km,
        performedBy: webId,
        performedByName: performedByName,
        createdAt: DateTime.now(),
      );

      await _db.oil.addOilRecord(moto.id, record);

      try {
        await _scheduleReminder(moto, km);
      } catch (_) {}

      if (!mounted) return;
      _toast('Catatan ganti oli berhasil disimpan!');
      Navigator.pop(context, true);
    } catch (e) {
      _toast('Gagal menyimpan catatan: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Placeholder pengingat notifikasi (siap dihubungkan ketika NotificationService aktif)
  Future<void> _scheduleReminder(Motorcycle moto, int km) async {
    // TODO: Terhubung dengan modul Notifikasi tim ketika sudah siap.
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1976D2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _applyPresetKm(int lastKm, int addAmount) {
    final newKm = lastKm + addAmount;
    _km.text = newKm.toString();
    _km.selection =
        TextSelection.fromPosition(TextPosition(offset: _km.text.length));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Catat Ganti Oli',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: _loadingMotos
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1976D2)),
            )
          : _motos.isEmpty
              ? _buildEmptyMotors(isDark)
              : _buildForm(isDark),
    );
  }

  Widget _buildForm(bool isDark) {
    final selectedMotor = _motos.firstWhere(
      (m) => m.id == _selectedMotorId,
      orElse: () => _motos.first,
    );

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // 1. KARTU PILIH MOTOR (Dropdown Kustom)
          _buildMotorSelectorCard(_motos, selectedMotor, isDark),

          const SizedBox(height: 16),

          // 2. KARTU INPUT ODOMETER BESAR & TOMBOL PRESET
          _buildOdometerInputCard(selectedMotor, isDark),

          const SizedBox(height: 16),

          // 3. KARTU PEMILIH TANGGAL SERVIS
          _buildDatePickerCard(isDark),

          const SizedBox(height: 16),

          // 4. PREVIEW ESTIMASI TARGET BERIKUTNYA
          _buildNextTargetPreview(selectedMotor, isDark),

          const SizedBox(height: 28),

          // 5. TOMBOL SIMPAN
          _buildSaveButton(),
        ],
      ),
    );
  }

  /// 1. Kartu Pemilih Motor dengan Dropdown Kustom Rapi
  Widget _buildMotorSelectorCard(
    List<Motorcycle> motos,
    Motorcycle selectedMotor,
    bool isDark,
  ) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final fillBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PILIH KENDARAAN',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: selectedMotor.isGroupMotor
                      ? const Color(0xFF2E7D32).withValues(alpha: 0.15)
                      : const Color(0xFF1976D2).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  selectedMotor.isGroupMotor ? 'Grup Keluarga' : 'Pribadi',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: selectedMotor.isGroupMotor
                        ? (isDark
                            ? const Color(0xFF4ADE80)
                            : const Color(0xFF2E7D32))
                        : (isDark
                            ? const Color(0xFF60A5FA)
                            : const Color(0xFF1976D2)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Dropdown Kustom dengan Menu Rounded & Ikon Halus
          DropdownButtonFormField<String>(
            initialValue: _selectedMotorId,
            dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF1976D2),
            ),
            items: motos.map((m) {
              final detail = m.brand.isNotEmpty || m.model.isNotEmpty
                  ? ' (${m.brand} ${m.model})'
                  : '';
              final plate =
                  m.plate != null && m.plate!.isNotEmpty ? ' • ${m.plate}' : '';
              return DropdownMenuItem<String>(
                value: m.id,
                child: Text(
                  '${m.name}$detail$plate',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _selectedMotorId = val);
              }
            },
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              filled: true,
              fillColor: fillBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: borderColor),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 14,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                'Odometer Servis Terakhir: ',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : Colors.grey.shade600,
                ),
              ),
              Text(
                '${NumberFormat('#,###').format(selectedMotor.lastOdometer)} KM',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 2. Kartu Input Odometer Besar & Tombol Preset
  Widget _buildOdometerInputCard(Motorcycle selectedMotor, bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final fillBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final lastKm = selectedMotor.lastOdometer;
    final defaultInterval = selectedMotor.reminderIntervalKm;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.speed_rounded,
                    size: 18,
                    color: Color(0xFF1976D2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'KM Odometer Saat Ini',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF334155)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Wajib',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Input Odometer
          TextFormField(
            controller: _km,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              hintText: lastKm > 0 ? '${lastKm + defaultInterval}' : '12500',
              hintStyle: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? const Color(0xFF475569)
                    : Colors.grey.shade300,
              ),
              suffixIcon: Container(
                margin: const EdgeInsets.all(8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1976D2).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'KM',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1976D2),
                  ),
                ),
              ),
              filled: true,
              fillColor: fillBg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide:
                    const BorderSide(color: Color(0xFF1976D2), width: 2),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'KM wajib diisi';
              final n = int.tryParse(v.trim());
              if (n == null || n <= 0) return 'KM tidak valid';
              if (n < lastKm) {
                return 'KM harus >= KM servis terakhir ($lastKm)';
              }
              return null;
            },
          ),

          const SizedBox(height: 16),

          // Preset Chips Pintasan Cepat
          Text(
            'Pintasan Cepat (+Interval dari Terakhir):',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPresetChip(
                  label: '+1.500 KM',
                  onTap: () => _applyPresetKm(lastKm, 1500),
                  isDefault: defaultInterval == 1500,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildPresetChip(
                  label: '+2.000 KM',
                  onTap: () => _applyPresetKm(lastKm, 2000),
                  isDefault: defaultInterval == 2000,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildPresetChip(
                  label: '+2.500 KM',
                  onTap: () => _applyPresetKm(lastKm, 2500),
                  isDefault: defaultInterval == 2500,
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildPresetChip(
                  label: '+3.000 KM',
                  onTap: () => _applyPresetKm(lastKm, 3000),
                  isDefault: defaultInterval == 3000,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip({
    required String label,
    required VoidCallback onTap,
    required bool isDefault,
    required bool isDark,
  }) {
    final chipBg = isDefault
        ? const Color(0xFF1976D2).withValues(alpha: 0.15)
        : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9));
    final chipBorder = isDefault
        ? const Color(0xFF1976D2)
        : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: chipBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: chipBorder, width: isDefault ? 1.4 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDefault) ...[
              const Icon(
                Icons.star_rounded,
                size: 14,
                color: Color(0xFF1976D2),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isDefault ? FontWeight.bold : FontWeight.w600,
                color: isDefault
                    ? (isDark
                        ? const Color(0xFF60A5FA)
                        : const Color(0xFF1565C0))
                    : (isDark
                        ? const Color(0xFFCBD5E1)
                        : const Color(0xFF334155)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 3. Kartu Pemilih Tanggal
  Widget _buildDatePickerCard(bool isDark) {
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1976D2).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  size: 20,
                  color: Color(0xFF1976D2),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tanggal Ganti Oli',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('dd MMMM yyyy').format(_tanggal),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
            ],
          ),
          OutlinedButton(
            onPressed: _pickDate,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              side: BorderSide(color: borderColor),
            ),
            child: const Text('Ubah', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// 4. Kartu Preview Target Servis Berikutnya
  Widget _buildNextTargetPreview(Motorcycle moto, bool isDark) {
    final previewBg =
        isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
    final borderColor =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _km,
      builder: (context, value, _) {
        final enteredKm = int.tryParse(value.text.trim()) ?? 0;
        final nextTargetKm = enteredKm > 0
            ? enteredKm + moto.reminderIntervalKm
            : moto.lastOdometer + moto.reminderIntervalKm;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: previewBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.notifications_active_outlined,
                color: Color(0xFF1976D2),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimasi Target Servis Berikutnya: ${NumberFormat('#,###').format(nextTargetKm)} KM',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pengingat berkala 30 hari akan terjadwal di perangkat Anda.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 5. Tombol Simpan
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
                    'Menyimpan Catatan...',
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
                  const Text(
                    'Simpan Catatan Oli',
                    style: TextStyle(
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

  Widget _buildEmptyMotors(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.two_wheeler_rounded,
                size: 64,
                color: Color(0xFF1976D2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Belum Ada Motor',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tambahkan motor pertamamu terlebih dahulu sebelum mencatat riwayat ganti oli.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const AddMotorPage()),
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah Motor Sekarang'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1976D2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
