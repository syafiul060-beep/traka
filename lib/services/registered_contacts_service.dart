import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

/// Service untuk cek kontak mana yang terdaftar sebagai user Traka.
class RegisteredContactsService {
  RegisteredContactsService._();

  /// Normalisasi nomor HP ke format +62 (08, 62, +62).
  static String? normalizePhone(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    if (digits.startsWith('62') && digits.length >= 10) {
      return '+$digits';
    }
    if (digits.startsWith('0') && digits.length >= 10) {
      return '+62${digits.substring(1)}';
    }
    if (digits.length >= 9) {
      return '+62$digits';
    }
    return null;
  }

  /// Cek maksimal 50 nomor ke backend. Return Map<normalizedPhone, {uid, displayName, photoUrl}>.
  static Future<Map<String, Map<String, dynamic>>> checkRegistered(
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
      final callable = FirebaseFunctions.instance.httpsCallable(
        'checkRegisteredContacts',
      );
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
        };
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  /// Ambil kontak dari HP (dengan properties untuk nomor, photo).
  static Future<List<Contact>> getContacts() async {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) return [];
    return FlutterContacts.getContacts(
      withProperties: true,
      withPhoto: true,
    );
  }

  /// Ekstrak nomor HP dari Contact.
  static List<String> getPhonesFromContact(Contact c) {
    final phones = c.phones;
    if (phones.isEmpty) return [];
    return phones.map((p) => p.number).where((n) => n.isNotEmpty).toList();
  }
}
