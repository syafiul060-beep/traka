import 'package:cloud_firestore/cloud_firestore.dart';

/// Model transfer penumpang dari driver pertama ke driver kedua (Oper Driver).
class DriverTransferModel {
  final String id;
  final String orderId;
  final String fromDriverUid;
  final String toDriverUid;
  final String status; // pending | scanned | completed | cancelled
  final DateTime? createdAt;
  final DateTime? scannedAt;
  final double? transferLat;
  final double? transferLng;
  final double? toDriverStartLat;
  final double? toDriverStartLng;

  const DriverTransferModel({
    required this.id,
    required this.orderId,
    required this.fromDriverUid,
    required this.toDriverUid,
    required this.status,
    this.createdAt,
    this.scannedAt,
    this.transferLat,
    this.transferLng,
    this.toDriverStartLat,
    this.toDriverStartLng,
  });

  factory DriverTransferModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return DriverTransferModel(
      id: doc.id,
      orderId: (d['orderId'] as String?) ?? '',
      fromDriverUid: (d['fromDriverUid'] as String?) ?? '',
      toDriverUid: (d['toDriverUid'] as String?) ?? '',
      status: (d['status'] as String?) ?? 'pending',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      scannedAt: (d['scannedAt'] as Timestamp?)?.toDate(),
      transferLat: (d['transferLat'] as num?)?.toDouble(),
      transferLng: (d['transferLng'] as num?)?.toDouble(),
      toDriverStartLat: (d['toDriverStartLat'] as num?)?.toDouble(),
      toDriverStartLng: (d['toDriverStartLng'] as num?)?.toDouble(),
    );
  }

  static const String statusPending = 'pending';
  static const String statusScanned = 'scanned';
  static const String statusCompleted = 'completed';
  static const String statusCancelled = 'cancelled';

  bool get isPending => status == statusPending;
  bool get isScanned => status == statusScanned;
  bool get isCompleted => status == statusCompleted;
}
