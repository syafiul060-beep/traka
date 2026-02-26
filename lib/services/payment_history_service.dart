import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'app_config_service.dart';
import 'lacak_barang_service.dart';

/// Jenis pembayaran via Google Play.
enum PaymentType {
  lacakDriver,
  lacakBarang,
  violation,
}

/// Satu record pembayaran untuk riwayat & struk.
class PaymentRecord {
  final String id;
  final PaymentType type;
  final double amountRupiah;
  final DateTime paidAt;
  final String? orderId;
  final String? orderNumber;
  final String? description;

  const PaymentRecord({
    required this.id,
    required this.type,
    required this.amountRupiah,
    required this.paidAt,
    this.orderId,
    this.orderNumber,
    this.description,
  });

  String get typeLabel {
    switch (type) {
      case PaymentType.lacakDriver:
        return 'Lacak Driver';
      case PaymentType.lacakBarang:
        return 'Lacak Barang';
      case PaymentType.violation:
        return 'Pelanggaran';
    }
  }
}

/// Service untuk riwayat pembayaran penumpang/driver via Google Play.
class PaymentHistoryService {
  static const String _collectionOrders = 'orders';
  static const String _collectionViolationRecords = 'violation_records';

  /// Ambil riwayat pembayaran user (Lacak Driver, Lacak Barang, Pelanggaran).
  /// Diurutkan paidAt descending.
  static Future<List<PaymentRecord>> getPaymentHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final records = <PaymentRecord>[];

    // 1. Lacak Driver: orders dengan passengerTrackDriverPaidAt
    final lacakDriverSnap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('passengerUid', isEqualTo: user.uid)
        .where('passengerTrackDriverPaidAt', isNotEqualTo: null)
        .orderBy('passengerTrackDriverPaidAt', descending: true)
        .limit(50)
        .get();

    final lacakDriverFee = await AppConfigService.getLacakDriverFeeRupiah();

    for (final doc in lacakDriverSnap.docs) {
      final d = doc.data();
      final paidAt = d['passengerTrackDriverPaidAt'] as Timestamp?;
      if (paidAt == null) continue;
      records.add(PaymentRecord(
        id: 'lacak_driver_${doc.id}',
        type: PaymentType.lacakDriver,
        amountRupiah: lacakDriverFee.toDouble(),
        paidAt: paidAt.toDate(),
        orderId: doc.id,
        orderNumber: d['orderNumber'] as String?,
        description: 'Lacak Driver - ${d['orderNumber'] ?? doc.id}',
      ));
    }

    // 2. Lacak Barang: pengirim (passengerUid) dan penerima (receiverUid)
    final lacakBarangAsPengirim = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('orderType', isEqualTo: 'kirim_barang')
        .where('passengerUid', isEqualTo: user.uid)
        .where('passengerLacakBarangPaidAt', isNotEqualTo: null)
        .get();
    final lacakBarangAsPenerima = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('orderType', isEqualTo: 'kirim_barang')
        .where('receiverUid', isEqualTo: user.uid)
        .where('receiverLacakBarangPaidAt', isNotEqualTo: null)
        .get();

    for (final doc in lacakBarangAsPengirim.docs) {
      final d = doc.data();
      final orderId = doc.id;
      final orderNumber = d['orderNumber'] as String?;
      final pengirimPaidAt = d['passengerLacakBarangPaidAt'] as Timestamp?;
      if (pengirimPaidAt == null) continue;
      final fee = await _getLacakBarangFeeForOrder(d);
      records.add(PaymentRecord(
        id: 'lacak_barang_pengirim_$orderId',
        type: PaymentType.lacakBarang,
        amountRupiah: fee,
        paidAt: pengirimPaidAt.toDate(),
        orderId: orderId,
        orderNumber: orderNumber,
        description: 'Lacak Barang (Pengirim) - ${orderNumber ?? orderId}',
      ));
    }
    for (final doc in lacakBarangAsPenerima.docs) {
      final d = doc.data();
      final orderId = doc.id;
      final orderNumber = d['orderNumber'] as String?;
      final penerimaPaidAt = d['receiverLacakBarangPaidAt'] as Timestamp?;
      if (penerimaPaidAt == null) continue;
      final fee = await _getLacakBarangFeeForOrder(d);
      records.add(PaymentRecord(
        id: 'lacak_barang_penerima_$orderId',
        type: PaymentType.lacakBarang,
        amountRupiah: fee,
        paidAt: penerimaPaidAt.toDate(),
        orderId: orderId,
        orderNumber: orderNumber,
        description: 'Lacak Barang (Penerima) - ${orderNumber ?? orderId}',
      ));
    }

    // 3. Pelanggaran: violation_records dengan paidAt != null
    final violationSnap = await FirebaseFirestore.instance
        .collection(_collectionViolationRecords)
        .where('userId', isEqualTo: user.uid)
        .where('type', isEqualTo: 'passenger')
        .get();

    for (final doc in violationSnap.docs) {
      final d = doc.data();
      final paidAt = d['paidAt'] as Timestamp?;
      if (paidAt == null) continue;
      final amount = (d['amount'] as num?)?.toDouble() ?? 5000.0;
      records.add(PaymentRecord(
        id: 'violation_${doc.id}',
        type: PaymentType.violation,
        amountRupiah: amount,
        paidAt: paidAt.toDate(),
        orderId: d['orderId'] as String?,
        description: 'Pelanggaran - ${d['orderId'] ?? doc.id}',
      ));
    }

    // Urutkan semua berdasarkan paidAt descending
    records.sort((a, b) => b.paidAt.compareTo(a.paidAt));
    return records.take(100).toList();
  }

  static Future<double> _getLacakBarangFeeForOrder(
      Map<String, dynamic> orderData) async {
    try {
      final pickLat = (orderData['pickupLat'] ?? orderData['passengerLat'])
          as num?;
      final pickLng = (orderData['pickupLng'] ?? orderData['passengerLng'])
          as num?;
      final recvLat = orderData['receiverLat'] as num?;
      final recvLng = orderData['receiverLng'] as num?;
      if (pickLat != null &&
          pickLng != null &&
          recvLat != null &&
          recvLng != null) {
        final (_, fee) = await LacakBarangService.getTierAndFee(
          originLat: pickLat.toDouble(),
          originLng: pickLng.toDouble(),
          destLat: recvLat.toDouble(),
          destLng: recvLng.toDouble(),
        );
        return fee.toDouble();
      }
    } catch (_) {}
    return 7500.0; // default
  }
}
