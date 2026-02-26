import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:face_verification/face_verification.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../config/indonesia_config.dart';
import '../services/camera_image_converter.dart';

/// Verifikasi wajah saat login: kamera depan otomatis terbuka, verifikasi otomatis tanpa tombol ambil foto.
/// Dipanggil saat login pertama kali atau login dari device ID berbeda.
class LoginFaceVerificationScreen extends StatefulWidget {
  final String uid;

  const LoginFaceVerificationScreen({super.key, required this.uid});

  @override
  State<LoginFaceVerificationScreen> createState() =>
      _LoginFaceVerificationScreenState();
}

class _LoginFaceVerificationScreenState
    extends State<LoginFaceVerificationScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  String? _error;
  bool _isVerifying = false;
  bool _verified = false;
  DateTime? _lastVerifyTime;
  static const _verifyIntervalMs = 400;
  static const _matchThreshold = 0.7;
  File? _tempStoredFile;

  static ResolutionPreset _getResolutionPreset() {
    switch (IndonesiaConfig.cameraResolutionPreset) {
      case 'high':
        return ResolutionPreset.high;
      case 'medium':
        return ResolutionPreset.medium;
      default:
        return ResolutionPreset.low;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadStoredFaceAndInitCamera();
  }

  Future<void> _loadStoredFaceAndInitCamera() async {
    try {
      final ref = FirebaseStorage.instance.ref().child(
        'users/${widget.uid}/face_verification.jpg',
      );
      final bytes = await ref.getData();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
            _error = 'Data wajah tidak ditemukan.';
          });
        }
        return;
      }

      final tempDir = await getTemporaryDirectory();
      _tempStoredFile = File('${tempDir.path}/login_verify_${widget.uid}.jpg');
      await _tempStoredFile!.writeAsBytes(bytes);

      await FaceVerification.instance.registerFromImagePath(
        id: widget.uid,
        imagePath: _tempStoredFile!.path,
        imageId: 'login_verify',
      );

      if (!mounted) return;
      await _initCamera();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _error = 'Gagal memuat data wajah.';
        });
      }
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _controller = CameraController(
        front,
        _getResolutionPreset(),
        imageFormatGroup: ImageFormatGroup.yuv420,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (!mounted) return;
      try {
        await _controller!.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (!mounted) return;
      if (_controller!.value.isStreamingImages) return;
      await _controller!.startImageStream(_onImageStream);
      setState(() {
        _isInitialized = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _error = 'Kamera gagal: $e';
        });
      }
    }
  }

  void _onImageStream(CameraImage image) async {
    if (_isVerifying || _verified) return;
    final now = DateTime.now();
    if (_lastVerifyTime != null &&
        now.difference(_lastVerifyTime!).inMilliseconds < _verifyIntervalMs) {
      return;
    }
    _lastVerifyTime = now;
    _isVerifying = true;

    try {
      final path = await CameraImageConverter.writeCameraImageToTempFile(image);
      if (path == null || !mounted) {
        _isVerifying = false;
        return;
      }

      final matchId = await FaceVerification.instance.verifyFromImagePath(
        imagePath: path,
        threshold: _matchThreshold,
        staffId: widget.uid,
      );

      if (matchId == widget.uid && mounted) {
        _verified = true;
        await _controller?.stopImageStream();
        if (mounted) {
          Navigator.of(context).pop((verified: true, selfiePath: path));
        }
      }
    } catch (_) {}
    if (mounted) setState(() {});
    _isVerifying = false;
  }

  void _onCancel() {
    Navigator.of(context).pop((verified: false, selfiePath: null));
  }

  @override
  void dispose() {
    try {
      FaceVerification.instance.deleteRecord(widget.uid);
    } catch (_) {}
    try {
      _tempStoredFile?.deleteSync();
    } catch (_) {}
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller != null &&
                _controller!.value.isInitialized &&
                _isInitialized &&
                _error == null)
              ClipRect(
                child: OverflowBox(
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.previewSize!.height,
                      height: _controller!.value.previewSize!.width,
                      child: CameraPreview(_controller!),
                    ),
                  ),
                ),
              ),
            if (_isInitialized && _error == null)
              Positioned(
                bottom: 48,
                left: 24,
                right: 24,
                child: Text(
                  'Arahkan wajah ke kamera. Verifikasi otomatis.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    shadows: [
                      Shadow(color: Colors.black, blurRadius: 4),
                      Shadow(color: Colors.black, offset: Offset(1, 1)),
                    ],
                  ),
                ),
              ),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            Positioned(
              top: 16,
              left: 16,
              child: TextButton.icon(
                onPressed: _onCancel,
                icon: const Icon(Icons.close, color: Colors.white, size: 24),
                label: const Text(
                  'Batal',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
