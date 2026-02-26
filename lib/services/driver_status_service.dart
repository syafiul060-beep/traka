import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Data rute kerja aktif dari Firestore (untuk restore saat app dibuka lagi).
class DriverActiveRouteData {
  final double originLat;
  final double originLng;
  final double destLat;
  final double destLng;
  final String originText;
  final String destText;
  final String? routeJourneyNumber;
  final DateTime? routeStartedAt;
  final int? estimatedDurationSeconds;
  final bool routeFromJadwal;

  /// Index rute alternatif yang dipilih (0, 1, 2, ...).
  final int routeSelectedIndex;

  /// ID jadwal yang sedang dijalankan (pesanan terjadwal). Hanya terisi jika routeFromJadwal true.
  final String? scheduleId;

  const DriverActiveRouteData({
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    required this.originText,
    required this.destText,
    this.routeJourneyNumber,
    this.routeStartedAt,
    this.estimatedDurationSeconds,
    this.routeFromJadwal = false,
    this.routeSelectedIndex = 0,
    this.scheduleId,
  });
}

/// Service untuk update status dan lokasi driver ke Firestore.
/// Driver yang aktif (status "siap_kerja" dengan rute) akan terlihat oleh penumpang yang mencari travel.
class DriverStatusService {
  static const String _collectionDriverStatus = 'driver_status';

  /// Status driver: "siap_kerja" = sedang kerja (ada rute), "tidak_aktif" = tidak kerja.
  static const String statusSiapKerja = 'siap_kerja';
  static const String statusTidakAktif = 'tidak_aktif';

  /// Jarak minimal perpindahan (meter) untuk update lokasi otomatis.
  /// 2 km: hemat Firestore writes & baterai, tetap cukup untuk tracking.
  static const double minDistanceToUpdateMeters = 2000; // 2 km

  /// Interval waktu maksimal (menit) untuk update lokasi paksa (meskipun tidak pindah jauh).
  static const int maxMinutesForceUpdate = 15; // 15 menit

  /// Update status driver ke Firestore.
  /// [status]: "siap_kerja" atau "tidak_aktif"
  /// [position]: posisi driver saat ini (lat, lng)
  /// [routeOrigin]: titik awal rute (jika ada)
  /// [routeDestination]: titik tujuan rute (jika ada)
  /// [routeOriginText]: teks lokasi awal rute
  /// [routeDestinationText]: teks lokasi tujuan rute
  /// [routeJourneyNumber]: nomor rute perjalanan (unik, terisi otomatis)
  /// [routeStartedAt]: waktu mulai rute (tanggal dan hari)
  /// [estimatedDurationSeconds]: estimasi waktu perjalanan (detik), untuk auto-end
  /// [currentPassengerCount]: jumlah penumpang agreed/picked_up untuk rute ini (untuk warna icon mobil)
  /// [routeSelectedIndex]: index rute alternatif yang dipilih (0, 1, 2, ...)
  /// [scheduleId]: ID jadwal yang dijalankan (untuk pesanan terjadwal); dipakai saat routeFromJadwal true.
  static Future<void> updateDriverStatus({
    required String status,
    required Position position,
    LatLng? routeOrigin,
    LatLng? routeDestination,
    String? routeOriginText,
    String? routeDestinationText,
    String? routeJourneyNumber,
    DateTime? routeStartedAt,
    int? estimatedDurationSeconds,
    int? currentPassengerCount,
    bool routeFromJadwal = false,
    int routeSelectedIndex = 0,
    String? scheduleId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final data = <String, dynamic>{
      'uid': user.uid,
      'status': status,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'lastUpdated': FieldValue.serverTimestamp(),
    };

    if (currentPassengerCount != null) {
      data['currentPassengerCount'] = currentPassengerCount;
    }

    // Jika driver siap kerja (ada rute), simpan info rute + nomor rute perjalanan
    if (status == statusSiapKerja &&
        routeOrigin != null &&
        routeDestination != null) {
      data['routeOriginLat'] = routeOrigin.latitude;
      data['routeOriginLng'] = routeOrigin.longitude;
      data['routeDestLat'] = routeDestination.latitude;
      data['routeDestLng'] = routeDestination.longitude;
      data['routeOriginText'] = routeOriginText ?? '';
      data['routeDestText'] = routeDestinationText ?? '';
      data['routeFromJadwal'] = routeFromJadwal;
      data['routeSelectedIndex'] = routeSelectedIndex >= 0
          ? routeSelectedIndex
          : 0;
      if (routeJourneyNumber != null)
        data['routeJourneyNumber'] = routeJourneyNumber;
      if (scheduleId != null && scheduleId.isNotEmpty)
        data['scheduleId'] = scheduleId;
      if (routeStartedAt != null)
        data['routeStartedAt'] = Timestamp.fromDate(routeStartedAt);
      if (estimatedDurationSeconds != null)
        data['estimatedDurationSeconds'] = estimatedDurationSeconds;
    } else {
      // Jika tidak aktif, hapus info rute
      data['routeOriginLat'] = null;
      data['routeOriginLng'] = null;
      data['routeDestLat'] = null;
      data['routeDestLng'] = null;
      data['routeOriginText'] = null;
      data['routeDestText'] = null;
      data['routeJourneyNumber'] = null;
      data['routeStartedAt'] = null;
      data['estimatedDurationSeconds'] = null;
      data['currentPassengerCount'] = null;
      data['routeFromJadwal'] = null;
      data['routeSelectedIndex'] = null;
      data['scheduleId'] = null;
    }

    await FirebaseFirestore.instance
        .collection(_collectionDriverStatus)
        .doc(user.uid)
        .set(data, SetOptions(merge: true));
  }

  /// Update hanya currentPassengerCount (dipanggil saat daftar pesanan berubah).
  static Future<void> updateCurrentPassengerCount(int count) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance
        .collection(_collectionDriverStatus)
        .doc(user.uid)
        .set({'currentPassengerCount': count}, SetOptions(merge: true));
  }

  /// Cek apakah perlu update lokasi berdasarkan jarak dan waktu.
  /// Mengembalikan true jika harus update (pindah >= 2 km atau sudah >= 15 menit sejak update terakhir).
  static bool shouldUpdateLocation({
    required Position currentPosition,
    Position? lastUpdatedPosition,
    DateTime? lastUpdatedTime,
  }) {
    // Jika belum pernah update, harus update
    if (lastUpdatedPosition == null || lastUpdatedTime == null) {
      return true;
    }

    // Cek jarak perpindahan
    final distance = Geolocator.distanceBetween(
      lastUpdatedPosition.latitude,
      lastUpdatedPosition.longitude,
      currentPosition.latitude,
      currentPosition.longitude,
    );

    // Jika pindah >= 2 km, update
    if (distance >= minDistanceToUpdateMeters) {
      return true;
    }

    // Cek waktu sejak update terakhir
    final minutesSinceLastUpdate = DateTime.now()
        .difference(lastUpdatedTime)
        .inMinutes;

    // Jika sudah >= 15 menit, update paksa (meskipun tidak pindah jauh)
    if (minutesSinceLastUpdate >= maxMinutesForceUpdate) {
      return true;
    }

    return false;
  }

  /// Hapus status driver (ketika logout atau selesai bekerja).
  static Future<void> removeDriverStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection(_collectionDriverStatus)
        .doc(user.uid)
        .delete();
  }

  /// Ambil rute kerja aktif driver dari Firestore (jika status siap_kerja + ada data rute).
  /// Dipanggil saat app dibuka untuk restore rute yang masih aktif.
  static Future<DriverActiveRouteData?> getActiveRouteFromFirestore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final doc = await FirebaseFirestore.instance
        .collection(_collectionDriverStatus)
        .doc(user.uid)
        .get();

    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;

    final status = data['status'] as String?;
    if (status != statusSiapKerja) return null;

    final originLat = data['routeOriginLat'] as num?;
    final originLng = data['routeOriginLng'] as num?;
    final destLat = data['routeDestLat'] as num?;
    final destLng = data['routeDestLng'] as num?;
    if (originLat == null ||
        originLng == null ||
        destLat == null ||
        destLng == null) {
      return null;
    }

    final startedAt = data['routeStartedAt'] as Timestamp?;
    final estSec = data['estimatedDurationSeconds'] as num?;
    final fromJadwal = data['routeFromJadwal'] as bool?;
    final selectedIndex = data['routeSelectedIndex'] as num?;
    final scheduleId = data['scheduleId'] as String?;

    return DriverActiveRouteData(
      originLat: originLat.toDouble(),
      originLng: originLng.toDouble(),
      destLat: destLat.toDouble(),
      destLng: destLng.toDouble(),
      originText: (data['routeOriginText'] as String?) ?? '',
      destText: (data['routeDestText'] as String?) ?? '',
      routeJourneyNumber: data['routeJourneyNumber'] as String?,
      routeStartedAt: startedAt?.toDate(),
      estimatedDurationSeconds: estSec?.toInt(),
      routeFromJadwal: fromJadwal ?? false,
      routeSelectedIndex: selectedIndex != null && selectedIndex.toInt() >= 0
          ? selectedIndex.toInt()
          : 0,
      scheduleId: scheduleId,
    );
  }

  /// Stream posisi driver (lat, lng) dari driver_status. Untuk "Cek lokasi driver" oleh pengirim/penerima.
  static Stream<(double, double)?> streamDriverPosition(String driverUid) {
    return FirebaseFirestore.instance
        .collection(_collectionDriverStatus)
        .doc(driverUid)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      final d = doc.data();
      if (d == null) return null;
      final lat = (d['latitude'] as num?)?.toDouble();
      final lng = (d['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return (lat, lng);
    });
  }
}
