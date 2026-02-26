import 'dart:math' show asin, cos, sqrt;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import 'order_number_service.dart';
import 'chat_service.dart';

import '../models/order_model.dart';
import '../utils/app_logger.dart';

/// Service untuk pesanan penumpang (nomor pesanan, kesepakatan driver-penumpang).
/// Nomor pesanan unik; dibuat otomatis saat driver dan penumpang sama-sama klik kesepakatan.
class OrderService {
  static const String _collectionOrders = 'orders';
  static const String _fieldRouteJourneyNumber = 'routeJourneyNumber';
  static const String _fieldDriverUid = 'driverUid';
  static const String _fieldPassengerUid = 'passengerUid';
  static const String _fieldStatus = 'status';

  static const String statusAgreed = 'agreed';
  static const String statusPickedUp = 'picked_up';
  static const String statusCompleted = 'completed';
  static const String statusPendingAgreement = 'pending_agreement';
  /// Kirim barang: menunggu penerima setuju jadi penerima.
  static const String statusPendingReceiver = 'pending_receiver';
  static const String statusCancelled = 'cancelled';

  /// Nilai routeJourneyNumber untuk pesanan terjadwal (dari Pesan nanti).
  static const String routeJourneyNumberScheduled = 'scheduled';

  /// Cari user (penerima) by email atau no. telepon. Return {uid, displayName, photoUrl} atau null.
  static Future<Map<String, dynamic>?> findUserByEmailOrPhone(String input) async {
    final trim = input.trim();
    if (trim.isEmpty) return null;
    try {
      if (trim.contains('@')) {
        final q = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: trim.toLowerCase())
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          final d = q.docs.first.data();
          return {
            'uid': q.docs.first.id,
            'displayName': d['displayName'] as String?,
            'photoUrl': d['photoUrl'] as String?,
          };
        }
      } else {
        var q = await FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', isEqualTo: trim)
            .limit(1)
            .get();
        if (q.docs.isEmpty && trim.startsWith('0')) {
          final normalized = '+62${trim.substring(1)}';
          q = await FirebaseFirestore.instance
              .collection('users')
              .where('phoneNumber', isEqualTo: normalized)
              .limit(1)
              .get();
        }
        if (q.docs.isNotEmpty) {
          final d = q.docs.first.data();
          return {
            'uid': q.docs.first.id,
            'displayName': d['displayName'] as String?,
            'photoUrl': d['photoUrl'] as String?,
          };
        }
      }
    } catch (_) {}
    return null;
  }

  /// Radius "dekat" untuk tombol Batal dinonaktifkan (meter).
  static const int radiusDekatMeter = 300;

  /// Radius maksimal agar icon panggilan suara aktif: driver ≤ 5 km dari penumpang.
  static const int radiusVoiceCallKm = 5;

  /// Radius "berdekatan" untuk scan/konfirmasi (meter). Driver dan penumpang dalam 30 m boleh scan penjemputan/selesai tanpa harus di titik awal/tujuan.
  static const int radiusBerdekatanMeter = 30;

  /// Radius "menjauh" untuk auto-complete (meter). Jika driver dan penumpang berjarak > ini setelah dijemput → pesanan selesai otomatis.
  static const int radiusMenjauhMeter = 500;

  /// Jarak antara dua titik (haversine) dalam km.
  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const p = 0.017453292519943295; // pi/180
    final a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lng2 - lng1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2*R*asin (R=6371 km)
  }

  /// Jarak antara dua titik dalam meter (untuk validasi radius).
  static double _distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    return _haversineKm(lat1, lng1, lat2, lng2) * 1000;
  }

  /// Ambil posisi driver dari driver_status (untuk validasi scan penumpang).
  static Future<(double?, double?)> _getDriverPosition(String driverUid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('driver_status')
          .doc(driverUid)
          .get();
      final d = doc.data();
      if (d == null) return (null, null);
      final lat = (d['latitude'] as num?)?.toDouble();
      final lng = (d['longitude'] as num?)?.toDouble();
      return (lat, lng);
    } catch (_) {
      return (null, null);
    }
  }

  /// Jumlah pesanan aktif (status agreed atau picked_up) untuk suatu nomor rute.
  static Future<int> countActiveOrdersForRoute(
    String routeJourneyNumber,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldRouteJourneyNumber, isEqualTo: routeJourneyNumber)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, whereIn: [statusAgreed, statusPickedUp])
        .get();

    return snapshot.docs.length;
  }

  /// Jumlah pesanan yang sudah dijemput (status picked_up) untuk suatu nomor rute.
  /// Termasuk: penumpang yang sudah dijemput (driver scan barcode penumpang) dan kirim barang yang sudah dijemput.
  /// Dipakai untuk validasi "Selesai Bekerja": tombol tidak bisa diklik jika count > 0; jika masih kosong boleh diklik.
  static Future<int> countPickedUpOrdersForRoute(
    String routeJourneyNumber,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldRouteJourneyNumber, isEqualTo: routeJourneyNumber)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusPickedUp)
        .get();

    return snapshot.docs.length;
  }

  /// Buat pesanan (permintaan penumpang ke driver).
  /// Untuk kirim_barang + receiverUid: status = pending_receiver (tunggu penerima setuju).
  /// [receiverName], [receiverPhotoUrl]: untuk kirim_barang saat link penerima.
  /// [scheduleId] + [scheduledDate]: untuk pesanan terjadwal (Pesan nanti); routeJourneyNumber dipakai 'scheduled'.
  static Future<String?> createOrder({
    required String passengerUid,
    required String driverUid,
    required String routeJourneyNumber,
    required String passengerName,
    String? passengerPhotoUrl,
    required String originText,
    required String destText,
    double? originLat,
    double? originLng,
    double? destLat,
    double? destLng,
    String orderType = 'travel',
    String? receiverUid,
    String? receiverName,
    String? receiverPhotoUrl,
    int? jumlahKerabat,
    String? scheduleId,
    String? scheduledDate,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    if (user.uid != passengerUid) return null;

    final isScheduled =
        (scheduleId?.isNotEmpty ?? false) &&
        (scheduledDate?.isNotEmpty ?? false);
    final effectiveRoute = isScheduled
        ? routeJourneyNumberScheduled
        : routeJourneyNumber;

    final now = FieldValue.serverTimestamp();
    final data = <String, dynamic>{
      'orderNumber': null,
      'passengerUid': passengerUid,
      'driverUid': driverUid,
      'routeJourneyNumber': effectiveRoute,
      'passengerName': passengerName,
      'passengerPhotoUrl': passengerPhotoUrl ?? '',
      'originText': originText,
      'destText': destText,
      'originLat': originLat,
      'originLng': originLng,
      'destLat': destLat,
      'destLng': destLng,
      'passengerLat': null,
      'passengerLng': null,
      'passengerLocationText': null,
      'driverAgreed': false,
      'passengerAgreed': false,
      'orderType': orderType,
      'createdAt': now,
      'updatedAt': now,
    };
    final isKirimBarangWithReceiver = orderType == OrderModel.typeKirimBarang &&
        receiverUid != null &&
        receiverUid.isNotEmpty;
    if (isKirimBarangWithReceiver) {
      data['status'] = statusPendingReceiver;
      data['receiverUid'] = receiverUid;
      if (receiverName != null) data['receiverName'] = receiverName;
      if (receiverPhotoUrl != null) data['receiverPhotoUrl'] = receiverPhotoUrl;
    } else {
      data['status'] = statusPendingAgreement;
      if (receiverUid != null) data['receiverUid'] = receiverUid;
    }
    if (jumlahKerabat != null) data['jumlahKerabat'] = jumlahKerabat;
    if (scheduleId != null) data['scheduleId'] = scheduleId;
    if (scheduledDate != null) data['scheduledDate'] = scheduledDate;
    final ref = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .add(data);
    return ref.id;
  }

  /// Jumlah penumpang dan jumlah kirim barang yang sudah dipesan untuk jadwal ini (status agreed/picked_up).
  /// Untuk tampilan: kapasitas dan "sudah X penumpang, sudah Y kirim barang".
  static Future<({int totalPenumpang, int kirimBarangCount})>
  getScheduledBookingCounts(String scheduleId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection(_collectionOrders)
          .where('scheduleId', isEqualTo: scheduleId)
          .where(_fieldStatus, whereIn: [statusAgreed, statusPickedUp])
          .get();

      int totalPenumpang = 0;
      int kirimBarangCount = 0;
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final orderType = (d['orderType'] as String?) ?? 'travel';
        if (orderType == OrderModel.typeKirimBarang) {
          kirimBarangCount++;
        } else {
          final jk = (d['jumlahKerabat'] as num?)?.toInt();
          totalPenumpang += (jk == null || jk <= 0) ? 1 : (1 + jk);
        }
      }
      return (
        totalPenumpang: totalPenumpang,
        kirimBarangCount: kirimBarangCount,
      );
    } catch (_) {
      return (totalPenumpang: 0, kirimBarangCount: 0);
    }
  }

  /// Daftar order terjadwal dengan info penumpang (nama, foto) untuk satu jadwal.
  /// [travelOnly] true = hanya order travel; [kirimBarangOnly] true = hanya kirim barang.
  static Future<List<Map<String, dynamic>>> getScheduledOrdersWithPassengerInfo(
    String scheduleId, {
    bool? travelOnly,
    bool? kirimBarangOnly,
  }) async {
    try {
      var query = FirebaseFirestore.instance
          .collection(_collectionOrders)
          .where('scheduleId', isEqualTo: scheduleId)
          .where(_fieldStatus, whereIn: [statusAgreed, statusPickedUp]);

      final snap = await query.get();
      final list = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final d = doc.data();
        final orderType = (d['orderType'] as String?) ?? 'travel';
        if (travelOnly == true && orderType != OrderModel.typeTravel) continue;
        if (kirimBarangOnly == true && orderType != OrderModel.typeKirimBarang)
          continue;
        list.add({
          'orderId': doc.id,
          'passengerName': (d['passengerName'] as String?) ?? 'Penumpang',
          'passengerPhotoUrl': d['passengerPhotoUrl'] as String?,
          'orderType': orderType,
          'jumlahKerabat': (d['jumlahKerabat'] as num?)?.toInt(),
        });
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Daftar pesanan terjadwal driver yang sudah ada kesepakatan (agreed/picked_up). Untuk pengingat "punya pesanan terjadwal".
  static Future<List<OrderModel>> getDriverScheduledOrdersWithAgreed() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection(_collectionOrders)
          .where(_fieldDriverUid, isEqualTo: user.uid)
          .where(_fieldStatus, whereIn: [statusAgreed, statusPickedUp])
          .limit(50)
          .get();
      final orders = snap.docs
          .map((d) => OrderModel.fromFirestore(d))
          .where((o) => o.scheduleId != null && o.scheduleId!.isNotEmpty)
          .toList();
      orders.sort((a, b) {
        final ad = a.scheduledDate ?? '';
        final bd = b.scheduledDate ?? '';
        return ad.compareTo(bd);
      });
      return orders;
    } catch (_) {
      return [];
    }
  }

  /// Stream pesanan terjadwal untuk driver (satu scheduleId). Dipakai saat driver aktif dari jadwal.
  static Stream<List<OrderModel>> streamOrdersForDriverBySchedule(
    String scheduleId,
  ) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('scheduleId', isEqualTo: scheduleId)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(
          _fieldStatus,
          whereIn: [
            statusPendingAgreement,
            statusAgreed,
            statusPickedUp,
            statusCompleted,
          ],
        )
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => OrderModel.fromFirestore(d))
              .toList();
          list.sort((a, b) {
            final at = a.createdAt ?? a.updatedAt;
            final bt = b.createdAt ?? b.updatedAt;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
          return list;
        });
  }

  /// Driver klik kesepakatan → masukkan harga → set driverAgreed = true, agreedPrice, agreedPriceAt.
  static Future<bool> setDriverAgreedPrice(
    String orderId,
    double priceRp,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    if (priceRp < 0) return false;

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null || (data[_fieldDriverUid] as String?) != user.uid)
      return false;

    await ref.update({
      'driverAgreed': true,
      'agreedPrice': priceRp,
      'agreedPriceAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Driver klik kesepakatan (tanpa harga, backward compat). Set driverAgreed = true.
  static Future<bool> setDriverAgreed(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null || (data[_fieldDriverUid] as String?) != user.uid)
      return false;

    await ref.update({
      'driverAgreed': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Penumpang klik kesepakatan → set passengerAgreed = true.
  /// Mengembalikan (success, passengerBarcodePayload?) — payload hanya ada saat status jadi agreed.
  static Future<(bool, String?)> setPassengerAgreed(
    String orderId, {
    required double passengerLat,
    required double passengerLng,
    required String passengerLocationText,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, null);

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists) return (false, null);
    final data = doc.data();
    if (data == null || (data[_fieldPassengerUid] as String?) != user.uid)
      return (false, null);

    final driverAgreed = (data['driverAgreed'] as bool?) ?? false;
    final orderType = (data['orderType'] as String?) ?? OrderModel.typeTravel;
    final now = FieldValue.serverTimestamp();
    bool willBecomeAgreed = false;
    String? barcodePayload;

    if (driverAgreed) {
      final orderNumber = await OrderNumberService.generateOrderNumber();
      barcodePayload = 'TRAKA:$orderId:P:${const Uuid().v4()}';
      await ref.update({
        'passengerAgreed': true,
        'orderNumber': orderNumber,
        'passengerLat': passengerLat,
        'passengerLng': passengerLng,
        'passengerLocationText': passengerLocationText,
        'status': statusAgreed,
        'passengerBarcodePayload': barcodePayload,
        'updatedAt': now,
      });
      willBecomeAgreed = true;
    } else {
      await ref.update({'passengerAgreed': true, 'updatedAt': now});
    }

    // Jika status menjadi agreed, hapus semua order lain dari jenis yang sama yang belum agreed
    if (willBecomeAgreed) {
      _deleteOtherOrders(user.uid, orderId, orderType)
          .then((deletedCount) {
            log(
              'OrderService.setPassengerAgreed: Menghapus $deletedCount order $orderType lain untuk penumpang ${user.uid}',
            );
          })
          .catchError((e) {
            log('OrderService.setPassengerAgreed: Error menghapus order lain', e);
          });
    }

    return (true, willBecomeAgreed ? barcodePayload : null);
  }

  /// Update lokasi penumpang di order (untuk live tracking saat driver menuju jemput).
  /// Hanya berlaku jika order status agreed dan penumpang belum dijemput.
  static Future<bool> updatePassengerLocation(
    String orderId, {
    required double passengerLat,
    required double passengerLng,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final ref = FirebaseFirestore.instance
          .collection(_collectionOrders)
          .doc(orderId);
      final doc = await ref.get();
      if (!doc.exists) return false;
      final data = doc.data();
      if (data == null || (data[_fieldPassengerUid] as String?) != user.uid) {
        return false;
      }
      final status = data[_fieldStatus] as String?;
      final driverScanned = data['driverScannedAt'] != null;
      if (status != statusAgreed || driverScanned) return false;

      await ref.update({
        'passengerLat': passengerLat,
        'passengerLng': passengerLng,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Hapus semua order lain dari jenis yang sama yang belum agreed untuk penumpang yang sama.
  /// Dipanggil ketika penumpang setuju kesepakatan dengan satu driver.
  /// Juga menghapus semua chat messages dan file media dari Storage.
  static Future<int> _deleteOtherOrders(
    String passengerUid,
    String excludeOrderId,
    String orderType,
  ) async {
    try {
      // Ambil semua order dari jenis yang sama yang belum agreed
      final snapshot = await FirebaseFirestore.instance
          .collection(_collectionOrders)
          .where(_fieldPassengerUid, isEqualTo: passengerUid)
          .where('orderType', isEqualTo: orderType)
          .where(_fieldStatus, isEqualTo: statusPendingAgreement)
          .get();

      int deletedCount = 0;
      final batch = FirebaseFirestore.instance.batch();
      final deleteStoragePromises = <Future<void>>[];

      for (final doc in snapshot.docs) {
        // Skip order yang sedang disetujui
        if (doc.id == excludeOrderId) continue;

        // Ambil semua chat messages untuk menghapus file media
        final messagesSnap = await doc.reference.collection('messages').get();
        for (final msgDoc in messagesSnap.docs) {
          final msgData = msgDoc.data();
          final msgType = msgData['type'] as String?;

          // Hapus file audio dari Storage
          if (msgType == 'audio') {
            final audioUrl = msgData['audioUrl'] as String?;
            if (audioUrl != null && audioUrl.isNotEmpty) {
              try {
                final uri = Uri.parse(audioUrl);
                final path = uri.path.split('/o/')[1].split('?')[0];
                final decodedPath = Uri.decodeComponent(path);
                deleteStoragePromises.add(
                  FirebaseStorage.instance.ref(decodedPath).delete().catchError((
                    e,
                  ) {
                    log('OrderService._deleteOtherOrders: Gagal hapus audio', e);
                  }),
                );
              } catch (e) {
                log('OrderService._deleteOtherOrders: Error parsing audio URL', e);
              }
            }
          }

          // Hapus file image/video dari Storage
          if (msgType == 'image' || msgType == 'video') {
            final mediaUrl = msgData['mediaUrl'] as String?;
            if (mediaUrl != null && mediaUrl.isNotEmpty) {
              try {
                final uri = Uri.parse(mediaUrl);
                final path = uri.path.split('/o/')[1].split('?')[0];
                final decodedPath = Uri.decodeComponent(path);
                deleteStoragePromises.add(
                  FirebaseStorage.instance.ref(decodedPath).delete().catchError((
                    e,
                  ) {
                    log('OrderService._deleteOtherOrders: Gagal hapus media', e);
                  }),
                );
              } catch (e) {
                log('OrderService._deleteOtherOrders: Error parsing media URL', e);
              }
            }
          }

          // Hapus message document
          batch.delete(msgDoc.reference);
        }

        // Hapus order document
        batch.delete(doc.reference);
        deletedCount++;
      }

      // Commit batch delete untuk Firestore
      if (deletedCount > 0) {
        await batch.commit();
      }

      // Tunggu semua delete Storage selesai (tidak blocking jika ada error)
      await Future.wait(deleteStoragePromises);

      return deletedCount;
    } catch (e) {
      log('OrderService._deleteOtherOrders error', e);
      return 0;
    }
  }

  /// Ambil routeJourneyNumber dari salah satu order aktif driver (agreed/picked_up).
  /// Hanya pakai filter driverUid agar tidak butuh composite index (berguna setelah ganti Firebase project).
  static Future<String?> getRouteJourneyNumberFromDriverActiveOrders() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .limit(50)
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final status = data[_fieldStatus] as String?;
      if (status != statusAgreed && status != statusPickedUp) continue;
      final journey = data[_fieldRouteJourneyNumber] as String?;
      if (journey != null && journey.isNotEmpty) return journey;
    }
    return null;
  }

  /// Stream pesanan untuk driver (rute tertentu): pending_agreement + agreed.
  static Stream<List<OrderModel>> streamOrdersForDriverByRoute(
    String routeJourneyNumber,
  ) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldRouteJourneyNumber, isEqualTo: routeJourneyNumber)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(
          _fieldStatus,
          whereIn: [
            statusPendingAgreement,
            statusAgreed,
            statusPickedUp,
            statusCompleted,
          ],
        )
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => OrderModel.fromFirestore(d)).toList(),
        );
  }

  /// Daftar pesanan status agreed untuk driver saat ini (untuk cek auto-konfirmasi dijemput).
  static Future<List<OrderModel>> getAgreedOrdersForDriver() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusAgreed)
        .limit(50)
        .get();

    return snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
  }

  /// Daftar pesanan status picked_up (travel) untuk driver (untuk cek auto-complete saat menjauh).
  static Future<List<OrderModel>> getPickedUpTravelOrdersForDriver() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusPickedUp)
        .where('orderType', isEqualTo: OrderModel.typeTravel)
        .limit(50)
        .get();

    return snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
  }

  /// Daftar pesanan status picked_up (travel) untuk penumpang (untuk cek auto-complete saat menjauh).
  static Future<List<OrderModel>> getPickedUpTravelOrdersForPassenger() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldPassengerUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusPickedUp)
        .where('orderType', isEqualTo: OrderModel.typeTravel)
        .limit(50)
        .get();

    return snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
  }

  /// Semua pesanan completed untuk driver (untuk fallback riwayat lama tanpa sesi rute).
  static Future<List<OrderModel>> getAllCompletedOrdersForDriver() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusCompleted)
        .get();

    final orders = snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
    orders.sort((a, b) {
      final at = a.completedAt ?? a.updatedAt ?? a.createdAt;
      final bt = b.completedAt ?? b.updatedAt ?? b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return orders;
  }

  /// Daftar pesanan completed untuk satu rute (Riwayat → tap rute).
  /// Untuk rute terjadwal: [scheduleId] wajib agar penumpang per jadwal tampil.
  static Future<List<OrderModel>> getCompletedOrdersForRoute(
    String routeJourneyNumber, {
    String? scheduleId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return [];

    var query = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusCompleted);

    if (routeJourneyNumber == routeJourneyNumberScheduled &&
        scheduleId != null &&
        scheduleId.isNotEmpty) {
      query = query
          .where(_fieldRouteJourneyNumber, isEqualTo: routeJourneyNumberScheduled)
          .where('scheduleId', isEqualTo: scheduleId);
    } else if (routeJourneyNumber.isNotEmpty) {
      query = query.where(
        _fieldRouteJourneyNumber,
        isEqualTo: routeJourneyNumber,
      );
    }

    final snap = await query.get();

    final orders = snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
    orders.sort((a, b) {
      final at = a.completedAt ?? a.updatedAt ?? a.createdAt;
      final bt = b.completedAt ?? b.updatedAt ?? b.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return orders;
  }

  /// Stream pesanan completed untuk driver (Riwayat Rute).
  /// TIDAK filter chatHiddenByDriver agar riwayat tetap tampil walau chat disembunyikan/dihapus.
  static Stream<List<OrderModel>> streamCompletedOrdersForDriver() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: user.uid)
        .where(_fieldStatus, isEqualTo: statusCompleted)
        .snapshots()
        .map((snap) {
          final orders =
              snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
          orders.sort((a, b) {
            final at = a.completedAt ?? a.updatedAt ?? a.createdAt;
            final bt = b.completedAt ?? b.updatedAt ?? b.createdAt;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
          return orders;
        });
  }

  /// Batas order untuk stream (optimasi: hindari load seluruh riwayat).
  static const int streamOrdersLimit = 50;

  /// Stream pesanan untuk penumpang (milik saya).
  /// [includeHidden] true = untuk Data Order/Riwayat (tampilkan semua termasuk yang disembunyikan).
  /// false = untuk list Pesan (exclude chatHiddenByPassenger).
  /// Dibatasi 50 order terakhir.
  static Stream<List<OrderModel>> streamOrdersForPassenger(
      {bool includeHidden = false}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldPassengerUid, isEqualTo: user.uid)
        .orderBy('updatedAt', descending: true)
        .limit(streamOrdersLimit)
        .snapshots()
        .map((snap) {
          try {
            var orders = snap.docs.map((d) => OrderModel.fromFirestore(d));
            if (!includeHidden) {
              orders = orders.where((o) => !o.chatHiddenByPassenger);
            }
            final list = orders.toList();
            list.sort((a, b) {
              final aTime = a.updatedAt ?? a.createdAt;
              final bTime = b.updatedAt ?? b.createdAt;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });
            return list;
          } catch (e) {
            return <OrderModel>[];
          }
        });
  }

  /// Ambil satu pesanan by ID.
  static Future<OrderModel?> getOrderById(String orderId) async {
    final doc = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId)
        .get();
    if (!doc.exists || doc.data() == null) return null;
    return OrderModel.fromFirestore(doc);
  }

  /// Set flag cancellation untuk driver atau penumpang.
  /// Jika kedua pihak sudah klik batalkan, maka status menjadi cancelled.
  static Future<bool> setCancellationFlag(String orderId, bool isDriver) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    final passengerUid = data[_fieldPassengerUid] as String?;
    final driverUid = data[_fieldDriverUid] as String?;

    // Verifikasi user adalah driver atau penumpang dari order ini
    if (isDriver && driverUid != user.uid) return false;
    if (!isDriver && passengerUid != user.uid) return false;

    final currentDriverCancelled = (data['driverCancelled'] as bool?) ?? false;
    final currentPassengerCancelled =
        (data['passengerCancelled'] as bool?) ?? false;

    // Set flag cancellation
    final updateData = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (isDriver) {
      updateData['driverCancelled'] = true;
    } else {
      updateData['passengerCancelled'] = true;
    }

    // Jika kedua pihak sudah klik batalkan, set status menjadi cancelled
    final willBeBothCancelled =
        (isDriver && currentPassengerCancelled) ||
        (!isDriver && currentDriverCancelled);

    if (willBeBothCancelled) {
      updateData['status'] = statusCancelled;

      // Hapus semua chat messages ketika order dibatalkan dan dikonfirmasi
      // Jalankan di background (tidak blocking)
      ChatService.deleteAllMessages(orderId)
          .then((success) {
            if (success) {
              log('OrderService.setCancellationFlag: Chat messages dihapus untuk order $orderId');
            } else {
              log('OrderService.setCancellationFlag: Gagal menghapus chat messages untuk order $orderId');
            }
          })
          .catchError((e) {
            log('OrderService.setCancellationFlag: Error menghapus chat', e);
          });
    }

    await ref.update(updateData);
    return true;
  }

  /// Sembunyikan chat dari list Pesan (order tetap ada untuk riwayat).
  /// Tandai pesan belum terbaca sebagai sudah terbaca.
  /// Hanya untuk order yang sudah agreed/picked_up/completed.
  static Future<String?> hideChatForPassenger(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Anda belum login.';
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return 'Pesanan tidak ditemukan.';
    final data = doc.data()! as Map<String, dynamic>;
    if ((data[_fieldPassengerUid] as String?) != user.uid) {
      return 'Anda bukan penumpang pesanan ini.';
    }
    await ref.update({
      'chatHiddenByPassenger': true,
      'passengerLastReadAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return null;
  }

  /// Sembunyikan chat dari list Pesan (order tetap ada untuk riwayat).
  /// Tandai pesan belum terbaca sebagai sudah terbaca.
  static Future<String?> hideChatForDriver(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Anda belum login.';
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return 'Pesanan tidak ditemukan.';
    final data = doc.data()! as Map<String, dynamic>;
    if ((data[_fieldDriverUid] as String?) != user.uid) {
      return 'Anda bukan driver pesanan ini.';
    }
    await ref.update({
      'chatHiddenByDriver': true,
      'driverLastReadAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return null;
  }

  /// Hapus order beserta seluruh isi chat (messages + media). Dipanggil saat user hapus manual dari list Pesan.
  /// Diperbolehkan: pending_agreement, cancelled (pembatasan pesanan).
  /// Order agreed/picked_up/completed tidak boleh dihapus; gunakan Sembunyikan.
  /// Mengembalikan null jika sukses; String pesan error jika gagal.
  static Future<String?> deleteOrderAndChat(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Anda belum login.';
    if (orderId.isEmpty) return 'ID pesanan tidak valid.';

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    DocumentSnapshot doc;
    try {
      doc = await ref.get();
    } catch (e) {
      log('OrderService.deleteOrderAndChat get error', e);
      return 'Gagal mengakses data. Cek koneksi internet.';
    }
    if (!doc.exists || doc.data() == null) return 'Pesanan tidak ditemukan.';
    final data = doc.data()! as Map<String, dynamic>;
    final driverUid = data[_fieldDriverUid] as String?;
    final passengerUid = data[_fieldPassengerUid] as String?;
    final status = data[_fieldStatus] as String? ?? '';
    if (driverUid != user.uid && passengerUid != user.uid) {
      return 'Anda bukan driver/penumpang pesanan ini.';
    }
    // Order yang sudah kesepakatan/selesai tidak boleh dihapus
    if (status == statusAgreed ||
        status == statusPickedUp ||
        status == statusCompleted) {
      return 'Pesanan yang sudah terjadi kesepakatan tidak bisa dihapus. Gunakan Sembunyikan untuk menyembunyikan dari daftar.';
    }

    // Hapus isi chat dulu (boleh gagal; kalau kosong tidak apa-apa)
    try {
      await ChatService.deleteAllMessages(orderId);
    } catch (e) {
      log('OrderService.deleteOrderAndChat deleteAllMessages', e);
    }
    // Selalu hapus dokumen order agar item hilang dari list (driver & penumpang)
    try {
      await ref.delete();
      return null;
    } on FirebaseException catch (e) {
      log('OrderService.deleteOrderAndChat FirebaseException: ${e.code} ${e.message}');
      if (e.code == 'permission-denied') {
        return 'Izin ditolak. Pastikan Rules Firestore sudah di-publish (izin hapus untuk driver/penumpang).';
      }
      return e.message ?? 'Gagal menghapus (${e.code}).';
    } catch (e) {
      log('OrderService.deleteOrderAndChat error', e);
      return 'Gagal menghapus: $e';
    }
  }

  /// Konfirmasi pembatalan (jika lawan sudah klik batalkan, konfirmasi = benar-benar cancel).
  static Future<bool> confirmCancellation(String orderId, bool isDriver) async {
    // Sama dengan setCancellationFlag, karena jika lawan sudah klik, maka ini akan trigger cancelled
    return await setCancellationFlag(orderId, isDriver);
  }

  /// Batalkan pesanan (penumpang atau driver). Status → cancelled.
  /// [Deprecated] Gunakan setCancellationFlag untuk logika baru.
  static Future<bool> cancelOrder(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    final passengerUid = data[_fieldPassengerUid] as String?;
    final driverUid = data[_fieldDriverUid] as String?;
    if (passengerUid != user.uid && driverUid != user.uid) return false;

    await ref.update({
      'status': statusCancelled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Validasi payload barcode penumpang: TRAKA:orderId:P:*
  /// Return (orderId atau null, pesan error).
  static (String?, String?) parsePassengerBarcodePayload(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length < 4) return (null, 'Format barcode tidak valid.');
    if (parts[0] != 'TRAKA' || parts[2] != 'P')
      return (null, 'Barcode bukan barcode penumpang Traka.');
    return (parts[1], null);
  }

  /// Driver scan barcode penumpang: validasi payload TRAKA:orderId:P:*, pastikan order milik driver,
  /// dan driver dalam radius [radiusDekatMeter] dari lokasi penumpang (titik jemput). Lalu set driverScannedAt, pickupLat/pickupLng, status picked_up.
  /// Return (success, errorMessage, driverBarcodePayload). Jika sukses, driverPayload dipakai untuk kirim ke chat.
  static Future<(bool, String?, String?)> applyDriverScanPassenger(
    String rawPayload, {
    double? pickupLat,
    double? pickupLng,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.', null);

    final (orderId, parseError) = parsePassengerBarcodePayload(rawPayload);
    if (orderId == null)
      return (false, parseError ?? 'Payload tidak valid.', null);

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null)
      return (false, 'Pesanan tidak ditemukan.', null);
    final data = doc.data()!;
    if ((data[_fieldDriverUid] as String?) != user.uid)
      return (false, 'Barcode ini bukan untuk pesanan Anda.', null);
    if ((data[_fieldStatus] as String?) == statusPickedUp)
      return (false, 'Penumpang sudah di-scan sebelumnya.', null);
    if ((data[_fieldStatus] as String?) != statusAgreed)
      return (false, 'Status pesanan tidak sesuai.', null);

    final orderType = (data['orderType'] as String?) ?? OrderModel.typeTravel;
    final isKirimBarang = orderType == OrderModel.typeKirimBarang;

    if (!isKirimBarang) {
      // Travel: tidak ada batasan titik lokasi. Yang penting HP driver dan penumpang saling dekat (dapat scan = berdekatan).
      // Cukup pastikan lokasi driver tersedia untuk catatan perjalanan.
      if (pickupLat == null || pickupLng == null) {
        return (
          false,
          'Lokasi Anda tidak terdeteksi. Pastikan GPS aktif lalu coba lagi.',
          null,
        );
      }
    } else {
      // Kirim barang: tidak wajib pada titik lokasi; yang penting scan barcode. Cukup pastikan lokasi driver tersedia untuk catatan.
      if (pickupLat == null || pickupLng == null) {
        return (
          false,
          'Lokasi Anda tidak terdeteksi. Pastikan GPS aktif lalu coba lagi.',
          null,
        );
      }
    }

    final driverPayload = 'TRAKA:$orderId:D:${const Uuid().v4()}';
    final now = FieldValue.serverTimestamp();
    final updateData = <String, dynamic>{
      'driverScannedAt': now,
      'driverBarcodePayload': driverPayload,
      'status': statusPickedUp,
      'updatedAt': now,
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
    };
    await ref.update(updateData);
    return (true, null, driverPayload);
  }

  /// Driver berhasil scan barcode penumpang (jarak ≤ 500 m). Status → picked_up.
  static Future<bool> setPickedUp(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    if ((data[_fieldDriverUid] as String?) != user.uid) return false;

    await ref.update({
      'status': statusPickedUp,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Validasi payload barcode driver: TRAKA:orderId:D:*
  /// Return (orderId atau null, pesan error).
  static (String?, String?) parseDriverBarcodePayload(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length < 4) return (null, 'Format barcode tidak valid.');
    if (parts[0] != 'TRAKA' || parts[2] != 'D')
      return (null, 'Barcode bukan barcode driver Traka.');
    return (parts[1], null);
  }

  /// Tarif per km (Rupiah). Dibaca dari Firestore app_config/settings; default 70, rentang 70–85.
  static const int _defaultTarifPerKm = 70;
  static const int _minTarifPerKm = 70;
  static const int _maxTarifPerKm = 85;

  static Future<int> _getTarifPerKm() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('settings')
          .get();
      final v = doc.data()?['tarifPerKm'];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n > 0) {
          if (n < _minTarifPerKm) return _minTarifPerKm;
          if (n > _maxTarifPerKm) return _maxTarifPerKm;
          return n;
        }
      }
    } catch (_) {}
    return _defaultTarifPerKm;
  }

  /// Biaya pelanggaran (Rp). Dibaca dari Firestore app_config/settings.
  /// Di bawah 5000 tetap 5000; di atas 5000 mengikuti Firestore.
  static const int _minViolationFeeRupiah = 5000;

  static Future<int> _getViolationFeeRupiah() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('app_config')
          .doc('settings')
          .get();
      final v = doc.data()?['violationFeeRupiah'];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n > 0) {
          return n < _minViolationFeeRupiah ? _minViolationFeeRupiah : n;
        }
      }
    } catch (_) {}
    return _minViolationFeeRupiah;
  }

  /// Radius (meter): jika penumpang masih dalam jarak ini dari titik penjemputan, scan diblokir.
  static const int radiusMasihDiPenjemputanMeter = 150;

  /// Penumpang scan barcode driver: validasi TRAKA:orderId:D:*, order milik penumpang.
  /// Validasi: penumpang tidak boleh masih di titik penjemputan (harus sudah bergerak ke tujuan).
  /// Lalu set passengerScannedAt, status completed, titik turun (jika ada), jarak, tarif.
  /// Return (success, error, orderId). Sukses: (true, null, orderId). Gagal: (false, error, null).
  static Future<(bool, String?, String?)> applyPassengerScanDriver(
    String rawPayload, {
    double? dropLat,
    double? dropLng,
    double? tripDistanceKm,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.', null);

    final (orderId, parseError) = parseDriverBarcodePayload(rawPayload);
    if (orderId == null) return (false, parseError ?? 'Payload tidak valid.', null);

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null)
      return (false, 'Pesanan tidak ditemukan.', null);
    final data = doc.data()!;
    if ((data[_fieldPassengerUid] as String?) != user.uid)
      return (false, 'Barcode ini bukan untuk pesanan Anda.', null);
    if ((data[_fieldStatus] as String?) == statusCompleted)
      return (false, 'Perjalanan sudah selesai.', null);
    if ((data[_fieldStatus] as String?) != statusPickedUp)
      return (false, 'Status pesanan tidak sesuai.', null);

    // Validasi: penumpang tidak boleh masih di titik penjemputan (1 titik lokasi).
    // Scan hanya bisa saat sudah bergerak ke tujuan (bukan masih di tempat jemput).
    final pickLat =
        (data['pickupLat'] as num?)?.toDouble() ??
        (data['passengerLat'] as num?)?.toDouble();
    final pickLng =
        (data['pickupLng'] as num?)?.toDouble() ??
        (data['passengerLng'] as num?)?.toDouble();
    if (pickLat != null &&
        pickLng != null &&
        dropLat != null &&
        dropLng != null) {
      final distDariPenjemputan =
          _distanceMeters(dropLat, dropLng, pickLat, pickLng);
      if (distDariPenjemputan <= radiusMasihDiPenjemputanMeter) {
        return (
          false,
          'Anda masih di titik penjemputan. Scan barcode hanya bisa dilakukan saat sampai tujuan.',
          null,
        );
      }
    } else if (dropLat == null || dropLng == null) {
      return (
        false,
        'Aktifkan GPS dan izin lokasi untuk konfirmasi sampai tujuan.',
        null,
      );
    }

    // Sembunyikan chat langsung untuk driver dan penumpang (pesanan selesai)
    final updateData = <String, dynamic>{
      'passengerScannedAt': FieldValue.serverTimestamp(),
      'status': statusCompleted,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'chatHiddenByPassenger': true,
      'chatHiddenByDriver': true,
      'passengerLastReadAt': FieldValue.serverTimestamp(),
      'driverLastReadAt': FieldValue.serverTimestamp(),
    };
    updateData['dropLat'] = dropLat;
    updateData['dropLng'] = dropLng;
    double? km;
    if (pickLat != null && pickLng != null) {
      km = _haversineKm(pickLat, pickLng, dropLat, dropLng);
      updateData['tripDistanceKm'] = km;
    }
    if (tripDistanceKm != null && tripDistanceKm >= 0) {
      km = tripDistanceKm;
      updateData['tripDistanceKm'] = tripDistanceKm;
    }
    if (km != null && km >= 0) {
      final tarifPerKm = await _getTarifPerKm();
      updateData['tripFareRupiah'] = (km * tarifPerKm).round();
    }
    await ref.update(updateData);
    return (true, null, orderId);
  }

  /// Cek apakah driver dan penumpang saling dekat (untuk nonaktifkan tombol Batal).
  /// [currentLat], [currentLng]: lokasi pengguna yang membuka (driver atau penumpang).
  /// [isDriver]: true = pemanggil adalah driver (bandingkan dengan lokasi penumpang dari order); false = penumpang (bandingkan dengan lokasi driver dari driver_status).
  static Future<bool> isDriverPenumpangDekatForCancel({
    required OrderModel order,
    required double currentLat,
    required double currentLng,
    required bool isDriver,
  }) async {
    if (isDriver) {
      final passLat = order.passengerLat;
      final passLng = order.passengerLng;
      if (passLat == null || passLng == null) return false;
      return _distanceMeters(currentLat, currentLng, passLat, passLng) <=
          radiusDekatMeter;
    } else {
      final (driverLat, driverLng) = await _getDriverPosition(order.driverUid);
      if (driverLat == null || driverLng == null) return false;
      return _distanceMeters(currentLat, currentLng, driverLat, driverLng) <=
          radiusDekatMeter;
    }
  }

  /// Cek apakah panggilan suara boleh digunakan: kesepakatan harga + driver ≤ 5 km dari penumpang.
  /// Return (boleh, alasan jika tidak).
  static Future<(bool, String)> canUseVoiceCall(OrderModel order) async {
    if (order.status != statusAgreed) {
      return (false, 'Panggilan suara hanya tersedia setelah kesepakatan harga.');
    }
    final passLat = order.passengerLat ?? order.pickupLat ?? order.originLat;
    final passLng = order.passengerLng ?? order.pickupLng ?? order.originLng;
    if (passLat == null || passLng == null) {
      return (false, 'Lokasi penumpang belum tersedia.');
    }
    final (driverLat, driverLng) = await _getDriverPosition(order.driverUid);
    if (driverLat == null || driverLng == null) {
      return (false, 'Lokasi driver belum tersedia.');
    }
    final distM = _distanceMeters(driverLat, driverLng, passLat, passLng);
    final radiusM = radiusVoiceCallKm * 1000;
    if (distM > radiusM) {
      return (
        false,
        'Panggilan suara tersedia saat driver dalam radius $radiusVoiceCallKm km dari penumpang (jarak saat ini: ${(distM / 1000).toStringAsFixed(1)} km).',
      );
    }
    return (true, '');
  }

  /// Set waktu driver sampai di titik penjemputan (sekali saja). Dipanggil dari driver app saat driver pertama kali dalam radius 300 m dari titik jemput.
  static Future<bool> setDriverArrivedAtPickupAt(String orderId) async {
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    if ((data[_fieldStatus] as String?) != statusAgreed) return false;
    if (data['driverArrivedAtPickupAt'] != null) return true; // sudah diset
    await ref.update({
      'driverArrivedAtPickupAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Driver konfirmasi penumpang dijemput tanpa scan (semi-otomatis). Sah jika HP driver dan penumpang berdekatan (≤30 m).
  static Future<(bool, String?)> driverConfirmPickupNoScan(
    String orderId,
    double pickupLat,
    double pickupLng,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.');

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null)
      return (false, 'Pesanan tidak ditemukan.');
    final data = doc.data()!;
    if ((data[_fieldDriverUid] as String?) != user.uid)
      return (false, 'Bukan pesanan Anda.');
    if ((data[_fieldStatus] as String?) == statusPickedUp)
      return (false, 'Penumpang sudah dijemput.');
    if ((data[_fieldStatus] as String?) != statusAgreed)
      return (false, 'Status pesanan tidak sesuai.');

    final passLat = (data['passengerLat'] as num?)?.toDouble();
    final passLng = (data['passengerLng'] as num?)?.toDouble();
    if (passLat == null || passLng == null)
      return (false, 'Lokasi penumpang tidak tersedia.');
    final distM = _distanceMeters(pickupLat, pickupLng, passLat, passLng);
    if (distM > radiusBerdekatanMeter) {
      return (
        false,
        'Hanya bisa saat HP Anda dan penumpang berdekatan (radius $radiusBerdekatanMeter m).',
      );
    }

    final orderType = (data['orderType'] as String?) ?? OrderModel.typeTravel;
    final violationFeeRupiah = await _getViolationFeeRupiah();

    final updateData = <String, dynamic>{
      'driverScannedAt': FieldValue.serverTimestamp(),
      'driverBarcodePayload': 'TRAKA:$orderId:D:${const Uuid().v4()}',
      'pickupLat': pickupLat,
      'pickupLng': pickupLng,
      'status': statusPickedUp,
      'updatedAt': FieldValue.serverTimestamp(),
      'autoConfirmPickup': true,
    };
    // Pelanggaran hanya untuk travel, bukan kirim barang.
    if (orderType == OrderModel.typeTravel) {
      updateData['driverViolationFee'] = violationFeeRupiah;
    }
    await ref.update(updateData);

    // Catat pelanggaran driver untuk admin (bayar via kontribusi).
    if (orderType == OrderModel.typeTravel) {
      await FirebaseFirestore.instance.collection('violation_records').add({
        'userId': user.uid,
        'orderId': orderId,
        'amount': violationFeeRupiah,
        'type': 'driver',
        'paidAt': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    return (true, null);
  }

  /// Cek apakah penumpang bisa konfirmasi sampai tujuan: berdekatan (≤30 m) dengan driver ATAU (di tujuan dan dekat driver 300 m). Untuk tampilkan tombol tanpa scan.
  static Future<bool> passengerCanConfirmArrival(
    String orderId,
    double dropLat,
    double dropLng,
  ) async {
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    if ((data[_fieldStatus] as String?) != statusPickedUp) return false;
    final driverUid = data[_fieldDriverUid] as String?;
    if (driverUid == null) return false;
    final (driverLat, driverLng) = await _getDriverPosition(driverUid);
    if (driverLat == null || driverLng == null) return false;
    final distKeDriver = _distanceMeters(dropLat, dropLng, driverLat, driverLng);
    if (distKeDriver <= radiusBerdekatanMeter) return true;
    final destLat = (data['destLat'] as num?)?.toDouble();
    final destLng = (data['destLng'] as num?)?.toDouble();
    if (destLat != null && destLng != null) {
      if (_distanceMeters(dropLat, dropLng, destLat, destLng) >
          radiusDekatMeter)
        return false;
    }
    return distKeDriver <= radiusDekatMeter;
  }

  /// Penumpang konfirmasi sampai tujuan tanpa scan (semi-otomatis). Sah jika penumpang dan driver berdekatan (≤30 m) atau dalam radius 300 m dari tujuan dan dari driver.
  static Future<(bool, String?)> passengerConfirmArrivalNoScan(
    String orderId,
    double dropLat,
    double dropLng,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.');

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null)
      return (false, 'Pesanan tidak ditemukan.');
    final data = doc.data()!;
    if ((data[_fieldPassengerUid] as String?) != user.uid)
      return (false, 'Bukan pesanan Anda.');
    if ((data[_fieldStatus] as String?) == statusCompleted)
      return (false, 'Perjalanan sudah selesai.');
    if ((data[_fieldStatus] as String?) != statusPickedUp)
      return (false, 'Status pesanan tidak sesuai.');

    final driverUid = data[_fieldDriverUid] as String?;
    if (driverUid == null) return (false, 'Data driver tidak valid.');
    final (driverLat, driverLng) = await _getDriverPosition(driverUid);
    if (driverLat == null || driverLng == null)
      return (false, 'Lokasi driver tidak tersedia.');
    final distKeDriver = _distanceMeters(dropLat, dropLng, driverLat, driverLng);
    if (distKeDriver > radiusBerdekatanMeter) {
      final destLat = (data['destLat'] as num?)?.toDouble();
      final destLng = (data['destLng'] as num?)?.toDouble();
      if (destLat != null && destLng != null) {
        if (_distanceMeters(dropLat, dropLng, destLat, destLng) >
            radiusDekatMeter) {
          return (
            false,
            'Anda belum dalam radius $radiusDekatMeter m dari tujuan atau berdekatan $radiusBerdekatanMeter m dengan driver.',
          );
        }
      }
      if (distKeDriver > radiusDekatMeter) {
        return (
          false,
          'Anda belum dalam radius $radiusDekatMeter m dari driver atau berdekatan $radiusBerdekatanMeter m.',
        );
      }
    }

    final orderType = (data['orderType'] as String?) ?? OrderModel.typeTravel;
    final violationFeeRupiah = await _getViolationFeeRupiah();

    final updateData = <String, dynamic>{
      'passengerScannedAt': FieldValue.serverTimestamp(),
      'status': statusCompleted,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'dropLat': dropLat,
      'dropLng': dropLng,
      'chatHiddenByPassenger': true,
      'chatHiddenByDriver': true,
      'passengerLastReadAt': FieldValue.serverTimestamp(),
      'driverLastReadAt': FieldValue.serverTimestamp(),
      'autoConfirmComplete': true,
    };
    // Pelanggaran hanya untuk travel, bukan kirim barang.
    if (orderType == OrderModel.typeTravel) {
      updateData['passengerViolationFee'] = violationFeeRupiah;
    }
    final pickLat =
        (data['pickupLat'] as num?)?.toDouble() ??
        (data['passengerLat'] as num?)?.toDouble();
    final pickLng =
        (data['pickupLng'] as num?)?.toDouble() ??
        (data['passengerLng'] as num?)?.toDouble();
    if (pickLat != null && pickLng != null) {
      final km = _haversineKm(pickLat, pickLng, dropLat, dropLng);
      updateData['tripDistanceKm'] = km;
      final tarifPerKm = await _getTarifPerKm();
      updateData['tripFareRupiah'] = (km * tarifPerKm).round();
    }
    await ref.update(updateData);

    // Pelanggaran penumpang: catat dan update outstanding di users (hanya travel).
    if (orderType == OrderModel.typeTravel) {
      await FirebaseFirestore.instance.collection('violation_records').add({
        'userId': user.uid,
        'orderId': orderId,
        'amount': violationFeeRupiah,
        'type': 'passenger',
        'paidAt': null,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      await userRef.update({
        'outstandingViolationFee': FieldValue.increment(violationFeeRupiah),
        'outstandingViolationCount': FieldValue.increment(1),
      });
    }
    return (true, null);
  }

  /// Auto-complete pesanan saat driver dan penumpang menjauh (>500 m). Dipanggil dari driver atau penumpang app.
  /// [callerLat], [callerLng]: posisi pemanggil. [isDriver]: true jika pemanggil driver.
  static Future<(bool, String?)> completeOrderWhenFarApart(
    String orderId,
    double callerLat,
    double callerLng,
    bool isDriver,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.');

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null)
      return (false, 'Pesanan tidak ditemukan.');
    final data = doc.data()!;
    if ((data[_fieldStatus] as String?) == statusCompleted)
      return (false, 'Perjalanan sudah selesai.');
    if ((data[_fieldStatus] as String?) != statusPickedUp)
      return (false, 'Status pesanan tidak sesuai.');

    double otherLat;
    double otherLng;
    double dropLat;
    double dropLng;
    if (isDriver) {
      if ((data[_fieldDriverUid] as String?) != user.uid)
        return (false, 'Bukan pesanan Anda.');
      final passLat = (data['passengerLat'] as num?)?.toDouble();
      final passLng = (data['passengerLng'] as num?)?.toDouble();
      if (passLat == null || passLng == null)
        return (false, 'Lokasi penumpang belum tersedia.');
      otherLat = passLat;
      otherLng = passLng;
      dropLat = passLat;
      dropLng = passLng;
    } else {
      if ((data[_fieldPassengerUid] as String?) != user.uid)
        return (false, 'Bukan pesanan Anda.');
      final driverUid = data[_fieldDriverUid] as String?;
      if (driverUid == null) return (false, 'Data driver tidak valid.');
      final (driverLat, driverLng) = await _getDriverPosition(driverUid);
      if (driverLat == null || driverLng == null)
        return (false, 'Lokasi driver tidak tersedia.');
      otherLat = driverLat;
      otherLng = driverLng;
      dropLat = callerLat;
      dropLng = callerLng;
    }

    final distM = _distanceMeters(callerLat, callerLng, otherLat, otherLng);
    if (distM <= radiusMenjauhMeter)
      return (false, 'Belum menjauh. Jarak masih ${distM.round()} m.');

    final orderType = (data['orderType'] as String?) ?? OrderModel.typeTravel;
    final violationFeeRupiah = await _getViolationFeeRupiah();

    final updateData = <String, dynamic>{
      'passengerScannedAt': FieldValue.serverTimestamp(),
      'status': statusCompleted,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'dropLat': dropLat,
      'dropLng': dropLng,
      'chatHiddenByPassenger': true,
      'chatHiddenByDriver': true,
      'passengerLastReadAt': FieldValue.serverTimestamp(),
      'driverLastReadAt': FieldValue.serverTimestamp(),
      'autoConfirmComplete': true,
    };
    if (orderType == OrderModel.typeTravel) {
      updateData['passengerViolationFee'] = violationFeeRupiah;
    }
    final pickLat =
        (data['pickupLat'] as num?)?.toDouble() ??
        (data['passengerLat'] as num?)?.toDouble();
    final pickLng =
        (data['pickupLng'] as num?)?.toDouble() ??
        (data['passengerLng'] as num?)?.toDouble();
    if (pickLat != null && pickLng != null) {
      final km = _haversineKm(pickLat, pickLng, dropLat, dropLng);
      updateData['tripDistanceKm'] = km;
      final tarifPerKm = await _getTarifPerKm();
      updateData['tripFareRupiah'] = (km * tarifPerKm).round();
    }
    await ref.update(updateData);

    if (orderType == OrderModel.typeTravel) {
      final passengerUid = data[_fieldPassengerUid] as String?;
      if (passengerUid != null) {
        await FirebaseFirestore.instance.collection('violation_records').add({
          'userId': passengerUid,
          'orderId': orderId,
          'amount': violationFeeRupiah,
          'type': 'passenger',
          'paidAt': null,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await FirebaseFirestore.instance.collection('users').doc(passengerUid).update({
          'outstandingViolationFee': FieldValue.increment(violationFeeRupiah),
          'outstandingViolationCount': FieldValue.increment(1),
        });
      }
    }
    return (true, null);
  }

  /// Penumpang scan barcode driver (sampai tujuan) atau driver scan barcode penerima (kirim barang). Status → completed.
  static Future<bool> setCompleted(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    final driverUid = data[_fieldDriverUid] as String?;
    final passengerUid = data[_fieldPassengerUid] as String?;
    final receiverUid = data['receiverUid'] as String?;
    if (user.uid != driverUid &&
        user.uid != passengerUid &&
        user.uid != receiverUid)
      return false;

    await ref.update({
      'status': statusCompleted,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'chatHiddenByPassenger': true,
      'chatHiddenByDriver': true,
      'passengerLastReadAt': FieldValue.serverTimestamp(),
      'driverLastReadAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Cari pesanan aktif (pending_agreement atau agreed) antara penumpang dan driver.
  /// Untuk membuka chat dengan orderId yang sama.
  static Future<OrderModel?> getActiveOrderBetween(
    String passengerUid,
    String driverUid,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldPassengerUid, isEqualTo: passengerUid)
        .where(_fieldDriverUid, isEqualTo: driverUid)
        .where(
          _fieldStatus,
          whereIn: [statusPendingAgreement, statusAgreed, statusPickedUp],
        )
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return OrderModel.fromFirestore(snapshot.docs.first);
  }

  /// Pesanan aktif pertama untuk driver (untuk tab Chat driver).
  static Future<OrderModel?> getFirstActiveOrderForDriver(
    String driverUid,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: driverUid)
        .where(
          _fieldStatus,
          whereIn: [statusPendingAgreement, statusAgreed, statusPickedUp],
        )
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;
    return OrderModel.fromFirestore(snapshot.docs.first);
  }

  /// Daftar pesanan penumpang untuk halaman list chat (status bukan cancelled).
  static Future<List<OrderModel>> getOrdersForPassenger(
    String passengerUid,
  ) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldPassengerUid, isEqualTo: passengerUid)
        .where(
          _fieldStatus,
          whereIn: [
            statusPendingAgreement,
            statusAgreed,
            statusPickedUp,
            statusCompleted,
          ],
        )
        .orderBy('updatedAt', descending: true)
        .get();

    return snapshot.docs.map((d) => OrderModel.fromFirestore(d)).toList();
  }

  /// Daftar pesanan driver untuk halaman list chat (status bukan cancelled).
  static Future<List<OrderModel>> getOrdersForDriver(String driverUid) async {
    final snapshot = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: driverUid)
        .where(
          _fieldStatus,
          whereIn: [
            statusPendingAgreement,
            statusAgreed,
            statusPickedUp,
            statusCompleted,
          ],
        )
        .orderBy('updatedAt', descending: true)
        .get();

    return snapshot.docs.map((d) => OrderModel.fromFirestore(d)).toList();
  }

  /// Penerima setuju jadi penerima (kirim barang). Status → pending_agreement; order lalu muncul ke driver.
  static Future<bool> setReceiverAgreed(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    if ((data['receiverUid'] as String?) != user.uid) return false;
    if ((data[_fieldStatus] as String?) != statusPendingReceiver) return false;
    await ref.update({
      'receiverAgreedAt': FieldValue.serverTimestamp(),
      'status': statusPendingAgreement,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Penerima menolak jadi penerima (kirim barang). Status → cancelled.
  static Future<bool> setReceiverRejected(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null) return false;
    final data = doc.data()!;
    if ((data['receiverUid'] as String?) != user.uid) return false;
    if ((data[_fieldStatus] as String?) != statusPendingReceiver) return false;
    await ref.update({
      'status': statusCancelled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return true;
  }

  /// Penerima scan barcode driver (barang diterima). Kirim barang tidak wajib pada titik lokasi — yang penting scan barcode. Set receiverScannedAt, status completed.
  /// Return (success, error, orderId). Kirim barang: tidak ada rating driver.
  static Future<(bool, String?, String?)> applyReceiverScanDriver(
    String rawPayload, {
    double? dropLat,
    double? dropLng,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return (false, 'Anda belum login.', null);

    final (orderId, parseError) = parseDriverBarcodePayload(rawPayload);
    if (orderId == null) return (false, parseError ?? 'Payload tidak valid.', null);

    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists || doc.data() == null)
      return (false, 'Pesanan tidak ditemukan.', null);
    final data = doc.data()!;
    if ((data['receiverUid'] as String?) != user.uid)
      return (false, 'Barcode ini bukan untuk pesanan Anda (penerima).', null);
    if ((data['orderType'] as String?) != OrderModel.typeKirimBarang)
      return (false, 'Bukan pesanan kirim barang.', null);
    if ((data[_fieldStatus] as String?) == statusCompleted)
      return (false, 'Barang sudah diterima.', null);
    if ((data[_fieldStatus] as String?) != statusPickedUp)
      return (false, 'Driver belum mengantarkan barang. Pastikan driver sudah scan pengirim.', null);

    if (dropLat == null || dropLng == null)
      return (false, 'Lokasi Anda tidak terdeteksi. Pastikan GPS aktif.', null);

    // Kirim barang: tidak validasi jarak penerima–driver; yang penting scan barcode.
    // Sembunyikan chat langsung untuk driver dan penumpang (pesanan selesai)

    final updateData = <String, dynamic>{
      'receiverScannedAt': FieldValue.serverTimestamp(),
      'status': statusCompleted,
      'completedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'dropLat': dropLat,
      'dropLng': dropLng,
      'chatHiddenByPassenger': true,
      'chatHiddenByDriver': true,
      'passengerLastReadAt': FieldValue.serverTimestamp(),
      'driverLastReadAt': FieldValue.serverTimestamp(),
    };
    final pickLat = (data['pickupLat'] as num?)?.toDouble() ?? (data['passengerLat'] as num?)?.toDouble();
    final pickLng = (data['pickupLng'] as num?)?.toDouble() ?? (data['passengerLng'] as num?)?.toDouble();
    if (pickLat != null && pickLng != null) {
      updateData['tripDistanceKm'] = _haversineKm(pickLat, pickLng, dropLat, dropLng);
    }
    await ref.update(updateData);
    return (true, null, orderId);
  }

  /// Stream pesanan dimana user adalah penerima (untuk konfirmasi "Anda ditunjuk sebagai penerima").
  static Stream<List<OrderModel>> streamOrdersForReceiver(String receiverUid) {
    return FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where('receiverUid', isEqualTo: receiverUid)
        .where(_fieldStatus, whereIn: [statusPendingReceiver, statusPendingAgreement, statusAgreed, statusPickedUp, statusCompleted])
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) => OrderModel.fromFirestore(d)).toList();
          list.sort((a, b) {
            final at = a.updatedAt ?? a.createdAt;
            final bt = b.updatedAt ?? b.createdAt;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
          return list;
        });
  }

  /// Stream pesanan untuk driver (untuk badge unread chat).
  /// Stream pesanan untuk driver (list chat). Filter: exclude chatHiddenByDriver.
  /// Termasuk status cancelled agar chat pesanan yang dibatalkan bisa dihapus manual.
  /// Dibatasi 50 order terakhir.
  static Stream<List<OrderModel>> streamOrdersForDriver(String driverUid) {
    return FirebaseFirestore.instance
        .collection(_collectionOrders)
        .where(_fieldDriverUid, isEqualTo: driverUid)
        .where(
          _fieldStatus,
          whereIn: [
            statusPendingAgreement,
            statusAgreed,
            statusPickedUp,
            statusCompleted,
            statusCancelled,
          ],
        )
        .orderBy('updatedAt', descending: true)
        .limit(streamOrdersLimit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => OrderModel.fromFirestore(d))
            .where((o) => !o.chatHiddenByDriver)
            .toList());
  }

  /// Set waktu terakhir driver baca chat (untuk badge unread). Dipanggil saat driver buka chat.
  static Future<bool> setDriverLastReadAt(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null || (data[_fieldDriverUid] as String?) != user.uid)
      return false;
    await ref.update({'driverLastReadAt': FieldValue.serverTimestamp()});
    return true;
  }

  /// Set waktu terakhir penumpang baca chat (untuk badge unread). Dipanggil saat penumpang buka chat.
  static Future<bool> setPassengerLastReadAt(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final ref = FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId);
    final doc = await ref.get();
    if (!doc.exists) return false;
    final data = doc.data();
    if (data == null || (data[_fieldPassengerUid] as String?) != user.uid)
      return false;
    await ref.update({'passengerLastReadAt': FieldValue.serverTimestamp()});
    return true;
  }
}
