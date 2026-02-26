import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Kompresi gambar sebelum upload: max 1200px, quality 85.
class ImageCompressionService {
  static const int _maxDimension = 1200;
  static const int _quality = 85;

  /// Kompres gambar: resize ke max 1200px, encode JPG quality 85.
  /// Return path file hasil kompresi, atau path asli jika gagal.
  static Future<String> compressForUpload(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      var image = img.decodeImage(bytes);
      if (image == null) return imagePath;

      final w = image.width;
      final h = image.height;
      int? newWidth;
      int? newHeight;

      if (w > _maxDimension || h > _maxDimension) {
        if (w >= h) {
          newWidth = _maxDimension;
        } else {
          newHeight = _maxDimension;
        }
      }

      if (newWidth != null || newHeight != null) {
        image = img.copyResize(
          image,
          width: newWidth,
          height: newHeight,
          interpolation: img.Interpolation.linear,
        );
      }

      final dir = await getTemporaryDirectory();
      final outPath =
          '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final outFile = File(outPath);
      await outFile.writeAsBytes(img.encodeJpg(image, quality: _quality));
      return outPath;
    } catch (_) {
      return imagePath;
    }
  }
}
