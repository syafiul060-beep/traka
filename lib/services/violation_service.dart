import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service untuk pelanggaran (tidak scan barcode, konfirmasi otomatis).
class ViolationService {
  static const String _collectionUsers = 'users';
  static const String _collectionViolationRecords = 'violation_records';
  static const String _collectionAppConfig = 'app_config';

  /// Biaya pelanggaran (Rp) dari app_config/settings. Min 5000; di atas 5000 ikuti Firestore.
  static Future<int> getViolationFeeRupiah() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collectionAppConfig)
          .doc('settings')
          .get();
      final v = doc.data()?['violationFeeRupiah'];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n > 0) {
          return n < 5000 ? 5000 : n;
        }
      }
    } catch (_) {}
    return 5000;
  }

  /// Ambil outstanding violation fee penumpang dari users/{uid}.
  static Future<double> getOutstandingViolationFee(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection(_collectionUsers)
        .doc(uid)
        .get();
    if (!doc.exists || doc.data() == null) return 0;
    final fee = (doc.data()!['outstandingViolationFee'] as num?)?.toDouble();
    return fee ?? 0;
  }

  /// Ambil jumlah pelanggaran belum bayar.
  static Future<int> getOutstandingViolationCount(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection(_collectionUsers)
        .doc(uid)
        .get();
    if (!doc.exists || doc.data() == null) return 0;
    final count = (doc.data()!['outstandingViolationCount'] as num?)?.toInt();
    return count ?? 0;
  }

  /// Cek apakah penumpang punya pelanggaran belum bayar (blok cari travel).
  static Future<bool> hasOutstandingViolation(String uid) async {
    final fee = await getOutstandingViolationFee(uid);
    return fee > 0;
  }
}
