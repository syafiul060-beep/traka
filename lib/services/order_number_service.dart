import 'package:cloud_firestore/cloud_firestore.dart';

/// Generator nomor pesanan unik (format TRK-YYYYMMDD-XXXXXX).
/// Menggunakan counter di Firestore agar tidak bentrok dengan pengguna lain.
class OrderNumberService {
  static const String _collectionCounters = 'counters';
  static const String _docOrderNumber = 'order_number';
  static const String _fieldLastSequence = 'lastSequence';
  static const String _prefix = 'TRK';

  /// Generate nomor pesanan unik. Format: TRK-YYYYMMDD-000001, TRK-YYYYMMDD-000002, ...
  /// Memakai transaction agar aman untuk banyak pengguna.
  static Future<String> generateOrderNumber() async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    final ref = FirebaseFirestore.instance
        .collection(_collectionCounters)
        .doc(_docOrderNumber);

    final newSequence = await FirebaseFirestore.instance.runTransaction<int>((
      tx,
    ) async {
      final snap = await tx.get(ref);
      final current = (snap.data()?[_fieldLastSequence] as num?)?.toInt() ?? 0;
      final next = current + 1;
      tx.set(ref, {_fieldLastSequence: next}, SetOptions(merge: true));
      return next;
    });

    return '$_prefix-$dateStr-${newSequence.toString().padLeft(6, '0')}';
  }
}
