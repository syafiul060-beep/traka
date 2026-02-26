import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'order_service.dart';
import 'route_journey_number_service.dart';

/// Service untuk riwayat perjalanan driver (koleksi `trips`).
/// Saat driver menekan "Selesai Bekerja", rute yang selesai disimpan ke Firestore.
class TripService {
  static const String _collectionTrips = 'trips';
  static const String _statusCompleted = 'completed';

  /// Simpan perjalanan yang baru selesai ke Firestore.
  /// [orderNumbers] diisi dari koleksi orders (pesanan dengan routeJourneyNumber ini).
  static Future<void> saveCompletedTrip({
    required double routeOriginLat,
    required double routeOriginLng,
    required double routeDestLat,
    required double routeDestLng,
    required String routeOriginText,
    required String routeDestText,
    String? routeJourneyNumber,
    DateTime? routeStartedAt,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final dayName = RouteJourneyNumberService.getDayName(now);
    final nowStamp = FieldValue.serverTimestamp();

    List<String> orderNumbers = <String>[];
    if (routeJourneyNumber != null && routeJourneyNumber.isNotEmpty) {
      final ordersSnap = await FirebaseFirestore.instance
          .collection('orders')
          .where('routeJourneyNumber', isEqualTo: routeJourneyNumber)
          .where('driverUid', isEqualTo: user.uid)
          .where(
            'status',
            whereIn: [
              OrderService.statusAgreed,
              OrderService.statusPickedUp,
              OrderService.statusCompleted,
            ],
          )
          .get();
      for (final d in ordersSnap.docs) {
        final num_ = (d.data()['orderNumber'] as String?);
        if (num_ != null && num_.isNotEmpty) orderNumbers.add(num_);
      }
    }

    await FirebaseFirestore.instance.collection(_collectionTrips).add({
      'driverUid': user.uid,
      'routeJourneyNumber': routeJourneyNumber ?? '',
      'routeOriginLat': routeOriginLat,
      'routeOriginLng': routeOriginLng,
      'routeDestLat': routeDestLat,
      'routeDestLng': routeDestLng,
      'routeOriginText': routeOriginText,
      'routeDestText': routeDestText,
      'routeStartedAt': routeStartedAt != null
          ? Timestamp.fromDate(routeStartedAt)
          : null,
      'orderNumbers': orderNumbers,
      'status': _statusCompleted,
      'date': dateStr,
      'day': dayName,
      'completedAt': nowStamp,
      'createdAt': nowStamp,
    });
  }
}
