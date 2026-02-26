import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'driver_screen.dart';
import 'penumpang_screen.dart';

import '../l10n/app_localizations.dart';
import '../services/account_deletion_service.dart';
import '../services/device_security_service.dart';
import '../services/fcm_service.dart';
import '../theme/responsive.dart';
import '../services/fake_gps_overlay_service.dart';
import '../services/location_service.dart';
import 'privacy_screen.dart';
import 'terms_screen.dart';

/// Tipe pendaftaran: Penumpang atau Driver.
enum RegisterType { penumpang, driver }

class RegisterScreen extends StatefulWidget {
  final RegisterType type;

  const RegisterScreen({super.key, required this.type});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _agreeToTerms = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _isSendingCode = false;

  AppLocalizations get l10n => AppLocalizations(locale: AppLocale.id);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkDeviceAndBlockIfNeeded();
      if (!mounted) return;
      await _requestLocationPermissionForAll();
    });
  }

  /// Minta izin lokasi untuk semua pengguna (penumpang dan driver).
  Future<void> _requestLocationPermissionForAll() async {
    final hasPermission = await LocationService.requestPermissionPersistent(
      context,
    );
    if (!hasPermission && mounted) {
      // User tidak kasih izin, kembali ke login
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Izin lokasi diperlukan untuk menggunakan aplikasi Traka.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: Duration(seconds: 4),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  /// Cek device: jika perangkat sudah terdaftar (penumpang/driver), langsung ke halaman login dan tampilkan notifikasi.
  Future<void> _checkDeviceAndBlockIfNeeded() async {
    final role = widget.type == RegisterType.penumpang ? 'penumpang' : 'driver';
    final result = await DeviceSecurityService.checkRegistrationAllowed(role);
    if (!mounted) return;
    if (!result.allowed) {
      final message =
          result.message ??
          (l10n.locale == AppLocale.id
              ? 'Perangkat sudah digunakan oleh $role. Silakan login.'
              : 'Device already in use by $role. Please login.');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => LoginScreen(deviceAlreadyUsedMessage: message),
        ),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendVerificationCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Isi email terlebih dahulu'
                : 'Fill email first',
          ),
        ),
      );
      return;
    }

    // Validasi format email
    if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Format email tidak valid'
                : 'Invalid email format',
          ),
        ),
      );
      return;
    }

    setState(() => _isSendingCode = true);

    try {
      // Panggil Callable Cloud Function (Admin SDK bypass Firestore rules)
      final callable = FirebaseFunctions.instance.httpsCallable(
        'requestVerificationCode',
      );
      await callable.call({'email': email.trim().toLowerCase()});

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Kode verifikasi telah dikirim ke email Anda. Cek inbox atau folder Spam.'
                : 'Verification code has been sent to your email. Check inbox or Spam folder.',
          ),
          duration: const Duration(seconds: 10),
          backgroundColor: Colors.green,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = e.message ?? e.toString();
      String errorMessage;
      switch (e.code) {
        case 'already-exists':
          errorMessage = l10n.locale == AppLocale.id
              ? 'Email Sudah Terdaftar...!!! gunakan email lainnya yang aktif'
              : 'Email Already Registered...!!! use another active email';
          break;
        case 'invalid-argument':
          errorMessage = msg;
          break;
        default:
          errorMessage = l10n.locale == AppLocale.id
              ? 'Gagal mengirim kode. Pastikan Cloud Functions sudah di-deploy (firebase deploy --only functions) dan koneksi internet stabil.'
              : 'Failed to send code. Ensure Cloud Functions are deployed (firebase deploy --only functions) and connection is stable.';
      }
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
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.locale == AppLocale.id
                ? 'Gagal mengirim kode. Cek: 1) firebase deploy --only functions, 2) Gmail App Password di functions, 3) koneksi internet.'
                : 'Failed to send code. Check: 1) firebase deploy --only functions, 2) Gmail App Password in functions, 3) internet connection.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSendingCode = false);
      }
    }
  }

  void _openTerms() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const TermsScreen()),
    );
  }

  void _openPrivacy() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const PrivacyScreen()),
    );
  }

  Future<bool?> _showCancelDeletionDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Akun dalam proses penghapusan'),
        content: const Text(
          'Akun ini sedang dalam proses penghapusan. Batalkan penghapusan dan login?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ya, batalkan & login'),
          ),
        ],
      ),
    );
  }

  Future<void> _onSubmit() async {
    if (!_agreeToTerms) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    bool success = false;
    String? errorMessage;

    try {
      final role = widget.type == RegisterType.penumpang
          ? 'penumpang'
          : 'driver';
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final code = _codeController.text.trim();
      final name = _nameController.text.trim();

      // Cek device + lokasi paralel agar lebih cepat (izin lokasi sudah diminta di initState)
      final securityFuture = DeviceSecurityService.checkRegistrationAllowed(role);
      final locationFuture = LocationService.getDriverLocationResult();
      final codeFuture = code.isEmpty
          ? null
          : FirebaseFirestore.instance
              .collection('verification_codes')
              .doc(email)
              .get();

      final securityResult = await securityFuture;
      if (!securityResult.allowed) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              securityResult.message ?? 'Registrasi tidak diperbolehkan.',
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

      // Langkah 1: Verifikasi kode
      if (code.isEmpty) {
        throw Exception(
          l10n.locale == AppLocale.id
              ? 'Kode verifikasi wajib diisi'
              : 'Verification code is required',
        );
      }

      final codeDoc = await codeFuture!;
      if (!codeDoc.exists) {
        throw Exception(
          l10n.locale == AppLocale.id
              ? 'Kode verifikasi tidak ditemukan. Silakan kirim ulang kode.'
              : 'Verification code not found. Please resend code.',
        );
      }

      final codeData = codeDoc.data()!;
      final savedCode = codeData['code'] as String;
      final expiresAt = (codeData['expiresAt'] as Timestamp).toDate();

      if (DateTime.now().isAfter(expiresAt)) {
        throw Exception(
          l10n.locale == AppLocale.id
              ? 'Kode verifikasi sudah kedaluwarsa. Silakan kirim ulang.'
              : 'Verification code expired. Please resend.',
        );
      }

      if (code != savedCode) {
        throw Exception(
          l10n.locale == AppLocale.id
              ? 'Kode verifikasi tidak sesuai'
              : 'Verification code does not match',
        );
      }

      // Untuk SEMUA pengguna: cek lokasi harus di Indonesia, deteksi Fake GPS
      String? userRegion;
      double? userLat;
      double? userLng;

      final locationResult = await locationFuture;
      // Gagal memperoleh lokasi atau Fake GPS terdeteksi
      if (locationResult.errorMessage != null) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        if (locationResult.isFakeGpsDetected) {
          FakeGpsOverlayService.showOverlay();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                locationResult.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              duration: const Duration(seconds: 5),
            ),
          );
        }
        return;
      }
      // Lokasi di luar Indonesia
      if (!locationResult.isInIndonesia) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n.trakaIndonesiaOnly,
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
      userRegion = locationResult.region ?? locationResult.country;
      userLat = locationResult.latitude;
      userLng = locationResult.longitude;

      // Langkah 2: Buat akun Firebase Auth
      UserCredential? userCredential;
      try {
        userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
      } on FirebaseAuthException catch (authErr) {
        if (authErr.code == 'email-already-in-use') {
          final existingUser = await AccountDeletionService.findUserByEmail(email);
          if (existingUser != null &&
              existingUser.exists &&
              AccountDeletionService.isDeleted(existingUser.data())) {
            if (!mounted) return;
            final confirm = await _showCancelDeletionDialog();
            if (!mounted || confirm != true) {
              setState(() => _isLoading = false);
              return;
            }
            userCredential = await FirebaseAuth.instance
                .signInWithEmailAndPassword(email: email, password: password);
            final uid = userCredential.user!.uid;
            await AccountDeletionService.cancelAccountDeletion(uid);
            await DeviceSecurityService.recordRegistration(uid, role);
            if (!mounted) return;
            setState(() => _isLoading = false);
            FcmService.saveTokenForUser(uid);
            if (role == 'penumpang') {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(builder: (_) => const PenumpangScreen()),
                (route) => false,
              );
            } else {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute<void>(builder: (_) => const DriverScreen()),
                (route) => false,
              );
            }
            return;
          }
        }
        rethrow;
      }
      final uid = userCredential.user!.uid;

      // Langkah 3: Simpan data ke Firestore (tanpa foto wajah - dilengkapi nanti saat verifikasi)
      final Map<String, dynamic> userData = {
        'role': role,
        'email': email,
        'displayName': name,
        'photoUrl': '',
        'faceVerificationUrl': '',
        'faceVerificationPool': [],
        'deviceId': '', // Diset saat login pertama.
        'verificationStatus': 'pending', // Dilengkapi saat user lengkapi data verifikasi.
        'createdAt': FieldValue.serverTimestamp(),
      };
      // Untuk SEMUA pengguna: simpan region/provinsi, kabupaten, dan koordinat lokasi
      if (userRegion != null) userData['region'] = userRegion;
      final userKabupaten = locationResult.kabupaten;
      if (userKabupaten != null && userKabupaten.isNotEmpty) {
        userData['kabupaten'] = userKabupaten;
      }
      if (userLat != null) userData['latitude'] = userLat;
      if (userLng != null) userData['longitude'] = userLng;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set(userData);

      // Langkah 5 & 6: Hapus kode verifikasi + catat registrasi - paralel
      try {
        await Future.wait([
          FirebaseFirestore.instance
              .collection('verification_codes')
              .doc(email)
              .delete(),
          DeviceSecurityService.recordRegistration(uid, role),
        ]);
      } catch (_) {}

      success = true;
    } on FirebaseAuthException catch (e) {
      errorMessage =
          e.message ??
          (l10n.locale == AppLocale.id
              ? 'Gagal membuat akun'
              : 'Failed to create account');
      if (e.code == 'email-already-in-use') {
        errorMessage = l10n.locale == AppLocale.id
            ? 'Email sudah terdaftar'
            : 'Email already registered';
      } else if (e.code == 'weak-password') {
        errorMessage = l10n.passwordRequirement;
      }
    } catch (e) {
      errorMessage = e.toString().replaceAll('Exception: ', '');
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.registerSuccess),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage ?? l10n.registerFailure),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) {
      return l10n.locale == AppLocale.id
          ? 'Kata sandi wajib diisi'
          : 'Password is required';
    }
    if (v.length < 8) return l10n.passwordRequirement;
    if (!RegExp(r'[0-9]').hasMatch(v)) return l10n.passwordRequirement;
    return null;
  }

  String? _validateConfirmPassword(String? v) {
    if (v == null || v.isEmpty) {
      return l10n.locale == AppLocale.id
          ? 'Konfirmasi sandi wajib diisi'
          : 'Confirm password is required';
    }
    if (v != _passwordController.text) {
      return l10n.locale == AppLocale.id
          ? 'Konfirmasi sandi tidak sama'
          : 'Password confirmation does not match';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.type == RegisterType.penumpang
        ? '${l10n.penumpang} – Pendaftaran'
        : '${l10n.driver} – Pendaftaran';

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: context.responsive.horizontalPadding),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: context.responsive.spacing(16)),
                _RegisterUnderlineField(
                  controller: _nameController,
                  hint: l10n.nameHint,
                  icon: Icons.person_outline,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l10n.locale == AppLocale.id
                          ? 'Nama wajib diisi'
                          : 'Name is required';
                    }
                    return null;
                  },
                ),
                SizedBox(height: context.responsive.spacing(20)),
                _RegisterUnderlineField(
                  controller: _emailController,
                  hint: l10n.emailHintRegister,
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l10n.locale == AppLocale.id
                          ? 'Email wajib diisi'
                          : 'Email is required';
                    }
                    if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w+$').hasMatch(v)) {
                      return l10n.locale == AppLocale.id
                          ? 'Format email tidak valid'
                          : 'Invalid email format';
                    }
                    return null;
                  },
                ),
                SizedBox(height: context.responsive.spacing(20)),
                _RegisterUnderlineField(
                  controller: _codeController,
                  hint: l10n.verificationCodeHint,
                  icon: Icons.shield_outlined,
                  suffix: _isSendingCode
                      ? const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: Icon(
                            Icons.refresh,
                            color: Theme.of(context).colorScheme.primary,
                            size: 22,
                          ),
                          onPressed: _sendVerificationCode,
                        ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l10n.locale == AppLocale.id
                          ? 'Kode verifikasi wajib diisi'
                          : 'Verification code is required';
                    }
                    return null;
                  },
                ),
                SizedBox(height: context.responsive.spacing(20)),
                _RegisterUnderlineField(
                  controller: _passwordController,
                  hint: l10n.passwordHintRegister,
                  icon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  suffix: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: _validatePassword,
                ),
                const SizedBox(height: 20),
                _RegisterUnderlineField(
                  controller: _confirmPasswordController,
                  hint: l10n.confirmPasswordHint,
                  icon: Icons.lock_outline,
                  obscureText: _obscureConfirm,
                  suffix: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  validator: _validateConfirmPassword,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.passwordRequirement,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 24),
                // Tombol Ajukan – hijau bila agree, abu-abu bila belum
                FilledButton(
                  onPressed: _agreeToTerms && !_isLoading ? _onSubmit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _agreeToTerms
                        ? const Color(0xFF22C55E) // Hijau saat setuju terms
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          l10n.submitButton,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: 16),
                // Checkbox + Terms & Privacy (klikabel)
                _TermsCheckbox(
                  value: _agreeToTerms,
                  onChanged: (v) => setState(() => _agreeToTerms = v ?? false),
                  onTermsTap: _openTerms,
                  onPrivacyTap: _openPrivacy,
                  label: l10n.agreeTerms,
                  termsLabel: l10n.termsOfService,
                  privacyLabel: l10n.privacyPolicy,
                ),
                const SizedBox(height: 32),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(l10n.backToLogin),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    side: BorderSide(color: Theme.of(context).colorScheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
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

class _RegisterUnderlineField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _RegisterUnderlineField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffix,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
        prefixIcon: Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
        suffixIcon: suffix,
        border: UnderlineInputBorder(
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red),
        ),
      ),
    );
  }
}

class _TermsCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onTermsTap;
  final VoidCallback onPrivacyTap;
  final String label;
  final String termsLabel;
  final String privacyLabel;

  const _TermsCheckbox({
    required this.value,
    required this.onChanged,
    required this.onTermsTap,
    required this.onPrivacyTap,
    required this.label,
    required this.termsLabel,
    required this.privacyLabel,
  });

  @override
  Widget build(BuildContext context) {
    // "I agree with the " [Terms of Service] " and " [Privacy Policy] "."
    final parts = label.split(termsLabel);
    final beforeTerms = parts.isNotEmpty ? parts[0] : label;
    final afterTerms = parts.length > 1 ? parts[1] : '';
    final andParts = afterTerms.split(privacyLabel);
    final between = andParts.isNotEmpty ? andParts[0] : '';
    final afterPrivacy = andParts.length > 1 ? andParts[1] : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 24,
          width: 24,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: Theme.of(context).colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.start,
            runSpacing: 2,
            children: [
              Text(
                beforeTerms,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              GestureDetector(
                onTap: onTermsTap,
                child: Text(
                  termsLabel,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              Text(
                between,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              GestureDetector(
                onTap: onPrivacyTap,
                child: Text(
                  privacyLabel,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              Text(
                afterPrivacy,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
