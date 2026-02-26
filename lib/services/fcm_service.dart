import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../firebase_options.dart';
import 'route_notification_service.dart';

/// Handler untuk pesan FCM saat app di background/terminated (harus top-level).
/// Untuk data-only message, tampilkan notifikasi lokal.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Jika pesan punya notification payload, sistem Android menampilkan otomatis.
  // Hanya tampilkan lokal untuk data-only message.
  if (message.notification != null) return;
  final data = message.data;
  final title = data['passengerName'] ?? 'Traka';
  final body = data['body'] ?? 'Pesan baru';
  await _showBackgroundNotification(title, body);
}

/// Icon notifikasi: siluet mobil (putih, monokrom) untuk status bar.
const String _notificationIcon = '@drawable/ic_notification';

Future<void> _showBackgroundNotification(String title, String body) async {
  if (!Platform.isAndroid) return;
  const channelId = 'traka_chat';
  const channelName = 'Chat';
  final plugin = FlutterLocalNotificationsPlugin();
  const android = AndroidInitializationSettings(_notificationIcon);
  await plugin.initialize(const InitializationSettings(android: android));
  await plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          channelId,
          channelName,
          description: 'Notifikasi chat dari penumpang',
          importance: Importance.high,
        ),
      );
  await plugin.show(
    2001,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: 'Notifikasi chat dari penumpang',
        importance: Importance.high,
        priority: Priority.high,
        icon: _notificationIcon,
      ),
    ),
  );
}

/// Service FCM: simpan token ke Firestore, tampilkan notifikasi saat foreground.
class FcmService {
  static const String _channelId = 'traka_chat';
  static const int _chatNotificationId = 2001;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await _setupLocalNotifications();
    await RouteNotificationService.requestPermissionIfNeeded();
    FirebaseMessaging.onMessage.listen(_onMessageForeground);
    _initialized = true;
  }

  static Future<void> _setupLocalNotifications() async {
    const android = AndroidInitializationSettings(_notificationIcon);
    const settings = InitializationSettings(android: android);
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (_) {},
    );
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _channelId,
              'Chat',
              description: 'Notifikasi chat dari penumpang',
              importance: Importance.high,
              enableVibration: true,
              playSound: true,
            ),
          );
    }
  }

  static void _onMessageForeground(RemoteMessage message) {
    final notification = message.notification;
    final data = message.data;
    final title = notification?.title ?? data['passengerName'] ?? 'Chat';
    final body = notification?.body ?? data['body'] ?? 'Pesan baru';
    _showLocalNotification(title, body);
  }

  static Future<void> _showLocalNotification(String title, String body) async {
    if (!Platform.isAndroid) return;
    await RouteNotificationService.requestPermissionIfNeeded();
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      'Chat',
      channelDescription: 'Notifikasi chat dari penumpang',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
      icon: _notificationIcon,
    );
    const details = NotificationDetails(android: androidDetails);
    await _localNotifications.show(_chatNotificationId, title, body, details);
  }

  /// Topic untuk broadcast notifikasi dari admin.
  static const String broadcastTopic = 'traka_broadcast';

  /// Dapatkan token FCM dan simpan ke users/{uid}/fcmToken. Panggil setelah login.
  /// Juga subscribe ke topic broadcast agar bisa terima notifikasi dari admin.
  static Future<void> saveTokenForUser(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || uid.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      });
      await FirebaseMessaging.instance.subscribeToTopic(broadcastTopic);
    } catch (_) {}
  }

  /// Hapus token saat logout (opsional, agar driver tidak dapat notifikasi dari device lama).
  static Future<void> removeTokenForUser(String uid) async {
    try {
      if (uid.isEmpty) return;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.delete(),
      });
    } catch (_) {}
  }
}
