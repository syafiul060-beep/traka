import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/chat_service.dart';
import '../services/fake_gps_overlay_service.dart';
import '../services/location_service.dart';
import '../services/order_service.dart';

/// Layar scan barcode penumpang oleh driver.
/// Setelah scan berhasil: update order (picked_up), kirim barcode driver ke chat, pop(true).
class ScanBarcodeDriverScreen extends StatefulWidget {
  const ScanBarcodeDriverScreen({super.key});

  @override
  State<ScanBarcodeDriverScreen> createState() =>
      _ScanBarcodeDriverScreenState();
}

class _ScanBarcodeDriverScreenState extends State<ScanBarcodeDriverScreen> {
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

    double? pickupLat;
    double? pickupLng;
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
        pickupLat = pos.latitude;
        pickupLng = pos.longitude;
      }
    } catch (_) {}

    final (
      success,
      error,
      driverPayload,
    ) = await OrderService.applyDriverScanPassenger(
      raw,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
    );

    if (!mounted) return;
    if (success && driverPayload != null) {
      _scanned = true;
      // Parse orderId dari payload TRAKA:orderId:D:uuid
      final parts = driverPayload.split(':');
      final orderId = parts.length >= 2 ? parts[1] : null;
      if (orderId != null) {
        await ChatService.sendBarcodeMessage(
          orderId,
          driverPayload,
          'barcode_driver',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scan berhasil. Penumpang tercatat sudah dijemput.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pop(true);
      }
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
        title: const Text('Scan barcode penumpang'),
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
              'Arahkan kamera ke barcode penumpang',
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
