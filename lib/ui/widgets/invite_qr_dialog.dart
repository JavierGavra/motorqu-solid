import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motorqu_solid/services/group_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

Future<void> showInviteQrDialog({
  required BuildContext context,
  required GroupService groupService,
  required String groupId,
  required String groupName,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext dialogContext) {
      return InviteQrDialog(
        groupService: groupService,
        groupId: groupId,
        groupName: groupName,
      );
    },
  );
}

class InviteQrDialog extends StatefulWidget {
  const InviteQrDialog({
    super.key,
    required this.groupService,
    required this.groupId,
    required this.groupName,
  });

  final GroupService groupService;
  final String groupId;
  final String groupName;

  @override
  State<InviteQrDialog> createState() {
    return _InviteQrDialogState();
  }
}

class _InviteQrDialogState extends State<InviteQrDialog> {
  late Future<String> _qrPayloadFuture;

  @override
  void initState() {
    super.initState();
    _qrPayloadFuture = widget.groupService.createInviteQrPayload(
      widget.groupId,
    );
  }

  void _regenerateQr() {
    setState(() {
      _qrPayloadFuture = widget.groupService.createInviteQrPayload(
        widget.groupId,
      );
    });
  }

  Future<void> _copyPayload(String payload) async {
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Kode undangan disalin ke clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Undang Anggota'),
          const SizedBox(height: 4),
          Text(
            widget.groupName,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 280,
        child: FutureBuilder<String>(
          future: _qrPayloadFuture,
          builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Menyiapkan QR & izin akses Pod...',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.error,
                      size: 44,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Gagal membuat QR undangan:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _regenerateQr,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              );
            }

            final payload = snapshot.data ?? '';

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: QrImageView(
                    data: payload,
                    version: QrVersions.auto,
                    size: 210,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Bagikan QR ini kepada anggota keluarga untuk bergabung ke "${widget.groupName}".',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                // const SizedBox(height: 8),
                // TextButton.icon(
                //   onPressed: () {
                //     _copyPayload(payload);
                //   },
                //   icon: const Icon(Icons.copy, size: 18),
                //   label: const Text('Salin Data Undangan'),
                // ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}
