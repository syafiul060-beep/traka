import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Tier penumpang berdasarkan jumlah pesanan selesai (seperti Shopee).
/// Basic: 0-4. Gold: 5-9. Platinum: ≥10.
class PassengerTierService {
  static const String _collectionOrders = 'orders';
  static const String _statusCompleted = 'completed';

  /// Jumlah pesanan selesai penumpang (sebagai passenger atau receiver).
  static Future<int> getPassengerCompletedOrderCount(String uid) async {
    final asPassenger = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('passengerUid', isEqualTo: uid)
        .where('status', isEqualTo: _statusCompleted)
        .get();

    final asReceiver = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('receiverUid', isEqualTo: uid)
        .where('status', isEqualTo: _statusCompleted)
        .get();

    final passengerIds = asPassenger.docs.map((d) => d.id).toSet();
    final receiverIds = asReceiver.docs.map((d) => d.id).toSet();
    final uniqueOrderIds = passengerIds.union(receiverIds);
    return uniqueOrderIds.length;
  }

  /// Tier label berdasarkan jumlah pesanan selesai.
  /// Basic: 0-4. Gold: 5-9. Platinum: ≥10.
  static String getPassengerTierLabel(int completedCount) {
    if (completedCount >= 10) return 'Platinum';
    if (completedCount >= 5) return 'Gold';
    return 'Basic';
  }
}
