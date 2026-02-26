import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'device_service.dart';

/// Keamanan device ID:
/// - Cegah spam: max 1 akun per role per device (penumpang + driver = OK)
/// - Rate limit: max gagal login per jam
/// - Deteksi emulator
///
/// Pengecualian: device sama untuk penumpang + driver diperbolehkan.
class DeviceSecurityService {
  static const _maxLoginFailedPerHour = 10;
  static const _loginRateLimitHours = 1;
  static const _collectionDeviceAccounts = 'device_accounts';
  static const _collectionDeviceRateLimit = 'device_rate_limit';
  static const _collectionUsers = 'users';

  /// Cek apakah perangkat adalah emulator.
  static Future<bool> isEmulator() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        return !android.isPhysicalDevice;
      } else if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        return !ios.isPhysicalDevice;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Cek apakah registrasi diperbolehkan.
  /// Satu device boleh punya: 1 penumpang + 1 driver (tidak boleh spam role sama).
  /// Mengecek: device_accounts (installId saja) + users (deviceId+role).
  ///
  /// Penting: device_accounts hanya dicek via installId (bukan deviceId) karena
  /// ANDROID_ID bisa tabrakan antar perangkat (OEM bug). installId unik per install.
  static Future<DeviceSecurityResult> checkRegistrationAllowed(
    String role,
  ) async {
    try {
      final info = await DeviceService.getDeviceInfo();
      final deviceId = info.deviceId?.trim() ?? '';
      final installId = info.installId.trim();

      if (kDebugMode) debugPrint('[Traka DeviceCheck] role=$role, deviceId=${deviceId.isEmpty ? "(kosong)" : "${deviceId.substring(0, deviceId.length.clamp(0, 8))}..."}, installId=${installId.isEmpty ? "(kosong)" : "${installId.substring(0, installId.length.clamp(0, 8))}..."}');

      final isEmu = await isEmulator();
      if (isEmu) {
        return DeviceSecurityResult.blocked(
          'Registrasi tidak diperbolehkan dari emulator.',
        );
      }

      final col = FirebaseFirestore.instance.collection(
        _collectionDeviceAccounts,
      );

      // 1. Cek device_accounts HANYA via installId (bukan deviceId - bisa tabrakan antar HP)
      if (installId.isNotEmpty) {
        final doc = await col.doc(installId).get();
        final data = doc.data();
        final existingRoleUid = role == 'penumpang'
            ? (data?['penumpangUid'] as String?)
            : (data?['driverUid'] as String?);

        if (existingRoleUid != null && existingRoleUid.isNotEmpty) {
          if (kDebugMode) debugPrint('[Traka DeviceCheck] device_accounts[installId] punya $role → blocked');
          return DeviceSecurityResult.blocked(
            role == 'driver'
                ? 'Perangkat ini sudah terdaftar sebagai driver. Silakan login.'
                : 'Perangkat ini sudah terdaftar sebagai penumpang. Silakan login.',
          );
        }
      }

      // 2. Fallback device_accounts: query by installId (pendaftaran lama, doc ID bukan installId)
      if (installId.isNotEmpty) {
        final query = await col
            .where('installId', isEqualTo: installId)
            .limit(1)
            .get();
        for (final doc in query.docs) {
          final data = doc.data();
          final existingRoleUid = role == 'penumpang'
              ? (data['penumpangUid'] as String?)
              : (data['driverUid'] as String?);
          if (existingRoleUid != null && existingRoleUid.isNotEmpty) {
            if (kDebugMode) debugPrint('[Traka DeviceCheck] device_accounts query installId punya $role → blocked');
            return DeviceSecurityResult.blocked(
              role == 'driver'
                  ? 'Perangkat ini sudah terdaftar sebagai driver. Silakan login.'
                  : 'Perangkat ini sudah terdaftar sebagai penumpang. Silakan login.',
            );
          }
        }
      }

      // 3. Cek users collection (deviceId+role) - untuk user yang sudah login (deviceId tersimpan)
      if (deviceId.isNotEmpty) {
        final usersWithSameDevice = await FirebaseFirestore.instance
            .collection(_collectionUsers)
            .where('deviceId', isEqualTo: deviceId)
            .where('role', isEqualTo: role)
            .limit(1)
            .get();

        if (usersWithSameDevice.docs.isNotEmpty) {
          if (kDebugMode) debugPrint('[Traka DeviceCheck] users punya deviceId+role $role → blocked');
          return DeviceSecurityResult.blocked(
            role == 'driver'
                ? 'Perangkat ini sudah terdaftar sebagai driver. Silakan login.'
                : 'Perangkat ini sudah terdaftar sebagai penumpang. Silakan login.',
          );
        }
      }

      if (kDebugMode) debugPrint('[Traka DeviceCheck] tidak ada konflik → allowed');
      return DeviceSecurityResult.allowed();
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Traka DeviceCheck] Error: $e\n$st');
      // Jangan silent allow saat error - lebih aman block dengan pesan
      return DeviceSecurityResult.blocked(
        'Tidak dapat memverifikasi perangkat. Silakan coba lagi atau hubungi admin.',
      );
    }
  }

  /// Melepaskan device lama dari device_accounts saat user login di device baru.
  /// Agar HP lama bisa dipakai untuk registrasi akun baru (driver/penumpang).
  static Future<void> releaseDeviceRegistration(
    String oldDeviceId,
    String role,
  ) async {
    final trimmed = oldDeviceId.trim();
    if (trimmed.isEmpty) return;
    try {
      final col =
          FirebaseFirestore.instance.collection(_collectionDeviceAccounts);
      final doc = await col.doc(trimmed).get();
      if (!doc.exists) return;
      final data = doc.data();
      final field = role == 'penumpang' ? 'penumpangUid' : 'driverUid';
      final storedUid = data?[field] as String?;
      if (storedUid == null || storedUid.isEmpty) return;

      await col.doc(trimmed).update({field: FieldValue.delete()});
      if (kDebugMode) debugPrint(
        '[Traka DeviceCheck] releaseDeviceRegistration: cleared $role dari $trimmed',
      );

      final installId = (data?['installId'] as String?)?.trim();
      if (installId != null &&
          installId.isNotEmpty &&
          installId != trimmed) {
        final installDoc = await col.doc(installId).get();
        if (installDoc.exists) {
          await col.doc(installId).update({field: FieldValue.delete()});
          if (kDebugMode) debugPrint(
            '[Traka DeviceCheck] releaseDeviceRegistration: cleared $role dari installId $installId',
          );
        }
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint(
        '[Traka DeviceCheck] releaseDeviceRegistration Error: $e\n$st',
      );
    }
  }

  /// Catat registrasi berhasil (panggil setelah akun tersimpan).
  /// Hanya menulis ke installId (deviceId bisa tabrakan antar HP, installId unik per install).
  static Future<void> recordRegistration(String uid, String role) async {
    try {
      final info = await DeviceService.getDeviceInfo();
      final installId = info.installId.trim();
      if (installId.isEmpty) {
        if (kDebugMode) debugPrint('[Traka DeviceCheck] recordRegistration: installId kosong, skip');
        return;
      }

      final field = role == 'penumpang' ? 'penumpangUid' : 'driverUid';
      final data = {
        field: uid,
        'osVersion': info.osVersion,
        'model': info.model,
        'installId': info.installId,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final col = FirebaseFirestore.instance.collection(
        _collectionDeviceAccounts,
      );
      await col.doc(installId).set(data, SetOptions(merge: true));
      if (kDebugMode) debugPrint('[Traka DeviceCheck] recordRegistration: berhasil tulis $role untuk installId');
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Traka DeviceCheck] recordRegistration Error: $e\n$st');
      // Jangan rethrow - akun sudah dibuat, hanya device_accounts yang gagal
    }
  }

  /// Cek rate limit login (gagal berulang).
  static Future<DeviceSecurityResult> checkLoginRateLimit() async {
    try {
      final info = await DeviceService.getDeviceInfo();
      final deviceKey = _deviceKey(info);
      if (deviceKey.isEmpty) return DeviceSecurityResult.allowed();

      final isEmu = await isEmulator();
      if (isEmu) {
        return DeviceSecurityResult.blocked(
          'Login tidak diperbolehkan dari emulator.',
        );
      }

      final doc = await FirebaseFirestore.instance
          .collection(_collectionDeviceRateLimit)
          .doc(deviceKey)
          .get();

      final data = doc.data();
      final failedCount = (data?['failedCount'] as int?) ?? 0;
      final firstFailedAt = (data?['firstFailedAt'] as Timestamp?)?.toDate();

      if (failedCount < _maxLoginFailedPerHour) {
        return DeviceSecurityResult.allowed();
      }

      if (firstFailedAt != null) {
        final hoursSince = DateTime.now().difference(firstFailedAt).inHours;
        if (hoursSince >= _loginRateLimitHours) {
          await _resetLoginRateLimit(deviceKey);
          return DeviceSecurityResult.allowed();
        }
      }

      return DeviceSecurityResult.blocked(
        'Terlalu banyak percobaan login gagal. Coba lagi dalam $_loginRateLimitHours jam.',
      );
    } catch (_) {
      return DeviceSecurityResult.allowed();
    }
  }

  /// Catat percobaan login (panggil saat login gagal).
  static Future<void> recordLoginFailed() async {
    try {
      final info = await DeviceService.getDeviceInfo();
      final deviceKey = _deviceKey(info);
      if (deviceKey.isEmpty) return;

      final ref = FirebaseFirestore.instance
          .collection(_collectionDeviceRateLimit)
          .doc(deviceKey);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final data = snap.data();
        final failedCount = ((data?['failedCount'] as int?) ?? 0) + 1;
        var firstFailedAt = (data?['firstFailedAt'] as Timestamp?)?.toDate();
        firstFailedAt ??= DateTime.now();

        tx.set(ref, {
          'failedCount': failedCount,
          'firstFailedAt': Timestamp.fromDate(firstFailedAt),
          'osVersion': info.osVersion,
          'model': info.model,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (_) {}
  }

  /// Reset rate limit saat login berhasil.
  static Future<void> recordLoginSuccess() async {
    try {
      final info = await DeviceService.getDeviceInfo();
      final deviceKey = _deviceKey(info);
      if (deviceKey.isEmpty) return;
      await _resetLoginRateLimit(deviceKey);
    } catch (_) {}
  }

  static Future<void> _resetLoginRateLimit(String deviceKey) async {
    try {
      await FirebaseFirestore.instance
          .collection(_collectionDeviceRateLimit)
          .doc(deviceKey)
          .delete();
    } catch (_) {}
  }

  static String _deviceKey(TrakaDeviceInfo info) {
    final id = info.deviceId ?? info.installId;
    if (id.isEmpty) return '';
    return id;
  }
}

/// Hasil pengecekan keamanan device.
class DeviceSecurityResult {
  final bool allowed;
  final String? message;

  const DeviceSecurityResult({required this.allowed, this.message});

  factory DeviceSecurityResult.allowed() =>
      const DeviceSecurityResult(allowed: true);

  factory DeviceSecurityResult.blocked(String message) =>
      DeviceSecurityResult(allowed: false, message: message);
}
