import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motorqu_solid/services/invite_codec.dart';
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
      // Flexible: judul panjang dibungkus ke baris berikutnya, tidak
      // keluar dari dialog.
      Flexible(child: Text(text)),
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

/// Dialog mengetik / menempel kode undangan (mis. `ridlofw-K7M2QX`).
/// Pesan chat utuh juga boleh ditempel; kodenya diambil otomatis.
/// Mengembalikan teks mentah atau null.
Future<String?> showEnterInviteCodeDialog(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: _dialogShape,
      title: _iconTitle(Icons.login_rounded, 'Masukkan Kode Undangan'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Ketik kode dari admin grup, atau tempel pesan undangannya.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) => Navigator.pop(ctx, v),
            style: const TextStyle(fontSize: 18, letterSpacing: 0.5),
            decoration: InputDecoration(
              hintText: 'namaakun-K7M2QX',
              // Samar agar jelas ini contoh, bukan isian.
              hintStyle: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurface
                    .withValues(alpha: 0.3),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                final text = data?.text;
                if (text == null) return;
                // Pesan chat utuh -> ambil kodenya saja.
                ctrl.text = InviteCode.parse(text)?.text ?? text.trim();
              },
              icon: const Icon(Icons.content_paste_rounded, size: 18),
              label: const Text('Tempel'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          style: groupFilledStyle(GroupPalette.primary),
          child: const Text('Gabung'),
        ),
      ],
    ),
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
