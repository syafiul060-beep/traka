import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/chat_message_model.dart';
import '../utils/app_logger.dart';
import 'chat_filter_service.dart';

/// Service untuk chat (pesan teks, audio, gambar, video) per order.
/// Pesan disimpan di subcollection: orders/{orderId}/messages.
class ChatService {
  static const String _collectionOrders = 'orders';
  static const String _subcollectionMessages = 'messages';

  /// Alasan pesan diblokir (jika sendMessage/sendAudioMessage/sendImageMessage return false karena filter).
  static String? lastBlockedReason;

  /// Kirim pesan teks ke order. Hanya penumpang atau driver order tersebut.
  static Future<bool> sendMessage(String orderId, String text) async {
    lastBlockedReason = null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || text.trim().isEmpty) return false;
    if (orderId.isEmpty) return false;

    if (ChatFilterService.containsBlockedContent(text)) {
      lastBlockedReason = ChatFilterService.blockedMessage;
      return false;
    }

    try {
      final ref = FirebaseFirestore.instance
          .collection(_collectionOrders)
          .doc(orderId)
          .collection(_subcollectionMessages);

      await ref.add({
        'senderUid': user.uid,
        'text': text.trim(),
        'type': 'text',
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
      });
      return true;
    } catch (e) {
      log('ChatService.sendMessage error', e);
      return false;
    }
  }

  /// Kirim pesan barcode (penumpang/driver) ke chat. [barcodeType]: 'barcode_passenger' | 'barcode_driver'.
  static Future<bool> sendBarcodeMessage(
    String orderId,
    String payload,
    String barcodeType,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || orderId.isEmpty || payload.isEmpty) return false;
    if (barcodeType != 'barcode_passenger' && barcodeType != 'barcode_driver')
      return false;
    try {
      final ref = FirebaseFirestore.instance
          .collection(_collectionOrders)
          .doc(orderId)
          .collection(_subcollectionMessages);
      await ref.add({
        'senderUid': user.uid,
        'text': payload,
        'type': barcodeType,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
      });
      return true;
    } catch (e) {
      log('ChatService.sendBarcodeMessage error', e);
      return false;
    }
  }

  /// Kirim pesan audio ke order.
  /// [audioFile]: File audio yang sudah direkam
  /// [duration]: Durasi audio dalam detik
  static Future<bool> sendAudioMessage(
    String orderId,
    File audioFile,
    int duration,
  ) async {
    lastBlockedReason = null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || orderId.isEmpty) {
      log('ChatService.sendAudioMessage: User null atau orderId kosong');
      return false;
    }

    if (ChatFilterService.blockAudioMessages) {
      lastBlockedReason = ChatFilterService.blockedMessage;
      return false;
    }

    // Validasi file
    if (!await audioFile.exists()) {
      log('ChatService.sendAudioMessage: File tidak ada di ${audioFile.path}');
      return false;
    }

    final fileSize = await audioFile.length();
    if (fileSize == 0) {
      log('ChatService.sendAudioMessage: File kosong (0 bytes)');
      return false;
    }

    try {
      // Upload audio ke Firebase Storage
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.m4a';
      final ref = FirebaseStorage.instance.ref('chat_audio/$orderId/$fileName');

      final uploadTask = ref.putFile(audioFile);
      await uploadTask;

      final audioUrl = await ref.getDownloadURL();

      // Simpan ke Firestore
      final messageRef = FirebaseFirestore.instance
          .collection(_collectionOrders)
          .doc(orderId)
          .collection(_subcollectionMessages);

      await messageRef.add({
        'senderUid': user.uid,
        'text': '', // Kosong untuk audio
        'type': 'audio',
        'audioUrl': audioUrl,
        'audioDuration': duration,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
      });

      return true;
    } catch (e, stackTrace) {
      log('ChatService.sendAudioMessage error', e, stackTrace);
      return false;
    }
  }

  /// Kirim pesan gambar ke order.
  static Future<bool> sendImageMessage(String orderId, File imageFile) async {
    lastBlockedReason = null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || orderId.isEmpty) return false;

    if (await ChatFilterService.imageContainsBlockedContent(imageFile)) {
      lastBlockedReason = ChatFilterService.blockedMessage;
      return false;
    }

    try {
      // Upload gambar ke Firebase Storage
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = FirebaseStorage.instance.ref(
        'chat_images/$orderId/$fileName',
      );

      await ref.putFile(imageFile);
      final imageUrl = await ref.getDownloadURL();

      // Simpan ke Firestore
      final messageRef = FirebaseFirestore.instance
          .collection(_collectionOrders)
          .doc(orderId)
          .collection(_subcollectionMessages);

      await messageRef.add({
        'senderUid': user.uid,
        'text': '', // Kosong untuk gambar
        'type': 'image',
        'mediaUrl': imageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
      });

      return true;
    } catch (e) {
      log('ChatService.sendImageMessage error', e);
      return false;
    }
  }

  /// Kirim pesan video ke order.
  static Future<bool> sendVideoMessage(String orderId, File videoFile) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || orderId.isEmpty) return false;

    try {
      // Upload video ke Firebase Storage
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.mp4';
      final ref = FirebaseStorage.instance.ref(
        'chat_videos/$orderId/$fileName',
      );

      await ref.putFile(videoFile);
      final videoUrl = await ref.getDownloadURL();

      // Simpan ke Firestore
      final messageRef = FirebaseFirestore.instance
          .collection(_collectionOrders)
          .doc(orderId)
          .collection(_subcollectionMessages);

      await messageRef.add({
        'senderUid': user.uid,
        'text': '', // Kosong untuk video
        'type': 'video',
        'mediaUrl': videoUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
      });

      return true;
    } catch (e) {
      log('ChatService.sendVideoMessage error', e);
      return false;
    }
  }

  static const String statusSent = 'sent';
  static const String statusDelivered = 'delivered';
  static const String statusRead = 'read';

  /// Batas pesan untuk mark delivered/read (optimasi: hindari fetch seluruh chat).
  static const int _markStatusLimit = 100;

  /// Penerima buka chat: tandai pesan lawan yang masih 'sent' (atau belum punya status) menjadi 'delivered'.
  /// Dibatasi ke 100 pesan terakhir untuk optimasi.
  static Future<void> markAsDelivered(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId)
        .collection(_subcollectionMessages)
        .orderBy('createdAt', descending: true)
        .limit(_markStatusLimit)
        .get();
    final batch = FirebaseFirestore.instance.batch();
    var hasWrites = false;
    for (final doc in snap.docs) {
      final data = doc.data();
      if ((data['senderUid'] as String?) != user.uid) {
        final s = data['status'] as String?;
        if (s == null || s == statusSent) {
          batch.update(doc.reference, {'status': statusDelivered});
          hasWrites = true;
        }
      }
    }
    if (hasWrites) await batch.commit();
  }

  /// Penerima sedang melihat chat: tandai pesan lawan 'delivered' menjadi 'read'.
  /// Dibatasi ke 100 pesan terakhir untuk optimasi.
  static Future<void> markAsRead(String orderId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId)
        .collection(_subcollectionMessages)
        .orderBy('createdAt', descending: true)
        .limit(_markStatusLimit)
        .get();
    final batch = FirebaseFirestore.instance.batch();
    var hasWrites = false;
    for (final doc in snap.docs) {
      final data = doc.data();
      if ((data['senderUid'] as String?) != user.uid &&
          (data['status'] as String?) == statusDelivered) {
        batch.update(doc.reference, {'status': statusRead});
        hasWrites = true;
      }
    }
    if (hasWrites) await batch.commit();
  }

  /// Cek apakah sudah ada pesan di order (untuk kirim pesan jenis hanya jika ini pesan pertama).
  static Future<bool> hasAnyMessage(String orderId) async {
    if (orderId.isEmpty) return true;
    final snap = await FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId)
        .collection(_subcollectionMessages)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// Batas pesan untuk tampilan chat (optimasi: hindari load seluruh riwayat).
  static const int streamMessagesLimit = 100;

  /// Stream pesan untuk satu order (untuk tampilan chat room).
  /// Dibatasi 100 pesan terakhir. Pesan terbaru di bawah seperti WhatsApp standar.
  static Stream<List<ChatMessageModel>> streamMessages(String orderId) {
    return FirebaseFirestore.instance
        .collection(_collectionOrders)
        .doc(orderId)
        .collection(_subcollectionMessages)
        .orderBy('createdAt', descending: true)
        .limit(streamMessagesLimit)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) => ChatMessageModel.fromFirestore(d)).toList();
          list.sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
          return list;
        });
  }

  /// Ambil info user (displayName, photoUrl, verified) dari users collection.
  /// verified = true jika driver (SIM) atau penumpang (KTP) sudah terverifikasi.
  static Future<Map<String, dynamic>> getUserInfo(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final d = doc.data();
    if (d == null)
      return {'displayName': null, 'photoUrl': null, 'verified': false};
    final verified = d['driverSIMVerifiedAt'] != null ||
        d['driverSIMNomorHash'] != null ||
        d['passengerKTPVerifiedAt'] != null;
    return {
      'displayName': d['displayName'] as String?,
      'photoUrl': d['photoUrl'] as String?,
      'verified': verified,
    };
  }

  /// Hapus semua pesan chat dari suatu order (ketika order dibatalkan).
  /// Juga menghapus file media (audio, image, video) dari Storage jika ada.
  static Future<bool> deleteAllMessages(String orderId) async {
    if (orderId.isEmpty) return false;

    try {
      // Ambil semua messages untuk mendapatkan URL media yang perlu dihapus
      final messagesSnap = await FirebaseFirestore.instance
          .collection(_collectionOrders)
          .doc(orderId)
          .collection(_subcollectionMessages)
          .get();

      // Hapus file media dari Storage
      final storageRef = FirebaseStorage.instance.ref();
      final deletePromises = <Future<void>>[];

      for (final doc in messagesSnap.docs) {
        final data = doc.data();
        final type = data['type'] as String?;

        // Hapus audio file
        if (type == 'audio') {
          final audioUrl = data['audioUrl'] as String?;
          if (audioUrl != null && audioUrl.isNotEmpty) {
            try {
              // Extract path dari URL
              final uri = Uri.parse(audioUrl);
              final path = uri.path.split('/o/')[1].split('?')[0];
              final decodedPath = Uri.decodeComponent(path);
              deletePromises.add(
                storageRef.child(decodedPath).delete().catchError((e) {
                  log('ChatService.deleteAllMessages: Gagal hapus audio', e);
                }),
              );
            } catch (e) {
              log('ChatService.deleteAllMessages: Error parsing audio URL', e);
            }
          }
        }

        // Hapus image file
        if (type == 'image' || type == 'video') {
          final mediaUrl = data['mediaUrl'] as String?;
          if (mediaUrl != null && mediaUrl.isNotEmpty) {
            try {
              // Extract path dari URL
              final uri = Uri.parse(mediaUrl);
              final path = uri.path.split('/o/')[1].split('?')[0];
              final decodedPath = Uri.decodeComponent(path);
              deletePromises.add(
                storageRef.child(decodedPath).delete().catchError((e) {
                  log('ChatService.deleteAllMessages: Gagal hapus media', e);
                }),
              );
            } catch (e) {
              log('ChatService.deleteAllMessages: Error parsing media URL', e);
            }
          }
        }
      }

      // Hapus semua messages dari Firestore menggunakan batch
      if (messagesSnap.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in messagesSnap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      // Tunggu semua delete Storage selesai (tidak blocking jika ada error)
      await Future.wait(deletePromises);

      log('ChatService.deleteAllMessages: Semua pesan dan media dihapus untuk order $orderId');
      return true;
    } catch (e) {
      log('ChatService.deleteAllMessages error', e);
      return false;
    }
  }
}
