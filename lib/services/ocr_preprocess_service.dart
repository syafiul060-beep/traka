import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Preprocessing gambar untuk meningkatkan akurasi OCR.
/// Teknik: grayscale, contrast enhancement, normalisasi.
class OcrPreprocessService {
  /// Kontras ditingkatkan (130% = teks lebih tajam dari background).
  static const double _contrastLevel = 130;

  /// Preprocess gambar untuk OCR: grayscale + contrast + normalize.
  /// Return path file temp yang sudah dipreprocess, atau null jika gagal.
  static Future<String?> preprocessForOcr(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return null;

      // Clone agar tidak mengubah original
      image = img.Image.from(image);

      // 1. Grayscale - mengurangi noise warna, fokus pada teks
      image = img.grayscale(image);

      // 2. Contrast enhancement - teks lebih jelas dari background
      image = img.contrast(image, contrast: _contrastLevel);

      // 3. Normalize - rentang nilai pixel lebih merata (0-255)
      image = img.normalize(image, min: 0, max: 255);

      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/ocr_preprocess_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final outFile = File(outPath);
      await outFile.writeAsBytes(img.encodeJpg(image, quality: 95));

      return outPath;
    } catch (_) {
      return null;
    }
  }

  /// Buat beberapa varian preprocess untuk dicoba OCR.
  /// [imagePath] = path gambar asli.
  /// Return list: [original, preprocessed] - keduanya path file.
  static Future<List<String>> getOcrVariants(String imagePath) async {
    final variants = <String>[imagePath];
    final preprocessed = await preprocessForOcr(imagePath);
    if (preprocessed != null) {
      variants.add(preprocessed);
    }
    return variants;
  }

  /// Jalankan OCR pada beberapa varian gambar (original + preprocessed).
  /// Return list teks hasil OCR, urutan: original dulu, lalu preprocessed.
  /// Berguna untuk SIM/KTP: coba ekstrak dari tiap teks, ambil yang pertama valid.
  static Future<List<String>> runOcrVariants(String imagePath) async {
    final variants = await getOcrVariants(imagePath);
    final results = <String>[];
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

    try {
      for (final path in variants) {
        try {
          final inputImage = InputImage.fromFilePath(path);
          final recognized = await textRecognizer.processImage(inputImage);
          if (recognized.text.trim().isNotEmpty) {
            results.add(recognized.text);
          }
        } catch (_) {}
      }
    } finally {
      await textRecognizer.close();
    }

    return results;
  }
}
