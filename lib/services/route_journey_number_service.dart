import 'package:cloud_firestore/cloud_firestore.dart';

/// Generator nomor rute perjalanan unik (format RUTE-YYYYMMDD-XXXXXX).
/// Unik antar driver, terisi otomatis dengan tanggal dan hari.
class RouteJourneyNumberService {
  static const String _collectionCounters = 'counters';
  static const String _docRouteJourney = 'route_journey_number';
  static const String _fieldLastSequence = 'lastSequence';
  static const String _prefix = 'RUTE';

  static final List<String> _hari = [
    'Minggu',
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
  ];

  /// Generate nomor rute perjalanan unik. Format: RUTE-YYYYMMDD-000001, ...
  static Future<String> generateRouteJourneyNumber() async {
    final now = DateTime.now();
    final dateStr =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    final ref = FirebaseFirestore.instance
        .collection(_collectionCounters)
        .doc(_docRouteJourney);

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

  /// Nama hari dari tanggal (untuk ditampilkan bersama nomor rute).
  static String getDayName(DateTime date) {
    return _hari[date.weekday % 7];
  }
}
