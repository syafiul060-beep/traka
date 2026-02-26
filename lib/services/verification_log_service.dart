import 'package:cloud_firestore/cloud_firestore.dart';

import 'device_service.dart';

/// Sumber verifikasi wajah.
enum VerificationLogSource {
  login,
  reverify,
  profilePenumpang,
  profileDriver,
  forgotPassword,
}

/// Audit trail verifikasi wajah untuk forensik.
/// Menyimpan log di users/{uid}/verification_logs.
class VerificationLogService {
  static const _collection = 'verification_logs';

  /// Log hasil verifikasi wajah. Fire-and-forget, tidak memblokir UI.
  static void log({
    required String userId,
    required bool success,
    required VerificationLogSource source,
    String? deviceId,
    String? errorMessage,
  }) {
    Future.microtask(() async {
      try {
        final did = deviceId ?? await DeviceService.getDeviceId();
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection(_collection)
            .add({
          'timestamp': FieldValue.serverTimestamp(),
          'success': success,
          'source': source.name,
          if (did != null && did.isNotEmpty) 'deviceId': did,
          if (errorMessage != null && errorMessage.isNotEmpty)
            'errorMessage': errorMessage,
        });
      } catch (_) {
        // Jangan gagalkan flow utama jika log gagal
      }
    });
  }
}
