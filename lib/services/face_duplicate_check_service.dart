import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_verification/face_verification.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Layanan cek wajah duplikat saat registrasi (image-based).
class FaceDuplicateCheckService {
  static const int maxUsersToCheck = 100;

  /// Threshold lebih rendah agar wajah yang sama (sesama role) terdeteksi duplikat.
  static const double matchThreshold = 0.50;

  static Future<bool> isDuplicateFace(String photoPath, String role) async {
    return _isDuplicateUsingImages(photoPath, role);
  }

  static Future<bool> _isDuplicateUsingImages(
    String photoPath,
    String role,
  ) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final usersQuery = await firestore
          .collection('users')
          .where('role', isEqualTo: role)
          .limit(maxUsersToCheck)
          .get();

      if (usersQuery.docs.isEmpty) return false;

      final tempDir = await getTemporaryDirectory();

      for (final doc in usersQuery.docs) {
        final uid = doc.id;
        try {
          final ref = FirebaseStorage.instance.ref().child(
            'users/$uid/face_verification.jpg',
          );
          final bytes = await ref.getData();
          if (bytes == null || bytes.isEmpty) continue;

          final tempFile = File('${tempDir.path}/dupcheck_$uid.jpg');
          await tempFile.writeAsBytes(bytes);

          await FaceVerification.instance.registerFromImagePath(
            id: 'dupcheck_$uid',
            imagePath: tempFile.path,
            imageId: 'dupcheck',
          );

          final matchId = await FaceVerification.instance.verifyFromImagePath(
            imagePath: photoPath,
            threshold: matchThreshold,
            staffId: 'dupcheck_$uid',
          );

          try {
            await tempFile.delete();
          } catch (_) {}
          try {
            await FaceVerification.instance.deleteRecord('dupcheck_$uid');
          } catch (_) {}

          if (matchId == 'dupcheck_$uid') return true;
        } catch (_) {
          try {
            await FaceVerification.instance.deleteRecord('dupcheck_$uid');
          } catch (_) {}
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
