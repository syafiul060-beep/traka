import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service untuk dashboard pendapatan driver.
/// Menghitung total pendapatan dari order completed (agreedPrice).
class DriverEarningsService {
  static const String _collectionOrders = 'orders';

  /// Total pendapatan driver dari order completed (agreedPrice).
  static Future<double> getTotalEarnings(String driverUid) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('driverUid', isEqualTo: driverUid)
        .where('status', isEqualTo: 'completed')
        .get();

    var total = 0.0;
    for (final doc in snap.docs) {
      final price = (doc.data()['agreedPrice'] as num?)?.toDouble();
      if (price != null && price > 0) total += price;
    }
    return total;
  }

  /// Pendapatan hari ini.
  static Future<double> getTodayEarnings(String driverUid) async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('driverUid', isEqualTo: driverUid)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .get();

    var total = 0.0;
    for (final doc in snap.docs) {
      final completedAt = (doc.data()['completedAt'] as Timestamp?)?.toDate();
      if (completedAt != null && completedAt.isAfter(startOfDay)) {
        final price = (doc.data()['agreedPrice'] as num?)?.toDouble();
        if (price != null && price > 0) total += price;
      }
    }
    return total;
  }

  /// Pendapatan minggu ini (7 hari terakhir).
  static Future<double> getWeekEarnings(String driverUid) async {
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('driverUid', isEqualTo: driverUid)
        .where('status', isEqualTo: 'completed')
        .where('completedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(weekAgo))
        .get();

    var total = 0.0;
    for (final doc in snap.docs) {
      final completedAt = (doc.data()['completedAt'] as Timestamp?)?.toDate();
      if (completedAt != null && completedAt.isAfter(weekAgo)) {
        final price = (doc.data()['agreedPrice'] as num?)?.toDouble();
        if (price != null && price > 0) total += price;
      }
    }
    return total;
  }

  /// Jumlah perjalanan selesai.
  static Future<int> getCompletedTripCount(String driverUid) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('driverUid', isEqualTo: driverUid)
        .where('status', isEqualTo: 'completed')
        .get();
    return snap.docs.length;
  }
}
