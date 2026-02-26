import 'dart:math' show min;

import 'package:flutter/material.dart';

/// Helper agar tampilan menyesuaikan ukuran layar (HP kecil vs besar).
/// Layar kecil: padding & spacing dikurangi, font & icon sedikit dikecilkan.
/// Layar sangat kecil (<320): skala lebih agresif agar tidak sesak.
class Responsive {
  Responsive._(this._context);
  final BuildContext _context;

  static Responsive of(BuildContext context) => Responsive._(context);

  MediaQueryData get _media => MediaQuery.of(_context);
  Size get size => _media.size;
  double get width => size.width;
  double get height => size.height;
  double get shortestSide => size.shortestSide;

  /// Layar sangat kecil: < 340 (mis. HP murah/compact).
  bool get isVeryCompact => shortestSide < 340;

  /// Layar kecil: 340–380.
  bool get isCompact => shortestSide >= 340 && shortestSide < 380;

  /// Layar sedang: 380–420.
  bool get isMedium => shortestSide >= 380 && shortestSide < 420;

  /// Layar besar: >= 420.
  bool get isLarge => shortestSide >= 420;

  /// Faktor skala untuk padding/spacing (layar kecil = lebih kecil).
  double get spacingScale {
    if (isVeryCompact) return 0.7;
    if (isCompact) return 0.8;
    if (isMedium) return 0.9;
    return 1.0;
  }

  /// Faktor skala untuk ukuran font (layar kecil = sedikit lebih kecil).
  double get fontScale {
    if (isVeryCompact) return 0.86;
    if (isCompact) return 0.9;
    if (isMedium) return 0.95;
    return 1.0;
  }

  /// Faktor skala untuk icon (layar kecil = icon lebih kecil).
  double get iconScale {
    if (isVeryCompact) return 0.85;
    if (isCompact) return 0.9;
    if (isMedium) return 0.95;
    return 1.0;
  }

  /// Padding horizontal yang menyesuaikan layar (untuk body halaman).
  double get horizontalPadding {
    final base = 24.0;
    return (base * spacingScale).clamp(12.0, 28.0);
  }

  /// Padding vertikal standar.
  double get verticalPadding => (16.0 * spacingScale).clamp(8.0, 24.0);

  /// Spacing yang di-scale (untuk SizedBox height/width).
  double spacing(double base) =>
      (base * spacingScale).clamp(min(4.0, base), base);

  /// Font size yang di-scale (agar teks tetap terbaca di layar kecil).
  double fontSize(double base) =>
      (base * fontScale).clamp(min(10.0, base), base);

  /// Icon size yang di-scale (agar proporsional dengan layar).
  double iconSize(double base) =>
      (base * iconScale).clamp(min(16.0, base), base);

  /// Radius yang di-scale.
  double radius(double base) =>
      (base * spacingScale).clamp(min(4.0, base), base);

  /// Margin untuk card/dialog (lebih kecil di layar kecil).
  EdgeInsets get cardMargin => EdgeInsets.all(spacing(16));

  /// Padding untuk card/dialog.
  EdgeInsets get cardPadding => EdgeInsets.all(spacing(16));
}

/// Extension agar bisa pakai: context.responsive
extension ResponsiveExtension on BuildContext {
  Responsive get responsive => Responsive.of(this);
}
