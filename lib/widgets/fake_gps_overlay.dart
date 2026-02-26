import 'package:flutter/material.dart';

import '../services/fake_gps_overlay_service.dart';
import '../services/location_service.dart';

/// Overlay full-screen merah saat Fake GPS terdeteksi.
/// Memblokir penggunaan aplikasi hingga user nonaktifkan lokasi palsu.
class FakeGpsOverlay extends StatelessWidget {
  const FakeGpsOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.red.shade900,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 80,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              Text(
                'Lokasi Terdeteksi Palsu',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Aplikasi Traka mendeteksi penggunaan lokasi palsu (Fake GPS).\n\n'
                'Harap matikan aplikasi lokasi palsu untuk menggunakan Traka.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.95),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () async {
                  FakeGpsOverlayService.hideOverlay();
                  // Cek ulang lokasi; jika masih fake, overlay akan muncul lagi dari screen yang memanggil
                  final result = await LocationService.getCurrentPositionWithMockCheck();
                  if (result.isFakeGpsDetected) {
                    FakeGpsOverlayService.showOverlay();
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Coba lagi (setelah nonaktifkan lokasi palsu)'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.red.shade900,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
