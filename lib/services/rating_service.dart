import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service untuk rating dan review driver oleh penumpang.
/// Rating disimpan di order: passengerRating, passengerReview, passengerRatedAt.
class RatingService {
  static const String _collectionOrders = 'orders';

  /// Simpan rating penumpang untuk driver (setelah perjalanan selesai).
  /// [orderId] harus order completed milik penumpang.
  /// [rating] 1-5 bintang.
  static Future<bool> submitPassengerRating(
    String orderId, {
    required int rating,
    String? review,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    if (rating < 1 || rating > 5) return false;

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    if ((data['passengerUid'] as String?) != user.uid) return false;
    if ((data['status'] as String?) != 'completed') return false;
    if (data['passengerRatedAt'] != null) return false; // sudah pernah rating

    await ref.update({
      'passengerRating': rating,
      'passengerReview': (review ?? '').trim().isEmpty ? null : (review ?? '').trim(),
      'passengerRatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Rata-rata rating driver dari order completed.
  static Future<double?> getDriverAverageRating(String driverUid) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('driverUid', isEqualTo: driverUid)
        .where('status', isEqualTo: 'completed')
        .where('passengerRating', isNotEqualTo: null)
        .get();

    if (snap.docs.isEmpty) return null;
    var sum = 0.0;
    var count = 0;
    for (final doc in snap.docs) {
      final r = (doc.data()['passengerRating'] as num?)?.toInt();
      if (r != null && r >= 1 && r <= 5) {
        sum += r;
        count++;
      }
    }
    return count > 0 ? sum / count : null;
  }

  /// Jumlah review driver.
  static Future<int> getDriverReviewCount(String driverUid) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('driverUid', isEqualTo: driverUid)
        .where('status', isEqualTo: 'completed')
        .where('passengerRating', isNotEqualTo: null)
        .get();
    return snap.docs.length;
  }

  /// Tier driver (Basic, Gold, Platinum) seperti Shopee.
  /// Basic: 0-2 ulasan. Gold: ≥3 ulasan & rata-rata ≥4.0. Platinum: ≥5 ulasan & rata-rata ≥4.5.
  static String getDriverTierLabel(double? avgRating, int reviewCount) {
    if (reviewCount <= 2) return 'Basic';
    if (reviewCount >= 5 && (avgRating ?? 0) >= 4.5) return 'Platinum';
    if (reviewCount >= 3 && (avgRating ?? 0) >= 4.0) return 'Gold';
    return 'Basic';
  }
}
