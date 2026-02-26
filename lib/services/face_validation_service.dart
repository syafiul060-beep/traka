import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

import '../config/indonesia_config.dart';

/// Hasil validasi foto wajah.
class FaceValidationResult {
  final bool isValid;
  final String? errorMessage;

  /// True jika gagal hanya karena blur (boleh tawarkan "Pakai foto ini").
  final bool isBlurError;

  const FaceValidationResult({
    required this.isValid,
    this.errorMessage,
    this.isBlurError = false,
  });

  static const valid = FaceValidationResult(isValid: true);
  static FaceValidationResult invalid(String msg, {bool isBlurError = false}) =>
      FaceValidationResult(
        isValid: false,
        errorMessage: msg,
        isBlurError: isBlurError,
      );
}

/// Hasil pilihan user saat dialog error validasi wajah.
enum FaceValidationDialogAction { cancel, retry, useAnyway }

/// Layanan validasi foto wajah untuk pendaftaran.
class FaceValidationService {
  /// Rasio wajah minimal terhadap lebar/gambar (10%).
  static const minFaceSizeRatio = 0.10;

  /// Batas sudut pose (derajat) - wajah harus menghadap kamera.
  static const maxYawDeg = 25.0;
  static const maxPitchDeg = 25.0;
  static const maxRollDeg = 25.0;

  /// Probabilitas mata terbuka minimal - deteksi kacamata gelap/tertutup.
  static const minEyeOpenProbability = 0.2;

  /// Threshold brightness (0-255) - cahaya cukup.
  static const maxBrightness = 220;

  /// Validasi resolusi gambar - sesuaikan spek HP Indonesia.
  static FaceValidationResult? _validateResolution(int width, int height) {
    final minW = IndonesiaConfig.minResolutionWidth;
    final minH = IndonesiaConfig.minResolutionHeight;
    if (width < minW || height < minH) {
      return FaceValidationResult.invalid(
        'Resolusi terlalu rendah. Gunakan minimal ${minW}x$minH piksel.',
      );
    }
    return null;
  }

  /// Validasi brightness (cahaya cukup) - toleran untuk HP budget.
  static FaceValidationResult? _validateBrightness(img.Image image) {
    double sum = 0;
    int count = 0;
    final stepX = (image.width / 20).clamp(1, 50).toInt();
    final stepY = (image.height / 20).clamp(1, 50).toInt();
    for (var y = 0; y < image.height; y += stepY) {
      for (var x = 0; x < image.width; x += stepX) {
        final p = image.getPixel(x, y);
        sum += (p.r.toInt() + p.g.toInt() + p.b.toInt()) / 3;
        count++;
      }
    }
    final avg = count > 0 ? sum / count : 0;
    if (avg < IndonesiaConfig.minBrightness) {
      return FaceValidationResult.invalid(
        'Cahaya terlalu gelap. Pastikan pencahayaan cukup.',
      );
    }
    if (avg > maxBrightness) {
      return FaceValidationResult.invalid(
        'Cahaya terlalu terang. Hindari silau.',
      );
    }
    return null;
  }

  /// Validasi blur (Laplacian variance) - sampling untuk performa.
  static FaceValidationResult? _validateBlur(img.Image image) {
    final gray = img.grayscale(image);
    double sum = 0;
    int count = 0;
    final step = 8;
    for (var y = 1; y < gray.height - 1; y += step) {
      for (var x = 1; x < gray.width - 1; x += step) {
        final c = gray.getPixel(x, y).r.toInt();
        final l = gray.getPixel(x - 1, y).r.toInt();
        final rVal = gray.getPixel(x + 1, y).r.toInt();
        final t = gray.getPixel(x, y - 1).r.toInt();
        final b = gray.getPixel(x, y + 1).r.toInt();
        final lap = (4 * c - l - rVal - t - b).abs();
        sum += lap;
        count++;
      }
    }
    final variance = count > 0 ? sum / count : 0;
    if (variance < IndonesiaConfig.blurThresholdMin) {
      return FaceValidationResult.invalid(
        'Foto blur. Pastikan:\n\n1) Cahaya cukup\n\n2) Pegang HP dengan stabil\n\n3) Tunggu wajah terlihat jelas lalu ulangi.',
        isBlurError: true,
      );
    }
    return null;
  }

  /// Validasi jumlah wajah dan ukuran.
  static FaceValidationResult? _validateFaceCountAndSize(
    List<Face> faces,
    int imageWidth,
    int imageHeight,
  ) {
    if (faces.isEmpty) {
      return FaceValidationResult.invalid(
        'Wajah tidak terdeteksi. Pastikan wajah menghadap kamera, cahaya cukup, dan tidak memakai masker.',
      );
    }
    if (faces.length > 1) {
      return FaceValidationResult.invalid(
        'Hanya boleh 1 wajah. Pastikan tidak ada orang lain di frame.',
      );
    }
    final face = faces.first;
    final box = face.boundingBox;
    final faceWidth = box.width / imageWidth;
    final faceHeight = box.height / imageHeight;
    if (faceWidth < minFaceSizeRatio || faceHeight < minFaceSizeRatio) {
      return FaceValidationResult.invalid(
        'Wajah terlalu kecil. Dekatkan wajah ke kamera.',
      );
    }
    return null;
  }

  /// Validasi proporsi bounding box (wajah tidak terlalu terpotong).
  static FaceValidationResult? _validateBoundingBox(
    Face face,
    int imageWidth,
    int imageHeight,
  ) {
    final box = face.boundingBox;
    final aspectRatio = box.width / box.height;
    if (aspectRatio < 0.5 || aspectRatio > 2.5) {
      return FaceValidationResult.invalid(
        'Wajah terpotong. Pastikan wajah tampil penuh.',
      );
    }
    return null;
  }

  /// Validasi landmark (mata, hidung, mulut) jika tersedia.
  static FaceValidationResult? _validateLandmarks(Face face) {
    final landmarks = face.landmarks;
    final requiredTypes = [
      FaceLandmarkType.leftEye,
      FaceLandmarkType.rightEye,
      FaceLandmarkType.noseBase,
      FaceLandmarkType.bottomMouth,
    ];
    int validCount = 0;
    for (final type in requiredTypes) {
      final lm = landmarks[type];
      if (lm != null) {
        validCount++;
      }
    }
    if (validCount < 3) {
      return FaceValidationResult.invalid(
        'Wajah tidak lengkap. Pastikan mata, hidung, dan mulut terlihat.',
      );
    }
    return null;
  }

  /// Validasi pose (yaw, pitch, roll) - wajah menghadap kamera.
  static FaceValidationResult? _validatePose(Face face) {
    final yaw = face.headEulerAngleY ?? 0;
    final pitch = face.headEulerAngleX ?? 0;
    final roll = face.headEulerAngleZ ?? 0;
    if (yaw.abs() > maxYawDeg ||
        pitch.abs() > maxPitchDeg ||
        roll.abs() > maxRollDeg) {
      return FaceValidationResult.invalid(
        'Wajah harus menghadap kamera lurus.',
      );
    }
    return null;
  }

  /// Validasi occlusion (mata tertutup, kacamata gelap).
  static FaceValidationResult? _validateOcclusion(Face face) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;
    if (left != null && left < minEyeOpenProbability) {
      return FaceValidationResult.invalid('Mata kiri tertutup atau terhalang.');
    }
    if (right != null && right < minEyeOpenProbability) {
      return FaceValidationResult.invalid(
        'Mata kanan tertutup atau terhalang. Lepas kacamata gelap jika ada.',
      );
    }
    return null;
  }

  /// Validasi foto wajah tanpa cek blur (untuk "Pakai foto ini").
  /// Tetap cek: wajah manusia, landmark, pose, occlusion (bukan dari gambar/layar).
  static Future<FaceValidationResult> validateFacePhotoSkipBlur(
    String imagePath,
  ) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        return FaceValidationResult.invalid('Gagal memuat gambar.');
      }

      var r = _validateResolution(image.width, image.height);
      if (r != null) return r;

      r = _validateBrightness(image);
      if (r != null) return r;

      // Skip blur - langsung ke face detection
      final inputImage = InputImage.fromFilePath(imagePath);
      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode:
              IndonesiaConfig.faceDetectorPerformanceMode == 'accurate'
              ? FaceDetectorMode.accurate
              : FaceDetectorMode.fast,
          enableContours: true,
          enableLandmarks: true,
          minFaceSize: minFaceSizeRatio,
          enableTracking: false,
        ),
      );
      final faces = await faceDetector.processImage(inputImage);
      await faceDetector.close();

      r = _validateFaceCountAndSize(faces, image.width, image.height);
      if (r != null) return r;

      final face = faces.first;

      r = _validateBoundingBox(face, image.width, image.height);
      if (r != null) return r;

      r = _validateLandmarks(face);
      if (r != null) return r;

      r = _validatePose(face);
      if (r != null) return r;

      r = _validateOcclusion(face);
      if (r != null) return r;

      return FaceValidationResult.valid;
    } catch (e) {
      return FaceValidationResult.invalid('Verifikasi gagal: $e');
    }
  }

  /// Jalankan semua validasi foto wajah.
  static Future<FaceValidationResult> validateFacePhoto(
    String imagePath,
  ) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) {
        return FaceValidationResult.invalid('Gagal memuat gambar.');
      }

      // 1. Validasi Kamera & Input (sebelum ML)
      var r = _validateResolution(image.width, image.height);
      if (r != null) return r;

      r = _validateBrightness(image);
      if (r != null) return r;

      r = _validateBlur(image);
      if (r != null) return r;

      // 2. Face Detection
      final inputImage = InputImage.fromFilePath(imagePath);
      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode:
              IndonesiaConfig.faceDetectorPerformanceMode == 'accurate'
              ? FaceDetectorMode.accurate
              : FaceDetectorMode.fast,
          enableContours: true,
          enableLandmarks: true,
          minFaceSize: minFaceSizeRatio,
          enableTracking: false,
        ),
      );
      final faces = await faceDetector.processImage(inputImage);
      await faceDetector.close();

      // 3. Validasi Face Detection
      r = _validateFaceCountAndSize(faces, image.width, image.height);
      if (r != null) return r;

      final face = faces.first;

      r = _validateBoundingBox(face, image.width, image.height);
      if (r != null) return r;

      // 4. Validasi Landmark
      r = _validateLandmarks(face);
      if (r != null) return r;

      // 5. Validasi Pose
      r = _validatePose(face);
      if (r != null) return r;

      // 6. Validasi Occlusion
      r = _validateOcclusion(face);
      if (r != null) return r;

      return FaceValidationResult.valid;
    } catch (e) {
      return FaceValidationResult.invalid('Verifikasi gagal: $e');
    }
  }
}
