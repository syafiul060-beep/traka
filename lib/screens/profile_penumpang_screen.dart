import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import '../services/ocr_preprocess_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'active_liveness_screen.dart';
import '../config/indonesia_config.dart';
import '../services/face_validation_service.dart';
import '../services/permission_service.dart';
import '../services/verification_log_service.dart';
import '../services/account_deletion_service.dart';
import '../services/image_compression_service.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/admin_contact_widget.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/theme_toggle_widget.dart';
import '../services/driver_status_service.dart';
import '../services/passenger_proximity_notification_service.dart';
import '../services/receiver_proximity_notification_service.dart';
import '../services/passenger_tier_service.dart';
import '../widgets/app_version_title.dart';
import 'login_screen.dart';
import 'payment_history_screen.dart';
import 'promo_list_screen.dart';

/// Halaman profil penumpang: tampilan & menu sama seperti driver.
/// Menu: 1. Verifikasi data (KTP), 2. Email & No.Telp, 3. Ubah password.
class ProfilePenumpangScreen extends StatefulWidget {
  const ProfilePenumpangScreen({super.key});

  @override
  State<ProfilePenumpangScreen> createState() => _ProfilePenumpangScreenState();
}

class _ProfilePenumpangScreenState extends State<ProfilePenumpangScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  DocumentSnapshot<Map<String, dynamic>>? _userDoc;
  bool _loading = true;
  bool _isCheckingFace = false;
  File? _photoFile;
  final _nameController = TextEditingController();

  static const _daysPhotoLock = 30;

  Future<int>? _cachedCompletedCountFuture;
  Future<int> get _passengerCompletedCountFuture {
    _cachedCompletedCountFuture ??= () async {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return 0;
      return PassengerTierService.getPassengerCompletedOrderCount(uid);
    }();
    return _cachedCompletedCountFuture!;
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

  /// Penumpang sudah isi verifikasi KTP (nama + NIK tersimpan sebagai hash).
  bool get _isPassengerKTPVerified =>
      _userData['passengerKTPVerifiedAt'] != null ||
      _userData['passengerKTPNomorHash'] != null;

  /// Email & No.Telp lengkap jika no. telepon sudah ditambahkan.
  bool get _isEmailDanTelpFilled {
    final String phone = ((_userData['phoneNumber'] as String?) ?? '').trim();
    return phone.isNotEmpty;
  }

  bool get _hasFaceVerification =>
      (_userData['faceVerificationUrl'] as String?)?.trim().isNotEmpty ?? false;

  int get _verificationCompleteCount =>
      (_isPassengerKTPVerified ? 1 : 0) +
      (_isEmailDanTelpFilled ? 1 : 0) +
      (_hasFaceVerification ? 1 : 0);

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
      final updates = <String, dynamic>{
        'photoUrl': photoUrl,
        'photoUpdatedAt': FieldValue.serverTimestamp(),
      };
      final faceRef = FirebaseStorage.instance.ref().child(
        'users/${user.uid}/face_verification.jpg',
      );
      await faceRef.putFile(fileToUpload);
      final faceUrl = await faceRef.getDownloadURL();
      updates['faceVerificationUrl'] = faceUrl;
      updates['faceVerificationLastVerifiedAt'] = FieldValue.serverTimestamp();
      await _firestore.collection('users').doc(user.uid).update(updates);
      VerificationLogService.log(
        userId: user.uid,
        success: true,
        source: VerificationLogSource.profilePenumpang,
      );
      if (mounted) setState(() => _photoFile = null);
      await _loadUser();
      if (mounted) _showSnackBar('Foto profil berhasil diubah.');
    } catch (e) {
      VerificationLogService.log(
        userId: user.uid,
        success: false,
        source: VerificationLogSource.profilePenumpang,
        errorMessage: 'Gagal mengunggah foto: $e',
      );
      if (mounted) _showSnackBar('Gagal mengunggah foto: $e', isError: true);
    }
  }

  void _showVerifikasiKTPDialog() {
    if (_isPassengerKTPVerified) {
      _showSnackBar(
        'Verifikasi data KTP sudah berhasil. Tidak perlu mengubah kembali.',
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Verifikasi Data',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Langkah 1: Foto selfie untuk verifikasi wajah. Kamera depan akan terbuka. '
          'Tahan wajah di lingkaran biru, lalu berkedip 1x atau tahan 2 detik. Foto diambil otomatis.\n\n'
          'Langkah 2: Ambil foto KTP Indonesia. Hanya nomor KTP (NIK) yang disimpan dalam bentuk terenkripsi (SHA-256). Foto KTP tidak disimpan. Nama akan dibaca untuk dikoreksi lalu disimpan ke profil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _captureSelfieThenScanKTP();
            },
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
  }

  /// Langkah 1: Selfie (jika belum ada faceVerification). Langkah 2: Scan KTP.
  Future<void> _captureSelfieThenScanKTP() async {
    final hasFace = (_userData['faceVerificationUrl'] as String?)?.trim().isNotEmpty ?? false;
    if (!hasFace) {
      final ok = await _captureAndUploadSelfie();
      if (!mounted) return;
      if (!ok) return; // User batal atau gagal
    }
    if (!mounted) return;
    _scanKTP();
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
        _showSnackBar('Foto verifikasi wajah berhasil. Lanjut ambil foto KTP.');
        await _loadUser();
        return true;
      }
      return false;
    }

    setState(() => _photoFile = file);
    await _uploadPhoto();
    if (!mounted) return false;
    _showSnackBar('Foto verifikasi wajah berhasil. Lanjut ambil foto KTP.');
    await _loadUser();
    return true;
  }

  Future<void> _scanKTP() async {
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
            Text('Membaca KTP...'),
          ],
        ),
      ),
    );

    try {
      // OCR dengan preprocessing: coba original + preprocessed untuk akurasi lebih baik
      final ocrTexts = await OcrPreprocessService.runOcrVariants(image.path);

      if (!mounted) return;
      Navigator.pop(context);

      Map<String, String?>? extracted;
      for (final text in ocrTexts) {
        extracted = _extractKTPData(text);
        if (extracted['nik'] != null && extracted['nama'] != null) {
          break;
        }
      }

      if (extracted == null || extracted['nik'] == null || extracted['nama'] == null) {
        if (mounted) {
          _showSnackBar(
            'Gagal membaca data KTP. Pastikan foto KTP jelas dan NIK/NAMA terbaca.',
            isError: true,
          );
        }
        return;
      }
      await _showKTPDataConfirmationDialog(
        extracted['nama']!,
        extracted['nik']!,
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('Gagal membaca KTP: $e', isError: true);
      }
    }
  }

  /// Ekstrak NIK (16 digit) dan nama dari teks OCR KTP Indonesia.
  /// Mendukung koreksi OCR: O↔0, I/l↔1.
  Map<String, String?> _extractKTPData(String ocrText) {
    String? nik;
    String? nama;

    // Pola standar: 16 digit
    final nikPattern = RegExp(r'\b\d{16}\b');
    var nikMatch = nikPattern.firstMatch(ocrText);
    if (nikMatch != null) {
      nik = nikMatch.group(0);
    } else {
      // Pola permissive untuk OCR error (O, I, l sebagai digit)
      final ocrNikPattern = RegExp(r'\b[0-9OIl]{16}\b');
      nikMatch = ocrNikPattern.firstMatch(ocrText);
      if (nikMatch != null) {
        nik = nikMatch
            .group(0)!
            .replaceAll('O', '0')
            .replaceAll('I', '1')
            .replaceAll('l', '1');
      }
    }

    final lines = ocrText.split('\n');
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim().toUpperCase();
      if (line.contains('NAMA') || line.contains('NAME')) {
        final parts = line.split(RegExp(r'NAMA|NAME'));
        if (parts.length > 1) {
          final partName = parts[1].trim();
          nama = partName.isEmpty && i + 1 < lines.length
              ? lines[i + 1].trim()
              : partName;
          if (nama.isNotEmpty) break;
        } else if (i + 1 < lines.length) {
          nama = lines[i + 1].trim();
        }
        if (nama != null && nama.isNotEmpty) break;
      }
    }
    if ((nama == null || nama.isEmpty) && lines.isNotEmpty) {
      for (final line in lines) {
        final t = line.trim();
        if (t.length >= 8 &&
            t.split(' ').length >= 2 &&
            !RegExp(r'\d{10,}').hasMatch(t) &&
            !t.contains('NIK') &&
            !t.contains('KTP')) {
          nama = t;
          break;
        }
      }
    }
    return {'nik': nik, 'nama': nama};
  }

  Future<void> _showKTPDataConfirmationDialog(String nama, String nik) async {
    final nikController = TextEditingController(text: nik);
    final namaController = TextEditingController(text: nama);
    bool setuju = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'Data KTP yang Dibaca',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Periksa dan koreksi jika perlu. NIK disimpan dalam bentuk terenkripsi (hash).',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nikController,
                  decoration: const InputDecoration(
                    labelText: 'NIK',
                    border: OutlineInputBorder(),
                    hintText: '16 digit nomor NIK KTP',
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 16,
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 4),
                Text(
                  'NIK harus sesuai identitas.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: namaController,
                  decoration: const InputDecoration(
                    labelText: 'Nama sesuai KTP',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 4),
                Text(
                  'Nama harus sesuai identitas.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: setuju,
                  onChanged: (value) =>
                      setDialogState(() => setuju = value ?? false),
                  title: const Text(
                    'Data sudah sesuai dan saya setuju',
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
              onPressed: setuju
                  ? () async {
                      Navigator.pop(ctx);
                      await _saveKTPData(
                        namaController.text.trim(),
                        nikController.text.trim(),
                      );
                    }
                  : null,
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    nikController.dispose();
    namaController.dispose();
  }

  String _hashNIK(String nik) {
    final bytes = utf8.encode(nik.trim());
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _saveKTPData(String nama, String nik) async {
    final nikClean = nik.replaceAll(RegExp(r'\D'), '');
    if (nama.isEmpty) {
      _showSnackBar('Nama wajib diisi.', isError: true);
      return;
    }
    if (nikClean.length != 16) {
      _showSnackBar('NIK harus 16 digit sesuai identitas.', isError: true);
      return;
    }
    final user = _auth.currentUser;
    if (user == null) return;

    final ktpHash = _hashNIK(nikClean);
    try {
      final q = await _firestore
          .collection('users')
          .where('passengerKTPNomorHash', isEqualTo: ktpHash)
          .limit(2)
          .get();
      final dipakaiLain = q.docs.any((doc) => doc.id != user.uid);
      if (dipakaiLain) {
        if (mounted) {
          _showSnackBar(
            'Nomor KTP sudah digunakan oleh penumpang lain.',
            isError: true,
          );
        }
        return;
      }

      await _firestore.collection('users').doc(user.uid).update({
        'displayName': nama,
        'passengerKTPNomorHash': ktpHash,
        'passengerKTPVerifiedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() => _nameController.text = nama);
        _showSnackBar(
          'Verifikasi data berhasil. Nama profil mengikuti nama KTP.',
        );
        _loadUser();
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Gagal menyimpan: $e', isError: true);
      }
    }
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
                  'Email untuk login. No. telepon divalidasi lewat SMS OTP.',
                  style: TextStyle(
                    fontSize: context.responsive.fontSize(12),
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: context.responsive.spacing(20)),
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
              if (!RegExp(r'^[\w.-]+@[\w.-]+\.\w+$').hasMatch(v.trim()))
                return 'Format email tidak valid';
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
                    'Link verifikasi telah dikirim ke $newEmail. Buka inbox dan klik link.',
                  );
                  _loadUser();
                }
              } on FirebaseAuthException catch (e) {
                if (mounted)
                  _showSnackBar(
                    e.message ?? 'Gagal mengirim verifikasi email.',
                    isError: true,
                  );
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
    final currentPhone = ((_userData['phoneNumber'] as String?) ?? '').trim();
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
            'No. telepon berhasil. Login bisa dengan email atau no. telepon.',
          );
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
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
      await AccountDeletionService.scheduleAccountDeletion(user.uid, 'penumpang');
      PassengerProximityNotificationService.stop();
      ReceiverProximityNotificationService.stop();
      await DriverStatusService.removeDriverStatus();
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
    PassengerProximityNotificationService.stop();
    ReceiverProximityNotificationService.stop();
    // JANGAN hapus deviceId saat logout - biarkan tersimpan untuk verifikasi saat login di device baru
    try {
      await DriverStatusService.removeDriverStatus();
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
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!_isPassengerKTPVerified || !_isEmailDanTelpFilled) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.6),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSm),
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 22,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Lengkapi data Anda: Verifikasi Data (KTP), '
                                  'Email & No. Telepon agar dapat menggunakan semua fitur.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'Verifikasi: ${_verificationCompleteCount}/3 lengkap',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: _canChangePhoto() && !_isCheckingFace
                                ? _pickAndVerifyPhoto
                                : null,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 40,
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
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
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
                                                : 'Nama Penumpang',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context).colorScheme.primary,
                                            ),
                                          ),
                                          if (_isPassengerKTPVerified) ...[
                                            const SizedBox(width: 4),
                                            Icon(
                                              Icons.verified,
                                              size: 20,
                                              color: Colors.green.shade700,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    FutureBuilder<int>(
                                      future: _passengerCompletedCountFuture,
                                      builder: (context, snap) {
                                        final count = snap.data ?? 0;
                                        final tier = PassengerTierService.getPassengerTierLabel(count);
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
                                          padding: const EdgeInsets.only(left: 8),
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
                                FutureBuilder<int>(
                                  future: _passengerCompletedCountFuture,
                                  builder: (context, snap) {
                                    final count = snap.data ?? 0;
                                    return Text(
                                      '$count pesanan selesai',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
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
                        Row(
                          children: List.generate(20, (index) {
                            return Expanded(
                              child: Container(
                                height: 4,
                                color: index % 2 == 0
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            );
                          }),
                        ),
                      ],
                      const SizedBox(height: 32),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMenuCard(
                              title: 'Verifikasi Data',
                              icon: Icons.badge_outlined,
                              verified: _isPassengerKTPVerified,
                              onTap: _showVerifikasiKTPDialog,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMenuCard(
                              title: 'Email & No.Telp',
                              icon: Icons.contact_phone,
                              verified: _isEmailDanTelpFilled,
                              onTap: _showEmailDanTelpSheet,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMenuCard(
                              title: 'Ubah Password',
                              icon: Icons.lock_outline,
                              onTap: _showChangePasswordDialog,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMenuCard(
                              title: 'Riwayat Pembayaran',
                              icon: Icons.receipt_long,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const PaymentHistoryScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMenuCard(
                              title: 'Info & Promo',
                              icon: Icons.campaign_outlined,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const PromoListScreen(role: 'penumpang'),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: SizedBox()),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMenuCard(
                              title: 'Hapus akun',
                              icon: Icons.delete_outline,
                              onTap: _showHapusAkunDialog,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(child: SizedBox()),
                          const SizedBox(width: 12),
                          const Expanded(child: SizedBox()),
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

  Widget _buildMenuCard({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    bool verified = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
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
                Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
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
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
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
        setState(() {
          _loading = false;
          _error = e.message ?? 'Verifikasi gagal. Coba lagi.';
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
        _error = 'Kode salah atau kedaluwarsa.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_stepOtp ? 'Masukkan kode SMS' : 'No. Telepon'),
      content: SingleChildScrollView(
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
                'Masukkan no. telepon Indonesia. Kode verifikasi akan dikirim via SMS.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: 'No. Telepon',
                  border: const OutlineInputBorder(),
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
