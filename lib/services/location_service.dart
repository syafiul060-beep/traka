import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Kode error khusus (mis. fake GPS terdeteksi).
const String kErrorCodeFakeGps = 'fake_gps';

/// Flag untuk disable fake GPS detection (untuk testing).
/// Set ke `true` untuk mematikan deteksi fake GPS sementara.
const bool kDisableFakeGpsCheck = false;

/// Hasil pengecekan lokasi untuk pendaftaran driver.
class DriverLocationResult {
  /// true jika lokasi di Indonesia.
  final bool isInIndonesia;

  /// Nama negara dari reverse geocoding.
  final String? country;

  /// Nama provinsi/region (administrative area).
  final String? region;

  /// Nama kabupaten/kota (subAdministrativeArea). Untuk filter admin per kabupaten.
  final String? kabupaten;

  /// Latitude.
  final double? latitude;

  /// Longitude.
  final double? longitude;

  /// Pesan error jika gagal (permission, timeout, dll).
  final String? errorMessage;

  /// Kode error (mis. [kErrorCodeFakeGps] untuk lokasi palsu).
  final String? errorCode;

  const DriverLocationResult({
    required this.isInIndonesia,
    this.country,
    this.region,
    this.kabupaten,
    this.latitude,
    this.longitude,
    this.errorMessage,
    this.errorCode,
  });

  static DriverLocationResult error(String message, {String? errorCode}) {
    return DriverLocationResult(
      isInIndonesia: false,
      errorMessage: message,
      errorCode: errorCode,
    );
  }

  /// true jika error karena Fake GPS / lokasi palsu terdeteksi.
  bool get isFakeGpsDetected => errorCode == kErrorCodeFakeGps;
}

/// Hasil ambil posisi dengan cek fake GPS. Dipakai untuk flow kritis (tracking driver, lokasi penumpang).
class PositionWithMockCheckResult {
  final Position? position;
  final String? errorCode;
  final String? errorMessage;

  const PositionWithMockCheckResult({
    this.position,
    this.errorCode,
    this.errorMessage,
  });

  bool get isFakeGpsDetected => errorCode == kErrorCodeFakeGps;
}

/// Service untuk izin lokasi, ambil koordinat, dan reverse geocoding.
/// Digunakan saat pendaftaran driver untuk validasi lokasi di Indonesia.
class LocationService {
  /// Minta izin lokasi dan buka pengaturan jika ditolak permanent.
  /// Mengembalikan true jika izin diberikan, false jika user tolak atau service GPS mati.
  /// Loop terus sampai user kasih izin atau keluar dari halaman.
  static Future<bool> requestPermissionPersistent(BuildContext context) async {
    while (true) {
      // Cek apakah GPS/Location service aktif
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // GPS mati, tampilkan dialog minta user nyalakan GPS
        final openSettings = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('GPS Tidak Aktif'),
            content: const Text(
              'Aplikasi Traka memerlukan GPS untuk pendaftaran driver. '
              'Silakan aktifkan GPS/Lokasi di pengaturan perangkat Anda.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Kembali'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Buka Pengaturan'),
              ),
            ],
          ),
        );

        if (openSettings == true) {
          await Geolocator.openLocationSettings();
          // Tunggu sebentar lalu cek lagi
          await Future.delayed(const Duration(seconds: 1));
          continue;
        } else {
          // User pilih kembali
          return false;
        }
      }

      // GPS aktif, cek permission
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.deniedForever) {
        // Izin ditolak permanent, harus buka app settings
        final openSettings = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Lokasi Diperlukan'),
            content: const Text(
              'Aplikasi Traka memerlukan izin lokasi untuk pendaftaran driver. '
              'Silakan aktifkan izin lokasi di pengaturan aplikasi.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Kembali'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Buka Pengaturan'),
              ),
            ],
          ),
        );

        if (openSettings == true) {
          await Geolocator.openAppSettings();
          // Tunggu sebentar lalu cek lagi
          await Future.delayed(const Duration(seconds: 1));
          continue;
        } else {
          return false;
        }
      }

      if (permission == LocationPermission.denied) {
        // Izin belum diberikan, request
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          // User tolak, tanya lagi
          final retry = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Izin Lokasi Diperlukan'),
              content: const Text(
                'Aplikasi Traka memerlukan izin lokasi untuk pendaftaran driver. '
                'Tanpa izin lokasi, Anda tidak dapat mendaftar sebagai driver.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Kembali'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Coba Lagi'),
                ),
              ],
            ),
          );

          if (retry == true) {
            continue;
          } else {
            return false;
          }
        }

        if (permission == LocationPermission.deniedForever) {
          // User pilih "Don't ask again"
          continue; // Akan masuk ke blok deniedForever di loop berikutnya
        }
      }

      // Izin diberikan (whileInUse atau always)
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        return true;
      }
    }
  }

  /// Cek dan minta izin lokasi.
  /// Mengembalikan true jika izin diberikan (atau sudah granted).
  static Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      return false;
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Ambil posisi dari cache (lastKnown) jika ada – cepat untuk tampil dulu di map.
  /// Kembalikan null jika tidak ada cache. Panggil getCurrentPosition() nanti untuk akurasi.
  static Future<Position?> getCachedPosition() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// Ambil posisi saat ini (koordinat).
  /// [forceRefresh]: jika true, paksa ambil lokasi baru tanpa cache.
  /// [forTracking]: jika true, gunakan medium accuracy (hemat baterai untuk update lokasi berkala).
  static Future<Position?> getCurrentPosition({
    bool forceRefresh = false,
    bool forTracking = false,
  }) async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return null;

    try {
      // Pastikan GPS aktif sebelum mengambil lokasi
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      final accuracy = forTracking ? LocationAccuracy.medium : LocationAccuracy.high;
      final timeLimit = forceRefresh ? 30 : 20;

      // Jika forceRefresh, JANGAN gunakan lastKnownPosition sebagai fallback
      if (forceRefresh) {
        return await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: accuracy,
            distanceFilter: 0,
            timeLimit: Duration(seconds: timeLimit),
          ),
          forceAndroidLocationManager: false,
        );
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: accuracy,
          distanceFilter: 0,
          timeLimit: Duration(seconds: timeLimit),
        ),
        forceAndroidLocationManager: false,
      );
    } catch (e) {
      // Jika forceRefresh dan error, jangan gunakan lastKnownPosition
      if (forceRefresh) {
        return null;
      }
      // Jika tidak forceRefresh, coba gunakan lastKnownPosition sebagai fallback
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  static const MethodChannel _channel = MethodChannel('traka/location');

  /// Ambil posisi dengan cek fake GPS. Untuk flow kritis: tracking driver, update lokasi penumpang.
  /// Di Android pakai native mock check; di iOS mock detection terbatas.
  static Future<PositionWithMockCheckResult> getCurrentPositionWithMockCheck({
    bool forceRefresh = false,
    bool forTracking = false,
  }) async {
    final hasPermission = await requestPermission();
    if (!hasPermission) {
      return const PositionWithMockCheckResult(
        errorMessage: 'Izin lokasi tidak diberikan.',
      );
    }

    if (Platform.isAndroid) {
      try {
        final dynamic raw = await _channel.invokeMethod(
          'getLocationWithMockCheck',
        );
        if (raw is! Map) {
          return const PositionWithMockCheckResult(
            errorMessage:
                'Tidak dapat memperoleh lokasi. Pastikan izin lokasi diaktifkan dan GPS menyala.',
          );
        }
        final map = Map<String, dynamic>.from(raw);
        final isMock = map['isMock'] as bool? ?? false;
        if (!kDisableFakeGpsCheck && isMock) {
          return PositionWithMockCheckResult(
            errorCode: kErrorCodeFakeGps,
            errorMessage: 'Fake GPS terdeteksi. Nonaktifkan aplikasi lokasi palsu.',
          );
        }
        final lat = (map['latitude'] as num?)?.toDouble();
        final lng = (map['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) {
          return const PositionWithMockCheckResult(
            errorMessage:
                'Tidak dapat memperoleh koordinat. Pastikan GPS menyala.',
          );
        }
        return PositionWithMockCheckResult(
          position: Position(
            latitude: lat,
            longitude: lng,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          ),
        );
      } on PlatformException catch (e) {
        if (e.code == 'PERMISSION_DENIED' ||
            e.code == 'TIMEOUT' ||
            e.code == 'NULL_LOCATION') {
          return const PositionWithMockCheckResult(
            errorMessage:
                'Tidak dapat memperoleh lokasi. Pastikan izin lokasi diaktifkan dan GPS menyala.',
          );
        }
        return PositionWithMockCheckResult(
          errorMessage: 'Gagal memeriksa lokasi: ${e.message}',
        );
      }
    }

    // iOS / platform lain: pakai geolocator (mock detection terbatas)
    final position = await getCurrentPosition(
      forceRefresh: forceRefresh,
      forTracking: forTracking,
    );
    if (position == null) {
      return const PositionWithMockCheckResult(
        errorMessage:
            'Tidak dapat memperoleh lokasi. Pastikan izin lokasi diaktifkan dan GPS menyala.',
      );
    }
    return PositionWithMockCheckResult(position: position);
  }

  /// Di Android: ambil lokasi via native dan cek mock; di platform lain pakai geolocator.
  static Future<DriverLocationResult> getDriverLocationResult() async {
    if (Platform.isAndroid) {
      try {
        final dynamic raw = await _channel.invokeMethod(
          'getLocationWithMockCheck',
        );
        if (raw is! Map) {
          return DriverLocationResult.error(
            'Tidak dapat memperoleh lokasi. Pastikan izin lokasi diaktifkan dan GPS menyala.',
          );
        }
        final map = Map<String, dynamic>.from(raw);
        final isMock = map['isMock'] as bool? ?? false;
        // Skip fake GPS check jika flag disable diaktifkan (untuk testing)
        if (!kDisableFakeGpsCheck && isMock) {
          return DriverLocationResult.error(
            'Fake GPS terdeteksi.',
            errorCode: kErrorCodeFakeGps,
          );
        }
        final lat = (map['latitude'] as num?)?.toDouble();
        final lng = (map['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) {
          return DriverLocationResult.error(
            'Tidak dapat memperoleh koordinat. Pastikan GPS menyala.',
          );
        }
        return await _reverseGeocodeAndCheckIndonesia(lat, lng);
      } on PlatformException catch (e) {
        if (e.code == 'PERMISSION_DENIED' ||
            e.code == 'TIMEOUT' ||
            e.code == 'NULL_LOCATION') {
          return DriverLocationResult.error(
            'Tidak dapat memperoleh lokasi. Pastikan izin lokasi diaktifkan dan GPS menyala.',
          );
        }
        return DriverLocationResult.error(
          'Gagal memeriksa lokasi: ${e.message}',
        );
      }
    }

    // iOS / platform lain: pakai geolocator (mock detection terbatas di iOS)
    final position = await getCurrentPosition();
    if (position == null) {
      return DriverLocationResult.error(
        'Tidak dapat memperoleh lokasi. Pastikan izin lokasi diaktifkan dan GPS menyala.',
      );
    }
    return await _reverseGeocodeAndCheckIndonesia(
      position.latitude,
      position.longitude,
    );
  }

  static Future<DriverLocationResult> _reverseGeocodeAndCheckIndonesia(
    double latitude,
    double longitude,
  ) async {
    try {
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) {
        return DriverLocationResult(
          isInIndonesia: false,
          latitude: latitude,
          longitude: longitude,
          errorMessage: 'Tidak dapat menentukan alamat dari koordinat.',
        );
      }

      final place = placemarks.first;
      final country = place.country ?? '';
      final provinsi = place.administrativeArea ?? '';
      final kabupaten = place.subAdministrativeArea ?? '';
      final region = provinsi.isNotEmpty ? provinsi : kabupaten;

      const indonesiaNames = ['Indonesia', 'ID', 'Republic of Indonesia'];
      final isInIndonesia = indonesiaNames.any(
        (name) => country.toLowerCase().contains(name.toLowerCase()),
      );

      return DriverLocationResult(
        isInIndonesia: isInIndonesia,
        country: country.isNotEmpty ? country : null,
        region: region.isNotEmpty ? region : null,
        kabupaten: kabupaten.isNotEmpty ? kabupaten : null,
        latitude: latitude,
        longitude: longitude,
      );
    } catch (e) {
      return DriverLocationResult.error('Gagal memeriksa lokasi: $e');
    }
  }
}
