import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../utils/app_logger.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service untuk merekam audio (voice message).
class AudioRecorderService {
  static final AudioRecorder _recorder = AudioRecorder();
  static bool _isRecording = false;
  static String? _currentPath;
  static DateTime? _startTime;

  /// Mulai rekam audio.
  /// Return path file audio jika berhasil, null jika gagal.
  static Future<String?> startRecording() async {
    if (_isRecording) return null;

    // Cek permission mikrofon
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      return null;
    }

    try {
      final dir = await getTemporaryDirectory();
      final fileName = 'audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final path = '${dir.path}/$fileName';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _isRecording = true;
      _currentPath = path;
      _startTime = DateTime.now();
      return path;
    } catch (e) {
      // ignore: avoid_print
      log('AudioRecorderService.startRecording error', e);
      return null;
    }
  }

  /// Stop rekam audio.
  /// Return file audio dan durasi dalam detik.
  static Future<({File file, int duration})?> stopRecording() async {
    if (!_isRecording || _currentPath == null || _startTime == null) {
      return null;
    }

    try {
      // Stop recorder dan dapatkan path file yang sebenarnya
      final path = await _recorder.stop();
      _isRecording = false;

      // Gunakan path yang dikembalikan oleh recorder, atau fallback ke _currentPath
      final finalPath = path ?? _currentPath;
      if (finalPath == null) {
        _currentPath = null;
        _startTime = null;
        return null;
      }

      final file = File(finalPath);

      // Tunggu sebentar untuk memastikan file sudah ditulis
      await Future.delayed(const Duration(milliseconds: 100));

      // Cek apakah file ada
      if (!await file.exists()) {
        // ignore: avoid_print
        log('AudioRecorderService.stopRecording: File tidak ditemukan di $finalPath');
        _currentPath = null;
        _startTime = null;
        return null;
      }

      // Cek ukuran file (harus lebih dari 0 bytes)
      final fileSize = await file.length();
      if (fileSize == 0) {
        // ignore: avoid_print
        log('AudioRecorderService.stopRecording: File kosong (0 bytes)');
        _currentPath = null;
        _startTime = null;
        return null;
      }

      final duration = DateTime.now().difference(_startTime!).inSeconds;
      _currentPath = null;
      _startTime = null;

      return (file: file, duration: duration);
    } catch (e) {
      // ignore: avoid_print
      log('AudioRecorderService.stopRecording error', e);
      _isRecording = false;
      _currentPath = null;
      _startTime = null;
      return null;
    }
  }

  /// Cancel rekam audio (hapus file).
  static Future<void> cancelRecording() async {
    if (_isRecording) {
      try {
        await _recorder.stop();
        if (_currentPath != null) {
          final file = File(_currentPath!);
          if (await file.exists()) {
            await file.delete();
          }
        }
      } catch (_) {}
    }
    _isRecording = false;
    _currentPath = null;
    _startTime = null;
  }

  /// Cek apakah sedang rekam.
  static bool get isRecording => _isRecording;

  /// Durasi rekaman saat ini dalam detik.
  static int get currentDuration {
    if (_startTime == null) return 0;
    return DateTime.now().difference(_startTime!).inSeconds;
  }
}
