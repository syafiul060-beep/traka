/// Konfigurasi untuk pengguna dan perangkat di Indonesia.
///
/// Target spesifikasi HP rata-rata pengguna Indonesia (2024):
/// - RAM: 4–6 GB (Transsion, Xiaomi Redmi, Oppo A/Vivo Y, Samsung A0x)
/// - Prosesor: Unisoc T606, MediaTek Helio G36, Snapdragon 4xx
/// - Kamera depan: 5–8 MP, resolusi 720p–1080p
/// - Layar: 720p–1080p, 60–90 Hz
/// - ASP: ~US\$195 (IDC 2024)
///
/// Optimasi: ringan di CPU/RAM, toleran pada kualitas kamera budget.
class IndonesiaConfig {
  IndonesiaConfig._();

  /// Zona waktu default Indonesia (WIB).
  static const String timezone = 'Asia/Jakarta';

  /// Format nomor telepon Indonesia.
  static const String phonePrefix = '+62';

  // === Validasi foto (FaceValidationService) ===

  /// Ambang blur (Laplacian variance) - lebih longgar untuk kamera budget.
  static const int blurThresholdMin = 65;

  /// Brightness minimal - HP budget sering lemah di low-light.
  static const int minBrightness = 35;

  /// Resolusi minimal - sesuaikan ResolutionPreset.medium (~480p).
  static const int minResolutionWidth = 360;
  static const int minResolutionHeight = 360;

  // === Kamera & Liveness (ActiveLivenessScreen) ===

  /// Resolusi stream kamera: medium (~480p) untuk keseimbangan kualitas & performa.
  static const String cameraResolutionPreset = 'medium';

  /// Interval sampling (ms) - CPU Unisoc/Helio G36 butuh jeda lebih lama.
  static const int sampleIntervalSearchMs = 380;
  static const int sampleIntervalFaceMs = 320;

  /// Durasi tahan wajah untuk verifikasi tanpa kedip (ms). 2 detik.
  static const int faceHoldVerifyMs = 2000;

  /// Durasi tunggu sebelum siap deteksi kedip (ms).
  static const int blinkReadyDelayMs = 1300;

  /// Durasi tunggu fokus kamera sebelum capture (ms).
  static const int focusStabilizeMs = 800;

  // === Konversi gambar (CameraImageConverter) ===

  /// Kualitas JPEG - 70 untuk ukuran file lebih kecil di storage terbatas.
  static const int jpegQuality = 70;

  // === Face detection (FaceValidationService) ===

  /// Mode deteksi wajah: 'fast' untuk CPU budget, 'accurate' untuk hasil lebih presisi.
  static const String faceDetectorPerformanceMode = 'fast';
}
