import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:motorqu_solid/services/group_service.dart';
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

  Future<void> _enterCode() async {
    if (_isProcessing) return;
    final text = await showEnterInviteCodeDialog(context);
    if (text == null || text.trim().isEmpty || !mounted) return;
    await _join(text, fromPaste: true);
  }

  Future<void> _join(String raw, {required bool fromPaste}) async {
    setState(() {
      _isProcessing = true;
      _fromPaste = fromPaste;
    });

    try {
      await _scannerController.stop();
    } catch (_) {
      // Kamera memang belum jalan (mis. izin ditolak): tetap lanjut.
    }

    try {
      final outcome = await widget.groupService.joinGroup(
        raw,
        // Scan QR: pembuat grup biasanya sedang membuka QR-nya, jadi akses
        // terbuka dalam beberapa detik. Kode lewat chat: cek singkat saja.
        wait: fromPaste
            ? const Duration(seconds: 6)
            : const Duration(seconds: 12),
      );

      if (!mounted) {
        return;
      }

      final name = outcome.groupName.isEmpty
          ? 'grup'
          : 'grup "${outcome.groupName}"';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: Duration(seconds: outcome.pending ? 6 : 3),
          content: Text(
            outcome.pending
                ? 'Berhasil bergabung ke $name! Data grup sedang disinkronkan '
                      'dan muncul otomatis saat HP pembuat grup membuka MotorQu.'
                : 'Berhasil bergabung ke $name!',
          ),
        ),
      );

      Navigator.of(context).pop<String>(outcome.groupId);
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showError(e.toString().replaceFirst('Exception: ', ''));

      setState(() {
        _isProcessing = false;
      });
      await _restartCamera();
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
    try {
      await _scannerController.toggleTorch();
    } catch (_) {
      return; // Kamera belum jalan / tidak punya lampu kilat.
    }
    if (!mounted) return;
    setState(() {
      _isTorchOn = !_isTorchOn;
    });
  }

  /// Buka ulang kamera (mis. setelah izin kamera diberikan di Pengaturan).
  Future<void> _restartCamera() async {
    try {
      await _scannerController.stop();
      await _scannerController.start();
    } catch (e) {
      // Galat ditampilkan oleh errorBuilder lewat state controller.
      debugPrint('[Scanner] gagal membuka kamera: $e');
    }
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
            errorBuilder: (context, error) =>
                _CameraErrorView(error: error, onRetry: _restartCamera),
          ),

          // Bingkai area fokus scan (disembunyikan saat kamera gagal dibuka)
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _scannerController,
            builder: (context, state, _) {
              if (state.error != null) return const SizedBox.shrink();
              return Center(
                child: Container(
                  width: 250,
                  height: 250,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                  ),
                ),
              );
            },
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
                      'Arahkan kamera ke QR Code undangan dari admin grup, '
                      'atau ketik kodenya.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _enterCode,
                    icon: const Icon(Icons.keyboard_rounded),
                    label: const Text('Masukkan Kode Undangan'),
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
                          'Bergabung ke grup...',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _fromPaste
                              ? 'Memeriksa kode undangan'
                              : 'Menyinkronkan data grup',
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

/// Pengganti tampilan galat bawaan mobile_scanner, yang di build rilis selalu
/// hanya menampilkan "An unexpected error occurred." tanpa penyebab.
class _CameraErrorView extends StatelessWidget {
  const _CameraErrorView({required this.error, required this.onRetry});

  final MobileScannerException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (
      IconData icon,
      String title,
      String body,
    ) = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied => (
        Icons.no_photography_outlined,
        'Izin kamera ditolak',
        'Izinkan akses kamera untuk MotorQu di Pengaturan HP '
            '(Aplikasi > MotorQu > Izin > Kamera), lalu ketuk Coba Lagi.\n\n'
            'Atau masukkan kode undangan secara manual di bawah.',
      ),
      MobileScannerErrorCode.unsupported => (
        Icons.videocam_off_outlined,
        'Kamera tidak tersedia',
        'HP ini tidak punya kamera yang bisa dipakai untuk memindai. '
            'Masukkan kode undangan secara manual di bawah.',
      ),
      _ => (
        Icons.error_outline,
        'Kamera gagal dibuka',
        'Tutup aplikasi lain yang sedang memakai kamera, lalu ketuk '
            'Coba Lagi. Atau masukkan kode undangan secara manual di bawah.'
            '${_detail()}',
      ),
    };

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 160),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba Lagi'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Detail teknis singkat agar laporan bug bisa dilacak.
  String _detail() {
    final d = error.errorDetails;
    final parts = [
      error.errorCode.name,
      if (d?.code != null) d!.code!,
      if (d?.message != null) d!.message!,
    ];
    // Baris pertama stack trace native (bila ada) untuk melacak sumbernya.
    final trace = d?.details?.toString().trim().split('\n').take(3).join('\n');
    return '\n\n(${parts.join(': ')})'
        '${trace == null || trace.isEmpty ? '' : '\n$trace'}';
  }
}
