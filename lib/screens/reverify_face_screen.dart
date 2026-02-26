import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../services/face_validation_service.dart';
import '../services/image_compression_service.dart';
import '../services/verification_log_service.dart';
import '../services/permission_service.dart';
import '../services/verification_service.dart';
import 'active_liveness_screen.dart';

/// Layar verifikasi wajah ulang: pengguna lama wajib verifikasi setiap 6 bulan.
/// User harus menyelesaikan sebelum bisa masuk ke home.
class ReverifyFaceScreen extends StatefulWidget {
  final String role;
  /// Dipanggil setelah verifikasi berhasil. Lalu navigasi ke home.
  final VoidCallback onSuccess;

  const ReverifyFaceScreen({
    super.key,
    required this.role,
    required this.onSuccess,
  });

  @override
  State<ReverifyFaceScreen> createState() => _ReverifyFaceScreenState();
}

class _ReverifyFaceScreenState extends State<ReverifyFaceScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _startVerification() async {
    final cameraOk = await PermissionService.requestCameraPermission(context);
    if (!cameraOk || !mounted) return;

    setState(() {
      _loading = false;
      _error = null;
    });

    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute<File>(builder: (_) => const ActiveLivenessScreen()),
    );

    if (file == null || file.path.isEmpty || !mounted) return;

    setState(() => _loading = true);

    final validationResult = await FaceValidationService.validateFacePhoto(file.path);
    if (!validationResult.isValid) {
      if (validationResult.isBlurError) {
        final action = await _showBlurErrorDialog(
          validationResult.errorMessage ?? 'Foto tidak memenuhi syarat.',
        );
        if (action == 'retry' && mounted) {
          setState(() => _loading = false);
          return _startVerification();
        }
        if (action == 'useAnyway' && mounted) {
          final skipBlurResult = await FaceValidationService.validateFacePhotoSkipBlur(file.path);
          if (!skipBlurResult.isValid) {
            if (mounted) {
              setState(() {
                _loading = false;
                _error = 'Foto harus wajah asli, bukan dari gambar atau layar. Silakan ambil foto ulang.';
              });
            }
            return;
          }
          // Lanjut upload (fall through)
        } else {
          if (mounted) setState(() => _loading = false);
          return;
        }
      } else {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = validationResult.errorMessage ?? 'Foto tidak memenuhi syarat.';
          });
        }
        return;
      }
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      if (!mounted) return;
      final compressedPath = await ImageCompressionService.compressForUpload(file.path);
      if (!mounted) return;
      final fileToUpload = File(compressedPath);

      final faceRef = FirebaseStorage.instance.ref().child(
        'users/${user.uid}/face_verification.jpg',
      );
      await faceRef.putFile(fileToUpload);
      if (!mounted) return;
      final faceUrl = await faceRef.getDownloadURL();
      if (!mounted) return;

      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'faceVerificationUrl': faceUrl,
        'faceVerificationLastVerifiedAt': FieldValue.serverTimestamp(),
      });

      VerificationLogService.log(
        userId: user.uid,
        success: true,
        source: VerificationLogSource.reverify,
      );

      if (!mounted) return;
      widget.onSuccess();
    } catch (e) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        VerificationLogService.log(
          userId: uid,
          success: false,
          source: VerificationLogSource.reverify,
          errorMessage: 'Gagal mengunggah: $e',
        );
      }
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Gagal mengunggah: $e';
        });
      }
    }
  }

  /// Returns 'retry' | 'useAnyway' | null (cancel)
  Future<String?> _showBlurErrorDialog(String message) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto tidak memenuhi syarat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            Text(
              'Foto kurang jelas. Anda bisa pakai foto ini jika wajah terdeteksi, atau ambil ulang untuk hasil lebih baik.',
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
                  child: const Text('Batal'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, 'useAnyway'),
                  child: const Text('Pakai foto ini'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'retry'),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.face_retouching_natural,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Verifikasi Wajah Diperlukan',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Untuk keamanan akun, verifikasi wajah dilakukan setiap ${VerificationService.faceReverifyMonths} bulan sekali.',
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Tahan wajah di lingkaran biru, lalu berkedip 1x atau tahan 2 detik.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              if (_error != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 32),
              if (_loading)
                const CircularProgressIndicator()
              else
                FilledButton.icon(
                  onPressed: _startVerification,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Verifikasi Sekarang'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
