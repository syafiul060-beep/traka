import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Kontribusi driver: set false untuk nonaktifkan sementara.
const bool kContributionEnabled = true;

/// Status kontribusi driver: wajib bayar jika total penumpang (travel) sudah >= 1× kapasitas sejak bayar terakhir.
class DriverContributionStatus {
  final int totalPenumpangServed;
  final int contributionPaidUpToCount;
  final int capacity;
  final bool mustPayContribution;

  const DriverContributionStatus({
    required this.totalPenumpangServed,
    required this.contributionPaidUpToCount,
    required this.capacity,
    required this.mustPayContribution,
  });

  /// Batas penumpang sebelum wajib bayar lagi (setelah bayar terakhir).
  int get threshold => contributionPaidUpToCount + (1 * capacity);

  /// Sisa penumpang sebelum wajib bayar (bisa negatif jika sudah wajib bayar).
  int get remainingBeforeMustPay => threshold - totalPenumpangServed;
}

/// Service untuk cek status kontribusi driver (1× kapasitas → wajib bayar).
class DriverContributionService {
  static const String _collectionUsers = 'users';

  /// Stream status kontribusi driver dari users/{uid}.
  /// Hanya untuk driver; penumpang tidak perlu.
  static Stream<DriverContributionStatus> streamContributionStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Stream.value(
        const DriverContributionStatus(
          totalPenumpangServed: 0,
          contributionPaidUpToCount: 0,
          capacity: 7,
          mustPayContribution: false,
        ),
      );
    }

    return FirebaseFirestore.instance
        .collection(_collectionUsers)
        .doc(user.uid)
        .snapshots()
        .map((doc) {
          final d = doc.data();
          final total = (d?['totalPenumpangServed'] as num?)?.toInt() ?? 0;
          final paidUp =
              (d?['contributionPaidUpToCount'] as num?)?.toInt() ?? 0;
          // Kapasitas dari vehicleJumlahPenumpang (Data Kendaraan). Min 1 agar tidak wajib bayar setelah 1 penumpang.
          final rawCap = (d?['vehicleJumlahPenumpang'] as num?)?.toInt();
          final cap = (rawCap != null && rawCap > 0) ? rawCap : 7;
          final threshold = paidUp + (1 * cap);
          final mustPay = kContributionEnabled && (total >= threshold);
          return DriverContributionStatus(
            totalPenumpangServed: total,
            contributionPaidUpToCount: paidUp,
            capacity: cap,
            mustPayContribution: mustPay,
          );
        });
  }

  /// Panggil Cloud Function untuk verifikasi pembayaran dan update contributionPaidUpToCount.
  static Future<Map<String, dynamic>> verifyContributionPayment({
    required String purchaseToken,
    required String orderId,
    String? productId,
    String? packageName,
  }) async {
    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('verifyContributionPayment');
    final result = await callable.call<Map<String, dynamic>>({
      'purchaseToken': purchaseToken,
      'orderId': orderId,
      if (productId != null) 'productId': productId,
      if (packageName != null) 'packageName': packageName,
    });
    return result.data;
  }
}
