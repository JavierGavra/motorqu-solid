import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motorqu_solid/services/group_service.dart';
import 'package:motorqu_solid/services/invite_codec.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

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

  /// Host grup memproses permintaan bergabung berkala selama dialog terbuka,
  /// sehingga anggota yang memindai QR langsung masuk.
  Timer? _pollTimer;
  bool _polling = false;
  bool? _isHost;
  int _joinedCount = 0;

  @override
  void initState() {
    super.initState();
    _qrPayloadFuture = widget.groupService.createInviteQrPayload(
      widget.groupId,
    );
    _startPollingIfHost();
  }

  Future<void> _startPollingIfHost() async {
    bool isHost;
    try {
      isHost = await widget.groupService.isHostOf(widget.groupId);
    } catch (_) {
      isHost = false;
    }
    if (!mounted) return;
    setState(() => _isHost = isHost);
    if (!isHost) return;

    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_polling) return;
      _polling = true;
      try {
        final added = await widget.groupService.processJoinRequests(
          widget.groupId,
        );
        if (added > 0 && mounted) {
          setState(() => _joinedCount += added);
        }
      } catch (e) {
        debugPrint('Gagal memproses permintaan bergabung: $e');
      } finally {
        _polling = false;
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _regenerateQr() {
    setState(() {
      _qrPayloadFuture = widget.groupService.createInviteQrPayload(
        widget.groupId,
      );
    });
  }

  String _shareText(String payload) => InviteCodec.shareMessage(
    groupName: widget.groupName,
    payloadJson: payload,
  );

  /// Untuk anggota yang tidak berada di dekat HP ini: salin pesan berisi
  /// kode undangan, lalu tempel di chat.
  Future<void> _copyInvite(String payload) async {
    await Clipboard.setData(ClipboardData(text: _shareText(payload)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pesan undangan disalin. Tempel di chat keluarga.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareInvite(String payload) async {
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: _shareText(payload),
          subject: 'Undangan grup MotorQu',
        ),
      );
    } catch (e) {
      // Bila lembar bagikan tidak tersedia, salin saja.
      await _copyInvite(payload);
    }
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
                      'Menyiapkan QR undangan...',
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
                  'Bagikan QR ini kepada anggota keluarga untuk bergabung ke "${widget.groupName}". QR hanya berlaku untuk satu orang.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                if (_isHost == true)
                  Text(
                    _joinedCount > 0
                        ? '$_joinedCount anggota baru berhasil bergabung.'
                        : 'Biarkan dialog ini terbuka sampai anggota selesai memindai.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: _joinedCount > 0
                          ? Colors.green.shade700
                          : theme.colorScheme.primary,
                    ),
                  )
                else if (_isHost == false)
                  Text(
                    'Anggota baru akan aktif setelah pembuat grup membuka aplikasi MotorQu.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Anggota tidak di dekat Anda? Kirim kodenya lewat chat:',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _copyInvite(payload),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Salin'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.tonalIcon(
                      onPressed: () => _shareInvite(payload),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: const Text('Bagikan'),
                    ),
                  ],
                ),
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
