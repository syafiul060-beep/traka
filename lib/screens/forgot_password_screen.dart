import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:face_verification/face_verification.dart';

import '../services/verification_log_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/device_service.dart';
import '../services/permission_service.dart';
import 'active_liveness_screen.dart';

/// Langkah alur lupa kata sandi.
enum _ForgotStep {
  chooseMethod,
  emailInput,
  emailOtpSent,
  phoneInput,
  phoneOtpSent,
  faceVerify,
  newPassword,
  done,
}

/// Lupa kata sandi: pilih email/telp → verifikasi OTP → verifikasi wajah → password baru.
/// Device ID dibaca dan di-update di Firestore jika berbeda setelah reset berhasil.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  _ForgotStep _step = _ForgotStep.chooseMethod;

  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _loading = false;
  String? _phoneVerificationId;
  String? _resetUid; // UID setelah sign in dengan phone (untuk face + update password)

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _phoneToE164(String phone) {
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) digits = '62${digits.substring(1)}';
    if (!digits.startsWith('62')) digits = '62$digits';
    return '+$digits';
  }

  Future<void> _onChooseEmail() async {
    setState(() => _step = _ForgotStep.emailInput);
  }

  Future<void> _onChoosePhone() async {
    setState(() => _step = _ForgotStep.phoneInput);
  }

  Future<void> _sendEmailOtp() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      _showSnack('Email wajib diisi', isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('requestForgotPasswordCode');
      await callable.call({'email': email});
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _ForgotStep.emailOtpSent;
      });
      _showSnack('Kode verifikasi telah dikirim ke email. Cek inbox atau folder Spam.');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final msg = e.message ?? e.code;
      if (e.code == 'not-found') {
        _showSnack('Email tidak terdaftar.', isError: true);
      } else {
        _showSnack(msg, isError: true);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      _showSnack('Gagal mengirim kode. Coba lagi.', isError: true);
    }
  }

  Future<void> _verifyEmailOtpAndContinue() async {
    final email = _emailController.text.trim().toLowerCase();
    final code = _otpController.text.trim();
    if (email.isEmpty || code.isEmpty) {
      _showSnack('Masukkan kode verifikasi dari email', isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('verifyForgotPasswordOtpAndGetToken');
      final result = await callable.call({'email': email, 'code': code});
      final customToken = result.data['customToken'] as String?;
      if (customToken == null || customToken.isEmpty) throw Exception('Token tidak diterima');
      await FirebaseAuth.instance.signInWithCustomToken(customToken);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || !mounted) {
        setState(() => _loading = false);
        _showSnack('Verifikasi gagal.', isError: true);
        return;
      }
      setState(() {
        _resetUid = uid;
        _step = _ForgotStep.faceVerify;
        _loading = false;
      });
      await _runFaceVerification(uid);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack(e.message ?? 'Kode salah atau kedaluwarsa.', isError: true);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      _showSnack('Kode salah atau kedaluwarsa. Coba lagi.', isError: true);
    }
  }

  Future<void> _sendPhoneOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      _showSnack('No. telepon wajib diisi', isError: true);
      return;
    }
    final phoneE164 = _phoneToE164(phone);
    setState(() => _loading = true);
    try {
      final q = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: phoneE164)
          .limit(1)
          .get();
      if (q.docs.isEmpty) {
        if (!mounted) return;
        setState(() => _loading = false);
        _showSnack('No. telepon tidak terdaftar.', isError: true);
        return;
      }
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneE164,
        verificationCompleted: (PhoneAuthCredential credential) async {
          if (!mounted) return;
          await _onPhoneVerified(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          setState(() => _loading = false);
          _showSnack(e.message ?? 'Verifikasi gagal.', isError: true);
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _phoneVerificationId = verificationId;
            _step = _ForgotStep.phoneOtpSent;
            _loading = false;
          });
          _showSnack('Kode verifikasi telah dikirim ke $phoneE164');
        },
        codeAutoRetrievalTimeout: (_) {},
      );
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _showSnack('Gagal. Coba lagi.', isError: true);
    }
  }

  Future<void> _onPhoneVerified(PhoneAuthCredential credential) async {
    try {
      final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
      final uid = userCredential.user?.uid;
      if (uid == null || !mounted) return;
      setState(() {
        _resetUid = uid;
        _step = _ForgotStep.faceVerify;
        _loading = false;
      });
      await _runFaceVerification(uid);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('No. telepon belum terhubung ke akun. Gunakan reset via email.', isError: true);
    }
  }

  Future<void> _verifyOtpAndContinue() async {
    final code = _otpController.text.trim();
    if (code.isEmpty || _phoneVerificationId == null) {
      _showSnack('Masukkan kode verifikasi dari SMS', isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _phoneVerificationId!,
        smsCode: code,
      );
      await _onPhoneVerified(credential);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      _showSnack('Kode salah atau kedaluwarsa. Coba lagi.', isError: true);
    }
  }

  Future<void> _runFaceVerification(String uid) async {
    File? tempStored;
    try {
      final ref = FirebaseStorage.instance.ref().child('users/$uid/face_verification.jpg');
      final bytes = await ref.getData();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) _showSnack('Data wajah tidak ditemukan.', isError: true);
        return;
      }
      final tempDir = await getTemporaryDirectory();
      tempStored = File('${tempDir.path}/reset_verify_$uid.jpg');
      await tempStored.writeAsBytes(bytes);
      await FaceVerification.instance.registerFromImagePath(
        id: uid,
        imagePath: tempStored.path,
        imageId: 'reset_verify',
      );
      if (!mounted) return;
      final cameraOk = await PermissionService.requestCameraPermission(context);
      if (!cameraOk || !mounted) {
        _showSnack('Izin kamera diperlukan untuk verifikasi wajah.', isError: true);
        return;
      }
      final file = await Navigator.of(context).push<File>(
        MaterialPageRoute<File>(builder: (_) => const ActiveLivenessScreen()),
      );
      if (file == null || file.path.isEmpty) {
        if (mounted) _showSnack('Verifikasi wajah dibatalkan.', isError: true);
        return;
      }
      final matchId = await FaceVerification.instance.verifyFromImagePath(
        imagePath: file.path,
        threshold: 0.7,
        staffId: uid,
      );
      try {
        FaceVerification.instance.deleteRecord(uid);
      } catch (_) {}
      final verified = matchId == uid;
      VerificationLogService.log(
        userId: uid,
        success: verified,
        source: VerificationLogSource.forgotPassword,
        errorMessage: verified ? null : 'Wajah tidak cocok.',
      );
      if (verified && mounted) {
        setState(() => _step = _ForgotStep.newPassword);
      } else if (mounted) {
        _showSnack('Wajah tidak cocok. Silakan coba lagi.', isError: true);
      }
    } catch (e) {
      VerificationLogService.log(
        userId: uid,
        success: false,
        source: VerificationLogSource.forgotPassword,
        errorMessage: 'Verifikasi wajah gagal: $e',
      );
      if (mounted) _showSnack('Verifikasi wajah gagal.', isError: true);
    } finally {
      try {
        tempStored?.deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _saveNewPassword() async {
    final newPass = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    if (newPass.length < 8) {
      _showSnack('Kata sandi minimal 8 karakter.', isError: true);
      return;
    }
    if (!RegExp(r'\d').hasMatch(newPass)) {
      _showSnack('Kata sandi harus mengandung angka.', isError: true);
      return;
    }
    if (newPass != confirm) {
      _showSnack('Konfirmasi kata sandi tidak sama.', isError: true);
      return;
    }
    final uid = _resetUid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showSnack('Sesi habis. Mulai dari awal.', isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in');
      await user.updatePassword(newPass);

      final currentDeviceId = await DeviceService.getDeviceId();
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final storedDeviceId = userDoc.data()?['deviceId'] as String?;
      if (currentDeviceId != null &&
          currentDeviceId.isNotEmpty &&
          currentDeviceId != storedDeviceId) {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'deviceId': currentDeviceId,
          'deviceIdUpdatedAt': FieldValue.serverTimestamp(),
        });
      }

      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _step = _ForgotStep.done;
      });
      _showSnack('Kata sandi berhasil diubah. Silakan login dengan kata sandi baru.');
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _showSnack('Gagal menyimpan: ${e.toString()}', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lupa kata sandi'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(context.responsive.horizontalPadding),
          child: _buildStepContent(),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case _ForgotStep.chooseMethod:
        return _buildChooseMethod();
      case _ForgotStep.emailInput:
        return _buildEmailInput();
      case _ForgotStep.emailOtpSent:
        return _buildEmailOtpInput();
      case _ForgotStep.phoneInput:
        return _buildPhoneInput();
      case _ForgotStep.phoneOtpSent:
        return _buildPhoneOtpInput();
      case _ForgotStep.faceVerify:
        return _buildFaceVerifyPrompt();
      case _ForgotStep.newPassword:
        return _buildNewPasswordForm();
      case _ForgotStep.done:
        return _buildDone();
    }
  }

  Widget _buildChooseMethod() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(24)),
        Text(
          'Pilih metode verifikasi',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Gunakan email atau no. telepon (jika sudah ditambahkan ke akun).',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14),
        ),
        SizedBox(height: context.responsive.spacing(24)),
        ListTile(
          leading: const Icon(Icons.email_outlined),
          title: const Text('Email'),
          subtitle: const Text('Kode OTP dikirim ke email, lalu verifikasi wajah dan atur kata sandi baru'),
          onTap: _onChooseEmail,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: const Icon(Icons.phone_android_outlined),
          title: const Text('No. telepon'),
          subtitle: const Text('Kode OTP via SMS (seperti saat tambah no. telepon), lalu verifikasi wajah dan atur kata sandi baru'),
          onTap: _onChoosePhone,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ],
    );
  }

  Widget _buildEmailInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(16)),
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'contoh@email.com',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
        ),
        SizedBox(height: context.responsive.spacing(24)),
        FilledButton(
          onPressed: _loading ? null : _sendEmailOtp,
          child: _loading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Kirim kode'),
        ),
      ],
    );
  }

  Widget _buildEmailOtpInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(16)),
        Text(
          'Masukkan kode verifikasi yang dikirim ke ${_emailController.text.trim().isEmpty ? "email Anda" : _emailController.text.trim()}',
          style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _otpController,
          decoration: const InputDecoration(
            labelText: 'Kode verifikasi (6 digit)',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        SizedBox(height: context.responsive.spacing(24)),
        FilledButton(
          onPressed: _loading ? null : _verifyEmailOtpAndContinue,
          child: _loading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verifikasi'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _step = _ForgotStep.emailInput;
            _otpController.clear();
          }),
          child: const Text('Ganti email'),
        ),
      ],
    );
  }

  Widget _buildPhoneInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(16)),
        TextField(
          controller: _phoneController,
          decoration: const InputDecoration(
            labelText: 'No. telepon',
            hintText: '08123456789',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
          keyboardType: TextInputType.phone,
        ),
        SizedBox(height: context.responsive.spacing(24)),
        FilledButton(
          onPressed: _loading ? null : _sendPhoneOtp,
          child: _loading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Kirim kode SMS'),
        ),
      ],
    );
  }

  Widget _buildPhoneOtpInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(16)),
        TextField(
          controller: _otpController,
          decoration: const InputDecoration(
            labelText: 'Kode verifikasi (6 digit)',
            prefixIcon: Icon(Icons.sms_outlined),
          ),
          keyboardType: TextInputType.number,
          maxLength: 6,
        ),
        SizedBox(height: context.responsive.spacing(24)),
        FilledButton(
          onPressed: _loading ? null : _verifyOtpAndContinue,
          child: _loading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Verifikasi'),
        ),
        TextButton(
          onPressed: () => setState(() {
            _step = _ForgotStep.phoneInput;
            _phoneVerificationId = null;
            _otpController.clear();
          }),
          child: const Text('Ganti no. telepon'),
        ),
      ],
    );
  }

  Widget _buildFaceVerifyPrompt() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(24)),
        const Center(
          child: CircularProgressIndicator(),
        ),
        const SizedBox(height: 16),
        const Center(
          child: Text('Membuka verifikasi wajah...'),
        ),
      ],
    );
  }

  Widget _buildNewPasswordForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: context.responsive.spacing(16)),
        Text(
          'Kata sandi baru',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPasswordController,
          decoration: const InputDecoration(
            labelText: 'Kata sandi baru',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          obscureText: true,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          decoration: const InputDecoration(
            labelText: 'Konfirmasi kata sandi baru',
            prefixIcon: Icon(Icons.lock_outline),
          ),
          obscureText: true,
          textInputAction: TextInputAction.done,
        ),
        const SizedBox(height: 8),
        Text(
          'Minimal 8 karakter, harus mengandung angka.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        SizedBox(height: context.responsive.spacing(24)),
        FilledButton(
          onPressed: _loading ? null : _saveNewPassword,
          child: _loading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Simpan'),
        ),
      ],
    );
  }

  Widget _buildDone() {
    return Column(
      children: [
        SizedBox(height: context.responsive.spacing(24)),
        Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade700),
        const SizedBox(height: 16),
        const Text(
          'Kata sandi berhasil diubah. Silakan login dengan kata sandi baru.',
          textAlign: TextAlign.center,
        ),
        SizedBox(height: context.responsive.spacing(24)),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kembali ke login'),
        ),
      ],
    );
  }
}
