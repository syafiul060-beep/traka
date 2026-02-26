import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_verification/face_verification.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/account_deletion_service.dart';
import '../services/device_security_service.dart';
import '../services/device_service.dart';
import '../services/fcm_service.dart';
import '../services/permission_service.dart';
import '../services/face_photo_pool_service.dart';
import '../services/face_validation_service.dart';
import '../services/verification_log_service.dart';
import 'active_liveness_screen.dart';
import '../widgets/app_update_wrapper.dart';
import 'driver_screen.dart';
import 'onboarding_screen.dart';
import 'forgot_password_screen.dart';
import 'penumpang_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  /// Jika tidak null, tampilkan SnackBar "Perangkat sudah digunakan oleh penumpang/driver" setelah halaman terbuka.
  final String? deviceAlreadyUsedMessage;

  const LoginScreen({super.key, this.deviceAlreadyUsedMessage});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  AppLocalizations l10n = AppLocalizations(locale: AppLocale.id);
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _loginWithPhone = false;
  String? _phoneVerificationId;
  bool _phoneOtpSent = false;

  @override
  void initState() {
    super.initState();
    _requestDeviceId();
    if (widget.deviceAlreadyUsedMessage != null &&
        widget.deviceAlreadyUsedMessage!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.deviceAlreadyUsedMessage!,
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
            backgroundColor: colorScheme.primaryContainer,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        );
      });
    }
  }

  /// Mendapatkan Device ID saat halaman login (untuk verifikasi perangkat).
  Future<void> _requestDeviceId() async {
    await DeviceService.getDeviceId();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String _phoneToE164(String phone) {
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) {
      digits = '62${digits.substring(1)}';
    } else if (!digits.startsWith('62'))
      digits = '62$digits';
    return '+$digits';
  }

  void _onLanguageSelected(AppLocale locale) {
    setState(() => l10n = l10n.copyWith(locale: locale));
  }

  Future<void> _onLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // Cek rate limit dan emulator
    final rateLimitResult = await DeviceSecurityService.checkLoginRateLimit();
    if (!rateLimitResult.allowed) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rateLimitResult.message ?? 'Login ditangguhkan.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password);
      final uid = userCredential.user!.uid;
      await _handlePostLogin(uid);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      try {
        await DeviceSecurityService.recordLoginFailed();
      } catch (_) {}

      String errorMessage;
      if (e.code == 'user-not-found') {
        // Email tidak terdaftar di Firebase Auth
        errorMessage = l10n.locale == AppLocale.id
            ? 'Akun Belum Terdaftar...!'
            : 'Account Not Registered...!';
      } else if (e.code == 'wrong-password') {
        // Password salah (email terdaftar)
        errorMessage = l10n.locale == AppLocale.id
            ? 'Password Salah...! jika lupa password pilih lupa sandi'
            : 'Wrong Password...! if you forgot password, select forgot password';
      } else if (e.code == 'invalid-credential') {
        // Invalid credential bisa berarti email tidak terdaftar atau password salah
        // Cek apakah email terdaftar di Firestore untuk menentukan pesan error
        try {
          final usersQuery = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: email)
              .limit(1)
              .get();

          if (usersQuery.docs.isNotEmpty) {
            // Email terdaftar di Firestore, berarti password salah
            errorMessage = l10n.locale == AppLocale.id
                ? 'Password Salah...! jika lupa password pilih lupa sandi'
                : 'Wrong Password...! if you forgot password, select forgot password';
          } else {
            // Email tidak terdaftar di Firestore
            errorMessage = l10n.locale == AppLocale.id
                ? 'Akun Belum Terdaftar...!'
                : 'Account Not Registered...!';
          }
        } catch (_) {
          // Jika error saat cek Firestore, default ke email tidak terdaftar
          errorMessage = l10n.locale == AppLocale.id
              ? 'Akun Belum Terdaftar...!'
              : 'Account Not Registered...!';
        }
      } else if (e.code == 'invalid-email') {
        errorMessage = l10n.locale == AppLocale.id
            ? 'Format email tidak valid.'
            : 'Invalid email format.';
      } else if (e.code == 'user-disabled') {
        errorMessage = l10n.locale == AppLocale.id
            ? 'Akun telah dinonaktifkan. Silakan hubungi administrator.'
            : 'Account has been disabled. Please contact administrator.';
      } else {
        errorMessage =
            e.message ??
            (l10n.locale == AppLocale.id
                ? 'Gagal login. Silakan coba lagi.'
                : 'Login failed. Please try again.');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      try {
        await DeviceSecurityService.recordLoginFailed();
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Gagal login. Silakan coba lagi.'
                : 'Login failed. Please try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Setelah berhasil sign in (email atau telepon), cek Firestore, role, verifikasi wajah, lalu navigasi.
  Future<void> _handlePostLogin(String uid) async {
    // Delay minimal untuk edge case: logout dari device A lalu langsung login di device B
    // Jalankan Firestore + deviceId paralel agar lebih cepat
    Future<DocumentSnapshot<Map<String, dynamic>>?> _fetchUserDoc() async {
      for (int r = 0; r < 3; r++) {
        try {
          return await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get(GetOptions(source: Source.server));
        } catch (e) {
          if (r < 2) await Future.delayed(Duration(milliseconds: 200 * (r + 1)));
          else rethrow;
        }
      }
      return null;
    }

    Future<String?> _fetchDeviceId() async {
      for (int r = 0; r < 3; r++) {
        final id = await DeviceService.getDeviceId();
        if (id != null && id.isNotEmpty) return id;
        if (r < 2) await Future.delayed(Duration(milliseconds: 150 * (r + 1)));
      }
      return null;
    }

    final results = await Future.wait([
      Future.delayed(const Duration(milliseconds: 350)),
      _fetchUserDoc(),
      _fetchDeviceId(),
    ]);
    final userDoc = results[1] as DocumentSnapshot<Map<String, dynamic>>?;
    final currentDeviceId = results[2] as String?;

    if (userDoc == null) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Gagal membaca data pengguna. Silakan coba lagi.'
                : 'Failed to read user data. Please try again.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (!userDoc.exists) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Akun Belum Terdaftar...!'
                : 'Account Not Registered...!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final userData = userDoc.data()!;
    final role = userData['role'] as String?;

    // Cek akun dalam proses penghapusan
    if (AccountDeletionService.isDeleted(userData)) {
      final daysLeft = AccountDeletionService.daysUntilDeletion(userData);
      final confirm = await _showCancelDeletionOnLoginDialog(daysLeft ?? 0);
      if (!mounted) return;
      if (confirm == true) {
        await AccountDeletionService.cancelAccountDeletion(uid);
        // Reload user doc setelah cancel
        final updatedDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get(GetOptions(source: Source.server));
        if (!updatedDoc.exists || !mounted) return;
        // Lanjut ke flow normal (jangan return)
      } else {
        await FirebaseAuth.instance.signOut();
        setState(() => _isLoading = false);
        return;
      }
    }

    final storedDeviceId = userData['deviceId'] as String?;
    final faceVerificationUrl = userData['faceVerificationUrl'] as String?;
    final isDemoAccount = userData['isDemoAccount'] == true;

    // currentDeviceId sudah diambil paralel dengan Firestore di atas
    // Normalisasi: string kosong, null, atau whitespace dianggap sebagai tidak ada deviceId
    final normalizedStoredDeviceId =
        (storedDeviceId == null || storedDeviceId.trim().isEmpty)
        ? null
        : storedDeviceId.trim();

    final hasStoredDeviceId =
        normalizedStoredDeviceId != null && normalizedStoredDeviceId.isNotEmpty;
    final hasCurrentDeviceId =
        currentDeviceId != null && currentDeviceId.isNotEmpty;

    // Pengecekan device ID berbeda: jika ada storedDeviceId DAN ada currentDeviceId DAN berbeda
    // Ini adalah kondisi UTAMA untuk wajib verifikasi wajah saat login di device baru
    final isFirstLogin = !hasStoredDeviceId;
    final deviceIdUnavailable = hasStoredDeviceId && !hasCurrentDeviceId;

    // Perbandingan deviceId dengan case-sensitive dan trim untuk memastikan akurat
    // Pastikan kedua deviceId tidak null sebelum membandingkan
    // CRITICAL: Logika ini HARUS dieksekusi untuk semua HP Android
    bool deviceIdDifferent = false;

    if (hasStoredDeviceId && hasCurrentDeviceId) {
      final storedIdTrimmed = normalizedStoredDeviceId.trim();
      final currentIdTrimmed = currentDeviceId.trim();

      deviceIdDifferent =
          storedIdTrimmed.isNotEmpty &&
          currentIdTrimmed.isNotEmpty &&
          storedIdTrimmed != currentIdTrimmed;

    }

    // Cek apakah device ID saat ini sudah digunakan oleh akun lain dengan role yang SAMA
    // (1 akun hanya boleh login di 1 device, tapi 1 device boleh punya 1 driver + 1 penumpang)
    // TAPI: jika deviceId berbeda dari yang tersimpan untuk akun ini, berarti login di device baru
    // → biarkan lanjut ke verifikasi wajah (jangan tolak dulu)
    // Gunakan Source.server untuk membaca data terbaru dari server, bukan cache
    if (hasCurrentDeviceId && role != null && !deviceIdDifferent) {
      // Hanya cek konflik jika deviceId SAMA (bukan berbeda)
      // Jika deviceId berbeda, berarti login di device baru → akan verifikasi wajah nanti
      final usersWithSameDeviceAndRole = await FirebaseFirestore.instance
          .collection('users')
          .where('deviceId', isEqualTo: currentDeviceId)
          .where('role', isEqualTo: role)
          .limit(1)
          .get(GetOptions(source: Source.server));

      // Jika ada user lain dengan role yang sama yang menggunakan device ID yang sama, tolak login
      if (usersWithSameDeviceAndRole.docs.isNotEmpty) {
        final otherUserDoc = usersWithSameDeviceAndRole.docs.first;
        final otherUserId = otherUserDoc.id;

        // Jika bukan akun yang sedang login, berarti device sudah dipakai akun lain dengan role yang sama
        if (otherUserId != uid) {
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                l10n.locale == AppLocale.id
                    ? 'Device ini sudah digunakan oleh akun $role lain. 1 akun hanya boleh login di 1 device. Silakan logout dari device lain terlebih dahulu.'
                    : 'This device is already used by another $role account. 1 account can only login on 1 device. Please logout from the other device first.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              duration: const Duration(seconds: 5),
            ),
          );
          return;
        }
      }
    }

    // WAJIB verifikasi wajah jika device ID berbeda dari yang tersimpan
    // Aturan: Jika device ID berbeda, SELALU wajib verifikasi wajah (untuk semua pengguna)
    // Syarat: user harus punya faceVerificationUrl untuk bisa verifikasi
    final shouldVerifyByDeviceId =
        deviceIdDifferent; // Device ID berbeda = wajib verifikasi
    final hasFaceData =
        faceVerificationUrl != null && faceVerificationUrl.isNotEmpty;

    // WAJIB verifikasi wajah jika:
    // 1. Device ID berbeda dari yang tersimpan (PRIORITAS UTAMA) ATAU
    // 2. Login pertama kali (belum ada deviceId tersimpan) ATAU
    // 3. Device ID tidak tersedia (device tidak support deviceId)
    // Syarat: user harus punya faceVerificationUrl untuk bisa verifikasi
    // IMPORTANT: Jika deviceId berbeda TAPI tidak ada faceVerificationUrl, tetap tolak login
    final needsFaceVerification =
        hasFaceData &&
        (shouldVerifyByDeviceId || isFirstLogin || deviceIdUnavailable);

    // CRITICAL CHECK: Jika deviceId berbeda, WAJIB verifikasi wajah
    // Jika deviceId berbeda tapi tidak ada faceVerificationUrl, tolak login
    // Akun demo (Google Play review): skip verifikasi wajah
    if (isDemoAccount) {
      final deviceIdToSave =
          currentDeviceId ?? await DeviceService.getDeviceId() ?? '';
      if (deviceIdToSave.isNotEmpty) {
        if (normalizedStoredDeviceId != null &&
            role != null &&
            normalizedStoredDeviceId != deviceIdToSave.trim()) {
          await DeviceSecurityService.releaseDeviceRegistration(
            normalizedStoredDeviceId,
            role,
          );
        }
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'deviceId': deviceIdToSave,
        });
      }
    } else if (isFirstLogin) {
      // Login pertama kali: langsung masuk app, set deviceId. Verifikasi dilengkapi nanti saat pesan travel/kirim barang/pilih rute.
      final deviceIdToSave =
          currentDeviceId ?? await DeviceService.getDeviceId() ?? '';
      if (deviceIdToSave.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'deviceId': deviceIdToSave,
        });
      }
    } else if (deviceIdDifferent) {
      if (!hasFaceData) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.locale == AppLocale.id
                  ? 'Device ID berbeda dari device terakhir login. Verifikasi wajah diperlukan tetapi data wajah tidak ditemukan. Silakan hubungi admin.'
                  : 'Device ID differs from last login device. Face verification required but face data not found. Please contact admin.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            duration: const Duration(seconds: 5),
          ),
        );
        return;
      }
      // Jika deviceId berbeda DAN ada faceVerificationUrl, WAJIB verifikasi wajah
      // PASTIKAN verifikasi wajah dipanggil (dengan retry)
      final result = await _runFaceVerificationWithRetry(uid);

      if (!mounted) return;
      if (!result.verified) {
        await FirebaseAuth.instance.signOut();
        setState(() => _isLoading = false);
        return;
      }
      // Lepaskan device lama dari device_accounts agar HP lama bisa daftar lagi
      final deviceIdToCompare =
          (currentDeviceId ?? await DeviceService.getDeviceId() ?? '').trim();
      if (normalizedStoredDeviceId != deviceIdToCompare && role != null) {
        await DeviceSecurityService.releaseDeviceRegistration(
          normalizedStoredDeviceId,
          role,
        );
      }
      // Setelah verifikasi wajah berhasil, update deviceId ke device baru
      final deviceIdToSave =
          currentDeviceId ?? await DeviceService.getDeviceId() ?? '';
      if (deviceIdToSave.isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'deviceId': deviceIdToSave,
        });
      }
      if (result.selfiePath != null) {
        try {
          await FacePhotoPoolService.updatePoolOnLoginSuccess(
            uid,
            File(result.selfiePath!),
          );
        } catch (_) {}
      }
      // Setelah verifikasi wajah berhasil, lanjutkan ke navigasi
      // Jangan return di sini, biarkan lanjut ke navigasi normal
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    try {
      await DeviceSecurityService.recordLoginSuccess();
    } catch (_) {}

    if (role == 'penumpang' || role == 'driver') {
      FcmService.saveTokenForUser(uid);
      final faceUrl = (userData['faceVerificationUrl'] as String?)?.trim();
      final hasFacePhoto = faceUrl != null && faceUrl.isNotEmpty;
      final seenOnboarding = await OnboardingScreen.hasSeenOnboarding();
      if (!hasFacePhoto && !seenOnboarding) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => AppUpdateWrapper(
              child: OnboardingScreen(role: role ?? 'penumpang'),
            ),
          ),
        );
      } else if (role == 'penumpang') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const AppUpdateWrapper(child: PenumpangScreen()),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const AppUpdateWrapper(child: DriverScreen()),
          ),
        );
      }
    } else {
      await FirebaseAuth.instance.signOut();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Role tidak valid. Silakan hubungi administrator.'
                : 'Invalid role. Please contact administrator.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<bool?> _showCancelDeletionOnLoginDialog(int daysLeft) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Akun dalam proses penghapusan'),
        content: Text(
          daysLeft > 0
              ? 'Akun dalam proses penghapusan (sisa $daysLeft hari). Batalkan penghapusan?'
              : 'Akun dalam proses penghapusan. Batalkan penghapusan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, batalkan'),
          ),
        ],
      ),
    );
  }

  /// Verifikasi wajah dengan retry: tampilkan dialog "Coba lagi" saat gagal, tanpa keluar dari flow.
  Future<({bool verified, String? selfiePath, String? errorMessage})>
      _runFaceVerificationWithRetry(String uid) async {
    while (true) {
      final result = await _showFaceVerificationForLogin(uid);
      if (result.verified || !mounted) return result;
      // Gagal: tampilkan dialog dengan "Coba lagi" dan "Batal"
      final retry = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(
            l10n.locale == AppLocale.id ? 'Verifikasi gagal' : 'Verification failed',
          ),
          content: Text(
            result.errorMessage ??
                (l10n.locale == AppLocale.id
                    ? 'Verifikasi wajah gagal.'
                    : 'Face verification failed.'),
            style: const TextStyle(height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.locale == AppLocale.id ? 'Batal' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.locale == AppLocale.id ? 'Coba lagi' : 'Try again'),
            ),
          ],
        ),
      );
      if (retry != true || !mounted) return result;
    }
  }

  /// Returns 'retry' | 'useAnyway' | null (cancel)
  Future<String?> _showLoginBlurErrorDialog(String message) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.locale == AppLocale.id ? 'Foto tidak memenuhi syarat' : 'Photo does not meet requirements',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            Text(
              l10n.locale == AppLocale.id
                  ? 'Foto kurang jelas. Anda bisa pakai foto ini jika wajah terdeteksi, atau ambil ulang untuk hasil lebih baik.'
                  : 'Photo is unclear. You can use this photo if face is detected, or retake for better results.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.locale == AppLocale.id ? 'Batal' : 'Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'useAnyway'),
                  child: Text(l10n.locale == AppLocale.id ? 'Pakai foto ini' : 'Use this photo'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'retry'),
                  child: Text(l10n.locale == AppLocale.id ? 'Coba lagi' : 'Try again'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Verifikasi wajah: sama seperti pendaftaran – lingkaran, kedip atau diam 2 detik lalu otomatis ambil foto, lalu cocokkan dengan wajah tersimpan.
  /// [errorMessage]: pesan untuk user saat gagal (null jika berhasil).
  Future<({bool verified, String? selfiePath, String? errorMessage})>
      _showFaceVerificationForLogin(String uid) async {
    final cameraOk = await PermissionService.requestCameraPermission(context);
    if (!cameraOk || !mounted) {
      VerificationLogService.log(
        userId: uid,
        success: false,
        source: VerificationLogSource.login,
        errorMessage: l10n.locale == AppLocale.id
            ? 'Izin kamera diperlukan untuk verifikasi wajah.'
            : 'Camera permission required for face verification.',
      );
      return (
        verified: false,
        selfiePath: null,
        errorMessage: l10n.locale == AppLocale.id
            ? 'Izin kamera diperlukan untuk verifikasi wajah.'
            : 'Camera permission required for face verification.',
      );
    }
    try {
      await FaceVerification.instance.init();
    } catch (_) {}
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute<File>(builder: (_) => const ActiveLivenessScreen()),
    );
    if (file == null || file.path.isEmpty) {
      VerificationLogService.log(
        userId: uid,
        success: false,
        source: VerificationLogSource.login,
        errorMessage: l10n.locale == AppLocale.id
            ? 'Verifikasi wajah dibatalkan.'
            : 'Face verification cancelled.',
      );
      return (
        verified: false,
        selfiePath: null,
        errorMessage: l10n.locale == AppLocale.id
            ? 'Verifikasi wajah dibatalkan.'
            : 'Face verification cancelled.',
      );
    }

    File? tempStored;
    try {
      final ref = FirebaseStorage.instance.ref().child(
        'users/$uid/face_verification.jpg',
      );
      final bytes = await ref.getData();
      if (bytes == null || bytes.isEmpty) {
        VerificationLogService.log(
          userId: uid,
          success: false,
          source: VerificationLogSource.login,
          errorMessage: l10n.locale == AppLocale.id
              ? 'Data wajah tidak ditemukan. Silakan hubungi admin.'
              : 'Face data not found. Please contact admin.',
        );
        return (
          verified: false,
          selfiePath: null,
          errorMessage: l10n.locale == AppLocale.id
              ? 'Data wajah tidak ditemukan. Silakan hubungi admin.'
              : 'Face data not found. Please contact admin.',
        );
      }
      final tempDir = await getTemporaryDirectory();
      tempStored = File('${tempDir.path}/login_verify_$uid.jpg');
      await tempStored.writeAsBytes(bytes);

      await FaceVerification.instance.registerFromImagePath(
        id: uid,
        imagePath: tempStored.path,
        imageId: 'login_verify',
      );

      // Validasi foto dulu untuk feedback spesifik (blur, cahaya, dll)
      final validationResult =
          await FaceValidationService.validateFacePhoto(file.path);
      if (!validationResult.isValid) {
        if (validationResult.isBlurError) {
          final action = await _showLoginBlurErrorDialog(
            validationResult.errorMessage ??
                (l10n.locale == AppLocale.id
                    ? 'Foto tidak memenuhi syarat.'
                    : 'Photo does not meet requirements.'),
          );
          if (action == 'retry') {
            VerificationLogService.log(
              userId: uid,
              success: false,
              source: VerificationLogSource.login,
              errorMessage: validationResult.errorMessage,
            );
            return (
              verified: false,
              selfiePath: null,
              errorMessage: validationResult.errorMessage,
            );
          }
          if (action == 'useAnyway') {
            final skipBlurResult =
                await FaceValidationService.validateFacePhotoSkipBlur(file.path);
            if (!skipBlurResult.isValid) {
              VerificationLogService.log(
                userId: uid,
                success: false,
                source: VerificationLogSource.login,
                errorMessage: l10n.locale == AppLocale.id
                    ? 'Foto harus wajah asli, bukan dari gambar atau layar.'
                    : 'Photo must be a real face.',
              );
              return (
                verified: false,
                selfiePath: null,
                errorMessage: l10n.locale == AppLocale.id
                    ? 'Foto harus wajah asli, bukan dari gambar atau layar. Silakan ambil foto ulang.'
                    : 'Photo must be a real face, not from image or screen. Please take a new photo.',
              );
            }
            // Lanjut ke face match (fall through)
          } else {
            VerificationLogService.log(
              userId: uid,
              success: false,
              source: VerificationLogSource.login,
              errorMessage: 'Verifikasi wajah dibatalkan.',
            );
            return (
              verified: false,
              selfiePath: null,
              errorMessage: l10n.locale == AppLocale.id
                  ? 'Verifikasi wajah dibatalkan.'
                  : 'Face verification cancelled.',
            );
          }
        } else {
          VerificationLogService.log(
            userId: uid,
            success: false,
            source: VerificationLogSource.login,
            errorMessage: validationResult.errorMessage,
          );
          return (
            verified: false,
            selfiePath: null,
            errorMessage: validationResult.errorMessage ??
                (l10n.locale == AppLocale.id
                    ? 'Foto tidak memenuhi syarat.'
                    : 'Photo does not meet requirements.'),
          );
        }
      }

      final matchId = await FaceVerification.instance.verifyFromImagePath(
        imagePath: file.path,
        threshold: 0.7,
        staffId: uid,
      );

      final verified = matchId == uid;
      try {
        FaceVerification.instance.deleteRecord(uid);
      } catch (_) {}
      VerificationLogService.log(
        userId: uid,
        success: verified,
        source: VerificationLogSource.login,
        errorMessage: verified
            ? null
            : (l10n.locale == AppLocale.id
                ? 'Wajah tidak cocok dengan data yang tersimpan.'
                : 'Face does not match stored data.'),
      );
      return (
        verified: verified,
        selfiePath: file.path,
        errorMessage: verified
            ? null
            : (l10n.locale == AppLocale.id
                ? 'Wajah tidak cocok dengan data yang tersimpan.'
                : 'Face does not match stored data.'),
      );
    } catch (e) {
      VerificationLogService.log(
        userId: uid,
        success: false,
        source: VerificationLogSource.login,
        errorMessage: 'Verifikasi wajah gagal: $e',
      );
      return (
        verified: false,
        selfiePath: null,
        errorMessage: l10n.locale == AppLocale.id
            ? 'Verifikasi wajah gagal. Silakan coba lagi.'
            : 'Face verification failed. Please try again.',
      );
    } finally {
      try {
        tempStored?.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _sendPhoneOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'No. telepon wajib diisi'
                : 'Phone number is required',
          ),
        ),
      );
      return;
    }
    final phoneE164 = _phoneToE164(phone);
    setState(() => _isLoading = true);
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneE164,
      verificationCompleted: (PhoneAuthCredential credential) async {
        if (!mounted) return;
        try {
          final userCredential = await FirebaseAuth.instance
              .signInWithCredential(credential);
          final uid = userCredential.user?.uid;
          if (uid != null) await _handlePostLogin(uid);
        } catch (_) {
          if (!mounted) return;
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No. telepon belum terdaftar atau tidak terhubung ke akun.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        String message = 'Verifikasi gagal. Coba lagi.';
        final code = e.code;
        final msg = (e.message ?? '').toLowerCase();
        if (code == 'missing-client-identifier' ||
            msg.contains('app identifier') ||
            msg.contains('play integrity') ||
            msg.contains('recaptcha')) {
          message =
              'Perangkat/aplikasi belum terverifikasi. '
              'Tambahkan SHA-1 di Firebase Console dan coba di HP asli. Lihat docs/FIREBASE_OTP_LANGKAH.md';
        } else if (msg.contains('blocked') ||
            msg.contains('unusual activity')) {
          message =
              'Perangkat ini sementara diblokir karena aktivitas tidak biasa. Tunggu beberapa jam lalu coba lagi.';
        } else if (e.message != null && e.message!.isNotEmpty) {
          message = e.message!;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        setState(() {
          _phoneVerificationId = verificationId;
          _phoneOtpSent = true;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.locale == AppLocale.id
                  ? 'Kode verifikasi telah dikirim ke $phoneE164'
                  : 'Verification code sent to $phoneE164',
            ),
            backgroundColor: Colors.green,
          ),
        );
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> _onLoginWithPhone() async {
    final code = _otpController.text.trim();
    if (code.isEmpty || _phoneVerificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Masukkan kode verifikasi dari SMS'
                : 'Enter verification code from SMS',
          ),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _phoneVerificationId!,
        smsCode: code,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final uid = userCredential.user?.uid;
      if (uid != null) {
        await _handlePostLogin(uid);
      } else {
        setState(() => _isLoading = false);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ??
                (l10n.locale == AppLocale.id
                    ? 'Kode salah atau kedaluwarsa.'
                    : 'Invalid or expired code.'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal login dengan no. telepon.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _onForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ForgotPasswordScreen(),
      ),
    );
  }

  void _onRegister() {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.radiusLg),
        ),
      ),
      builder: (ctx) {
        final modalScheme = Theme.of(ctx).colorScheme;
        final maxHeight = MediaQuery.of(ctx).size.height * 0.9;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.locale == AppLocale.id
                        ? 'Daftar sebagai'
                        : 'Register as',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: modalScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _RegisterTypeTile(
                    label: l10n.penumpang,
                    icon: Icons.person_outline,
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              RegisterScreen(type: RegisterType.penumpang),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  _RegisterTypeTile(
                    label: l10n.driver,
                    icon: Icons.directions_car_outlined,
                    onTap: () {
                      Navigator.pop(ctx);
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              RegisterScreen(type: RegisterType.driver),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: context.responsive.horizontalPadding,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: context.responsive.spacing(16)),
                // Language – kanan atas
                Align(
                  alignment: Alignment.centerRight,
                  child: _LanguageSelector(
                    current: l10n.locale,
                    onSelected: _onLanguageSelected,
                  ),
                ),
                SizedBox(height: context.responsive.spacing(24)),
                // Logo
                const _LogoSection(),
                SizedBox(height: context.responsive.spacing(40)),
                // Toggle: Login dengan Email / No. Telepon
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() {
                          _loginWithPhone = false;
                          _phoneOtpSent = false;
                          _phoneVerificationId = null;
                        }),
                        style: TextButton.styleFrom(
                          foregroundColor: _loginWithPhone
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.primary,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            l10n.locale == AppLocale.id
                                ? 'Login dengan Email'
                                : 'Login with Email',
                            style: TextStyle(
                              fontWeight: _loginWithPhone
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => setState(() {
                          _loginWithPhone = true;
                          _phoneOtpSent = false;
                          _phoneVerificationId = null;
                        }),
                        style: TextButton.styleFrom(
                          foregroundColor: _loginWithPhone
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            l10n.locale == AppLocale.id
                                ? 'Login dengan No. Telepon'
                                : 'Login with Phone',
                            style: TextStyle(
                              fontWeight: _loginWithPhone
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: context.responsive.spacing(16)),
                if (!_loginWithPhone) ...[
                  _UnderlineTextField(
                    controller: _emailController,
                    hint: l10n.emailHint,
                    prefixIcon: Icons.person_outline,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return l10n.locale == AppLocale.id
                            ? 'Email wajib diisi'
                            : 'Email is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  _UnderlineTextField(
                    controller: _passwordController,
                    hint: l10n.passwordHint,
                    prefixIcon: Icons.lock_outline,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return l10n.locale == AppLocale.id
                            ? 'Sandi wajib diisi'
                            : 'Password is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _isLoading ? null : _onLogin,
                    style: FilledButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : Text(
                            l10n.loginButton,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: _onForgotPassword,
                      child: Text(
                        l10n.forgotPassword,
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  _UnderlineTextField(
                    controller: _phoneController,
                    hint: l10n.locale == AppLocale.id
                        ? 'No. telepon (contoh: 08123456789)'
                        : 'Phone (e.g. 08123456789)',
                    prefixIcon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone,
                  ),
                  if (!_phoneOtpSent) ...[
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _isLoading ? null : _sendPhoneOtp,
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusXs,
                          ),
                        ),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : Text(
                              l10n.locale == AppLocale.id
                                  ? 'Kirim kode SMS'
                                  : 'Send SMS code',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ] else ...[
                    const SizedBox(height: 20),
                    _UnderlineTextField(
                      controller: _otpController,
                      hint: l10n.locale == AppLocale.id
                          ? 'Kode verifikasi (6 digit)'
                          : 'Verification code (6 digits)',
                      prefixIcon: Icons.sms_outlined,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 28),
                    FilledButton(
                      onPressed: _isLoading ? null : _onLoginWithPhone,
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusXs,
                          ),
                        ),
                      ),
                      child: _isLoading
                          ? SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : Text(
                              l10n.loginButton,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() {
                        _phoneOtpSent = false;
                        _phoneVerificationId = null;
                        _otpController.clear();
                      }),
                      child: Text(
                        l10n.locale == AppLocale.id
                            ? 'Ganti no. telepon'
                            : 'Change phone number',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 48),
                // Belum Punya Akun...? Daftar – tengah, Daftar diklik buka pilihan Penumpang/Driver
                Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.locale == AppLocale.id
                            ? 'Belum Punya Akun...? '
                            : "Don't have an account...? ",
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 15,
                        ),
                      ),
                      GestureDetector(
                        onTap: _onRegister,
                        child: Text(
                          l10n.register,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  final AppLocale current;
  final ValueChanged<AppLocale> onSelected;

  const _LanguageSelector({required this.current, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopupMenuButton<AppLocale>(
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      itemBuilder: (_) => [
        const PopupMenuItem(value: AppLocale.id, child: Text('Indonesia')),
        const PopupMenuItem(value: AppLocale.en, child: Text('English')),
      ],
      onSelected: onSelected,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Language',
            style: TextStyle(color: colorScheme.primary, fontSize: 14),
          ),
          const SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down, color: colorScheme.primary, size: 20),
        ],
      ),
    );
  }
}

class _LogoSection extends StatelessWidget {
  const _LogoSection();

  static const _logoAsset = 'assets/images/logo_traka.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      _logoAsset,
      height: 140,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.image_not_supported_outlined,
        size: 56,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _UnderlineTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _UnderlineTextField({
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        hintText: hint,
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
        prefixIcon: Icon(
          prefixIcon,
          size: 22,
          color: colorScheme.onSurfaceVariant,
        ),
        suffixIcon: suffixIcon,
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: colorScheme.error),
        ),
      ),
    );
  }
}

class _RegisterTypeTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _RegisterTypeTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 24, color: colorScheme.primary),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
