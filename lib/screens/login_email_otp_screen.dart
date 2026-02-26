import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

/// Verifikasi OTP email untuk login pertama kali (nomor HP belum ditambahkan).
class LoginEmailOtpScreen extends StatefulWidget {
  final String email;

  const LoginEmailOtpScreen({super.key, required this.email});

  @override
  State<LoginEmailOtpScreen> createState() => _LoginEmailOtpScreenState();
}

class _LoginEmailOtpScreenState extends State<LoginEmailOtpScreen> {
  final _otpController = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('requestLoginVerificationCode');
      await callable.call({'email': widget.email});
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Kode verifikasi telah dikirim ke email. Cek inbox atau folder Spam.',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message ?? e.code;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gagal mengirim kode. Coba lagi.';
      });
    }
  }

  Future<bool> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Masukkan kode verifikasi');
      return false;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('verifyLoginVerificationCode');
      await callable.call({'code': code});
      if (!mounted) return false;
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return false;
      setState(() {
        _loading = false;
        _error = e.message ?? 'Kode salah atau kedaluwarsa.';
      });
      return false;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _loading = false;
        _error = 'Verifikasi gagal. Coba lagi.';
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifikasi email'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Text(
                'Login pertama kali',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Nomor HP belum ditambahkan. Verifikasi via email ${widget.email}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 32),
              if (!_otpSent) ...[
                FilledButton(
                  onPressed: _loading ? null : _sendOtp,
                  child: _loading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kirim kode verifikasi'),
                ),
              ] else ...[
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Kode verifikasi',
                    hintText: 'Masukkan 6 digit kode',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  onPressed: _loading ? null : () async {
                    final ok = await _verifyOtp();
                    if (ok && mounted) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: _loading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verifikasi'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading ? null : _sendOtp,
                  child: const Text('Kirim ulang kode'),
                ),
              ],
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
