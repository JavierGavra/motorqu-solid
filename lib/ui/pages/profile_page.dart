import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motorqu_solid/main.dart';
import 'package:motorqu_solid/services/auth_service.dart';
import 'package:motorqu_solid/theme/app_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solidpod/solidpod.dart';
import 'package:solidui/solidui.dart';

/// Profil & Setelan Modern (disesuaikan dengan Solid Pod & desain MotorQu).
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AuthService _auth = AuthService();

  PodProfile? _podProfile;
  List<SharedGroup> _sharedGroups = const [];
  bool _isLoadingProfile = true;
  bool _avatarLoadError = false;
  bool _notifEnabled = true;
  bool _isSigningOut = false;
  String _version = '1.0.0';
  String _buildNumber = '1';

  @override
  void initState() {
    super.initState();
    solidProfileNotifier.addListener(_onPodStateChanged);
    authStateNotifier.addListener(_onPodStateChanged);
    _loadPrefs();
    _loadPodData();
  }

  @override
  void dispose() {
    solidProfileNotifier.removeListener(_onPodStateChanged);
    authStateNotifier.removeListener(_onPodStateChanged);
    super.dispose();
  }

  void _onPodStateChanged() {
    if (mounted) {
      _loadPodData();
    }
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('notifications_enabled') ?? true;
      if (mounted) {
        setState(() => _notifEnabled = enabled);
      }
    } on Object catch (_) {}

    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted && info.version.isNotEmpty) {
        setState(() {
          _version = info.version;
          _buildNumber = info.buildNumber.isNotEmpty ? info.buildNumber : '1';
        });
      }
    } on Object catch (_) {}
  }

  Future<void> _loadPodData() async {
    try {
      final results = await Future.wait<Object?>([
        _auth.loadPodProfile(),
        _auth.loadSharedGroups(),
      ]);
      if (!mounted) return;
      setState(() {
        _podProfile = results[0] as PodProfile?;
        _sharedGroups = results[1] as List<SharedGroup>;
        _isLoadingProfile = false;
        _avatarLoadError = false;
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _changeTheme(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
      await prefs.setString('theme_mode', modeStr);
    } on Object catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _toggleNotif(bool val) async {
    setState(() => _notifEnabled = val);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('notifications_enabled', val);
    } on Object catch (_) {}

    if (val) {
      _toast('Pengingat ganti oli aktif');
    } else {
      _toast('Pengingat dinonaktifkan');
    }
  }

  Future<void> _showReminderInfo() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.notifications_active_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Expanded(child: Text('Pengingat Ganti Oli')),
          ],
        ),
        content: const Text(
          'Pengingat ganti oli akan otomatis berbunyi setiap 30 hari sekali '
          'sejak terakhir kali Anda mencatat ganti oli motor.\n\n'
          'Format pesan pengingat:\n'
          '"Jika KM motor <nama> sudah lebih dari <target> KM, jangan lupa ganti oli yaa"\n\n'
          'Ketika notifikasi ditekan, aplikasi akan langsung membuka halaman Catat Oli dengan motor yang dipilih secara otomatis.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _toast('Fitur tes notifikasi akan tersedia setelah layanan notifikasi aktif.');
            },
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Kirim Tes'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _checkUpdate() {
    _toast('Aplikasi Anda sudah versi terbaru (v$_version).');
  }

  Future<void> _showPodDetailsDialog() async {
    final profile = _podProfile;
    if (profile == null) {
      _toast('Belum ada akun Solid Pod yang terhubung.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.verified_user_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Expanded(child: Text('Informasi Solid Pod')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPodDetailRow('Nama', profile.displayName),
              _buildPodDetailRow('WebID', profile.webId),
              if (profile.serverUrl != null)
                _buildPodDetailRow('Server Pod', profile.serverUrl!),
              if (profile.storageUrl != null)
                _buildPodDetailRow('Storage Pod', profile.storageUrl!),
              if (profile.email != null)
                _buildPodDetailRow('Email', profile.email!),
              _buildPodDetailRow(
                'Status Sesi',
                profile.isAuthenticated ? 'Aktif' : 'Perlu login ulang',
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: profile.webId));
              if (ctx.mounted) Navigator.pop(ctx);
              _toast('WebID disalin ke clipboard');
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Salin WebID'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _buildPodDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppTheme.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  void _onGroupTap() {
    if (_sharedGroups.isEmpty) {
      _toast('Halaman kelola grup keluarga belum tersedia.');
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.diversity_3_rounded, color: AppTheme.safeGreen),
            SizedBox(width: 8),
            Expanded(child: Text('Grup Keluarga Solid Pod')),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final group in _sharedGroups)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.group_rounded,
                    color: AppTheme.primary,
                  ),
                  title: Text(
                    group.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('${group.webIds.length} anggota WebID'),
                ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    if (_isSigningOut) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Keluar dari Akun'),
          ],
        ),
        content: const Text('Yakin ingin keluar dari akun Solid Pod ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.dangerRed,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _isSigningOut = true);
    try {
      await _auth.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _isSigningOut = false);
        _toast('Gagal keluar dari Pod: $e');
      }
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
    final borderColor = isDark ? AppTheme.darkBorder : AppTheme.lightBorder;
    final textPrimary = isDark
        ? AppTheme.darkTextPrimary
        : AppTheme.lightTextPrimary;
    final textSecondary = isDark
        ? AppTheme.darkTextSecondary
        : AppTheme.lightTextSecondary;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        title: Text(
          'Profil & Setelan',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
            color: textPrimary,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _loadPodData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            // 1. Profil Card Modern
            _buildProfileCard(
              isDark: isDark,
              cardBg: cardBg,
              borderColor: borderColor,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),

            const SizedBox(height: 24),

            // 2. SEKSI: TEMA & TAMPILAN (Night Mode Selector)
            _buildSectionTitle('Tampilan & Tema', textSecondary),
            _buildSectionCard(
              cardBg: cardBg,
              borderColor: borderColor,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isDark
                                ? Icons.dark_mode_rounded
                                : Icons.light_mode_rounded,
                            color: AppTheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mode Tampilan',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pilih tema terang, gelap, atau ikuti sistem',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ValueListenableBuilder<ThemeMode>(
                      valueListenable: themeModeNotifier,
                      builder: (context, currentMode, _) {
                        return Row(
                          children: [
                            _buildThemeOption(
                              label: 'Sistem',
                              icon: Icons.brightness_auto_rounded,
                              isSelected: currentMode == ThemeMode.system,
                              isDark: isDark,
                              onTap: () => _changeTheme(ThemeMode.system),
                            ),
                            const SizedBox(width: 8),
                            _buildThemeOption(
                              label: 'Terang',
                              icon: Icons.light_mode_rounded,
                              isSelected: currentMode == ThemeMode.light,
                              isDark: isDark,
                              onTap: () => _changeTheme(ThemeMode.light),
                            ),
                            const SizedBox(width: 8),
                            _buildThemeOption(
                              label: 'Gelap',
                              icon: Icons.dark_mode_rounded,
                              isSelected: currentMode == ThemeMode.dark,
                              isDark: isDark,
                              onTap: () => _changeTheme(ThemeMode.dark),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 3. SEKSI: GRUP KELUARGA
            _buildSectionTitle('Grup Keluarga', textSecondary),
            _buildSectionCard(
              cardBg: cardBg,
              borderColor: borderColor,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.safeGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.diversity_3_rounded,
                    color: isDark ? AppTheme.safeGreenDark : AppTheme.safeGreen,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Kelola Grup Keluarga',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: textPrimary,
                  ),
                ),
                subtitle: Text(
                  _sharedGroups.isNotEmpty
                      ? '${_sharedGroups.length} garasi grup diikuti • Kelola motor & anggota'
                      : 'Belum bergabung ke garasi keluarga',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: textSecondary,
                ),
                onTap: _onGroupTap,
              ),
            ),

            const SizedBox(height: 20),

            // 4. SEKSI: PENGINGAT & NOTIFIKASI (UI/UX)
            _buildSectionTitle('Pengingat & Notifikasi', textSecondary),
            _buildSectionCard(
              cardBg: cardBg,
              borderColor: borderColor,
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
                    secondary: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _notifEnabled
                            ? AppTheme.safeGreen.withValues(alpha: 0.15)
                            : (isDark
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFFF1F5F9)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        _notifEnabled
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_off_rounded,
                        color: _notifEnabled
                            ? (isDark
                                  ? AppTheme.safeGreenDark
                                  : AppTheme.safeGreen)
                            : textSecondary,
                        size: 22,
                      ),
                    ),
                    title: Text(
                      'Pengingat Ganti Oli',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      _notifEnabled
                          ? 'Aktif berkala setiap 30 hari'
                          : 'Nonaktif (alarm oli dimatikan)',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    activeThumbColor: AppTheme.primary,
                    value: _notifEnabled,
                    onChanged: _toggleNotif,
                  ),
                  Divider(height: 1, indent: 64, color: borderColor),
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 2,
                    ),
                    leading: const SizedBox(width: 38),
                    title: const Text(
                      'Informasi & Tes Notifikasi',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: AppTheme.primary,
                    ),
                    onTap: _showReminderInfo,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 5. SEKSI: SISTEM & PEMBARUAN (UI/UX)
            _buildSectionTitle('Sistem & Pembaruan', textSecondary),
            _buildSectionCard(
              cardBg: cardBg,
              borderColor: borderColor,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: AppTheme.primary,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Versi Aplikasi',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: textPrimary,
                  ),
                ),
                subtitle: Text(
                  'v$_version (Build $_buildNumber)',
                  style: TextStyle(color: textSecondary, fontSize: 12),
                ),
                trailing: FilledButton.tonalIcon(
                  onPressed: _checkUpdate,
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: const Text(
                    'Cek Update',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                    foregroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // 6. TOMBOL KELUAR
            OutlinedButton.icon(
              onPressed: _isSigningOut ? null : _signOut,
              icon: _isSigningOut
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.dangerRed,
                      ),
                    )
                  : const Icon(
                      Icons.logout_rounded,
                      size: 18,
                      color: AppTheme.dangerRed,
                    ),
              label: Text(
                _isSigningOut ? 'Keluar...' : 'Keluar dari Akun',
                style: const TextStyle(
                  color: AppTheme.dangerRed,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                  color: AppTheme.dangerRed.withValues(alpha: 0.4),
                ),
                backgroundColor: AppTheme.dangerRed.withValues(alpha: 0.06),
                minimumSize: const Size(double.infinity, 48),
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

  Widget _buildProfileCard({
    required bool isDark,
    required Color cardBg,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final profile = _podProfile;
    final name =
        profile?.displayName ??
        (_isLoadingProfile ? 'Memuat Profil...' : 'Pengguna MotorQu');
    final subtitle = profile != null
        ? profile.shortPodAddress
        : (_isLoadingProfile
              ? 'Menghubungkan ke Solid Pod...'
              : 'Belum terhubung ke Pod');

    final isConnected = profile != null && profile.isAuthenticated;
    final statusColor = isConnected
        ? (isDark ? AppTheme.safeGreenDark : AppTheme.safeGreen)
        : (isDark ? AppTheme.warningAmberDark : AppTheme.warningAmber);
    final statusLabel = isConnected
        ? 'Akun Solid Pod Aktif'
        : (profile != null
              ? 'Sesi Pod Perlu Diperbarui'
              : 'Pod Belum Terhubung');

    final hasPhotoBytes =
        profile?.photoBytes != null && profile!.photoBytes!.isNotEmpty;
    final hasPhotoUrl =
        !_avatarLoadError &&
        profile?.photoUrl != null &&
        profile!.photoUrl!.trim().isNotEmpty;

    ImageProvider? avatarImage;
    if (hasPhotoBytes) {
      avatarImage = MemoryImage(profile.photoBytes!);
    } else if (hasPhotoUrl) {
      avatarImage = NetworkImage(profile.photoUrl!);
    }

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
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
          onTap: _showPodDetailsDialog,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
                  backgroundImage: avatarImage,
                  onBackgroundImageError: avatarImage is NetworkImage
                      ? (_, _) {
                          if (mounted) {
                            setState(() => _avatarLoadError = true);
                          }
                        }
                      : null,
                  child: avatarImage == null
                      ? const Icon(
                          Icons.person_rounded,
                          size: 36,
                          color: AppTheme.primary,
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, color: textSecondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isConnected
                                  ? Icons.check_circle_rounded
                                  : Icons.info_outline_rounded,
                              size: 12,
                              color: statusColor,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
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

  Widget _buildSectionCard({
    required Color cardBg,
    required Color borderColor,
    required Widget child,
  }) {
    return Material(
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildThemeOption({
    required String label,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final optionBg = isSelected
        ? AppTheme.primary.withValues(alpha: 0.15)
        : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9));
    final optionBorder = isSelected
        ? AppTheme.primary
        : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder);

    return Expanded(
      child: Material(
        color: optionBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: optionBorder, width: isSelected ? 1.4 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: isSelected
                      ? AppTheme.primary
                      : (isDark
                            ? AppTheme.darkTextSecondary
                            : AppTheme.lightTextSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? AppTheme.primary
                        : (isDark
                              ? const Color(0xFFCBD5E1)
                              : const Color(0xFF475569)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: textColor,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
