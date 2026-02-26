import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../utils/app_logger.dart';
import 'package:path/path.dart' as path;

/// Service untuk menyimpan file media (audio, gambar, video) secara lokal di HP.
/// File disimpan di folder aplikasi dan tidak di-upload ke server.
class LocalStorageService {
  /// Simpan file audio ke storage lokal.
  /// Return path lokal file yang disimpan.
  static Future<String?> saveAudioLocally(
    File audioFile,
    String orderId,
    String messageId,
  ) async {
    try {
      final dir = await _getChatMediaDirectory(orderId, 'audio');
      final fileName = '$messageId.m4a';
      final savedFile = File(path.join(dir.path, fileName));
      await audioFile.copy(savedFile.path);
      return savedFile.path;
    } catch (e) {
      // ignore: avoid_print
      log('LocalStorageService.saveAudioLocally error', e);
      return null;
    }
  }

  /// Simpan file gambar ke storage lokal.
  /// Return path lokal file yang disimpan.
  static Future<String?> saveImageLocally(
    File imageFile,
    String orderId,
    String messageId,
  ) async {
    try {
      final dir = await _getChatMediaDirectory(orderId, 'images');
      final fileName = '$messageId.jpg';
      final savedFile = File(path.join(dir.path, fileName));
      await imageFile.copy(savedFile.path);
      return savedFile.path;
    } catch (e) {
      // ignore: avoid_print
      log('LocalStorageService.saveImageLocally error', e);
      return null;
    }
  }

  /// Simpan file video ke storage lokal.
  /// Return path lokal file yang disimpan.
  static Future<String?> saveVideoLocally(
    File videoFile,
    String orderId,
    String messageId,
  ) async {
    try {
      final dir = await _getChatMediaDirectory(orderId, 'videos');
      final fileName = '$messageId.mp4';
      final savedFile = File(path.join(dir.path, fileName));
      await videoFile.copy(savedFile.path);
      return savedFile.path;
    } catch (e) {
      // ignore: avoid_print
      print('LocalStorageService.saveVideoLocally error: $e');
      return null;
    }
  }

  /// Ambil direktori untuk menyimpan media chat.
  /// Struktur: app_documents/chat_media/{orderId}/{type}/
  static Future<Directory> _getChatMediaDirectory(
    String orderId,
    String type,
  ) async {
    final appDir = await getApplicationDocumentsDirectory();
    final chatMediaDir = Directory(
      path.join(appDir.path, 'chat_media', orderId, type),
    );
    if (!await chatMediaDir.exists()) {
      await chatMediaDir.create(recursive: true);
    }
    return chatMediaDir;
  }

  /// Baca file audio dari path lokal.
  static File? getAudioFile(String localPath) {
    final file = File(localPath);
    return file.existsSync() ? file : null;
  }

  /// Baca file gambar dari path lokal.
  static File? getImageFile(String localPath) {
    final file = File(localPath);
    return file.existsSync() ? file : null;
  }

  /// Baca file video dari path lokal.
  static File? getVideoFile(String localPath) {
    final file = File(localPath);
    return file.existsSync() ? file : null;
  }

  /// Hapus semua file media untuk order tertentu (untuk cleanup).
  static Future<void> deleteOrderMedia(String orderId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final orderMediaDir = Directory(
        path.join(appDir.path, 'chat_media', orderId),
      );
      if (await orderMediaDir.exists()) {
        await orderMediaDir.delete(recursive: true);
      }
    } catch (e) {
      // ignore: avoid_print
      log('LocalStorageService.deleteOrderMedia error', e);
    }
  }
}
