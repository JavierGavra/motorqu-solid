import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:motorqu_solid/services/group_service.dart';

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

    setState(() {
      _isProcessing = true;
    });

    await _scannerController.stop();

    try {
      final joinedGroupId = await widget.groupService.joinGroupWithQr(rawValue);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Berhasil bergabung ke grup!')),
      );

      // Langsung kembali ke halaman Grup sambil membawa ID grup baru
      Navigator.of(context).pop<String>(joinedGroupId);
    } catch (e) {
      if (!mounted) {
        return;
      }

      final cleanMessage = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cleanMessage),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );

      setState(() {
        _isProcessing = false;
      });
      await _scannerController.start();
    }
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
        title: const Text('Scan QR Gabung Grup'),
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

          // Petunjuk di bagian bawah layar
          if (!_isProcessing)
            Positioned(
              left: 24,
              right: 24,
              bottom: 48,
              child: Container(
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
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                          'Memproses undangan grup...',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Menyinkronkan data dengan Solid Pod',
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
