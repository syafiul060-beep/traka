import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';

import '../config/indonesia_config.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Mengonversi CameraImage ke InputImage untuk ML Kit.
/// Path cepat: YUV→NV21→InputImage.fromBytes (tanpa file I/O).
class CameraImageConverter {
  /// Konversi cepat: YUV420 ke InputImage via NV21 (tanpa tulis file).
  static InputImage? toInputImageFast(CameraImage image) {
    try {
      if (image.format.group == ImageFormatGroup.yuv420) {
        final nv21 = _yuv420ToNv21(image);
        if (nv21 == null || nv21.isEmpty) return null;
        final meta = InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        );
        return InputImage.fromBytes(bytes: nv21, metadata: meta);
      }
      if (image.format.group == ImageFormatGroup.bgra8888) {
        final plane = image.planes.first;
        final meta = InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        );
        return InputImage.fromBytes(bytes: plane.bytes, metadata: meta);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _yuv420ToNv21(CameraImage image) {
    final y = image.planes[0].bytes;
    final u = image.planes[1].bytes;
    final v = image.planes[2].bytes;
    final width = image.width;
    final height = image.height;
    final yRowStride = image.planes[0].bytesPerRow;
    final uRowStride = image.planes[1].bytesPerRow;
    final vRowStride = image.planes[2].bytesPerRow;
    final nv21 = Uint8List(width * height * 3 ~/ 2);
    var dst = 0;
    for (var j = 0; j < height; j++) {
      final src = j * yRowStride;
      final len = width;
      if (src + len <= y.length && dst + len <= nv21.length) {
        nv21.setRange(dst, dst + len, y, src);
      }
      dst += width;
    }
    for (var j = 0; j < height ~/ 2; j++) {
      for (var i = 0; i < width ~/ 2; i++) {
        final vIdx = j * vRowStride + i;
        final uIdx = j * uRowStride + i;
        if (dst < nv21.length - 1 && vIdx < v.length && uIdx < u.length) {
          nv21[dst++] = v[vIdx];
          nv21[dst++] = u[uIdx];
        }
      }
    }
    return nv21;
  }

  /// Fallback: konversi via temp file (jika fast path gagal).
  static Future<InputImage?> toInputImage(CameraImage image) async {
    final fast = toInputImageFast(image);
    if (fast != null) return fast;
    try {
      final path = await _writeToTempFile(image);
      if (path == null) return null;
      return InputImage.fromFilePath(path);
    } catch (_) {
      return null;
    }
  }

  /// Menulis CameraImage ke file temp (JPEG). Untuk verifikasi wajah dari stream (login).
  static Future<String?> writeCameraImageToTempFile(CameraImage image) async {
    return _writeToTempFile(image);
  }

  static Future<String?> _writeToTempFile(CameraImage image) async {
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/liveness_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final file = File(path);

      Uint8List bytes;
      if (image.format.group == ImageFormatGroup.bgra8888) {
        bytes = _bgraToJpeg(image);
      } else if (image.format.group == ImageFormatGroup.yuv420) {
        bytes = _yuv420ToJpeg(image);
      } else {
        return null;
      }
      if (bytes.isEmpty) return null;
      await file.writeAsBytes(bytes);
      return path;
    } catch (_) {
      return null;
    }
  }

  static Uint8List _bgraToJpeg(CameraImage image) {
    final plane = image.planes.first;
    final width = image.width;
    final height = image.height;
    final rowStride = plane.bytesPerRow;
    final bgra = plane.bytes;
    final rgb = Uint8List(width * height * 3);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final src = y * rowStride + x * 4;
        final dst = (y * width + x) * 3;
        rgb[dst] = bgra[src + 2];
        rgb[dst + 1] = bgra[src + 1];
        rgb[dst + 2] = bgra[src];
      }
    }
    final im = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgb.buffer,
    );
    return img.encodeJpg(im, quality: IndonesiaConfig.jpegQuality);
  }

  static Uint8List _yuv420ToJpeg(CameraImage image) {
    final y = image.planes[0].bytes;
    final u = image.planes[1].bytes;
    final v = image.planes[2].bytes;
    final yRowStride = image.planes[0].bytesPerRow;
    final uRowStride = image.planes[1].bytesPerRow;
    final vRowStride = image.planes[2].bytesPerRow;
    final width = image.width;
    final height = image.height;
    final rgb = _yuv420ToRgb(
      y,
      u,
      v,
      width,
      height,
      yRowStride,
      uRowStride,
      vRowStride,
    );
    final im = img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgb.buffer,
    );
    return img.encodeJpg(im, quality: IndonesiaConfig.jpegQuality);
  }

  static Uint8List _yuv420ToRgb(
    Uint8List y,
    Uint8List u,
    Uint8List v,
    int width,
    int height,
    int yRowStride,
    int uRowStride,
    int vRowStride,
  ) {
    final rgb = Uint8List(width * height * 3);
    for (var j = 0; j < height; j++) {
      for (var i = 0; i < width; i++) {
        final yIndex = j * yRowStride + i;
        final uvJ = j ~/ 2;
        final uvI = i ~/ 2;
        final uIndex = uvJ * uRowStride + uvI;
        final vIndex = uvJ * vRowStride + uvI;
        final yVal = y[yIndex].toInt() - 16;
        final uVal = u[uIndex].toInt() - 128;
        final vVal = v[vIndex].toInt() - 128;
        final r = (1.164 * yVal + 1.596 * vVal).clamp(0, 255).round();
        final g = (1.164 * yVal - 0.391 * uVal - 0.813 * vVal)
            .clamp(0, 255)
            .round();
        final b = (1.164 * yVal + 2.018 * uVal).clamp(0, 255).round();
        final idx = (j * width + i) * 3;
        rgb[idx] = r;
        rgb[idx + 1] = g;
        rgb[idx + 2] = b;
      }
    }
    return rgb;
  }
}
