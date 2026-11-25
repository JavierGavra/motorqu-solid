import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motorqu_solid/ui/widgets/group/group_common.dart';

Widget _iconTitle(
  IconData icon,
  String text, {
  Color color = GroupPalette.primary,
}) {
  return Row(
    children: [
      Icon(icon, color: color),
      const SizedBox(width: 8),
      Text(text),
    ],
  );
}

RoundedRectangleBorder get _dialogShape =>
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));

/// Dialog input teks generik. Mengembalikan teks (sudah di-trim) atau null
/// kalau dibatalkan.
Future<String?> _showTextInputDialog(
  BuildContext context, {
  required Widget title,
  required String label,
  String? hint,
  required String confirmLabel,
  String initialText = '',
  TextCapitalization capitalization = TextCapitalization.none,
  int? maxLength,
  String Function(String)? transform,
}) {
  final ctrl = TextEditingController(text: initialText);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: _dialogShape,
      title: title,
      content: TextField(
        controller: ctrl,
        textCapitalization: capitalization,
        maxLength: maxLength,
        autofocus: true,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () {
            final text = ctrl.text.trim();
            Navigator.pop(ctx, transform != null ? transform(text) : text);
          },
          style: groupFilledStyle(GroupPalette.primary),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

Future<String?> showCreateGroupDialog(BuildContext context) {
  return _showTextInputDialog(
    context,
    title: _iconTitle(Icons.group_add_rounded, 'Buat Garasi Grup'),
    label: 'Nama Grup',
    hint: 'contoh: Keluarga Ridlo, Motor Kantor',
    confirmLabel: 'Buat Grup',
  );
}

Future<String?> showJoinGroupDialog(BuildContext context) {
  return _showTextInputDialog(
    context,
    title: _iconTitle(Icons.login_rounded, 'Gabung Garasi Grup'),
    label: 'Kode Undangan (6 Karakter)',
    hint: 'contoh: ABC123',
    confirmLabel: 'Gabung',
    capitalization: TextCapitalization.characters,
    maxLength: 6,
    transform: (s) => s.toUpperCase(),
  );
}

Future<String?> showEditGroupNameDialog(
  BuildContext context,
  String currentName,
) {
  return _showTextInputDialog(
    context,
    title: const Text('Ubah Nama Grup'),
    label: 'Nama Grup Baru',
    confirmLabel: 'Simpan',
    initialText: currentName,
  );
}

/// Dialog konfirmasi generik (keluarkan motor/anggota, jadikan owner, dll).
/// Mengembalikan true hanya kalau pengguna menekan tombol konfirmasi.
Future<bool> showConfirmDialog(
  BuildContext context, {
  IconData? icon,
  Color? iconColor,
  required String title,
  required String message,
  required String confirmLabel,
  required Color confirmColor,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: _dialogShape,
      title: icon != null
          ? _iconTitle(icon, title, color: iconColor ?? GroupPalette.primary)
          : Text(title),
      content: Text(message, style: const TextStyle(height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: groupFilledStyle(confirmColor),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<void> showNoPrivateMotorDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: _dialogShape,
      title: const Text('Tidak Ada Motor Pribadi'),
      content: const Text(
        'Semua motor Anda sudah masuk ke grup ini, atau Anda belum menambahkan motor.',
        style: TextStyle(height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}

/// Dialog kode undangan. [onCopied] dipanggil setelah kode disalin dan
/// dialog ditutup (misalnya untuk menampilkan toast).
Future<void> showInviteCodeDialog(
  BuildContext context, {
  required String groupName,
  required String code,
  required VoidCallback onCopied,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final cardBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  final textSecondary =
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: GroupPalette.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.confirmation_number_rounded,
              color: GroupPalette.primary,
            ),
          ),
          const SizedBox(width: 12),
          const Text('Kode Undangan'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Bagikan kode 6 karakter ini kepada anggota keluarga untuk bergabung ke "$groupName".',
            style: TextStyle(fontSize: 13, height: 1.4, color: textSecondary),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: GroupPalette.primary.withValues(alpha: 0.4),
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Text(
                  'KODE GABUNG',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                    color: textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  code,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: GroupPalette.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Berlaku 7 hari • Sekali pakai',
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            Navigator.pop(ctx);
            onCopied();
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Salin Kode'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          style: groupFilledStyle(GroupPalette.primary),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}
