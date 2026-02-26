import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_contact_config_service.dart';
import 'order_service.dart';

import '../models/order_model.dart';

/// Service untuk fitur SOS / Darurat.
/// Menyimpan event ke Firestore dan membuka WhatsApp ke admin dengan pesan berisi lokasi.
class SosService {
  static const String _collectionSosEvents = 'sos_events';

  /// Trigger SOS: simpan ke Firestore, buka WhatsApp ke admin.
  /// [order] pesanan aktif. [isDriver] true jika yang trigger adalah driver.
  static Future<void> triggerSOS({
    required OrderModel order,
    required bool isDriver,
    required double lat,
    required double lng,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final mapsUrl = 'https://www.google.com/maps?q=$lat,$lng';
    final now = DateTime.now();
    final timeStr = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final message = '''🚨 SOS - Traka

Lokasi: $mapsUrl
Pesanan: ${order.orderNumber ?? order.id}
Asal: ${order.originText}
Tujuan: ${order.destText}
Status: ${order.status}
Waktu: $timeStr
${isDriver ? 'Trigger: Driver' : 'Trigger: Penumpang'}''';

    await FirebaseFirestore.instance.collection(_collectionSosEvents).add({
      'uid': user.uid,
      'orderId': order.id,
      'orderNumber': order.orderNumber,
      'isDriver': isDriver,
      'lat': lat,
      'lng': lng,
      'originText': order.originText,
      'destText': order.destText,
      'status': order.status,
      'triggeredAt': FieldValue.serverTimestamp(),
    });

    await AdminContactConfigService.load();
    final wa = AdminContactConfigService.adminWhatsApp;
    final cleanWa = wa.replaceAll(RegExp(r'\D'), '');
    final uri = Uri.parse(
      'https://wa.me/$cleanWa?text=${Uri.encodeComponent(message)}',
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  /// Ambil lokasi saat ini dan trigger SOS.
  static Future<void> triggerSOSWithLocation({
    required OrderModel order,
    required bool isDriver,
  }) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await triggerSOS(
        order: order,
        isDriver: isDriver,
        lat: pos.latitude,
        lng: pos.longitude,
      );
    } catch (_) {
      await triggerSOS(
        order: order,
        isDriver: isDriver,
        lat: 0,
        lng: 0,
      );
    }
  }
}
