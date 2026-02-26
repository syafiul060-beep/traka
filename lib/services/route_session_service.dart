import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Satu sesi rute yang sudah diakhiri driver (untuk Riwayat).
class RouteSessionModel {
  final String id;
  final String driverUid;
  final String routeJourneyNumber;
  /// Untuk rute terjadwal: scheduleId agar penumpang di detail bisa difilter per jadwal.
  final String? scheduleId;
  final String routeOriginText;
  final String routeDestText;
  final double? routeOriginLat;
  final double? routeOriginLng;
  final double? routeDestLat;
  final double? routeDestLng;
  final DateTime? routeStartedAt;
  final DateTime endedAt;

  const RouteSessionModel({
    required this.id,
    required this.driverUid,
    required this.routeJourneyNumber,
    this.scheduleId,
    required this.routeOriginText,
    required this.routeDestText,
    this.routeOriginLat,
    this.routeOriginLng,
    this.routeDestLat,
    this.routeDestLng,
    this.routeStartedAt,
    required this.endedAt,
  });

  static RouteSessionModel fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    final ended = d['endedAt'] as Timestamp?;
    final started = d['routeStartedAt'] as Timestamp?;
    return RouteSessionModel(
      id: doc.id,
      driverUid: (d['driverUid'] as String?) ?? '',
      routeJourneyNumber: (d['routeJourneyNumber'] as String?) ?? '',
      scheduleId: d['scheduleId'] as String?,
      routeOriginText: (d['routeOriginText'] as String?) ?? '',
      routeDestText: (d['routeDestText'] as String?) ?? '',
      routeOriginLat: (d['routeOriginLat'] as num?)?.toDouble(),
      routeOriginLng: (d['routeOriginLng'] as num?)?.toDouble(),
      routeDestLat: (d['routeDestLat'] as num?)?.toDouble(),
      routeDestLng: (d['routeDestLng'] as num?)?.toDouble(),
      routeStartedAt: started?.toDate(),
      endedAt: ended?.toDate() ?? DateTime.now(),
    );
  }
}

/// Service untuk sesi rute yang sudah selesai (Riwayat driver).
class RouteSessionService {
  static const String _collectionSessions = 'route_sessions';

  /// Simpan sesi rute saat driver mengakhiri rute (sebelum status di-set tidak_aktif).
  static Future<void> saveCurrentRouteSession({
    required String routeJourneyNumber,
    String? scheduleId,
    required String routeOriginText,
    required String routeDestText,
    double? routeOriginLat,
    double? routeOriginLng,
    double? routeDestLat,
    double? routeDestLng,
    DateTime? routeStartedAt,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection(_collectionSessions).add({
      'driverUid': user.uid,
      'routeJourneyNumber': routeJourneyNumber,
      if (scheduleId != null && scheduleId.isNotEmpty) 'scheduleId': scheduleId,
      'routeOriginText': routeOriginText,
      'routeDestText': routeDestText,
      'routeOriginLat': routeOriginLat,
      'routeOriginLng': routeOriginLng,
      'routeDestLat': routeDestLat,
      'routeDestLng': routeDestLng,
      'routeStartedAt': routeStartedAt != null
          ? Timestamp.fromDate(routeStartedAt)
          : null,
      'endedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream daftar sesi rute driver (urut endedAt terbaru).
  static Stream<List<RouteSessionModel>> streamSessionsForDriver() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection(_collectionSessions)
        .where('driverUid', isEqualTo: user.uid)
        .orderBy('endedAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => RouteSessionModel.fromFirestore(d)).toList(),
        );
  }
}
