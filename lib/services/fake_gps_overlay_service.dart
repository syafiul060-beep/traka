import 'package:flutter/foundation.dart';

/// Service global untuk menampilkan overlay full-screen saat Fake GPS terdeteksi.
/// Panggil [showOverlay] ketika lokasi palsu terdeteksi.
class FakeGpsOverlayService {
  static final ValueNotifier<bool> fakeGpsDetected = ValueNotifier(false);

  /// Tampilkan overlay full-screen (blokir penggunaan aplikasi).
  static void showOverlay() {
    fakeGpsDetected.value = true;
  }

  /// Sembunyikan overlay (setelah user nonaktifkan fake GPS dan tap Coba lagi).
  static void hideOverlay() {
    fakeGpsDetected.value = false;
  }
}
