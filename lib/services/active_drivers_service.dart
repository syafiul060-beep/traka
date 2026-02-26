import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'directions_service.dart';
import 'rating_service.dart';
import 'route_utils.dart';

/// Data driver dengan rute aktif (untuk penumpang memilih travel).
/// [driverLat], [driverLng]: posisi driver saat ini (untuk map & filter jarak).
/// [maxPassengers], [currentPassengerCount]: untuk warna icon mobil (nanti dari Data Mobil).
class ActiveDriverRoute {
  final String driverUid;
  final String routeJourneyNumber;
  final String routeOriginText;
  final String routeDestText;
  final double routeOriginLat;
  final double routeOriginLng;
  final double routeDestLat;
  final double routeDestLng;

  /// Posisi driver saat ini (dari driver_status).
  final double driverLat;
  final double driverLng;
  final String? driverName;
  final String? driverPhotoUrl;

  /// Kapasitas mobil (dari Data Mobil). Null = belum diisi, icon hijau.
  final int? maxPassengers;

  /// Jenis mobil / merek (dari data driver, users). Contoh: Toyota, Daihatsu.
  final String? vehicleMerek;

  /// Type mobil / model (dari data driver, users). Contoh: Avanza, Xenia.
  final String? vehicleType;

  /// Jumlah penumpang saat ini (dari orders agreed/picked_up). Null = 0.
  final int? currentPassengerCount;

  /// Timestamp terakhir update lokasi driver (dari driver_status.lastUpdated).
  /// Digunakan untuk menentukan apakah driver sedang bergerak.
  final DateTime? lastUpdated;

  /// Driver sudah verifikasi (SIM terverifikasi: driverSIMVerifiedAt atau driverSIMNomorHash ada di users).
  final bool isVerified;

  /// Rata-rata rating driver (1-5) dari order completed. Null jika belum ada rating.
  final double? averageRating;

  /// Jumlah review driver.
  final int reviewCount;

  const ActiveDriverRoute({
    required this.driverUid,
    required this.routeJourneyNumber,
    required this.routeOriginText,
    required this.routeDestText,
    required this.routeOriginLat,
    required this.routeOriginLng,
    required this.routeDestLat,
    required this.routeDestLng,
    required this.driverLat,
    required this.driverLng,
    this.driverName,
    this.driverPhotoUrl,
    this.maxPassengers,
    this.vehicleMerek,
    this.vehicleType,
    this.currentPassengerCount,
    this.lastUpdated,
    this.isVerified = false,
    this.averageRating,
    this.reviewCount = 0,
  });

  /// Sisa kapasitas penumpang (hanya penumpang yang mengurangi; kirim barang tidak).
  /// Null jika maxPassengers belum diisi.
  int? get remainingPassengerCapacity {
    if (maxPassengers == null || maxPassengers! <= 0) return null;
    final current = currentPassengerCount ?? 0;
    final remaining = maxPassengers! - current;
    return remaining < 0 ? 0 : remaining;
  }

  /// True jika driver masih punya kursi untuk penumpang (untuk kategori penumpang).
  bool get hasPassengerCapacity {
    final r = remainingPassengerCapacity;
    return r != null && r > 0;
  }

  /// Apakah driver sedang bergerak berdasarkan waktu update terakhir.
  /// Jika update dalam 30 detik terakhir, dianggap sedang bergerak.
  bool get isMoving {
    if (lastUpdated == null) return false;
    final now = DateTime.now();
    final difference = now.difference(lastUpdated!);
    return difference.inSeconds <= 30; // Update dalam 30 detik = bergerak
  }

  /// Hue untuk icon mobil: hijau = sedikit, kuning = hampir penuh, merah = penuh.
  /// DEPRECATED: Sekarang menggunakan custom icon (car_merah.png / car_hijau.png) berdasarkan status pergerakan.
  double get markerHue {
    if (maxPassengers == null ||
        maxPassengers! <= 0 ||
        currentPassengerCount == null) {
      return BitmapDescriptor.hueGreen;
    }
    final ratio = currentPassengerCount! / maxPassengers!;
    if (ratio >= 1.0) return BitmapDescriptor.hueRed;
    if (ratio >= 0.7) return BitmapDescriptor.hueYellow;
    return BitmapDescriptor.hueGreen;
  }
}

/// Service untuk daftar driver yang sedang siap kerja (ada rute aktif).
/// Dipakai penumpang untuk "Cari travel".
class ActiveDriversService {
  static const String _collectionDriverStatus = 'driver_status';
  static const String _collectionUsers = 'users';
  static const String _collectionVehicleData = 'vehicle_data';
  static const String _statusSiapKerja = 'siap_kerja';

  /// Maksimal usia lastUpdated (jam) agar driver dianggap aktif.
  /// Driver dengan lastUpdated > 6 jam dianggap tidak aktif (HP mati, sinyal putus).
  /// Disesuaikan untuk Kalimantan: jarak jauh, sinyal terbatas.
  static const int maxLastUpdatedHours = 6;

  /// Daftar driver dengan rute aktif (status siap_kerja + ada data rute).
  /// Hanya driver yang lastUpdated dalam 6 jam terakhir (untuk filter HP mati/tidak aktif).
  /// maxPassengers dari vehicle_data; currentPassengerCount dari driver_status.
  static Future<List<ActiveDriverRoute>> getActiveDriverRoutes() async {
    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionDriverStatus)
        .where('status', isEqualTo: _statusSiapKerja)
        .get();

    final list = <ActiveDriverRoute>[];
    for (final doc in snapshot.docs) {
      final d = doc.data();
      final uid = doc.id;
      final status = d['status'] as String?;
      if (status != _statusSiapKerja) continue;
      final originLat = (d['routeOriginLat'] as num?)?.toDouble();
      final originLng = (d['routeOriginLng'] as num?)?.toDouble();
      final destLat = (d['routeDestLat'] as num?)?.toDouble();
      final destLng = (d['routeDestLng'] as num?)?.toDouble();
      final driverLat = (d['latitude'] as num?)?.toDouble();
      final driverLng = (d['longitude'] as num?)?.toDouble();
      final journeyNumber = d['routeJourneyNumber'] as String?;
      final currentPassengerCount = (d['currentPassengerCount'] as num?)
          ?.toInt();
      final lastUpdatedTimestamp = d['lastUpdated'] as Timestamp?;
      DateTime? lastUpdated;
      if (lastUpdatedTimestamp != null) {
        lastUpdated = lastUpdatedTimestamp.toDate();
      }
      // Filter: driver dianggap tidak aktif jika lastUpdated > 6 jam (HP mati, sinyal putus)
      if (lastUpdated == null ||
          DateTime.now().difference(lastUpdated).inHours >= maxLastUpdatedHours) {
        continue;
      }
      if (originLat == null ||
          originLng == null ||
          destLat == null ||
          destLng == null ||
          driverLat == null ||
          driverLng == null ||
          journeyNumber == null ||
          journeyNumber.isEmpty) {
        continue;
      }

      String? driverName;
      String? driverPhotoUrl;
      bool isVerified = false;
      String? vehicleMerek;
      String? vehicleType;
      int? maxPassengers;
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection(_collectionUsers)
            .doc(uid)
            .get();
        final userData = userDoc.data();
        driverName = userData?['displayName'] as String?;
        driverPhotoUrl = userData?['photoUrl'] as String?;
        isVerified =
            userData?['driverSIMVerifiedAt'] != null ||
            userData?['driverSIMNomorHash'] != null;
        // Data kendaraan dari data driver (users): jenis mobil, type mobil, kapasitas penumpang
        vehicleMerek = userData?['vehicleMerek'] as String?;
        vehicleType = userData?['vehicleType'] as String?;
        final jumlahPenumpang = userData?['vehicleJumlahPenumpang'] as num?;
        if (jumlahPenumpang != null) {
          final n = jumlahPenumpang.toInt();
          maxPassengers = n <= 0 ? null : n;
        }
      } catch (_) {}

      // Fallback: kapasitas dari vehicle_data jika belum ada di users
      if (maxPassengers == null) {
        try {
          final vehicleDoc = await FirebaseFirestore.instance
              .collection(_collectionVehicleData)
              .doc(uid)
              .get();
          final vehicleData = vehicleDoc.data();
          if (vehicleData != null &&
              (vehicleData['maxPassengers'] as num?) != null) {
            final n = (vehicleData['maxPassengers'] as num).toInt();
            maxPassengers = n <= 0 ? null : n;
          }
        } catch (_) {}
      }

      list.add(
        ActiveDriverRoute(
          driverUid: uid,
          routeJourneyNumber: journeyNumber,
          routeOriginText: (d['routeOriginText'] as String?) ?? '',
          routeDestText: (d['routeDestText'] as String?) ?? '',
          routeOriginLat: originLat,
          routeOriginLng: originLng,
          routeDestLat: destLat,
          routeDestLng: destLng,
          driverLat: driverLat,
          driverLng: driverLng,
          driverName: driverName,
          driverPhotoUrl: driverPhotoUrl,
          maxPassengers: maxPassengers,
          vehicleMerek: vehicleMerek,
          vehicleType: vehicleType,
          currentPassengerCount: currentPassengerCount,
          lastUpdated: lastUpdated,
          isVerified: isVerified,
        ),
      );
    }
    // Fetch ratings in parallel untuk semua driver
    final ratings = await Future.wait(
      list.map((r) async {
        final avg = await RatingService.getDriverAverageRating(r.driverUid);
        final count = await RatingService.getDriverReviewCount(r.driverUid);
        return (avg, count);
      }),
    );
    return [
      for (var i = 0; i < list.length; i++)
        ActiveDriverRoute(
          driverUid: list[i].driverUid,
          routeJourneyNumber: list[i].routeJourneyNumber,
          routeOriginText: list[i].routeOriginText,
          routeDestText: list[i].routeDestText,
          routeOriginLat: list[i].routeOriginLat,
          routeOriginLng: list[i].routeOriginLng,
          routeDestLat: list[i].routeDestLat,
          routeDestLng: list[i].routeDestLng,
          driverLat: list[i].driverLat,
          driverLng: list[i].driverLng,
          driverName: list[i].driverName,
          driverPhotoUrl: list[i].driverPhotoUrl,
          maxPassengers: list[i].maxPassengers,
          vehicleMerek: list[i].vehicleMerek,
          vehicleType: list[i].vehicleType,
          currentPassengerCount: list[i].currentPassengerCount,
          lastUpdated: list[i].lastUpdated,
          isVerified: list[i].isVerified,
          averageRating: ratings[i].$1,
          reviewCount: ratings[i].$2,
        ),
    ];
  }

  /// Driver yang cocok untuk ditampilkan di map penumpang.
  /// Logika luas (cross-route): pickup dan dropoff boleh di rute alternatif berbeda.
  /// Contoh: driver Batulicin-Banjarmasin (biru), penumpang Satui-Banjarbaru;
  /// Satui di rute biru, Banjarbaru di rute kuning → tetap match.
  /// [passengerOriginLat/Lng]: lokasi awal penumpang (titik penjemputan).
  /// [passengerDestLat/Lng]: tujuan penumpang.
  /// [onlyDriversBeforePassenger]: true = hanya driver yang belum melewati penumpang (default true).
  static Future<List<ActiveDriverRoute>> getActiveDriversForMap({
    double? passengerOriginLat,
    double? passengerOriginLng,
    double? passengerDestLat,
    double? passengerDestLng,
    bool onlyDriversBeforePassenger = true,
  }) async {
    final all = await getActiveDriverRoutes();
    if (all.isEmpty) return [];

    // Jika tidak ada lokasi awal atau tujuan penumpang, kembalikan semua driver
    if (passengerOriginLat == null ||
        passengerOriginLng == null ||
        passengerDestLat == null ||
        passengerDestLng == null) {
      return all;
    }

    final passengerOrigin = LatLng(passengerOriginLat, passengerOriginLng);
    final passengerDest = LatLng(passengerDestLat, passengerDestLng);
    final filtered = <ActiveDriverRoute>[];

    for (final d in all) {
      try {
        final alternativeRoutes = await DirectionsService.getAlternativeRoutes(
          originLat: d.routeOriginLat,
          originLng: d.routeOriginLng,
          destLat: d.routeDestLat,
          destLng: d.routeDestLng,
        );

        if (alternativeRoutes.isEmpty) continue;

        final routePolylines = alternativeRoutes.map((r) => r.points).toList();
        final driverDest = LatLng(d.routeDestLat, d.routeDestLng);
        final driverOrigin = LatLng(d.routeOriginLat, d.routeOriginLng);

        // Cross-route: pickup dan dropoff boleh di rute berbeda
        final pickupNearAny = RouteUtils.isPointNearAnyRoute(
          passengerOrigin,
          routePolylines,
          toleranceMeters: RouteUtils.defaultToleranceMeters,
        );
        final dropoffNearAny = RouteUtils.isPointNearAnyRoute(
          passengerDest,
          routePolylines,
          toleranceMeters: RouteUtils.defaultToleranceMeters,
        );

        if (!pickupNearAny || !dropoffNearAny) continue;

        // Urutan: pickup harus sebelum dropoff (jarak pickup ke tujuan > jarak dropoff ke tujuan)
        if (!RouteUtils.isPickupBeforeDropoffByDistance(
          passengerOrigin,
          passengerDest,
          driverDest,
        )) {
          continue;
        }

        // Driver belum melewati titik penjemputan, ATAU sudah lewat tapi masih dalam 10 km
        if (onlyDriversBeforePassenger) {
          final driverPos = LatLng(d.driverLat, d.driverLng);
          const maxMetersPastPickup = 10000.0; // 10 km - driver yang baru lewat masih ditampilkan
          final pickupRouteIdx = RouteUtils.findRouteIndexWithPoint(
            passengerOrigin,
            routePolylines,
            toleranceMeters: RouteUtils.defaultToleranceMeters,
          );
          bool driverOk = pickupRouteIdx >= 0 &&
              RouteUtils.isDriverBeforePointAlongRoute(
                driverPos,
                passengerOrigin,
                routePolylines[pickupRouteIdx],
                toleranceMeters: RouteUtils.defaultToleranceMeters,
              );
          if (!driverOk) {
            driverOk = RouteUtils.isDriverBeforePickupByDistance(
              driverPos,
              passengerOrigin,
              driverOrigin,
            );
          }
          // Driver sudah lewat pickup tapi masih dalam 10 km → tetap tampilkan
          if (!driverOk) {
            driverOk = RouteUtils.isDriverWithinXMetersPastPickup(
              driverPos,
              passengerOrigin,
              driverOrigin,
              maxMetersPast: maxMetersPastPickup,
            );
          }
          if (!driverOk) continue;
        }

        filtered.add(d);
      } catch (e) {
        if (kDebugMode) debugPrint('ActiveDriversService.getActiveDriversForMap: Error cek rute untuk driver ${d.driverUid}: $e');
      }
    }

    return filtered;
  }
}
