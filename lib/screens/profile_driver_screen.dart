import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'active_liveness_screen.dart';
import '../services/face_validation_service.dart';
import '../services/verification_log_service.dart';
import '../services/permission_service.dart';
import '../services/ocr_preprocess_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../config/indonesia_config.dart';
import '../services/account_deletion_service.dart';
import '../services/driver_status_service.dart';
import '../services/image_compression_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../services/stnk_scan_service.dart';
import '../services/driver_earnings_service.dart';
import '../services/rating_service.dart';
import '../services/route_persistence_service.dart';
import '../widgets/admin_contact_widget.dart';
import '../widgets/theme_toggle_widget.dart';
import '../widgets/app_version_title.dart';
import '../widgets/shimmer_loading.dart';
import 'data_kendaraan_screen.dart';
import 'login_screen.dart';
import 'payment_history_screen.dart';
import 'promo_list_screen.dart';

/// Halaman profil khusus driver (tanpa nomor telepon dan login sidik jari/wajah).
class ProfileDriverScreen extends StatefulWidget {
  const ProfileDriverScreen({super.key});

  @override
  State<ProfileDriverScreen> createState() => _ProfileDriverScreenState();
}

class _ProfileDriverScreenState extends State<ProfileDriverScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  DocumentSnapshot<Map<String, dynamic>>? _userDoc;
  bool _loading = true;
  bool _isCheckingFace = false;
  File? _photoFile;
  final _nameController = TextEditingController();

  static const _daysPhotoLock = 30;

  Future<(double?, int)>? _cachedRatingFuture;
  Future<(double?, int)> get _driverRatingFuture {
    _cachedRatingFuture ??= () async {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return (null, 0);
      final avg = await RatingService.getDriverAverageRating(uid);
      final count = await RatingService.getDriverReviewCount(uid);
      return (avg, count);
    }();
    return _cachedRatingFuture!;
  }

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (mounted) {
        setState(() {
          _userDoc = doc;
          _loading = false;
          if (doc.exists && doc.data() != null) {
            final d = doc.data()!;
            _nameController.text = (d['displayName'] as String?) ?? '';
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> get _userData => _userDoc?.data() ?? <String, dynamic>{};

  /// Driver sudah isi verifikasi SIM (nama + nomor SIM tersimpan).
  bool get _isDriverVerified {
    return _userData['driverSIMVerifiedAt'] != null ||
        _userData['driverSIMNomorHash'] != null;
  }

  /// Data kendaraan sudah diisi (plat/merek/type tersimpan di users).
  bool get _isDataKendaraanFilled {
    return _userData['vehiclePlat'] != null ||
        _userData['vehicleUpdatedAt'] != null;
  }

  /// Email & No.Telp dianggap lengkap jika no. telepon sudah ditambahkan (email selalu ada dari registrasi).
  bool get _isEmailDanTelpFilled {
    final String phone = ((_userData['phoneNumber'] as String?) ?? '').trim();
    return phone.isNotEmpty;
  }

  /// Semua menu verifikasi sudah lengkap: Data Kendaraan + Verifikasi Driver + Email & No.Telp.
  bool get _isAllProfileVerified =>
      _isDataKendaraanFilled && _isDriverVerified && _isEmailDanTelpFilled;

  int get _verificationCompleteCount =>
      (_isDataKendaraanFilled ? 1 : 0) +
      (_isDriverVerified ? 1 : 0) +
      (_isEmailDanTelpFilled ? 1 : 0);

  DateTime? _timestamp(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    return null;
  }

  bool _canChangePhoto() {
    final updatedAt = _timestamp(_userData['photoUpdatedAt']);
    if (updatedAt == null) return true;
    return DateTime.now().difference(updatedAt).inDays >= _daysPhotoLock;
  }

  int? _daysUntilPhotoChange() {
    final updatedAt = _timestamp(_userData['photoUpdatedAt']);
    if (updatedAt == null) return null;
    final days = _daysPhotoLock - DateTime.now().difference(updatedAt).inDays;
    return days > 0 ? days : null;
  }

  Future<void> _pickAndVerifyPhoto() async {
    if (!_canChangePhoto()) return;
    final cameraOk = await PermissionService.requestCameraPermission(context);
    if (!cameraOk || !mounted) return;

    setState(() => _isCheckingFace = true);
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute<File>(builder: (_) => const ActiveLivenessScreen()),
    );
    if (!mounted) return;
    setState(() => _isCheckingFace = false);

    if (file == null || file.path.isEmpty) return;

    final validationResult = await FaceValidationService.validateFacePhoto(file.path);
    if (!validationResult.isValid) {
      final action = await _showFaceValidationErrorDialog(
        validationResult.errorMessage ?? 'Foto tidak memenuhi syarat.',
        isBlurError: validationResult.isBlurError,
      );
      if (action == FaceValidationDialogAction.retry && mounted) return _pickAndVerifyPhoto();
      if (action == FaceValidationDialogAction.useAnyway && mounted) {
        final skipBlurResult = await FaceValidationService.validateFacePhotoSkipBlur(file.path);
        if (!skipBlurResult.isValid) {
          final retry = await _showFaceValidationErrorDialog(
            'Foto harus wajah asli, bukan dari gambar atau layar. Silakan ambil foto ulang.',
            isBlurError: false,
          );
          if (retry == FaceValidationDialogAction.retry && mounted) return _pickAndVerifyPhoto();
          return;
        }
        setState(() => _photoFile = file);
        await _uploadPhoto();
      }
      return;
    }

    setState(() => _photoFile = file);
    await _uploadPhoto();
  }

  Future<FaceValidationDialogAction?> _showFaceValidationErrorDialog(
    String message, {
    bool isBlurError = false,
  }) async {
    return showDialog<FaceValidationDialogAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Foto tidak memenuhi syarat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            if (isBlurError) ...[
              const SizedBox(height: 12),
              Text(
                'Foto kurang jelas. Anda bisa pakai foto ini jika wajah terdeteksi, atau ambil ulang untuk hasil lebih baik.',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
                  onPressed: () => Navigator.pop(ctx, FaceValidationDialogAction.cancel),
                  child: const Text('Batal'),
                ),
                if (isBlurError)
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, FaceValidationDialogAction.useAnyway),
                    child: const Text('Pakai foto ini'),
                  ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, FaceValidationDialogAction.retry),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadPhoto() async {
    final user = _auth.currentUser;
    final file = _photoFile;
    if (user == null || file == null) return;
    try {
      final compressedPath = await ImageCompressionService.compressForUpload(file.path);
      final fileToUpload = File(compressedPath);
      final photoRef = FirebaseStorage.instance.ref().child(
        'users/${user.uid}/photo.jpg',
      );
      await photoRef.putFile(fileToUpload);
      final photoUrl = await photoRef.getDownloadURL();
      final faceRef = FirebaseStorage.instance.ref().child(
        'users/${user.uid}/face_verification.jpg',
      );
      await faceRef.putFile(fileToUpload);
      final faceUrl = await faceRef.getDownloadURL();
      final updates = <String, dynamic>{
        'photoUrl': photoUrl,
        'photoUpdatedAt': FieldValue.serverTimestamp(),
        'faceVerificationUrl': faceUrl,
        'faceVerificationLastVerifiedAt': FieldValue.serverTimestamp(),
      };
      await _firestore.collection('users').doc(user.uid).update(updates);
      VerificationLogService.log(
        userId: user.uid,
        success: true,
        source: VerificationLogSource.profileDriver,
      );
      if (mounted) setState(() => _photoFile = null);
      await _loadUser();
      if (mounted) _showSnackBar('Foto profil berhasil diubah.');
    } catch (e) {
      VerificationLogService.log(
        userId: user.uid,
        success: false,
        source: VerificationLogSource.profileDriver,
        errorMessage: 'Gagal mengunggah foto: $e',
      );
      if (mounted) _showSnackBar('Gagal mengunggah foto: $e', isError: true);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final oldC = TextEditingController();
    final newC = TextEditingController();
    final confirmC = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ganti Password'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: oldC,
                decoration: const InputDecoration(
                  labelText: 'Password lama',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newC,
                decoration: const InputDecoration(
                  labelText: 'Password baru',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmC,
                decoration: const InputDecoration(
                  labelText: 'Ulangi password baru',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              final old = oldC.text;
              final newP = newC.text;
              final confirm = confirmC.text;
              if (newP.length < 8) {
                _showSnackBar(
                  'Password baru minimal 8 karakter.',
                  isError: true,
                );
                return;
              }
              if (newP != confirm) {
                _showSnackBar('Password tidak sama.', isError: true);
                return;
              }
              Navigator.pop(ctx);
              final user = _auth.currentUser;
              if (user == null) return;
              try {
                final cred = EmailAuthProvider.credential(
                  email: user.email!,
                  password: old,
                );
                await user.reauthenticateWithCredential(cred);
                await user.updatePassword(newP);
                if (mounted) _showSnackBar('Password berhasil diubah.');
              } on FirebaseAuthException catch (e) {
                if (e.code == 'wrong-password' ||
                    e.code == 'invalid-credential') {
                  _showSnackBar('Password lama salah.', isError: true);
                } else {
                  _showSnackBar('Gagal: ${e.message}', isError: true);
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  /// Dialog ketika driver sudah terverifikasi (tidak perlu ubah lagi).
  Future<void> _showVerifikasiSudahBerhasilDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade700, size: 28),
            const SizedBox(width: 8),
            const Text(
              'Verifikasi Driver',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'Verifikasi Berhasil anda tidak perlu mengubah data verifikasi kembali. Silahkan hubungi Admin.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showEmailDanTelpSheet() {
    final user = _auth.currentUser;
    if (user == null) return;
    final String email = user.email ?? '';
    final String phone = ((_userData['phoneNumber'] as String?) ?? '').trim();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(context.responsive.radius(AppTheme.radiusLg)),
        ),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: EdgeInsets.all(context.responsive.spacing(AppTheme.spacingLg)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Email & No. Telepon',
                  style: TextStyle(
                    fontSize: context.responsive.fontSize(18),
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                SizedBox(height: context.responsive.spacing(8)),
                Text(
                  'Email untuk login. Ubah email via link verifikasi di inbox. No. telepon divalidasi lewat SMS OTP.',
                  style: TextStyle(
                    fontSize: context.responsive.fontSize(12),
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: context.responsive.spacing(20)),
                // Email — card rapi dengan ikon
                _buildContactRow(
                  ctx: ctx,
                  icon: Icons.email_outlined,
                  label: 'Email',
                  value: email.isEmpty ? '—' : email,
                  actionLabel: 'Ubah Email',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showUbahEmailDialog();
                  },
                ),
                SizedBox(height: context.responsive.spacing(16)),
                // No. Telepon — card rapi dengan ikon
                _buildContactRow(
                  ctx: ctx,
                  icon: Icons.phone_outlined,
                  label: 'No. Telepon',
                  value: phone.isEmpty ? 'Belum ditambahkan' : phone,
                  actionLabel: phone.isEmpty ? 'Tambah No. Telepon' : 'Ubah No. Telepon',
                  onTap: () {
                    Navigator.pop(ctx);
                    _showTeleponVerifikasiDialog();
                  },
                ),
                if (phone.isNotEmpty) ...[
                  SizedBox(height: context.responsive.spacing(8)),
                  Text(
                    'Login juga bisa menggunakan no. telepon + kode SMS.',
                    style: TextStyle(
                      fontSize: context.responsive.fontSize(11),
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                SizedBox(height: context.responsive.spacing(24)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactRow({
    required BuildContext ctx,
    required IconData icon,
    required String label,
    required String value,
    required String actionLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: EdgeInsets.all(context.responsive.spacing(AppTheme.spacingMd)),
      decoration: BoxDecoration(
        color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(context.responsive.radius(AppTheme.radiusSm)),
        border: Border.all(color: Theme.of(ctx).colorScheme.outline),
      ),
      child: Row(
        children: [
          Icon(icon, size: context.responsive.iconSize(24), color: AppTheme.primary),
          SizedBox(width: context.responsive.spacing(12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: context.responsive.fontSize(12),
                    fontWeight: FontWeight.w600,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: context.responsive.spacing(4)),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: context.responsive.fontSize(14),
                    color: Theme.of(ctx).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: Text(actionLabel, style: TextStyle(fontSize: context.responsive.fontSize(13))),
          ),
        ],
      ),
    );
  }

  Future<void> _showUbahEmailDialog() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final controller = TextEditingController(text: user.email);
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah Email'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Email baru',
              border: OutlineInputBorder(),
              hintText: 'contoh@email.com',
            ),
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email wajib diisi';
              if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w+$').hasMatch(v.trim())) {
                return 'Format email tidak valid';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final newEmail = controller.text.trim().toLowerCase();
              if (newEmail == user.email) {
                Navigator.pop(ctx);
                return;
              }
              Navigator.pop(ctx);
              try {
                await user.verifyBeforeUpdateEmail(newEmail);
                if (mounted) {
                  _showSnackBar(
                    'Link verifikasi telah dikirim ke $newEmail. Buka inbox (atau folder Spam) dan klik link untuk mengaktifkan email baru.',
                  );
                  _loadUser();
                }
              } on FirebaseAuthException catch (e) {
                if (mounted) {
                  _showSnackBar(
                    e.message ?? 'Gagal mengirim verifikasi email.',
                    isError: true,
                  );
                }
              }
            },
            child: const Text('Kirim link verifikasi'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTeleponVerifikasiDialog() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final String currentPhone = ((_userData['phoneNumber'] as String?) ?? '')
        .trim();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _TeleponVerifikasiDialog(
        currentUserId: user.uid,
        currentPhone: currentPhone,
        onSuccess: () {
          Navigator.pop(ctx);
          _loadUser();
          _showSnackBar(
            'No. telepon berhasil ditambahkan. Login bisa dengan email atau no. telepon.',
          );
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
  }

  Future<void> _showVerifikasiDriverDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Verifikasi Driver',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Langkah 1: Foto selfie untuk verifikasi wajah. Kamera depan akan terbuka. '
          'Tahan wajah di lingkaran biru, lalu berkedip 1x atau tahan 2 detik. Foto diambil otomatis.\n\n'
          'Langkah 2: Ambil foto SIM/Surat Izin Mengemudi untuk verifikasi. Foto akan digunakan untuk membaca nama dan nomor SIM.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _captureSelfieThenScanSIM();
            },
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
  }

  /// Langkah 1: Selfie (jika belum ada faceVerification). Langkah 2: Scan SIM.
  Future<void> _captureSelfieThenScanSIM() async {
    final hasFace = (_userData['faceVerificationUrl'] as String?)?.trim().isNotEmpty ?? false;
    if (!hasFace) {
      final ok = await _captureAndUploadSelfie();
      if (!mounted) return;
      if (!ok) return; // User batal atau gagal
    }
    if (!mounted) return;
    _scanSIM();
  }

  /// Ambil foto selfie via kamera depan: lingkaran biru, berkedip 1x atau tahan 2 detik.
  /// Langsung ke kamera (bukan galeri) untuk memastikan foto wajah asli.
  /// Returns true jika berhasil, false jika batal/gagal.
  Future<bool> _captureAndUploadSelfie() async {
    final cameraOk = await PermissionService.requestCameraPermission(context);
    if (!cameraOk || !mounted) return false;

    setState(() => _isCheckingFace = true);
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute<File>(builder: (_) => const ActiveLivenessScreen()),
    );
    if (!mounted) return false;
    setState(() => _isCheckingFace = false);

    if (file == null || file.path.isEmpty) return false;

    final validationResult = await FaceValidationService.validateFacePhoto(file.path);
    if (!validationResult.isValid) {
      final action = await _showFaceValidationErrorDialog(
        validationResult.errorMessage ?? 'Foto tidak memenuhi syarat.',
        isBlurError: validationResult.isBlurError,
      );
      if (action == FaceValidationDialogAction.retry && mounted) return _captureAndUploadSelfie();
      if (action == FaceValidationDialogAction.useAnyway && mounted) {
        final skipBlurResult = await FaceValidationService.validateFacePhotoSkipBlur(file.path);
        if (!skipBlurResult.isValid) {
          final retry = await _showFaceValidationErrorDialog(
            'Foto harus wajah asli, bukan dari gambar atau layar. Silakan ambil foto ulang.',
            isBlurError: false,
          );
          if (retry == FaceValidationDialogAction.retry && mounted) return _captureAndUploadSelfie();
          return false;
        }
        setState(() => _photoFile = file);
        await _uploadPhoto();
        if (!mounted) return false;
        _showSnackBar('Foto verifikasi wajah berhasil. Lanjut ambil foto SIM.');
        await _loadUser();
        return true;
      }
      return false;
    }

    setState(() => _photoFile = file);
    await _uploadPhoto();
    if (!mounted) return false;
    _showSnackBar('Foto verifikasi wajah berhasil. Lanjut ambil foto SIM.');
    await _loadUser();
    return true;
  }

  Future<void> _scanSIM() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100, // Kualitas maksimal untuk akurasi OCR
    );
    if (image == null || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Membaca SIM...'),
          ],
        ),
      ),
    );

    try {
      // OCR dengan preprocessing: coba original + preprocessed untuk akurasi lebih baik
      final ocrTexts = await OcrPreprocessService.runOcrVariants(image.path);

      if (!mounted) return;
      Navigator.pop(context); // Tutup loading dialog

      Map<String, String?>? extractedData;
      for (final text in ocrTexts) {
        extractedData = _extractSIMData(text);
        if (extractedData['nama'] != null && extractedData['nomorSIM'] != null) {
          break;
        }
      }

      if (extractedData == null ||
          extractedData['nama'] == null ||
          extractedData['nomorSIM'] == null) {
        if (mounted) {
          _showSnackBar(
            'Gagal membaca data SIM. Pastikan foto SIM jelas dan lengkap.',
            isError: true,
          );
        }
        return;
      }

      await _showSIMDataConfirmationDialog(
        extractedData['nama']!,
        extractedData['nomorSIM']!,
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Tutup loading dialog jika masih terbuka
        _showSnackBar('Gagal membaca SIM: $e', isError: true);
      }
    }
  }

  /// Ekstrak nama dan nomor SIM dari teks OCR. Mendukung koreksi OCR: O↔0, I/l↔1.
  Map<String, String?> _extractSIMData(String ocrText) {
    String? nama;
    String? nomorSIM;

    // Pattern untuk nomor SIM (format Indonesia: 12-16 digit)
    final simPattern = RegExp(r'\b\d{12,16}\b');
    var simMatch = simPattern.firstMatch(ocrText);
    if (simMatch != null) {
      nomorSIM = simMatch.group(0);
    } else {
      // Pola permissive untuk OCR error (O, I, l sebagai digit)
      final ocrSimPattern = RegExp(r'\b[0-9OIl]{12,16}\b');
      simMatch = ocrSimPattern.firstMatch(ocrText);
      if (simMatch != null) {
        nomorSIM = simMatch
            .group(0)!
            .replaceAll('O', '0')
            .replaceAll('I', '1')
            .replaceAll('l', '1');
      }
    }

    // Pattern untuk mencari nama (biasanya setelah kata kunci seperti "NAMA", "NAME", atau di baris tertentu)
    final lines = ocrText.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim().toUpperCase();

      // Cari baris yang mengandung "NAMA" atau "NAME"
      if (line.contains('NAMA') || line.contains('NAME')) {
        // Ambil baris berikutnya atau bagian setelah "NAMA"
        if (line.contains('NAMA') || line.contains('NAME')) {
          final parts = line.split(RegExp(r'NAMA|NAME'));
          if (parts.length > 1) {
            nama = parts[1].trim();
            if (nama.isEmpty && i + 1 < lines.length) {
              nama = lines[i + 1].trim();
            }
          } else if (i + 1 < lines.length) {
            nama = lines[i + 1].trim();
          }
        }
      }

      // Jika belum ditemukan, coba cari pola nama (huruf besar, minimal 3 kata)
      if (nama == null || nama.isEmpty) {
        final namePattern = RegExp(r'^[A-Z\s]{10,}$');
        if (namePattern.hasMatch(line) &&
            line.split(' ').length >= 2 &&
            !line.contains('SIM') &&
            !line.contains('DRIVER') &&
            !line.contains('LICENSE')) {
          nama = line;
        }
      }
    }

    // Jika masih belum ditemukan nama, ambil baris pertama yang panjang (kemungkinan nama)
    if ((nama == null || nama.isEmpty) && lines.isNotEmpty) {
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.length >= 10 &&
            trimmed.split(' ').length >= 2 &&
            !trimmed.contains(
              RegExp(r'\d{4,}'),
            ) && // Tidak mengandung banyak angka
            !trimmed.contains('SIM') &&
            !trimmed.contains('DRIVER')) {
          nama = trimmed;
          break;
        }
      }
    }

    return {'nama': nama, 'nomorSIM': nomorSIM};
  }

  Future<void> _showSIMDataConfirmationDialog(
    String nama,
    String nomorSIM,
  ) async {
    final namaController = TextEditingController(text: nama);
    final simController = TextEditingController(text: nomorSIM);
    bool dataSetuju = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'Data SIM yang Dibaca',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Periksa data di bawah. Anda dapat mengubah jika foto kabur/buram.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: namaController,
                  decoration: const InputDecoration(
                    labelText: 'Nama',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: simController,
                  decoration: const InputDecoration(
                    labelText: 'Nomor SIM',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 20),
                CheckboxListTile(
                  value: dataSetuju,
                  onChanged: (value) =>
                      setDialogState(() => dataSetuju = value ?? false),
                  title: const Text(
                    'Data sudah sesuai dan setuju',
                    style: TextStyle(fontSize: 14),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: dataSetuju
                  ? () async {
                      Navigator.pop(ctx);
                      await _saveSIMData(
                        namaController.text.trim(),
                        simController.text.trim(),
                      );
                    }
                  : null,
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  /// Hash nomor SIM dengan SHA-256
  String _hashNomorSIM(String nomorSIM) {
    final bytes = utf8.encode(nomorSIM.trim());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _saveSIMData(String nama, String nomorSIM) async {
    if (nama.isEmpty || nomorSIM.isEmpty) {
      _showSnackBar('Nama dan nomor SIM wajib diisi', isError: true);
      return;
    }

    final user = _auth.currentUser;
    if (user == null) return;

    final simHash = _hashNomorSIM(nomorSIM);

    try {
      // Cek apakah nomor SIM (hash) sudah dipakai oleh akun lain
      final querySnapshot = await _firestore
          .collection('users')
          .where('driverSIMNomorHash', isEqualTo: simHash)
          .limit(1)
          .get();

      final usedByOther = querySnapshot.docs.any((doc) => doc.id != user.uid);

      if (usedByOther) {
        if (mounted) {
          _showSnackBar(
            'Nomor sim sudah pernah dipakai di akun lain.',
            isError: true,
          );
        }
        return;
      }

      await _firestore.collection('users').doc(user.uid).update({
        'displayName': nama,
        'driverSIMNama': nama,
        'driverSIMNomorHash': simHash,
        'driverSIMVerifiedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() => _nameController.text = nama);
        _showSnackBar(
          'Data SIM berhasil disimpan. Nama profil telah diperbarui.',
        );
        _loadUser();
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Gagal menyimpan data SIM: $e', isError: true);
      }
    }
  }

  Future<void> _showDataKendaraanDialog() async {
    // Tampilkan keterangan dan tombol Ambil foto STNK dulu
    final shouldScan = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.directions_car, color: Theme.of(ctx).primaryColor),
            const SizedBox(width: 8),
            const Text('Data Kendaraan'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ambil Foto STNK, nomor polisi/plat kendaraan Anda harus jelas.',
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.camera_alt, size: 20),
            label: const Text('Ambil foto STNK'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    if (!mounted || shouldScan != true) return;

    // Buka kamera untuk scan STNK otomatis
    final scannedPlat = await StnkScanService.scanPlatFromCamera();
    if (!mounted) return;

    // Jika tidak scan foto (batal atau tidak terbaca), jangan tampilkan form - untuk keamanan
    if (scannedPlat == null || scannedPlat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Scan STNK diperlukan untuk mengisi data kendaraan. Silakan ambil foto STNK.',
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Cek apakah plat sudah dipakai driver lain
    final usedByOther = await _checkPlatUsedByOtherDriver(scannedPlat);
    if (!mounted) return;
    if (usedByOther) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mobil milik Driver lain. Silakan scan STNK kendaraan Anda.',
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return; // Jangan tampilkan form - driver harus scan STNK yang valid
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Nomor plat terdeteksi: $scannedPlat'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => DataKendaraanFormSheet(
            scrollController: scrollController,
            initialPlatFromScan: scannedPlat,
          ),
        ),
      ),
    );
    // Refresh profil agar status verifikasi data kendaraan langsung tampil
    if (mounted) _loadUser();
  }

  /// Cek apakah nomor plat sudah dipakai driver lain (bukan driver saat ini)
  Future<bool> _checkPlatUsedByOtherDriver(String plat) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    try {
      final platUpper = plat.trim().toUpperCase();
      final querySnapshot = await _firestore
          .collection('users')
          .where('vehiclePlat', isEqualTo: platUpper)
          .limit(1)
          .get();
      if (querySnapshot.docs.isNotEmpty) {
        return querySnapshot.docs.first.id != user.uid;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showHapusAkunDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus akun'),
        content: const Text(
          'Akun akan dijadwalkan penghapusan dalam 30 hari. Dalam masa tersebut Anda dapat batalkan dengan login kembali. Yakin ingin menghapus akun?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus akun'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await AccountDeletionService.scheduleAccountDeletion(user.uid, 'driver');
      await DriverStatusService.removeDriverStatus();
      await RoutePersistenceService.clear();
      await _auth.signOut();
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (mounted) _showSnackBar('Gagal menghapus akun: $e', isError: true);
    }
  }

  Future<void> _onLogout() async {
    final navigator = Navigator.of(context, rootNavigator: true);
    // JANGAN hapus deviceId saat logout - biarkan tersimpan di Firestore
    // Saat login di device baru, akan dicek apakah deviceId sama atau berbeda dengan device terakhir login
    // Jika berbeda → wajib verifikasi wajah → update deviceId ke yang baru
    try {
      await DriverStatusService.removeDriverStatus();
    } catch (_) {}
    try {
      await RoutePersistenceService.clear();
    } catch (_) {}
    try {
      await _auth.signOut();
    } catch (_) {}
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showSnackBar(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = _userData['photoUrl'] as String?;
    final daysPhoto = _daysUntilPhotoChange();

    return Scaffold(
      appBar: AppBar(
        title: const AppVersionTitle(),
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _onLogout),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: _loading
                ? const Center(child: ShimmerLoading())
                : SingleChildScrollView(
                  padding: EdgeInsets.all(context.responsive.spacing(AppTheme.spacingLg)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Dashboard pendapatan
                      FutureBuilder<Map<String, dynamic>>(
                        future: () async {
                          final uid = _auth.currentUser?.uid;
                          if (uid == null) return <String, dynamic>{};
                          final total = await DriverEarningsService.getTotalEarnings(uid);
                          final today = await DriverEarningsService.getTodayEarnings(uid);
                          final week = await DriverEarningsService.getWeekEarnings(uid);
                          final count = await DriverEarningsService.getCompletedTripCount(uid);
                          return <String, dynamic>{
                            'total': total,
                            'today': today,
                            'week': week,
                            'count': count,
                          };
                        }(),
                        builder: (context, snap) {
                          if (!snap.hasData) return const SizedBox.shrink();
                          final d = snap.data!;
                          final total = (d['total'] as num?)?.toDouble() ?? 0;
                          final today = (d['today'] as num?)?.toDouble() ?? 0;
                          final week = (d['week'] as num?)?.toDouble() ?? 0;
                          final count = (d['count'] as num?)?.toInt() ?? 0;
                          if (count == 0) return const SizedBox.shrink();
                          return Card(
                            margin: EdgeInsets.only(bottom: context.responsive.spacing(16)),
                            child: Padding(
                              padding: EdgeInsets.all(context.responsive.spacing(16)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.account_balance_wallet, color: Colors.green.shade700),
                                      SizedBox(width: context.responsive.spacing(8)),
                                      Text(
                                        'Pendapatan',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context).colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: context.responsive.spacing(12)),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Hari ini', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                          Text('Rp ${today.round()}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('Minggu ini', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                          Text('Rp ${week.round()}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: context.responsive.spacing(8)),
                                  Divider(),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Total (${count} perjalanan)', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                      Text('Rp ${total.round()}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Verifikasi: ${_verificationCompleteCount}/3 lengkap',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Layout horizontal: foto di kiri, nama dan rating di tengah, gambar admin di kanan
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Foto profil di sebelah kiri
                          GestureDetector(
                            onTap: _canChangePhoto() && !_isCheckingFace
                                ? _pickAndVerifyPhoto
                                : null,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 40, // Ukuran lebih kecil
                                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  backgroundImage:
                                      (photoUrl != null && photoUrl.isNotEmpty)
                                      ? CachedNetworkImageProvider(photoUrl)
                                      : null,
                                  child: (photoUrl == null || photoUrl.isEmpty)
                                      ? const Icon(Icons.person, size: 40)
                                      : null,
                                ),
                                if (_isCheckingFace)
                                  const CircularProgressIndicator(),
                                if (!_canChangePhoto() && !_isCheckingFace)
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Icon(
                                      Icons.lock,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      size: 20,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(width: context.responsive.spacing(16)),
                          // Nama dan rating di tengah
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Nama (dengan centang verifikasi jika semua lengkap) + tombol Platinum; nama bisa turun ke bawah jika panjang
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            _nameController.text.isNotEmpty
                                                ? _nameController.text
                                                : 'Nama Driver',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                          if (_isAllProfileVerified)
                                            const SizedBox(width: 4),
                                          if (_isAllProfileVerified)
                                            Icon(
                                              Icons.verified,
                                              size: 20,
                                              color: Colors.green.shade700,
                                            ),
                                        ],
                                      ),
                                    ),
                                    // Badge tier (Basic/Gold/Platinum)
                                    FutureBuilder<(double?, int)>(
                                      future: _driverRatingFuture,
                                          builder: (context, snap) {
                                            final avg = snap.data?.$1;
                                            final count = snap.data?.$2 ?? 0;
                                            final tier = RatingService.getDriverTierLabel(avg, count);
                                            Color tierColor;
                                            switch (tier) {
                                              case 'Platinum':
                                                tierColor = Colors.deepPurple;
                                                break;
                                              case 'Gold':
                                                tierColor = Colors.amber.shade700;
                                                break;
                                              default:
                                                tierColor = Colors.grey.shade600;
                                            }
                                            return Padding(
                                              padding: const EdgeInsets.only(left: 8, right: 8),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: tierColor,
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  tier,
                                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Rating bintang (5 bintang) + angka + jumlah ulasan
                                FutureBuilder<(double?, int)>(
                                  future: _driverRatingFuture,
                                  builder: (context, snap) {
                                    final avg = snap.data?.$1;
                                    final count = snap.data?.$2 ?? 0;
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ...List.generate(5, (index) {
                                          final starValue = index + 1.0;
                                          IconData icon;
                                          if (avg == null || avg < starValue - 0.5) {
                                            icon = Icons.star_border;
                                          } else if (avg < starValue) {
                                            icon = Icons.star_half;
                                          } else {
                                            icon = Icons.star;
                                          }
                                          return Icon(icon, color: Colors.amber.shade700, size: 20);
                                        }),
                                        if (avg != null || count > 0) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            avg != null
                                                ? '${avg.toStringAsFixed(1)}${count > 0 ? ' ($count ulasan)' : ''}'
                                                : count > 0
                                                    ? '($count ulasan)'
                                                    : '',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (daysPhoto != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Foto profil dapat diubah setelah $daysPhoto hari lagi.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ] else if (_canChangePhoto()) ...[
                        const SizedBox(height: 12),
                        // Garis dekoratif putih-biru bergantian dari ujung kiri sampai kanan (lebih besar)
                        Row(
                          children: List.generate(20, (index) {
                            return Expanded(
                              child: Container(
                                height:
                                    4, // Lebih besar dari sebelumnya (2 -> 4)
                                color: index % 2 == 0
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            );
                          }),
                        ),
                      ],
                      const SizedBox(height: 32), // Jarak antara garis dan menu
                      // Menu dengan efek 3D
                      Column(
                        children: [
                          // Baris pertama: Menu 1, 2, 3 sejajar
                          Row(
                            children: [
                              // Menu 1: Data Kendaraan (bercentang jika sudah isi, menu tetap berfungsi)
                              Expanded(
                                child: _buildMenuCard(
                                  title: 'Data Kendaraan',
                                  icon: Icons.directions_car,
                                  verified: _isDataKendaraanFilled,
                                  onTap: _showDataKendaraanDialog,
                                ),
                              ),
                              SizedBox(width: context.responsive.spacing(12)),
                              // Menu 2: Verifikasi Driver (bercentang jika sudah verifikasi)
                              Expanded(
                                child: _buildMenuCard(
                                  title: 'Verifikasi Driver',
                                  icon: Icons.person_add_alt_1,
                                  verified: _isDriverVerified,
                                  onTap: _isDriverVerified
                                      ? _showVerifikasiSudahBerhasilDialog
                                      : _showVerifikasiDriverDialog,
                                ),
                              ),
                              SizedBox(width: context.responsive.spacing(12)),
                              // Menu 3: Email & No.Telp (bercentang jika no.telp sudah ditambahkan)
                              Expanded(
                                child: _buildMenuCard(
                                  title: 'Email & No.Telp',
                                  icon: Icons.contact_phone,
                                  verified: _isEmailDanTelpFilled,
                                  onTap: _showEmailDanTelpSheet,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: context.responsive.spacing(12)),
                          // Baris kedua: Menu 4, 5
                          Row(
                            children: [
                              // Menu 4: Ubah Password
                              Expanded(
                                child: _buildMenuCard(
                                  title: 'Ubah Password',
                                  icon: Icons.lock_outline,
                                  onTap: _showChangePasswordDialog,
                                ),
                              ),
                              SizedBox(width: context.responsive.spacing(12)),
                              // Menu 5: Riwayat Pembayaran
                              Expanded(
                                child: _buildMenuCard(
                                  title: 'Riwayat Pembayaran',
                                  icon: Icons.receipt_long,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            const PaymentHistoryScreen(isDriver: true),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              SizedBox(width: context.responsive.spacing(12)),
                              Expanded(
                                child: _buildMenuCard(
                                  title: 'Info & Promo',
                                  icon: Icons.campaign_outlined,
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const PromoListScreen(role: 'driver'),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: context.responsive.spacing(12)),
                          Row(
                            children: [
                              Expanded(
                                child: _buildMenuCard(
                                  title: 'Hapus akun',
                                  icon: Icons.delete_outline,
                                  onTap: _showHapusAkunDialog,
                                ),
                              ),
                              SizedBox(width: context.responsive.spacing(12)),
                              const Expanded(child: SizedBox()),
                              SizedBox(width: context.responsive.spacing(12)),
                              const Expanded(child: SizedBox()),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
          ),
          // Toggle tema (kiri) + Gambar admin (kanan): fixed di bawah viewport
          if (!_loading)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const ThemeToggleWidget(),
                  const AdminContactWidget(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Widget untuk membuat menu card dengan efek 3D
  Widget _buildMenuCard({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    bool verified = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.responsive.radius(12)),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.responsive.spacing(12),
          vertical: context.responsive.spacing(16),
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(context.responsive.radius(12)),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 4),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
              spreadRadius: 0,
            ),
          ],
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5), width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: context.responsive.iconSize(32), color: Theme.of(context).colorScheme.primary),
                if (verified)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Icon(
                      Icons.verified,
                      size: 18,
                      color: Colors.green.shade700,
                    ),
                  ),
              ],
            ),
            SizedBox(height: context.responsive.spacing(8)),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: context.responsive.fontSize(12),
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog verifikasi no. telepon dengan Firebase OTP (SMS).
class _TeleponVerifikasiDialog extends StatefulWidget {
  const _TeleponVerifikasiDialog({
    required this.currentUserId,
    required this.currentPhone,
    required this.onSuccess,
    required this.onCancel,
  });

  final String currentUserId;
  final String currentPhone;
  final VoidCallback onSuccess;
  final VoidCallback onCancel;

  @override
  State<_TeleponVerifikasiDialog> createState() =>
      _TeleponVerifikasiDialogState();
}

class _TeleponVerifikasiDialogState extends State<_TeleponVerifikasiDialog> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _stepOtp = false;
  String? _verificationId;
  String _phoneE164 = '';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.currentPhone.isNotEmpty) {
      _phoneController.text = widget.currentPhone.replaceFirst(
        RegExp(r'^\+62'),
        '0',
      );
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String _toE164(String phone) {
    String digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) {
      digits = '62${digits.substring(1)}';
    } else if (!digits.startsWith('62'))
      digits = '62$digits';
    return '+$digits';
  }

  Future<bool> _isPhoneUsedByOtherUser(String phoneE164) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('phoneNumber', isEqualTo: phoneE164)
        .limit(2)
        .get();
    return snapshot.docs.any((doc) => doc.id != widget.currentUserId);
  }

  Future<void> _sendOtp() async {
    _error = null;
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'No. telepon wajib diisi');
      return;
    }
    _phoneE164 = _toE164(phone);
    if (_phoneE164.length < 10) {
      setState(() => _error = 'Format no. telepon tidak valid');
      return;
    }

    setState(() => _loading = true);
    final usedByOther = await _isPhoneUsedByOtherUser(_phoneE164);
    if (!mounted) return;
    if (usedByOther) {
      setState(() {
        _loading = false;
        _error = 'Nomor telepon sudah digunakan.';
      });
      return;
    }

    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: _phoneE164,
      verificationCompleted: (PhoneAuthCredential credential) async {
        if (!mounted) return;
        await _linkPhone(credential);
        setState(() => _loading = false);
        widget.onSuccess();
      },
      verificationFailed: (FirebaseAuthException e) {
        if (!mounted) return;
        String message = 'Verifikasi gagal. Coba lagi.';
        final code = e.code;
        final msg = (e.message ?? '').toLowerCase();
        if (code == 'missing-client-identifier' ||
            msg.contains('app identifier') ||
            msg.contains('play integrity') ||
            msg.contains('recaptcha')) {
          message =
              'Perangkat/aplikasi belum terverifikasi oleh Firebase. '
              'Pastikan SHA-1 sudah ditambahkan di Firebase Console dan coba di HP asli (bukan emulator). '
              'Lihat docs/FIREBASE_OTP_LANGKAH.md untuk langkah perbaikan.';
        } else if (msg.contains('blocked') ||
            msg.contains('unusual activity')) {
          message =
              'Perangkat ini sementara diblokir karena aktivitas tidak biasa (terlalu banyak percobaan). '
              'Tunggu beberapa jam lalu coba lagi, atau coba dari jaringan lain.';
        } else if (e.message != null && e.message!.isNotEmpty) {
          message = e.message!;
        }
        setState(() {
          _loading = false;
          _error = message;
        });
      },
      codeSent: (String verificationId, int? resendToken) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _stepOtp = true;
          _loading = false;
          _error = null;
        });
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> _linkPhone(PhoneAuthCredential credential) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
      try {
        await user.unlink(PhoneAuthProvider.PHONE_SIGN_IN_METHOD);
      } on FirebaseAuthException catch (_) {}
    }
    await user.linkWithCredential(credential);
    final phone = user.phoneNumber ?? _phoneE164;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'phoneNumber': phone,
    });
  }

  Future<void> _verifyOtp() async {
    final code = _otpController.text.trim();
    if (code.isEmpty || _verificationId == null) {
      setState(() => _error = 'Masukkan kode dari SMS');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final usedByOther = await _isPhoneUsedByOtherUser(_phoneE164);
    if (!mounted) return;
    if (usedByOther) {
      setState(() {
        _loading = false;
        _error = 'Nomor telepon sudah digunakan.';
      });
      return;
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: code,
      );
      await _linkPhone(credential);
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Kode salah atau kedaluwarsa. Coba kirim ulang.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_stepOtp ? 'Masukkan kode SMS' : 'No. Telepon'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
              if (!_stepOtp) ...[
                const Text(
                  'Masukkan no. telepon Indonesia (contoh: 08123456789). Kode verifikasi akan dikirim via SMS.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'No. Telepon',
                    border: OutlineInputBorder(),
                    prefixText: '${IndonesiaConfig.phonePrefix} ',
                  ),
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ] else ...[
                Text(
                  'Kode dikirim ke $_phoneE164',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _otpController,
                  decoration: const InputDecoration(
                    labelText: 'Kode verifikasi (6 digit)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  onChanged: (_) => setState(() => _error = null),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _loading ? null : widget.onCancel,
          child: const Text('Batal'),
        ),
        if (!_stepOtp)
          FilledButton(
            onPressed: _loading ? null : _sendOtp,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Kirim kode SMS'),
          )
        else
          FilledButton(
            onPressed: _loading ? null : _verifyOtp,
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Verifikasi'),
          ),
      ],
    );
  }
}
