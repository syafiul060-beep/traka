import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image/image.dart' as img;

import 'image_compression_service.dart';

/// Layanan pengelolaan pool foto verifikasi wajah (maks 3 foto).
/// Mengganti foto kualitas buruk dengan foto baru yang lebih bagus saat login dari device baru.
class FacePhotoPoolService {
  static const int maxPoolSize = 3;

  /// Update pool: tambah foto baru jika bagus, atau ganti yang paling buruk.
  static Future<void> updatePoolOnLoginSuccess(
    String uid,
    File selfieFile,
  ) async {
    try {
      final image = img.decodeImage(await selfieFile.readAsBytes());
      if (image == null) return;

      final width = image.width;
      final height = image.height;
      final quality = width * height;

      final firestore = FirebaseFirestore.instance;
      final doc = await firestore.collection('users').doc(uid).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      final pool = List<Map<String, dynamic>>.from(
        (data['faceVerificationPool'] as List<dynamic>?) ?? [],
      );
      final primaryUrl = data['faceVerificationUrl'] as String? ?? '';

      if (pool.isEmpty && primaryUrl.isNotEmpty) {
        pool.add({'url': primaryUrl, 'width': 0, 'height': 0});
      }

      if (pool.length < maxPoolSize) {
        final newUrl = await _uploadToStorage(uid, selfieFile, pool.length);
        pool.add({'url': newUrl, 'width': width, 'height': height});
      } else {
        var worstIdx = 0;
        var worstQuality =
            (pool[0]['width'] as int? ?? 0) * (pool[0]['height'] as int? ?? 0);
        for (var i = 1; i < pool.length; i++) {
          final q =
              (pool[i]['width'] as int? ?? 0) *
              (pool[i]['height'] as int? ?? 0);
          if (q < worstQuality) {
            worstQuality = q;
            worstIdx = i;
          }
        }
        if (quality > worstQuality) {
          final newUrl = await _uploadToStorage(uid, selfieFile, worstIdx);
          pool[worstIdx] = {'url': newUrl, 'width': width, 'height': height};
        } else {
          return;
        }
      }

      final compressedPath = await ImageCompressionService.compressForUpload(selfieFile.path);
      final fileToUpload = File(compressedPath);
      final primaryRef = FirebaseStorage.instance.ref().child(
        'users/$uid/face_verification.jpg',
      );
      await primaryRef.putFile(fileToUpload);
      final newPrimaryUrl = await primaryRef.getDownloadURL();

      await firestore.collection('users').doc(uid).update({
        'faceVerificationUrl': newPrimaryUrl,
        'faceVerificationPool': pool
            .map(
              (p) => {
                'url': p['url'],
                'width': p['width'],
                'height': p['height'],
              },
            )
            .toList(),
      });
    } catch (_) {}
  }

  static Future<String> _uploadToStorage(
    String uid,
    File file,
    int index,
  ) async {
    final compressedPath = await ImageCompressionService.compressForUpload(file.path);
    final fileToUpload = File(compressedPath);
    final ref = FirebaseStorage.instance.ref().child(
      'users/$uid/face_pool_$index.jpg',
    );
    await ref.putFile(fileToUpload);
    return ref.getDownloadURL();
  }
}
