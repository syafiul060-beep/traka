import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import '../models/order_model.dart';
import 'driver_status_service.dart';
import 'order_service.dart';
import 'route_notification_service.dart';

/// Jarak threshold (meter) untuk notifikasi driver mendekati penerima (Lacak Barang).
/// Hanya 1 km dan 500 m (5 km dihapus untuk kurangi spam notifikasi).
const int _threshold1km = 1000;
const int _threshold500m = 500;

/// Notifikasi ke penerima kirim barang: driver mendekati (5 km, 1 km, 500 m).
/// Hanya untuk order kirim_barang, status picked_up, penerima sudah bayar Lacak Barang.
class ReceiverProximityNotificationService {
  ReceiverProximityNotificationService._();

  static StreamSubscription<List<OrderModel>>? _ordersSub;
  static final Map<String, StreamSubscription<(double, double)?>> _driverSubs = {};
  static final Map<String, Set<int>> _proximityNotified = {};

  static int _notificationIdBase(String orderId) =>
      4000 + (orderId.hashCode % 500).abs();

  /// Mulai listen: hanya untuk user penerima (current user = receiver dari order kirim barang).
  static void start() {
    stop();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _ordersSub = OrderService.streamOrdersForReceiver(user.uid).listen((orders) {
      final active = orders.where((o) {
        if (o.orderType != OrderModel.typeKirimBarang) return false;
        if (o.status != OrderService.statusPickedUp) return false;
        if (o.receiverLacakBarangPaidAt == null) return false;
        if (o.receiverUid != user.uid) return false;
        if (o.receiverLat == null || o.receiverLng == null) return false;
        if (o.driverUid.isEmpty) return false;
        return true;
      }).toList();

      for (final orderId in _driverSubs.keys.toList()) {
        if (!active.any((o) => o.id == orderId)) {
          _driverSubs[orderId]?.cancel();
          _driverSubs.remove(orderId);
          _proximityNotified.remove(orderId);
        }
      }

      for (final order in active) {
        if (_driverSubs.containsKey(order.id)) continue;
        _startDriverPositionListener(order);
      }
    });
  }

  static void _startDriverPositionListener(OrderModel order) {
    final receiverLat = order.receiverLat!;
    final receiverLng = order.receiverLng!;
    final orderId = order.id;
    _proximityNotified[orderId] = <int>{};

    final sub = DriverStatusService.streamDriverPosition(order.driverUid).listen(
      (position) {
        if (position == null) return;
        final (driverLat, driverLng) = position;
        final distanceMeters = Geolocator.distanceBetween(
          receiverLat,
          receiverLng,
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
    // Hanya 1 km dan 500 m (kurangi spam).
    if (distanceMeters <= _threshold500m && !notified.contains(_threshold500m)) {
      notified.add(_threshold500m);
      RouteNotificationService.showReceiverProximityNotification(
        body: 'Driver dalam radius 500 m – siap terima barang',
        notificationId: base + 1000,
      );
    } else if (distanceMeters <= _threshold1km &&
        !notified.contains(_threshold1km)) {
      notified.add(_threshold1km);
      RouteNotificationService.showReceiverProximityNotification(
        body: 'Barang hampir sampai – driver 1 km dari lokasi Anda',
        notificationId: base + 500,
      );
    }
  }

  /// Hentikan listen (dipanggil saat penerima logout).
  static void stop() {
    _ordersSub?.cancel();
    _ordersSub = null;
    for (final sub in _driverSubs.values) {
      sub.cancel();
    }
    _driverSubs.clear();
    _proximityNotified.clear();
  }
}
