import 'package:cloud_functions/cloud_functions.dart';

/// Service untuk cek kontak yang terdaftar sebagai driver (role=driver).
/// Dipakai untuk Oper Driver: pilih driver kedua dari kontak.
class DriverContactService {
  DriverContactService._();

  static String? normalizePhone(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.startsWith('62') && digits.length >= 10) return '+$digits';
    if (digits.startsWith('0') && digits.length >= 10) return '+62${digits.substring(1)}';
    if (digits.length >= 9) return '+62$digits';
    return null;
  }

  /// Cek maksimal 50 nomor ke backend. Return Map<normalizedPhone, {uid, displayName, photoUrl, email}>.
  /// Hanya user dengan role=driver yang dikembalikan.
  static Future<Map<String, Map<String, dynamic>>> checkRegisteredDrivers(
    List<String> phoneNumbers,
  ) async {
    if (phoneNumbers.isEmpty) return {};
    final normalized = <String>[];
    final seen = <String>{};
    for (var i = 0; i < phoneNumbers.length && normalized.length < 50; i++) {
      final n = normalizePhone(phoneNumbers[i]);
      if (n != null && !seen.contains(n)) {
        seen.add(n);
        normalized.add(n);
      }
    }
    if (normalized.isEmpty) return {};
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('checkRegisteredDrivers');
      final result = await callable.call({'phoneNumbers': normalized});
      final data = result.data as Map<String, dynamic>?;
      final list = data?['registered'] as List<dynamic>? ?? [];
      final map = <String, Map<String, dynamic>>{};
      for (final item in list) {
        final m = item as Map<String, dynamic>?;
        if (m == null) continue;
        final phone = m['phoneNumber'] as String?;
        if (phone == null) continue;
        map[phone] = {
          'uid': m['uid'],
          'displayName': m['displayName'],
          'photoUrl': m['photoUrl'],
          'email': m['email'],
          'vehicleJumlahPenumpang': m['vehicleJumlahPenumpang'],
        };
      }
      return map;
    } catch (_) {
      return {};
    }
  }
}
