import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:geolocator/geolocator.dart';

/// Service untuk mengelola semua permission yang diperlukan aplikasi.
/// Jika user tidak memberikan izin, akan terus meminta sampai diberikan.
class PermissionService {
  /// Request izin minimal untuk masuk ke home (lokasi + device ID).
  /// Kamera & notifikasi diminta nanti saat dibutuhkan.
  static Future<bool> requestEssentialForHome(BuildContext context) async {
    bool allGranted = false;
    while (!allGranted) {
      final locationGranted = await requestLocationPermission(context);
      final phoneStateGranted = await requestPhoneStatePermission(context);
      allGranted = locationGranted && phoneStateGranted;
      if (!allGranted) {
        final shouldContinue = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Diperlukan'),
            content: const Text(
              'Aplikasi memerlukan izin lokasi dan device ID untuk masuk. '
              'Lokasi untuk peta, device ID untuk keamanan akun.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Tutup'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Berikan Izin'),
              ),
            ],
          ),
        );
        if (shouldContinue != true) return false;
        if (!locationGranted || !phoneStateGranted) {
          final open = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Buka Pengaturan'),
              content: const Text(
                'Buka pengaturan aplikasi dan berikan izin yang diperlukan.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Buka Pengaturan'),
                ),
              ],
            ),
          );
          if (open == true) {
            await ph.openAppSettings();
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }
    }
    return true;
  }

  /// Request semua permission yang diperlukan aplikasi.
  /// Akan terus meminta sampai semua permission diberikan.
  static Future<bool> requestAllPermissions(BuildContext context) async {
    bool allGranted = false;

    while (!allGranted) {
      // Request permission satu per satu
      final locationGranted = await requestLocationPermission(context);
      final phoneStateGranted = await requestPhoneStatePermission(context);
      final cameraGranted = await requestCameraPermission(context);
      final notificationGranted = await requestNotificationPermission(context);

      allGranted =
          locationGranted &&
          phoneStateGranted &&
          cameraGranted &&
          notificationGranted;

      if (!allGranted) {
        // Jika ada permission yang belum diberikan, tampilkan dialog
        final shouldContinue = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Diperlukan'),
            content: const Text(
              'Aplikasi Traka memerlukan beberapa izin untuk berfungsi dengan baik:\n\n'
              '• Lokasi: untuk menemukan driver dan menentukan rute\n'
              '• Device ID: untuk keamanan akun\n'
              '• Kamera: untuk verifikasi wajah\n'
              '• Notifikasi: untuk menerima pesan dan update\n\n'
              'Tanpa izin ini, aplikasi tidak dapat berfungsi dengan baik.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Tutup Aplikasi'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Berikan Izin'),
              ),
            ],
          ),
        );

        if (shouldContinue != true) {
          // User memilih tutup aplikasi
          return false;
        }

        // Buka pengaturan jika ada permission yang ditolak permanent
        if (!locationGranted ||
            !phoneStateGranted ||
            !cameraGranted ||
            !notificationGranted) {
          final openSettings = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Buka Pengaturan'),
              content: const Text(
                'Beberapa izin diperlukan. Silakan buka pengaturan aplikasi '
                'dan berikan semua izin yang diperlukan.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Buka Pengaturan'),
                ),
              ],
            ),
          );

          if (openSettings == true) {
            await ph.openAppSettings();
            // Tunggu sebentar lalu cek lagi
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }
    }

    return true;
  }

  /// Request permission lokasi dengan loop sampai diberikan.
  static Future<bool> requestLocationPermission(BuildContext context) async {
    while (true) {
      // Cek apakah GPS aktif
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        final openSettings = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('GPS Tidak Aktif'),
            content: const Text(
              'Aplikasi Traka memerlukan GPS untuk berfungsi. '
              'Silakan aktifkan GPS/Lokasi di pengaturan perangkat Anda.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
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
          await Future.delayed(const Duration(seconds: 1));
          continue;
        } else {
          return false;
        }
      }

      // Cek permission lokasi
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.deniedForever) {
        final openSettings = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Lokasi Diperlukan'),
            content: const Text(
              'Izin lokasi diperlukan untuk aplikasi Traka. '
              'Silakan buka pengaturan aplikasi dan berikan izin lokasi.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Buka Pengaturan'),
              ),
            ],
          ),
        );

        if (openSettings == true) {
          await ph.openAppSettings();
          await Future.delayed(const Duration(seconds: 1));
          continue;
        } else {
          return false;
        }
      }

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // User tolak, tanya lagi
          final retry = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Izin Lokasi Diperlukan'),
              content: const Text(
                'Aplikasi Traka memerlukan izin lokasi untuk berfungsi. '
                'Tanpa izin lokasi, aplikasi tidak dapat digunakan.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Berikan Izin'),
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
      }

      // Izin diberikan
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        return true;
      }
    }
  }

  /// Request permission READ_PHONE_STATE untuk membaca device ID.
  static Future<bool> requestPhoneStatePermission(BuildContext context) async {
    while (true) {
      final status = await ph.Permission.phone.status;

      if (status.isGranted) {
        return true;
      }

      if (status.isPermanentlyDenied) {
        final openSettings = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Device ID Diperlukan'),
            content: const Text(
              'Izin untuk membaca Device ID diperlukan untuk keamanan akun. '
              'Silakan buka pengaturan aplikasi dan berikan izin.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Buka Pengaturan'),
              ),
            ],
          ),
        );

        if (openSettings == true) {
          await ph.openAppSettings();
          await Future.delayed(const Duration(seconds: 1));
          continue;
        } else {
          return false;
        }
      }

      // Request permission
      final result = await ph.Permission.phone.request();

      if (result.isGranted) {
        return true;
      }

      if (result.isDenied) {
        // User tolak, tanya lagi
        final retry = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Device ID Diperlukan'),
            content: const Text(
              'Aplikasi Traka memerlukan izin untuk membaca Device ID '
              'untuk keamanan akun. Tanpa izin ini, aplikasi tidak dapat digunakan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Berikan Izin'),
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
    }
  }

  /// Request permission kamera.
  static Future<bool> requestCameraPermission(BuildContext context) async {
    while (true) {
      final status = await ph.Permission.camera.status;

      if (status.isGranted) {
        return true;
      }

      if (status.isPermanentlyDenied) {
        final openSettings = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Kamera Diperlukan'),
            content: const Text(
              'Izin kamera diperlukan untuk verifikasi wajah. '
              'Silakan buka pengaturan aplikasi dan berikan izin kamera.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Buka Pengaturan'),
              ),
            ],
          ),
        );

        if (openSettings == true) {
          await ph.openAppSettings();
          await Future.delayed(const Duration(seconds: 1));
          continue;
        } else {
          return false;
        }
      }

      // Request permission
      final result = await ph.Permission.camera.request();

      if (result.isGranted) {
        return true;
      }

      if (result.isDenied) {
        // User tolak, tanya lagi
        final retry = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Kamera Diperlukan'),
            content: const Text(
              'Aplikasi Traka memerlukan izin kamera untuk verifikasi wajah. '
              'Tanpa izin ini, Anda tidak dapat login atau mendaftar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Berikan Izin'),
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
    }
  }

  /// Request permission notifikasi (Android 13+).
  static Future<bool> requestNotificationPermission(
    BuildContext context,
  ) async {
    // Cek apakah Android 13+ (permission handler akan handle ini)
    final status = await ph.Permission.notification.status;

    if (status.isGranted) {
      return true;
    }

    if (status.isPermanentlyDenied) {
      final openSettings = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Izin Notifikasi Diperlukan'),
          content: const Text(
            'Izin notifikasi diperlukan untuk menerima pesan dan update. '
            'Silakan buka pengaturan aplikasi dan berikan izin notifikasi.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Buka Pengaturan'),
            ),
          ],
        ),
      );

      if (openSettings == true) {
        await ph.openAppSettings();
      }
      return false;
    }

    // Request permission
    final result = await ph.Permission.notification.request();
    return result.isGranted;
  }
}
