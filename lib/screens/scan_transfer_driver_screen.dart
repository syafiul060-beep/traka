import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/driver_transfer_service.dart';

/// Layar scan barcode Oper Driver oleh driver kedua.
/// Setelah scan berhasil: minta password, verifikasi, lalu selesaikan transfer.
class ScanTransferDriverScreen extends StatefulWidget {
  const ScanTransferDriverScreen({super.key});

  @override
  State<ScanTransferDriverScreen> createState() =>
      _ScanTransferDriverScreenState();
}

class _ScanTransferDriverScreenState extends State<ScanTransferDriverScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _scanned = false;
  bool _processing = false;
  String? _scannedPayload;
  final _passwordController = TextEditingController();
  bool _passwordObscure = true;

  @override
  void dispose() {
    _controller.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned || _processing) return;
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue;
    if (raw == null || raw.isEmpty) return;

    final (transferId, parseError) =
        DriverTransferService.parseTransferBarcodePayload(raw);
    if (transferId == null) return;

    setState(() {
      _scanned = true;
      _scannedPayload = raw;
    });
  }

  Future<void> _submitPassword() async {
    final payload = _scannedPayload;
    if (payload == null || payload.isEmpty) return;

    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan password akun')),
      );
      return;
    }

    setState(() => _processing = true);

    double? lat;
    double? lng;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );
      lat = pos.latitude;
      lng = pos.longitude;
    } catch (_) {}

    final (success, error) = await DriverTransferService.applyDriverScanTransfer(
      payload,
      password: password,
      toDriverLat: lat,
      toDriverLng: lng,
    );

    if (!mounted) return;
    setState(() => _processing = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Oper berhasil. Pesanan telah dipindah ke Anda.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Verifikasi gagal'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan barcode Oper Driver'),
        backgroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.87),
        foregroundColor: Colors.white,
      ),
      body: _scanned
          ? _buildPasswordForm()
          : Stack(
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                if (_processing)
                  Container(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Memverifikasi...',
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildPasswordForm() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green.shade700),
            const SizedBox(height: 16),
            const Text(
              'Scan berhasil',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Masukkan password akun Anda untuk menyelesaikan oper',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _passwordController,
              obscureText: _passwordObscure,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _passwordObscure ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () =>
                      setState(() => _passwordObscure = !_passwordObscure),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _processing ? null : _submitPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _processing
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Verifikasi & Selesaikan Oper'),
            ),
          ],
        ),
      ),
    );
  }
}
