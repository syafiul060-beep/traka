import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service untuk cek versi minimum dan in-app update.
/// - minVersion dari Firestore app_config/min_version
/// - In-App Update (Flexible) untuk Android
class AppUpdateService {
  static const _configDoc = 'app_config';
  static const _minVersionField = 'minVersion';
  static const _playStoreUrl = 'https://play.google.com/store/apps/details?id=id.traka.app';

  /// Cek apakah versi saat ini < minVersion dari Firestore.
  /// Return true jika user HARUS update (blokir akses).
  static Future<bool> isUpdateRequired() async {
    if (!Platform.isAndroid) return false;
    try {
      final config = await FirebaseFirestore.instance
          .collection(_configDoc)
          .doc('min_version')
          .get();
      final minVersion = (config.data()?[_minVersionField] as String?)?.trim();
      if (minVersion == null || minVersion.isEmpty) return false;

      final info = await PackageInfo.fromPlatform();
      final current = info.version;
      return _compareVersions(current, minVersion) < 0;
    } catch (_) {
      return false;
    }
  }

  /// Bandingkan versi: return -1 jika a < b, 0 jika a == b, 1 jika a > b.
  static int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final len = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < len; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av < bv) return -1;
      if (av > bv) return 1;
    }
    return 0;
  }

  /// Cek dan tampilkan In-App Update (Flexible) jika tersedia.
  /// Hanya untuk Android, dan hanya jika app dari Play Store.
  static Future<void> checkAndPromptFlexibleUpdate() async {
    if (!Platform.isAndroid) return;
    try {
      final updateInfo = await InAppUpdate.checkForUpdate();
      if (updateInfo.updateAvailability != UpdateAvailability.updateAvailable) return;
      if (updateInfo.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      } else if (updateInfo.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      }
    } catch (_) {
      // In-app update hanya bekerja jika app dari Play Store
    }
  }

  /// Buka halaman app di Play Store.
  static Future<void> openPlayStore() async {
    final uri = Uri.parse(_playStoreUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
