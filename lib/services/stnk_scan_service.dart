import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import 'ocr_preprocess_service.dart';

/// Service untuk scan STNK/plat kendaraan via OCR.
/// Foto TIDAK disimpan ke server - hanya dipakai untuk ekstraksi teks.
/// Menggunakan preprocessing gambar + multi-attempt untuk akurasi lebih baik.
class StnkScanService {
  static final ImagePicker _picker = ImagePicker();

  /// Ambil foto dari kamera atau galeri, ekstrak nomor plat via OCR.
  /// Return nomor plat jika ditemukan; null jika gagal/tidak ditemukan.
  static Future<String?> scanPlatFromCamera() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100, // Kualitas maksimal untuk akurasi OCR
    );
    if (image == null) return null;
    return _processImage(image.path);
  }

  static Future<String?> scanPlatFromGallery() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 100, // Kualitas maksimal untuk akurasi OCR
    );
    if (image == null) return null;
    return _processImage(image.path);
  }

  static Future<String?> _processImage(String path) async {
    try {
      final variants = await OcrPreprocessService.getOcrVariants(path);
      String? bestResult;

      for (final variantPath in variants) {
        final result = await _runOcrOnImage(variantPath);
        if (result != null && result.length >= 5) {
          bestResult = result;
          break; // Hasil valid ditemukan
        }
      }

      return bestResult;
    } catch (e) {
      return null;
    }
  }

  /// Jalankan OCR pada satu gambar dan ekstrak plat.
  static Future<String?> _runOcrOnImage(String path) async {
    try {
      final inputImage = InputImage.fromFilePath(path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      // Prioritas 1: Cari dari tiap block (plat sering di block terpisah di STNK)
      final candidates = <({String plat, double top})>[];
      for (final block in recognizedText.blocks) {
        final plat = _extractPlatFromText(block.text);
        if (plat != null && plat.length >= 5) {
          candidates.add((plat: plat, top: block.boundingBox.top));
        }
        for (final line in block.lines) {
          final linePlat = _extractPlatFromText(line.text);
          if (linePlat != null && linePlat.length >= 5) {
            candidates.add((plat: linePlat, top: line.boundingBox.top));
          }
        }
      }

      if (candidates.isNotEmpty) {
        candidates.sort((a, b) => a.top.compareTo(b.top));
        return candidates.first.plat;
      }

      return _extractPlatFromText(recognizedText.text);
    } catch (_) {
      return null;
    }
  }

  /// Ekstrak nomor plat Indonesia dari teks OCR.
  /// Format: 1-2 huruf + spasi + 1-4 angka + spasi + 1-3 huruf (contoh: B 1234 ABC)
  static String? _extractPlatFromText(String? text) {
    if (text == null || text.isEmpty) return null;

    // Normalisasi: hapus newline, ganti multiple space jadi single
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();

    // Pola plat Indonesia: [A-Z]{1,2} [0-9]{1,4} [A-Z]{1,3}
    // Juga tangkap variasi: B1234ABC, B 1234 ABC, AD 1234 XY
    final patterns = [
      RegExp(r'[A-Z]{1,2}\s*[0-9]{1,4}\s*[A-Z]{1,3}'),
      RegExp(r'[A-Z]{1,2}[0-9]{1,4}[A-Z]{1,3}'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(normalized);
      if (match != null) {
        var plat = match.group(0)!;
        plat = _formatPlatWithSpaces(plat);
        if (plat.length >= 5) return plat;
      }
    }

    // Pola permissive untuk OCR error (O↔0, I↔1, dll): [A-Z]{1,2}[A-Z0-9]{1,4}[A-Z0-9]{1,3}
    final ocrPattern = RegExp(r'[A-Z]{1,2}[A-Z0-9]{1,4}[A-Z0-9]{1,3}');
    for (final match in ocrPattern.allMatches(normalized)) {
      final corrected = _tryOcrCorrectPlat(match.group(0)!);
      if (corrected != null && corrected.length >= 5) return corrected;
    }

    // Cari per kata - kadang OCR memisahkan
    final words = normalized.split(RegExp(r'\s+'));
    for (var i = 0; i < words.length - 2; i++) {
      final a = words[i];
      final b = words[i + 1];
      final c = words[i + 2];
      if (_isRegionCode(a) && _isDigits(b) && _isSuffix(c)) {
        return '$a $b $c';
      }
    }

    return null;
  }

  static bool _isRegionCode(String s) =>
      s.length >= 1 && s.length <= 2 && s.contains(RegExp(r'^[A-Z]+$'));
  static bool _isDigits(String s) =>
      s.length >= 1 && s.length <= 4 && s.contains(RegExp(r'^[0-9]+$'));
  static bool _isSuffix(String s) =>
      s.length >= 1 && s.length <= 3 && s.contains(RegExp(r'^[A-Z]+$'));

  /// Format plat dengan spasi: B1234ABC -> B 1234 ABC
  static String _formatPlatWithSpaces(String plat) {
    final noSpace = plat.replaceAll(' ', '');
    final m = RegExp(r'^([A-Z]{1,2})([0-9]{1,4})([A-Z]{1,3})$').firstMatch(noSpace);
    if (m != null) {
      return '${m.group(1)} ${m.group(2)} ${m.group(3)}';
    }
    return plat;
  }

  /// Koreksi kesalahan OCR umum: O↔0, I↔1, B↔8, S↔5, G↔6 di bagian digit.
  /// Coba variasinya dan return yang valid.
  static String? _tryOcrCorrectPlat(String raw) {
    final noSpace = raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final m = RegExp(r'^([A-Z]{1,2})([A-Z0-9]{1,4})([A-Z0-9]{1,3})$').firstMatch(noSpace);
    if (m == null) return null;

    final prefix = m.group(1)!;
    final digits = m.group(2)!;
    final suffix = m.group(3)!;

    // Koreksi digit: O->0, I->1, l->1, B->8 (jarang), S->5, G->6
    final digitCorrected = digits
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('L', '1')
        .replaceAll('B', '8') // B di tengah bisa 8
        .replaceAll('S', '5')
        .replaceAll('G', '6')
        .replaceAll('Z', '2');

    // Koreksi suffix: 0->O, 1->I, 8->B
    final suffixCorrected = suffix
        .replaceAll('0', 'O')
        .replaceAll('1', 'I')
        .replaceAll('8', 'B');

    // Pastikan digit hanya angka
    if (!RegExp(r'^[0-9]{1,4}$').hasMatch(digitCorrected)) return null;
    if (!RegExp(r'^[A-Z]{1,3}$').hasMatch(suffixCorrected)) return null;

    return '$prefix $digitCorrected $suffixCorrected';
  }
}
