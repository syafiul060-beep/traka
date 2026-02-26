import 'package:cloud_firestore/cloud_firestore.dart';

/// Service untuk cek maintenance mode dari Firestore.
class MaintenanceService {
  static const _docPath = 'app_config/maintenance';

  /// Cek apakah maintenance mode aktif.
  /// Return (enabled, message) - message bisa null.
  static Future<(bool enabled, String? message)> check() async {
    try {
      final doc = await FirebaseFirestore.instance.doc(_docPath).get();
      final data = doc.data();
      if (data == null) return (false, null);
      final enabled = data['enabled'] == true;
      final message = (data['message'] as String?)?.trim();
      return (enabled, (message == null || message.isEmpty) ? null : message);
    } catch (_) {
      return (false, null);
    }
  }
}
