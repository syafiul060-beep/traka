import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../config/indonesia_config.dart';
import '../services/camera_image_converter.dart';

/// Layar Active Liveness – deteksi kedip untuk anti-fraud.
/// Menggunakan frame sampling 250ms agar ringan di device.
class ActiveLivenessScreen extends StatefulWidget {
  final VoidCallback? onSuccess;
  final VoidCallback? onCancel;

  const ActiveLivenessScreen({super.key, this.onSuccess, this.onCancel});

  @override
  State<ActiveLivenessScreen> createState() => _ActiveLivenessScreenState();
}

class _ActiveLivenessScreenState extends State<ActiveLivenessScreen> {
  CameraController? _controller;
  bool _isInitialized = false;
  String? _error;
  bool _isProcessing = false;
  bool _blinkDetected = false;
  bool _wasEyesClosed = false;
  bool _faceDetected = false;
  bool _readyForBlink = false;
  DateTime? _lastProcessTime;
  DateTime? _faceFirstDetectedAt;
  DateTime? _lastFocusPointTime;
  static const _sampleIntervalSearchMs = IndonesiaConfig.sampleIntervalSearchMs;
  static const _sampleIntervalFaceMs = IndonesiaConfig.sampleIntervalFaceMs;
  static const _blinkReadyDelayMs = IndonesiaConfig.blinkReadyDelayMs;
  static const _faceHoldVerifyMs = IndonesiaConfig.faceHoldVerifyMs;
  static const _focusPointIntervalMs = 1500;
  FaceDetector? _faceDetector;

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
    _initCamera();
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
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableLandmarks: true,
          enableContours: false,
          minFaceSize: 0.1,
        ),
      );
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
    if (_isProcessing || _blinkDetected) return;
    final now = DateTime.now();
    final interval = _faceDetected
        ? _sampleIntervalFaceMs
        : _sampleIntervalSearchMs;
    if (_lastProcessTime != null &&
        now.difference(_lastProcessTime!).inMilliseconds < interval) {
      return;
    }
    _lastProcessTime = now;
    _isProcessing = true;

    try {
      final inputImage =
          CameraImageConverter.toInputImageFast(image) ??
          await CameraImageConverter.toInputImage(image);
      if (inputImage == null || !mounted) {
        if (mounted) setState(() => _faceDetected = false);
        _isProcessing = false;
        return;
      }
      final faces = await _faceDetector!.processImage(inputImage);
      if (faces.isEmpty || faces.length > 1) {
        if (mounted) {
          setState(() {
            _faceDetected = false;
            _faceFirstDetectedAt = null;
            _readyForBlink = false;
          });
        }
        _isProcessing = false;
        return;
      }
      final face = faces.first;
      final left = face.leftEyeOpenProbability ?? 1;
      final right = face.rightEyeOpenProbability ?? 1;
      final bbox = face.boundingBox;
      final imgW = image.width;
      final imgH = image.height;

      final faceDurationMs = _faceFirstDetectedAt != null
          ? DateTime.now().difference(_faceFirstDetectedAt!).inMilliseconds
          : 0;
      final readyForBlink = faceDurationMs > _blinkReadyDelayMs;

      if (mounted) {
        final wasDetected = _faceDetected;
        if (!wasDetected) _faceFirstDetectedAt = DateTime.now();
        setState(() {
          _faceDetected = true;
          _readyForBlink = readyForBlink;
        });
      }

      if (_controller != null && imgW > 0 && imgH > 0) {
        final now = DateTime.now();
        if (_lastFocusPointTime == null ||
            now.difference(_lastFocusPointTime!).inMilliseconds >
                _focusPointIntervalMs) {
          _lastFocusPointTime = now;
          final cx = (bbox.left + bbox.width / 2) / imgW;
          final cy = (bbox.top + bbox.height / 2) / imgH;
          if (cx >= 0 && cx <= 1 && cy >= 0 && cy <= 1) {
            try {
              await _controller!.setFocusPoint(Offset(cx, cy));
            } catch (_) {}
          }
        }
      }

      if (faceDurationMs >= _faceHoldVerifyMs) {
        if (mounted) {
          setState(() => _blinkDetected = true);
          await _controller?.stopImageStream();
          await _faceDetector?.close();
          _captureAndReturn();
        }
        _isProcessing = false;
        return;
      }

      if (!readyForBlink) {
        _isProcessing = false;
        return;
      }

      if (left < 0.35 && right < 0.35) {
        _wasEyesClosed = true;
      } else if (_wasEyesClosed && left > 0.35 && right > 0.35) {
        if (mounted) {
          setState(() => _blinkDetected = true);
          await _controller?.stopImageStream();
          await _faceDetector?.close();
          _captureAndReturn();
        }
      } else if (left > 0.45 && right > 0.45) {
        _wasEyesClosed = false;
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _faceDetected = false;
          _faceFirstDetectedAt = null;
          _readyForBlink = false;
        });
      }
    }
    if (mounted) _isProcessing = false;
  }

  Future<void> _captureAndReturn() async {
    try {
      if (_controller != null && mounted) {
        try {
          await _controller!.setFocusPoint(const Offset(0.5, 0.5));
          await Future.delayed(
            Duration(milliseconds: IndonesiaConfig.focusStabilizeMs),
          );
        } catch (_) {}
      }
      if (!mounted) return;
      final file = await _controller?.takePicture();
      if (file != null && mounted) {
        widget.onSuccess?.call();
        Navigator.of(context).pop(File(file.path));
      }
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _faceDetector?.close();
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
                _isInitialized)
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
            if (_controller != null &&
                _controller!.value.isInitialized &&
                _isInitialized &&
                !_blinkDetected)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (_, c) => CustomPaint(
                    painter: _FaceGuidePainter(hasFace: _faceDetected),
                    size: Size(c.maxWidth, c.maxHeight),
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
            if (!_isInitialized && _error == null)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            Positioned(
              top: 24,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      _blinkDetected
                          ? 'Berhasil!'
                          : _readyForBlink
                          ? 'Berkedip sekarang'
                          : _faceDetected
                          ? 'Siap berkedip…'
                          : 'Tahan wajah di tengah lingkaran biru',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.54), blurRadius: 4)],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Berkedip 1x atau tahan wajah 2 detik • Foto akan diambil otomatis',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Cahaya cukup • Pegang HP stabil',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Tips: Wajah jelas, tidak memakai masker. Kacamata boleh.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                    if (_faceDetected && !_blinkDetected) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _readyForBlink ? 1.0 : (_faceFirstDetectedAt != null
                                ? (DateTime.now().difference(_faceFirstDetectedAt!).inMilliseconds / _blinkReadyDelayMs).clamp(0.0, 1.0)
                                : 0.0),
                            minHeight: 6,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF64B5F6)),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.face,
                              color: const Color(0xFF64B5F6),
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _readyForBlink ? 'Berkedip atau tahan 2 detik' : 'Wajah terdeteksi',
                              style: const TextStyle(
                                color: Color(0xFF90CAF9),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 32,
              left: 24,
              right: 24,
              child: Column(
                children: [
                  if (_blinkDetected)
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 48,
                    ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onCancel?.call();
                    },
                    child: const Text(
                      'Batal',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  final bool hasFace;

  _FaceGuidePainter({required this.hasFace});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width < size.height ? size.width : size.height) * 0.35;
    final paint = Paint()
      ..color = hasFace ? const Color(0xFF2196F3) : const Color(0xFF64B5F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = hasFace ? 4 : 3;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter old) => old.hasFace != hasFace;
}
