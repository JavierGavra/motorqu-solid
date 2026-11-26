import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:motorqu_solid/services/group_service.dart';
import 'package:motorqu_solid/services/invite_codec.dart';
import 'package:motorqu_solid/ui/widgets/group/group_dialogs.dart';

/// Gabung grup: scan QR (anggota di dekat pembuat grup) atau tempel kode
/// undangan yang dikirim lewat chat (anggota di tempat lain).
class JoinGroupScannerPage extends StatefulWidget {
  const JoinGroupScannerPage({super.key, required this.groupService});

  final GroupService groupService;

  @override
  State<JoinGroupScannerPage> createState() {
    return _JoinGroupScannerPageState();
  }
}

class _JoinGroupScannerPageState extends State<JoinGroupScannerPage> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _isProcessing = false;
  bool _fromPaste = false;
  bool _isTorchOn = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_isProcessing) {
      return;
    }

    String? rawValue;
    for (final barcode in capture.barcodes) {
      final candidate = barcode.rawValue;
      if (candidate != null && candidate.trim().isNotEmpty) {
        rawValue = candidate.trim();
        break;
      }
    }

    if (rawValue == null) {
      return;
    }

    await _join(rawValue, fromPaste: false);
  }

  Future<void> _pasteInvite() async {
    if (_isProcessing) return;
    final text = await showPasteInviteDialog(context);
    if (text == null || text.trim().isEmpty || !mounted) return;

    final payload = InviteCodec.decode(text);
    if (payload == null) {
      _showError(
        'Kode undangan tidak dikenali. Pastikan menempel pesan undangan '
        'MotorQu utuh (berisi kode yang diawali "${InviteCodec.prefix}").',
      );
      return;
    }
    await _join(payload, fromPaste: true);
  }

  Future<void> _join(String raw, {required bool fromPaste}) async {
    setState(() {
      _isProcessing = true;
      _fromPaste = fromPaste;
    });

    await _scannerController.stop();

    try {
      final outcome = await widget.groupService.joinGroupWithQr(
        raw,
        approvalWait: fromPaste
            ? const Duration(seconds: 4)
            : const Duration(seconds: 20),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: Duration(seconds: outcome.pending ? 6 : 3),
          content: Text(
            outcome.pending
                ? 'Permintaan bergabung terkirim. Grup akan muncul otomatis '
                      'setelah pembuat grup membuka aplikasi MotorQu.'
                : 'Berhasil bergabung ke grup!',
          ),
        ),
      );

      // Kembali ke halaman Grup. Grup yang masih menunggu persetujuan
      // belum bisa dipilih, jadi kembalikan null.
      Navigator.of(
        context,
      ).pop<String>(outcome.pending ? null : outcome.groupId);
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showError(e.toString().replaceFirst('Exception: ', ''));

      setState(() {
        _isProcessing = false;
      });
      await _scannerController.start();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _toggleTorch() async {
    await _scannerController.toggleTorch();
    setState(() {
      _isTorchOn = !_isTorchOn;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gabung Grup'),
        actions: [
          IconButton(
            onPressed: _isProcessing ? null : _toggleTorch,
            icon: Icon(_isTorchOn ? Icons.flash_on : Icons.flash_off),
            tooltip: 'Lampu Kilat',
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onBarcodeDetected,
          ),

          // Bingkai area fokus scan
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: theme.colorScheme.primary, width: 3),
              ),
            ),
          ),

          // Petunjuk + opsi tempel kode di bagian bawah layar
          if (!_isProcessing)
            Positioned(
              left: 24,
              right: 24,
              bottom: 40,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Arahkan kamera ke QR Code undangan dari admin grup',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _pasteInvite,
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('Tempel Kode Undangan'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Loading overlay saat memvalidasi & menyimpan ke Solid Pod
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.72),
              child: Center(
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        const Text(
                          'Memproses undangan grup...',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _fromPaste
                              ? 'Mengirim permintaan ke pembuat grup'
                              : 'Menunggu persetujuan pembuat grup '
                                    '(biarkan QR tetap terbuka di HP-nya)',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
