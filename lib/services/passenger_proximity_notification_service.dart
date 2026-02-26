import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import '../models/order_model.dart';
import 'driver_status_service.dart';
import 'order_service.dart';
import 'route_notification_service.dart';

/// Jarak threshold (meter) untuk notifikasi driver mendekati penumpang.
/// Hanya 1 km dan 500 m (5 km dihapus untuk kurangi spam notifikasi).
const int _threshold1km = 1000;
const int _threshold500m = 500;

/// Notifikasi ke penumpang: kesepakatan sudah terjadi + driver mendekati (5 km, 1 km, 500 m).
class PassengerProximityNotificationService {
  PassengerProximityNotificationService._();

  static StreamSubscription<List<OrderModel>>? _ordersSub;
  static final Map<String, StreamSubscription<(double, double)?>> _driverSubs = {};
  /// Status order terakhir yang kita lihat (untuk deteksi transisi ke agreed).
  static final Map<String, String> _lastOrderStatus = {};
  /// Per order: set threshold yang sudah dinotifikasi (5000, 1000, 500).
  static final Map<String, Set<int>> _proximityNotified = {};

  static int _notificationIdBase(String orderId) =>
      3000 + (orderId.hashCode % 500).abs();

  /// Mulai listen: hanya untuk user penumpang (current user = passenger dari order).
  static void start() {
    stop();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _ordersSub = OrderService.streamOrdersForPassenger().listen((orders) {
      final active = orders.where((o) {
        if (o.status != OrderService.statusAgreed &&
            o.status != OrderService.statusPickedUp) return false;
        if (o.driverUid.isEmpty) return false;
        if (o.originLat == null || o.originLng == null) return false;
        return true;
      }).toList();

      // Notifikasi kesepakatan: hanya saat status baru saja berubah jadi agreed
      for (final o in orders) {
        final prev = _lastOrderStatus[o.id];
        _lastOrderStatus[o.id] = o.status;
        if (o.status == OrderService.statusAgreed &&
            prev != null &&
            prev != OrderService.statusAgreed) {
          RouteNotificationService.showKesepakatanNotification();
        }
      }

      // Hapus subscription driver untuk order yang tidak lagi aktif
      for (final orderId in _driverSubs.keys.toList()) {
        if (!active.any((o) => o.id == orderId)) {
          _driverSubs[orderId]?.cancel();
          _driverSubs.remove(orderId);
          _proximityNotified.remove(orderId);
        }
      }

      // Untuk setiap order aktif, listen posisi driver
      for (final order in active) {
        if (_driverSubs.containsKey(order.id)) continue;
        _startDriverPositionListener(order);
      }
    });
  }

  static void _startDriverPositionListener(OrderModel order) {
    final originLat = order.originLat!;
    final originLng = order.originLng!;
    final orderId = order.id;
    _proximityNotified[orderId] = <int>{};

    final sub = DriverStatusService.streamDriverPosition(order.driverUid).listen(
      (position) {
        if (position == null) return;
        final (driverLat, driverLng) = position;
        final distanceMeters = Geolocator.distanceBetween(
          originLat,
          originLng,
          driverLat,
          driverLng,
        );
        _checkAndNotifyProximity(orderId, distanceMeters);
      },
    );
    _driverSubs[orderId] = sub;
  }

  static void _checkAndNotifyProximity(String orderId, double distanceMeters) {
    final notified = _proximityNotified[orderId];
    if (notified == null) return;

    final base = _notificationIdBase(orderId);
    // Driver mendekati: 1 km dan 500 m saja (kurangi spam).
    if (distanceMeters <= _threshold500m && !notified.contains(_threshold500m)) {
      notified.add(_threshold500m);
      RouteNotificationService.showDriverProximityNotification(
        distanceLabel: '500 m',
        notificationId: base + 1000,
      );
    } else if (distanceMeters <= _threshold1km && !notified.contains(_threshold1km)) {
      notified.add(_threshold1km);
      RouteNotificationService.showDriverProximityNotification(
        distanceLabel: '1 km',
        notificationId: base + 500,
      );
    }
  }

  /// Hentikan listen (dipanggil saat penumpang logout atau tidak perlu lagi).
  static void stop() {
    _ordersSub?.cancel();
    _ordersSub = null;
    for (final sub in _driverSubs.values) {
      sub.cancel();
    }
    _driverSubs.clear();
    _proximityNotified.clear();
    _lastOrderStatus.clear();
  }
}
