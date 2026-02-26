import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/fake_gps_overlay_service.dart';
import '../services/location_service.dart';
import '../services/order_service.dart';

/// Layar scan barcode driver oleh penumpang (saat sampai tujuan).
/// Setelah scan berhasil: update order (completed), pop(true).
class ScanBarcodePenumpangScreen extends StatefulWidget {
  const ScanBarcodePenumpangScreen({super.key});

  @override
  State<ScanBarcodePenumpangScreen> createState() =>
      _ScanBarcodePenumpangScreenState();
}

class _ScanBarcodePenumpangScreenState
    extends State<ScanBarcodePenumpangScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _scanned = false;
  bool _processing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_scanned || _processing) return;
    final barcode = capture.barcodes.firstOrNull;
    final raw = barcode?.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() => _processing = true);

    double? dropLat;
    double? dropLng;
    try {
      final result = await LocationService.getCurrentPositionWithMockCheck();
      if (result.isFakeGpsDetected) {
        if (mounted) {
          setState(() => _processing = false);
          FakeGpsOverlayService.showOverlay();
        }
        return;
      }
      final pos = result.position;
      if (pos != null) {
        dropLat = pos.latitude;
        dropLng = pos.longitude;
      }
    } catch (_) {}

    var (success, error, orderId) = await OrderService.applyPassengerScanDriver(
      raw,
      dropLat: dropLat,
      dropLng: dropLng,
    );

    // Untuk kirim barang: jika user adalah penerima, coba applyReceiverScanDriver
    bool isReceiverScan = false;
    String? completedOrderId = orderId;
    if (!success && error != null && error!.contains('bukan untuk pesanan')) {
      final (recSuccess, recError, recOrderId) = await OrderService.applyReceiverScanDriver(
        raw,
        dropLat: dropLat,
        dropLng: dropLng,
      );
      if (recSuccess) {
        success = true;
        isReceiverScan = true;
        error = null;
        completedOrderId = recOrderId;
      } else {
        error = recError;
      }
    }

    if (!mounted) return;
    if (success) {
      _scanned = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isReceiverScan ? 'Barang diterima. Terima kasih.' : 'Perjalanan selesai. Terima kasih.',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Kirim barang: tidak ada rating. Travel: kembalikan orderId untuk dialog rating.
      Navigator.of(context).pop(isReceiverScan ? true : completedOrderId);
    } else {
      setState(() => _processing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error ?? 'Scan gagal'),
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
        title: const Text('Scan barcode driver'),
        backgroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.87),
        foregroundColor: Colors.white,
      ),
      body: Stack(
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
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: Text(
              'Arahkan kamera ke barcode driver (saat sampai tujuan)',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                shadows: [
                  Shadow(color: Colors.black, blurRadius: 4),
                  Shadow(color: Colors.black, offset: Offset(1, 1)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
