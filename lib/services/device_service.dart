import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Informasi device untuk keamanan dan rate limiting.
class TrakaDeviceInfo {
  final String? deviceId;
  final String osVersion;
  final String model;
  final String installId;
  final String fingerprint;

  const TrakaDeviceInfo({
    this.deviceId,
    required this.osVersion,
    required this.model,
    required this.installId,
    required this.fingerprint,
  });
}

/// Layanan untuk mendapatkan Device ID dan informasi perangkat.
class DeviceService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  static const _prefInstallId = 'traka_install_id';
  static const _uuid = Uuid();

  /// Mendapatkan ID unik perangkat.
  static Future<String?> getDeviceId() async {
    try {
      if (Platform.isAndroid) {
        final android = await _deviceInfo.androidInfo;
        return android.id;
      } else if (Platform.isIOS) {
        final ios = await _deviceInfo.iosInfo;
        return ios.identifierForVendor;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Mendapatkan App Install ID (unik per install, persist di SharedPreferences).
  static Future<String> getInstallId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefInstallId);
    if (id == null || id.isEmpty) {
      id = _uuid.v4();
      await prefs.setString(_prefInstallId, id);
    }
    return id;
  }

  /// Mendapatkan informasi lengkap device (OS, model, install ID).
  static Future<TrakaDeviceInfo> getDeviceInfo() async {
    String osVersion = '';
    String model = '';
    try {
      if (Platform.isAndroid) {
        final android = await _deviceInfo.androidInfo;
        osVersion = 'Android ${android.version.release}';
        model = android.model;
      } else if (Platform.isIOS) {
        final ios = await _deviceInfo.iosInfo;
        osVersion = 'iOS ${ios.systemVersion}';
        model = ios.model;
      }
    } catch (_) {}
    final deviceId = await getDeviceId();
    final installId = await getInstallId();
    final fingerprint = _buildFingerprint(
      deviceId,
      osVersion,
      model,
      installId,
    );
    return TrakaDeviceInfo(
      deviceId: deviceId,
      osVersion: osVersion,
      model: model,
      installId: installId,
      fingerprint: fingerprint,
    );
  }

  static String _buildFingerprint(
    String? deviceId,
    String osVersion,
    String model,
    String installId,
  ) {
    final parts = [
      deviceId ?? 'unknown',
      osVersion.replaceAll(' ', '_'),
      model.replaceAll(' ', '_'),
      installId,
    ];
    return parts.join('|');
  }
}
