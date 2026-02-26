import 'package:cloud_firestore/cloud_firestore.dart';

import 'device_security_service.dart';

/// Service untuk penghapusan akun dengan masa tenggang 30 hari.
class AccountDeletionService {
  static const _gracePeriodDays = 30;
  static const _collectionUsers = 'users';

  /// Jadwalkan penghapusan akun: set deletedAt dan scheduledDeletionAt.
  /// Melepaskan device_accounts untuk user ini agar device bisa dipakai daftar lagi.
  static Future<void> scheduleAccountDeletion(String uid, String role) async {
    final now = DateTime.now();
    final scheduledDeletion = now.add(const Duration(days: _gracePeriodDays));

    await FirebaseFirestore.instance.collection(_collectionUsers).doc(uid).update({
      'deletedAt': FieldValue.serverTimestamp(),
      'scheduledDeletionAt': Timestamp.fromDate(scheduledDeletion),
    });

    // Lepaskan device_accounts untuk user ini
    final userDoc = await FirebaseFirestore.instance
        .collection(_collectionUsers)
        .doc(uid)
        .get();
    final deviceId = (userDoc.data()?['deviceId'] as String?)?.trim();
    if (deviceId != null && deviceId.isNotEmpty) {
      await DeviceSecurityService.releaseDeviceRegistration(deviceId, role);
    }
    await _releaseDeviceAccountsByUser(uid, role);
  }

  /// Lepaskan device_accounts dengan query penumpangUid/driverUid (karena doc ID = installId).
  static Future<void> _releaseDeviceAccountsByUser(String uid, String role) async {
    try {
      final col = FirebaseFirestore.instance.collection('device_accounts');
      final field = role == 'penumpang' ? 'penumpangUid' : 'driverUid';
      final query = await col.where(field, isEqualTo: uid).limit(10).get();
      for (final doc in query.docs) {
        await col.doc(doc.id).update({field: FieldValue.delete()});
      }
    } catch (_) {}
  }

  /// Batalkan penghapusan: hapus deletedAt dan scheduledDeletionAt.
  static Future<void> cancelAccountDeletion(String uid) async {
    await FirebaseFirestore.instance.collection(_collectionUsers).doc(uid).update({
      'deletedAt': FieldValue.delete(),
      'scheduledDeletionAt': FieldValue.delete(),
    });
  }

  /// Cek apakah user doc punya deletedAt.
  static bool isDeleted(Map<String, dynamic>? userData) {
    if (userData == null) return false;
    return userData['deletedAt'] != null;
  }

  /// Hitung sisa hari sebelum penghapusan permanen.
  static int? daysUntilDeletion(Map<String, dynamic>? userData) {
    if (userData == null) return null;
    final scheduled = userData['scheduledDeletionAt'];
    if (scheduled == null) return null;
    final dt = scheduled is Timestamp ? scheduled.toDate() : null;
    if (dt == null) return null;
    final days = dt.difference(DateTime.now()).inDays;
    return days > 0 ? days : 0;
  }

  /// Query users by email (untuk cek email-already-in-use, apakah punya deletedAt).
  static Future<DocumentSnapshot<Map<String, dynamic>>?> findUserByEmail(
    String email,
  ) async {
    final q = await FirebaseFirestore.instance
        .collection(_collectionUsers)
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (q.docs.isEmpty) return null;
    return q.docs.first;
  }
}
