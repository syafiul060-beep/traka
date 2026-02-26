import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Layanan validasi device & session (rate limit, device info).
class SessionValidationService {
  static const _prefPhotoAttempts = 'face_photo_attempts';
  static const _prefPhotoAttemptReset = 'face_photo_attempt_reset';
  static const _maxAttemptsPerHour = 10;
  static const _resetIntervalHours = 1;

  /// Cek rate limit untuk upload foto wajah.
  static Future<SessionValidationResult> checkPhotoRateLimit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final lastReset = prefs.getInt(_prefPhotoAttemptReset) ?? 0;
      final lastResetTime = DateTime.fromMillisecondsSinceEpoch(lastReset);
      final elapsed = now.difference(lastResetTime).inHours;

      if (elapsed >= _resetIntervalHours) {
        await prefs.setInt(_prefPhotoAttempts, 0);
        await prefs.setInt(_prefPhotoAttemptReset, now.millisecondsSinceEpoch);
      }

      final attempts = prefs.getInt(_prefPhotoAttempts) ?? 0;
      if (attempts >= _maxAttemptsPerHour) {
        return SessionValidationResult(
          isValid: false,
          errorMessage:
              'Terlalu banyak percobaan. Coba lagi dalam $_resetIntervalHours jam.',
        );
      }

      await prefs.setInt(_prefPhotoAttempts, attempts + 1);
      return SessionValidationResult(isValid: true);
    } catch (e) {
      return SessionValidationResult(isValid: true);
    }
  }

  /// Mendapatkan info device untuk logging/keamanan (Device ID, OS version, App version).
  static Future<Map<String, String>> getDeviceInfo() async {
    final info = <String, String>{};
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = await deviceInfo.androidInfo;
        info['deviceId'] = android.id;
        info['osVersion'] = android.version.release;
        info['model'] = android.model;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = await deviceInfo.iosInfo;
        info['deviceId'] = ios.identifierForVendor ?? '';
        info['osVersion'] = ios.systemVersion;
        info['model'] = ios.model;
      }
    } catch (_) {}
    return info;
  }
}

/// Hasil validasi session.
class SessionValidationResult {
  final bool isValid;
  final String? errorMessage;

  const SessionValidationResult({required this.isValid, this.errorMessage});
}
