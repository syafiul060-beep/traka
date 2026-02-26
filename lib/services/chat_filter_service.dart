import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Filter chat untuk mencegah transaksi di luar aplikasi (nomor WA, HP, rekening, dll).
class ChatFilterService {
  static const String blockedMessage =
      'Pesan tidak dapat dikirim. Dilarang membagikan kontak atau nomor untuk transaksi di luar aplikasi.';

  /// Blokir semua pesan audio (transkripsi audio memerlukan server-side).
  /// Set false untuk mengizinkan audio (tanpa filter konten).
  static const bool blockAudioMessages = false;

  static final List<RegExp> _blockedPatterns = [
    // Nomor HP Indonesia: 08xx, +62, 62xx, dengan spasi/dash
    RegExp(r'08[\d\s\-]{8,15}'),
    RegExp(r'\+62[\d\s\-]{8,15}'),
    RegExp(r'\b62[\d\s\-]{9,15}'),
    RegExp(r'0\d{9,12}'),
    // Link WhatsApp
    RegExp(r'wa\.me', caseSensitive: false),
    RegExp(r'whatsapp\.com', caseSensitive: false),
    RegExp(r'chat\.whatsapp\.com', caseSensitive: false),
    // Link platform lain
    RegExp(r't\.me/', caseSensitive: false),
    RegExp(r'telegram\.me', caseSensitive: false),
    RegExp(r'line\.me', caseSensitive: false),
    RegExp(r'line://', caseSensitive: false),
    // Nomor rekening (konteks: norek/rekening + digit, atau digit panjang berdiri sendiri)
    RegExp(r'(?:norek|rekening|no\.?\s*rek)[:\s]*\d{8,16}', caseSensitive: false),
    // Kata kunci
    RegExp(r'whatsapp|wa\s*me|chat\s*wa', caseSensitive: false),
    RegExp(r'transfer\s+ke|norek|no\s*rek|rekening', caseSensitive: false),
    RegExp(r'bayar\s*manual|deal\s*luar|luar\s*aplikasi', caseSensitive: false),
    RegExp(r'hubungi\s+saya|kontak\s+saya|nomor\s+saya', caseSensitive: false),
    RegExp(r'dilibank|ovo\s*dana|dana\s*ovo', caseSensitive: false),
    // Email (untuk kontak eksternal)
    RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'),
  ];

  /// Cek apakah teks mengandung konten yang diblokir.
  static bool containsBlockedContent(String text) {
    if (text.trim().isEmpty) return false;
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ');
    for (final pattern in _blockedPatterns) {
      if (pattern.hasMatch(normalized)) return true;
    }
    return false;
  }

  /// Cek apakah gambar mengandung teks yang diblokir (OCR dengan ML Kit).
  static Future<bool> imageContainsBlockedContent(File imageFile) async {
    if (!await imageFile.exists()) return false;
    try {
      final inputImage = InputImage.fromFilePath(imageFile.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();
      final text = recognizedText.text;
      if (text.isEmpty) return false;
      return containsBlockedContent(text);
    } catch (_) {
      return false; // Jika OCR gagal, izinkan (jangan blokir)
    }
  }
}
