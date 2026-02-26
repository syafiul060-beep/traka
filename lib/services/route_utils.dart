import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Utility functions untuk operasi rute dan polyline.
class RouteUtils {
  /// Toleransi jarak untuk mengecek apakah titik berada di dekat polyline (dalam meter).
  /// Default: 10 km = 10000 meter.
  static const double defaultToleranceMeters = 10000;

  /// Hitung jarak terdekat dari suatu titik ke polyline (dalam meter).
  /// Menggunakan algoritma untuk mencari jarak minimum dari titik ke setiap segmen garis.
  static double distanceToPolyline(LatLng point, List<LatLng> polyline) {
    if (polyline.isEmpty) return double.infinity;
    if (polyline.length == 1) {
      return Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        polyline.first.latitude,
        polyline.first.longitude,
      );
    }

    double minDistance = double.infinity;
    for (int i = 0; i < polyline.length - 1; i++) {
      final p1 = polyline[i];
      final p2 = polyline[i + 1];
      final distance = _distanceToLineSegment(point, p1, p2);
      if (distance < minDistance) {
        minDistance = distance;
      }
    }
    return minDistance;
  }

  /// Hitung jarak dari titik ke segmen garis (dalam meter).
  /// Menggunakan proyeksi ortogonal untuk mencari titik terdekat pada segmen.
  static double _distanceToLineSegment(
    LatLng point,
    LatLng lineStart,
    LatLng lineEnd,
  ) {
    // Vektor dari start ke end
    final dx = lineEnd.longitude - lineStart.longitude;
    final dy = lineEnd.latitude - lineStart.latitude;

    // Jika segmen adalah titik tunggal
    if (dx == 0 && dy == 0) {
      return Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        lineStart.latitude,
        lineStart.longitude,
      );
    }

    // Vektor dari start ke point
    final px = point.longitude - lineStart.longitude;
    final py = point.latitude - lineStart.latitude;

    // Proyeksi skalar
    final t = ((px * dx) + (py * dy)) / ((dx * dx) + (dy * dy));

    // Clamp t ke [0, 1] untuk memastikan titik berada di segmen
    final clampedT = t.clamp(0.0, 1.0);

    // Titik terdekat pada segmen
    final closestLat = lineStart.latitude + clampedT * dy;
    final closestLng = lineStart.longitude + clampedT * dx;

    // Jarak dari point ke titik terdekat
    return Geolocator.distanceBetween(
      point.latitude,
      point.longitude,
      closestLat,
      closestLng,
    );
  }

  /// Cek apakah suatu titik berada di dekat polyline (dalam toleransi tertentu).
  /// [toleranceMeters]: Jarak toleransi dalam meter. Default: 10 km.
  static bool isPointNearPolyline(
    LatLng point,
    List<LatLng> polyline, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    if (polyline.isEmpty) return false;
    final distance = distanceToPolyline(point, polyline);
    return distance <= toleranceMeters;
  }

  /// Cek apakah rute driver melewati lokasi awal dan tujuan penumpang.
  /// Driver ditampilkan jika:
  /// - Rute driver melewati lokasi awal penumpang (dalam toleransi)
  /// - Rute driver melewati lokasi tujuan penumpang (dalam toleransi)
  /// [driverRoutePolyline]: Polyline rute driver (dari origin ke destination).
  /// [passengerOrigin]: Lokasi awal penumpang.
  /// [passengerDest]: Lokasi tujuan penumpang.
  /// [toleranceMeters]: Toleransi jarak dalam meter. Default: 10 km.
  static bool doesRoutePassThrough(
    List<LatLng> driverRoutePolyline,
    LatLng passengerOrigin,
    LatLng passengerDest, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    if (driverRoutePolyline.isEmpty) return false;

    // Cek apakah rute melewati lokasi awal penumpang
    final passesOrigin = isPointNearPolyline(
      passengerOrigin,
      driverRoutePolyline,
      toleranceMeters: toleranceMeters,
    );

    // Cek apakah rute melewati lokasi tujuan penumpang
    final passesDest = isPointNearPolyline(
      passengerDest,
      driverRoutePolyline,
      toleranceMeters: toleranceMeters,
    );

    // Jika rute melewati kedua titik, cek urutan: origin harus sebelum dest
    if (passesOrigin && passesDest) {
      return _isOriginBeforeDest(
        driverRoutePolyline,
        passengerOrigin,
        passengerDest,
        toleranceMeters: toleranceMeters,
      );
    }

    return false;
  }

  /// Cek apakah lokasi awal muncul sebelum lokasi tujuan dalam polyline.
  /// Ini memastikan bahwa rute benar-benar melewati kedua titik dalam urutan yang benar.
  static bool _isOriginBeforeDest(
    List<LatLng> polyline,
    LatLng origin,
    LatLng dest, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    int originIndex = -1;
    int destIndex = -1;

    // Cari indeks terdekat untuk origin dan dest
    double minOriginDist = double.infinity;
    double minDestDist = double.infinity;

    for (int i = 0; i < polyline.length; i++) {
      final point = polyline[i];
      final originDist = Geolocator.distanceBetween(
        origin.latitude,
        origin.longitude,
        point.latitude,
        point.longitude,
      );
      final destDist = Geolocator.distanceBetween(
        dest.latitude,
        dest.longitude,
        point.latitude,
        point.longitude,
      );

      if (originDist < minOriginDist && originDist <= toleranceMeters) {
        minOriginDist = originDist;
        originIndex = i;
      }
      if (destDist < minDestDist && destDist <= toleranceMeters) {
        minDestDist = destDist;
        destIndex = i;
      }
    }

    // Origin harus muncul sebelum dest dalam polyline
    return originIndex >= 0 && destIndex >= 0 && originIndex < destIndex;
  }

  /// Indeks posisi titik sepanjang polyline (titik polyline terdekat dalam toleransi).
  /// Untuk cek "driver belum melewati penumpang": driverIndex < passengerOriginIndex.
  static int getIndexAlongPolyline(
    LatLng point,
    List<LatLng> polyline, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    if (polyline.isEmpty) return -1;
    int bestIndex = -1;
    double minDist = double.infinity;
    for (int i = 0; i < polyline.length; i++) {
      final p = polyline[i];
      final d = Geolocator.distanceBetween(
        point.latitude,
        point.longitude,
        p.latitude,
        p.longitude,
      );
      if (d < minDist && d <= toleranceMeters) {
        minDist = d;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  /// Cek apakah posisi driver belum melewati titik penumpang sepanjang rute.
  static bool isDriverBeforePointAlongRoute(
    LatLng driverPosition,
    LatLng passengerPoint,
    List<LatLng> routePolyline, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    final driverIdx = getIndexAlongPolyline(
      driverPosition,
      routePolyline,
      toleranceMeters: toleranceMeters,
    );
    final passengerIdx = getIndexAlongPolyline(
      passengerPoint,
      routePolyline,
      toleranceMeters: toleranceMeters,
    );
    return driverIdx >= 0 && passengerIdx >= 0 && driverIdx < passengerIdx;
  }

  /// Cek apakah titik dekat dengan salah satu rute dari daftar polyline.
  /// Untuk cross-route matching: pickup dan dropoff boleh di rute berbeda.
  static bool isPointNearAnyRoute(
    LatLng point,
    List<List<LatLng>> routes, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    for (final route in routes) {
      if (isPointNearPolyline(point, route, toleranceMeters: toleranceMeters)) {
        return true;
      }
    }
    return false;
  }

  /// Cek urutan perjalanan: pickup sebelum dropoff berdasarkan jarak ke tujuan driver.
  /// Pickup lebih jauh dari tujuan = driver melewati pickup dulu, baru dropoff.
  static bool isPickupBeforeDropoffByDistance(
    LatLng pickup,
    LatLng dropoff,
    LatLng driverDest,
  ) {
    final distPickupToDest = Geolocator.distanceBetween(
      pickup.latitude,
      pickup.longitude,
      driverDest.latitude,
      driverDest.longitude,
    );
    final distDropoffToDest = Geolocator.distanceBetween(
      dropoff.latitude,
      dropoff.longitude,
      driverDest.latitude,
      driverDest.longitude,
    );
    return distPickupToDest > distDropoffToDest;
  }

  /// Cek apakah posisi driver belum melewati titik penjemputan (berdasarkan jarak dari origin).
  /// Driver lebih dekat ke origin = belum sampai pickup.
  static bool isDriverBeforePickupByDistance(
    LatLng driverPosition,
    LatLng pickup,
    LatLng driverOrigin,
  ) {
    final distDriverToOrigin = Geolocator.distanceBetween(
      driverPosition.latitude,
      driverPosition.longitude,
      driverOrigin.latitude,
      driverOrigin.longitude,
    );
    final distPickupToOrigin = Geolocator.distanceBetween(
      pickup.latitude,
      pickup.longitude,
      driverOrigin.latitude,
      driverOrigin.longitude,
    );
    return distDriverToOrigin < distPickupToOrigin;
  }

  /// Cek apakah driver sudah melewati pickup tapi masih dalam jarak [maxMetersPast] meter.
  /// Untuk menampilkan driver yang baru saja lewat titik penjemputan (masih bisa putar balik/detour).
  static bool isDriverWithinXMetersPastPickup(
    LatLng driverPosition,
    LatLng pickup,
    LatLng driverOrigin, {
    double maxMetersPast = 10000,
  }) {
    final distDriverToOrigin = Geolocator.distanceBetween(
      driverPosition.latitude,
      driverPosition.longitude,
      driverOrigin.latitude,
      driverOrigin.longitude,
    );
    final distPickupToOrigin = Geolocator.distanceBetween(
      pickup.latitude,
      pickup.longitude,
      driverOrigin.latitude,
      driverOrigin.longitude,
    );
    if (distDriverToOrigin <= distPickupToOrigin) return false; // Belum lewat
    final distDriverToPickup = Geolocator.distanceBetween(
      driverPosition.latitude,
      driverPosition.longitude,
      pickup.latitude,
      pickup.longitude,
    );
    return distDriverToPickup <= maxMetersPast;
  }

  /// Cari rute yang melewati titik (untuk cek driver sebelum pickup).
  /// Returns index rute atau -1 jika tidak ada.
  static int findRouteIndexWithPoint(
    LatLng point,
    List<List<LatLng>> routes, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    for (int i = 0; i < routes.length; i++) {
      if (isPointNearPolyline(point, routes[i], toleranceMeters: toleranceMeters)) {
        return i;
      }
    }
    return -1;
  }

  /// Cek apakah posisi driver berada di dekat salah satu rute alternatif.
  /// Digunakan untuk auto-switch rute.
  /// [driverPosition]: Posisi driver saat ini.
  /// [alternativeRoutes]: List rute alternatif (polyline).
  /// [toleranceMeters]: Toleransi jarak dalam meter. Default: 10 km.
  /// Returns: Index rute yang terdekat jika dalam toleransi, atau -1 jika tidak ada.
  static int findNearestRouteIndex(
    LatLng driverPosition,
    List<List<LatLng>> alternativeRoutes, {
    double toleranceMeters = defaultToleranceMeters,
  }) {
    int nearestIndex = -1;
    double minDistance = double.infinity;

    for (int i = 0; i < alternativeRoutes.length; i++) {
      final route = alternativeRoutes[i];
      final distance = distanceToPolyline(driverPosition, route);
      if (distance < minDistance && distance <= toleranceMeters) {
        minDistance = distance;
        nearestIndex = i;
      }
    }

    return nearestIndex;
  }
}
