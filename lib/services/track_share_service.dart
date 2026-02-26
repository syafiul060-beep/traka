import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'order_service.dart';
import '../models/order_model.dart';

/// Service untuk membagikan link lacak perjalanan ke keluarga.
/// Hanya bisa digunakan jika penumpang sudah bayar Lacak Driver.
/// Link tidak berlaku saat pesanan sampai tujuan (status completed).
class TrackShareService {
  static const String _collection = 'track_share_links';

  /// Base URL halaman track (untuk keluarga buka di browser).
  /// Deploy track.html ke Firebase Hosting: https://syafiul-traka.web.app/track.html
  static const String trackBaseUrl = 'https://syafiul-traka.web.app/track.html';

  static String _randomToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    return List.generate(32, (_) => chars[r.nextInt(chars.length)]).join();
  }

  /// Generate token dan simpan ke Firestore, lalu return URL untuk dibagikan.
  /// Validasi: penumpang harus sudah bayar Lacak Driver (passengerTrackDriverPaidAt != null).
  /// Hanya untuk order travel (bukan kirim barang).
  static Future<String> generateShareUrl(OrderModel order) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Belum login');

    if (order.isKirimBarang) {
      throw Exception('Bagikan link hanya untuk pesanan travel (Lacak Driver).');
    }

    if (order.passengerTrackDriverPaidAt == null) {
      throw Exception('Bayar Lacak Driver dulu untuk membagikan link ke keluarga.');
    }

    if (order.status == OrderService.statusCompleted ||
        order.status == OrderService.statusCancelled) {
      throw Exception('Perjalanan sudah selesai. Link tidak dapat dibuat.');
    }

    if (order.driverUid.isEmpty) {
      throw Exception('Data driver tidak valid.');
    }

    final token = _randomToken();
    await FirebaseFirestore.instance.collection(_collection).doc(token).set({
      'orderId': order.id,
      'driverUid': order.driverUid,
      'originText': order.originText,
      'destText': order.destText,
      'orderNumber': order.orderNumber ?? order.id,
      'status': order.status,
      'passengerUid': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return '$trackBaseUrl?t=$token';
  }
}
