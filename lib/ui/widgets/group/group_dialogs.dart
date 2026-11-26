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

/// Dialog menempel pesan/kode undangan yang dikirim lewat chat.
/// Mengembalikan teks mentah (di-decode oleh InviteCodec) atau null.
Future<String?> showPasteInviteDialog(BuildContext context) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: _dialogShape,
      title: _iconTitle(Icons.login_rounded, 'Tempel Kode Undangan'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Tempel pesan undangan MotorQu yang kamu terima lewat chat. '
            'Pesan utuh boleh, tidak perlu dipotong.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'MQ1-...',
              border: OutlineInputBorder(),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final data = await Clipboard.getData(Clipboard.kTextPlain);
                final text = data?.text;
                if (text != null) ctrl.text = text;
              },
              icon: const Icon(Icons.content_paste_rounded, size: 18),
              label: const Text('Tempel dari clipboard'),
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
