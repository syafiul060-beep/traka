import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifikasi saat rute aktif dan aplikasi di background.
class RouteNotificationService {
  /// Icon notifikasi: siluet mobil (putih, monokrom) untuk status bar.
  static const String _notificationIcon = '@drawable/ic_notification';

  static const int _routeActiveNotificationId = 1001;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings(_notificationIcon);
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    if (Platform.isAndroid) {
      await _createAllChannels();
    }
    _initialized = true;
  }

  static Future<void> _createAllChannels() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        'traka_route_channel',
        'Rute Aktif',
        description: 'Notifikasi rute perjalanan driver',
        importance: Importance.defaultImportance,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _passengerChannelId,
        'Driver Mendekati',
        description: 'Notifikasi saat kesepakatan dan driver mendekati lokasi penumpang',
        importance: Importance.high,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _receiverChannelId,
        'Lacak Barang',
        description: 'Notifikasi saat driver mendekati lokasi penerima barang',
        importance: Importance.high,
      ),
    );
  }

  /// Minta izin notifikasi (Android 13+)
  static Future<void> requestPermissionIfNeeded() async {
    if (!Platform.isAndroid) return;
    if (!_initialized) await init();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  /// Terakhir kali notifikasi rute aktif ditampilkan (untuk cooldown).
  static DateTime? _lastRouteNotificationShownAt;
  static const Duration _routeNotificationCooldown = Duration(minutes: 30);

  /// Tampilkan notifikasi "Rute tujuan anda masih aktif"
  /// Cooldown 30 menit: tidak tampilkan lagi jika baru saja ditampilkan.
  static Future<void> showRouteActiveNotification() async {
    if (!_initialized) await init();
    if (!Platform.isAndroid) return;

    final now = DateTime.now();
    if (_lastRouteNotificationShownAt != null &&
        now.difference(_lastRouteNotificationShownAt!) < _routeNotificationCooldown) {
      return; // Masih dalam cooldown
    }
    _lastRouteNotificationShownAt = now;

    await requestPermissionIfNeeded();

    const androidDetails = AndroidNotificationDetails(
      'traka_route_channel',
      'Rute Aktif',
      channelDescription: 'Notifikasi rute perjalanan driver',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: _notificationIcon,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      _routeActiveNotificationId,
      'Traka',
      'Rute tujuan anda masih aktif',
      details,
    );
  }

  /// Hapus notifikasi rute aktif
  static Future<void> cancelRouteActiveNotification() async {
    _lastRouteNotificationShownAt = null; // Reset cooldown untuk rute berikutnya
    await _plugin.cancel(_routeActiveNotificationId);
  }

  // --- Notifikasi penumpang: kesepakatan & driver mendekati ---
  static const String _passengerChannelId = 'traka_passenger_channel';
  static const int _kesepakatanNotificationId = 3001;

  static Future<void> _ensurePassengerChannel() async {
    if (!_initialized) await init();
    if (!Platform.isAndroid) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _passengerChannelId,
            'Driver Mendekati',
            description: 'Notifikasi saat kesepakatan dan driver mendekati lokasi penumpang',
            importance: Importance.high,
          ),
        );
  }

  /// Notifikasi ke penumpang: kesepakatan sudah terjadi.
  static Future<void> showKesepakatanNotification() async {
    await _ensurePassengerChannel();
    if (!Platform.isAndroid) return;
    await requestPermissionIfNeeded();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _passengerChannelId,
        'Driver Mendekati',
        channelDescription: 'Notifikasi saat kesepakatan dan driver mendekati lokasi penumpang',
        importance: Importance.high,
        priority: Priority.high,
        icon: _notificationIcon,
      ),
    );
    await _plugin.show(
      _kesepakatanNotificationId,
      'Traka',
      'Kesepakatan sudah terjadi. Driver akan segera menuju lokasi Anda.',
      details,
    );
  }

  /// Notifikasi ke driver dan penumpang: konfirmasi otomatis dijemput (tanpa scan).
  static Future<void> showAutoConfirmPickupNotification() async {
    await _ensurePassengerChannel();
    if (!Platform.isAndroid) return;
    await requestPermissionIfNeeded();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _passengerChannelId,
        'Driver Mendekati',
        channelDescription: 'Notifikasi saat kesepakatan dan driver mendekati lokasi penumpang',
        importance: Importance.high,
        priority: Priority.high,
        icon: _notificationIcon,
      ),
    );
    await _plugin.show(
      3010,
      'Traka',
      'Penumpang tercatat dijemput (konfirmasi otomatis).',
      details,
    );
  }

  /// Notifikasi ke driver dan penumpang: pesanan selesai otomatis (saat menjauh).
  static Future<void> showAutoCompleteNotification() async {
    await _ensurePassengerChannel();
    if (!Platform.isAndroid) return;
    await requestPermissionIfNeeded();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _passengerChannelId,
        'Driver Mendekati',
        channelDescription: 'Notifikasi saat kesepakatan dan driver mendekati lokasi penumpang',
        importance: Importance.high,
        priority: Priority.high,
        icon: _notificationIcon,
      ),
    );
    await _plugin.show(
      3011,
      'Traka',
      'Pesanan selesai (konfirmasi otomatis – Anda sudah sampai tujuan).',
      details,
    );
  }

  /// Notifikasi ke penumpang: driver mendekati (jarak).
  static Future<void> showDriverProximityNotification({
    required String distanceLabel,
    required int notificationId,
  }) async {
    await _ensurePassengerChannel();
    if (!Platform.isAndroid) return;
    await requestPermissionIfNeeded();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _passengerChannelId,
        'Driver Mendekati',
        channelDescription: 'Notifikasi saat kesepakatan dan driver mendekati lokasi penumpang',
        importance: Importance.high,
        priority: Priority.high,
        icon: _notificationIcon,
      ),
    );
    await _plugin.show(
      notificationId,
      'Traka',
      'Driver sudah dekat ($distanceLabel). Siap-siap.',
      details,
    );
  }

  // --- Notifikasi penerima Lacak Barang: driver mendekati (5 km, 1 km, 500 m) ---
  static const String _receiverChannelId = 'traka_receiver_channel';

  static Future<void> _ensureReceiverChannel() async {
    if (!_initialized) await init();
    if (!Platform.isAndroid) return;
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _receiverChannelId,
            'Lacak Barang',
            description: 'Notifikasi saat driver mendekati lokasi penerima barang',
            importance: Importance.high,
          ),
        );
  }

  /// Notifikasi ke penerima: driver mendekati lokasi penerima (Lacak Barang).
  static Future<void> showReceiverProximityNotification({
    required String body,
    required int notificationId,
  }) async {
    await _ensureReceiverChannel();
    if (!Platform.isAndroid) return;
    await requestPermissionIfNeeded();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _receiverChannelId,
        'Lacak Barang',
        channelDescription: 'Notifikasi saat driver mendekati lokasi penerima barang',
        importance: Importance.high,
        priority: Priority.high,
        icon: _notificationIcon,
      ),
    );
    await _plugin.show(
      notificationId,
      'Traka',
      body,
      details,
    );
  }
}
