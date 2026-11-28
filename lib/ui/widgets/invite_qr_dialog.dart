import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motorqu_solid/services/group_service.dart';
import 'package:motorqu_solid/services/invite_codec.dart';
import 'package:motorqu_solid/ui/widgets/group/group_common.dart';
import 'package:motorqu_solid/ui/widgets/group/group_dialogs.dart';
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
  late Future<InviteInfo> _inviteFuture;

  /// Host grup memproses anggota baru berkala selama dialog terbuka,
  /// sehingga anggota yang memindai QR / mengetik kode langsung aktif.
  Timer? _pollTimer;
  bool _polling = false;
  bool? _isHost;
  int _joinedCount = 0;

  @override
  void initState() {
    super.initState();
    _inviteFuture = widget.groupService.getInvite(widget.groupId);
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
        debugPrint('Gagal memproses anggota baru: $e');
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

  void _retry() {
    setState(() {
      _inviteFuture = widget.groupService.getInvite(widget.groupId);
    });
  }

  Future<void> _regenerate() async {
    final ok = await showConfirmDialog(
      context,
      icon: Icons.refresh_rounded,
      title: 'Buat Kode Baru?',
      message:
          'Kode & QR lama langsung tidak berlaku. Anggota yang sudah '
          'bergabung tidak terpengaruh.',
      confirmLabel: 'Buat Baru',
      confirmColor: GroupPalette.primary,
    );
    if (!ok || !mounted) return;
    setState(() {
      _inviteFuture = widget.groupService.getInvite(
        widget.groupId,
        regenerate: true,
      );
    });
  }

  String _shareText(InviteInfo info) => InviteCode.shareMessage(
    groupName: widget.groupName,
    code: info.code.text,
    expiresAt: info.expiresAt,
  );

  Future<void> _copyCode(InviteInfo info) async {
    await Clipboard.setData(ClipboardData(text: info.code.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Kode undangan disalin.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _shareInvite(InviteInfo info) async {
    try {
      await SharePlus.instance.share(
        ShareParams(text: _shareText(info), subject: 'Undangan grup MotorQu'),
      );
    } catch (e) {
      // Bila lembar bagikan tidak tersedia, salin pesannya saja.
      await Clipboard.setData(ClipboardData(text: _shareText(info)));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pesan undangan disalin. Tempel di chat keluarga.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
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
        child: FutureBuilder<InviteInfo>(
          future: _inviteFuture,
          builder: (BuildContext context, AsyncSnapshot<InviteInfo> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Menyiapkan kode undangan...',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            if (snapshot.hasError || snapshot.data == null) {
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
                      'Gagal membuat kode undangan:\n'
                      '${snapshot.error.toString().replaceFirst('Exception: ', '')}',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              );
            }

            final info = snapshot.data!;

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: QrImageView(
                      data: info.code.text,
                      version: QrVersions.auto,
                      size: 190,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Atau ketik kode ini di HP anggota:',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Material(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _copyCode(info),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                info.code.text,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.copy_rounded,
                              size: 20,
                              color: theme.colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Bisa dipakai banyak anggota, berlaku sampai '
                    '${_formatDate(info.expiresAt)}. Anggota langsung masuk '
                    'tanpa persetujuan.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_isHost == true && _joinedCount > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$_joinedCount anggota baru berhasil bergabung.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      TextButton.icon(
                        onPressed: _regenerate,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Kode Baru'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _shareInvite(info),
                        icon: const Icon(Icons.share_rounded, size: 18),
                        label: const Text('Bagikan'),
                      ),
                    ],
                  ),
                ],
              ),
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
