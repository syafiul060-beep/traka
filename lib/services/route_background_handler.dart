import 'package:flutter/material.dart';

import 'route_notification_service.dart';

/// Handler untuk rute aktif saat app di background/closed.
/// DriverScreen mendaftarkan callback; app lifecycle di-main.dart.
class RouteBackgroundHandler {
  static DateTime? _routeBackgroundAt;
  static const Duration _maxDuration = Duration(hours: 1);

  static VoidCallback? _onEndRoute;
  static void Function(String)? _onShowSnackBar;
  static Future<void> Function()? _onPersistRequest;

  /// Daftarkan callback dari DriverScreen saat ada rute aktif.
  /// [onPersistRequest] dipanggil saat app ke background untuk menyimpan rute ke disk.
  static void register({
    required VoidCallback onEndRoute,
    required void Function(String) onShowSnackBar,
    Future<void> Function()? onPersistRequest,
  }) {
    _onEndRoute = onEndRoute;
    _onShowSnackBar = onShowSnackBar;
    _onPersistRequest = onPersistRequest;
  }

  /// Unregister saat DriverScreen dispose atau rute berakhir.
  static void unregister() {
    _onEndRoute = null;
    _onShowSnackBar = null;
    _onPersistRequest = null;
    _routeBackgroundAt = null;
    RouteNotificationService.cancelRouteActiveNotification();
  }

  static bool get hasActiveRoute => _onEndRoute != null;

  static void onAppPaused() {
    if (_onEndRoute == null) return;
    _routeBackgroundAt = DateTime.now();
    RouteNotificationService.showRouteActiveNotification();
    // Update timestamp background (data rute sudah disimpan saat rute aktif)
    _onPersistRequest?.call();
  }

  static void onAppResumed() {
    if (_onEndRoute == null || _onShowSnackBar == null) return;
    final bgAt = _routeBackgroundAt;
    if (bgAt == null) return;

    final elapsed = DateTime.now().difference(bgAt);
    if (elapsed >= _maxDuration) {
      _onEndRoute?.call();
      _onShowSnackBar?.call(
        'Rute diakhiri otomatis. Aplikasi di background lebih dari 1 jam.',
      );
      RouteNotificationService.cancelRouteActiveNotification();
      unregister();
    } else {
      _routeBackgroundAt = DateTime.now();
      RouteNotificationService.showRouteActiveNotification();
      _onShowSnackBar?.call(
        'Rute tujuan anda masih aktif. Waktu diperpanjang 1 jam.',
      );
    }
  }
}
