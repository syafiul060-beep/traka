import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/support_message_model.dart';
import '../models/support_ticket_model.dart';
import '../utils/app_logger.dart';
import 'chat_filter_service.dart';

/// Service live chat support dengan auto-reply, antrian, dan sambungan ke admin.
/// Struktur: admin_chats/{userId} + messages subcollection.
/// status: bot | in_queue | connected | closed
class SupportChatService {
  static const String _collectionAdminChats = 'admin_chats';
  static const String _subcollectionMessages = 'messages';
  static const String _collectionAdminStatus = 'admin_status';

  static const String statusBot = 'bot';
  static const String statusInQueue = 'in_queue';
  static const String statusConnected = 'connected';
  static const String statusClosed = 'closed';

  static const String senderUser = 'user';
  static const String senderAdmin = 'admin';
  static const String senderBot = 'bot';

  static const String _botUid = 'bot';

  static String? lastBlockedReason;

  /// Kata kunci untuk minta sambungan ke admin
  static final List<String> _requestAdminKeywords = [
    'admin',
    'hubungi admin',
    'sambungkan admin',
    'butuh admin',
    'tolong admin',
    'cs',
    'customer service',
    'bantuan manusia',
    'bantuan admin',
  ];

  static bool _isRequestAdminKeyword(String text) {
    final lower = text.toLowerCase().trim();
    return _requestAdminKeywords.any((k) => lower.contains(k));
  }

  /// Auto-reply bot saat pertama kali user kirim pesan
  static const String _welcomeMessage = '''Hai! Terima kasih telah menghubungi Traka. 👋

Saya adalah asisten otomatis. Ada yang bisa saya bantu?

• Ketik pertanyaan Anda, atau
• Ketik "admin" atau "hubungi admin" untuk berbicara langsung dengan tim kami.

Jika ada antrian, kami akan memberitahu posisi Anda.''';

  /// Balasan saat user minta admin dan masuk antrian
  static String _queueMessage(int position) =>
      'Anda telah masuk antrian. Posisi Anda: #$position. Admin akan segera melayani. Mohon tunggu.';

  /// Kirim pesan dari user. Handle auto-reply, request admin, dan forward ke admin.
  static Future<bool> sendUserMessage(String userId, String text) async {
    lastBlockedReason = null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || text.trim().isEmpty) return false;
    if (userId != user.uid) return false;

    if (ChatFilterService.containsBlockedContent(text)) {
      lastBlockedReason = ChatFilterService.blockedMessage;
      return false;
    }

    try {
      final firestore = FirebaseFirestore.instance;
      final chatRef = firestore.collection(_collectionAdminChats).doc(userId);
      final messagesRef = chatRef.collection(_subcollectionMessages);

      final chatDoc = await chatRef.get();
      final existing = chatDoc.data();
      final currentStatus = (existing?['status'] as String?) ?? statusBot;

      String displayName = user.displayName ?? user.email ?? '';
      try {
        final userDoc = await firestore.collection('users').doc(userId).get();
        final d = userDoc.data();
        if (d != null && (d['displayName'] as String?)?.isNotEmpty == true) {
          displayName = d['displayName'] as String;
        }
      } catch (_) {}

      final batch = firestore.batch();

      // 1. Simpan pesan user
      final userMsgData = {
        'senderUid': user.uid,
        'senderType': senderUser,
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
      };
      batch.set(messagesRef.doc(), userMsgData);

      Map<String, dynamic> chatUpdate = {
        'userId': userId,
        'displayName': displayName,
        'lastMessage': text.trim(),
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 2. Cek apakah user minta sambungan ke admin
      if (_isRequestAdminKeyword(text)) {
        if (currentStatus == statusBot || currentStatus == statusClosed) {
          // Cek ada admin online
          final availableAdmin = await _getAvailableAdmin(firestore);
          if (availableAdmin != null) {
            // Langsung sambungkan
            chatUpdate['status'] = statusConnected;
            chatUpdate['assignedAdminId'] = availableAdmin.id;
            chatUpdate['assignedAdminName'] = availableAdmin.name;
            // Kirim pesan sistem dari bot
            batch.set(messagesRef.doc(), {
              'senderUid': _botUid,
              'senderType': senderBot,
              'text': 'Anda terhubung dengan ${availableAdmin.name}. Silakan sampaikan keluhan Anda.',
              'createdAt': FieldValue.serverTimestamp(),
              'status': 'sent',
            });
            await _setAdminBusy(firestore, availableAdmin.id, userId);
          } else {
            // Masuk antrian - set dulu, lalu hitung posisi
            chatUpdate['status'] = statusInQueue;
            chatUpdate['queueJoinedAt'] = FieldValue.serverTimestamp();
            // Commit batch dulu untuk set queueJoinedAt, lalu hitung posisi
            batch.set(chatRef, chatUpdate, SetOptions(merge: true));
            await batch.commit();
            final position = await _getQueuePosition(firestore, userId);
            await chatRef.update({
              'queuePosition': position,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            await messagesRef.add({
              'senderUid': _botUid,
              'senderType': senderBot,
              'text': _queueMessage(position),
              'createdAt': FieldValue.serverTimestamp(),
              'status': 'sent',
            });
            return true;
          }
        } else if (currentStatus == statusInQueue) {
          // Sudah di antrian, kirim balasan bot
          final pos = (existing?['queuePosition'] as int?) ?? 1;
          batch.set(messagesRef.doc(), {
            'senderUid': _botUid,
            'senderType': senderBot,
            'text': _queueMessage(pos),
            'createdAt': FieldValue.serverTimestamp(),
            'status': 'sent',
          });
        }
      } else {
        // Bukan keyword admin - handle berdasarkan status
        if (currentStatus == statusBot || currentStatus == statusClosed) {
          // First message atau setelah closed: kirim welcome
          batch.set(messagesRef.doc(), {
            'senderUid': _botUid,
            'senderType': senderBot,
            'text': _welcomeMessage,
            'createdAt': FieldValue.serverTimestamp(),
            'status': 'sent',
          });
          if (currentStatus == statusClosed) {
            chatUpdate['status'] = statusBot;
          }
        }
      }

      batch.set(chatRef, chatUpdate, SetOptions(merge: true));
      await batch.commit();
      return true;
    } catch (e, st) {
      // ignore: avoid_print
      log('SupportChatService.sendUserMessage error', e, st);
      if (e is FirebaseException && e.code == 'permission-denied') {
        lastBlockedReason =
            'Akses ditolak. Pastikan aturan Firestore admin_status sudah di-deploy.';
      }
      return false;
    }
  }

  static Future<({String id, String name})?> _getAvailableAdmin(
      FirebaseFirestore firestore) async {
    final snap = await firestore
        .collection(_collectionAdminStatus)
        .where('status', isEqualTo: 'online')
        .limit(5)
        .get();
    for (final doc in snap.docs) {
      final d = doc.data();
      if ((d['currentChatUserId'] as String?)?.isEmpty != false) {
        return (id: doc.id, name: d['displayName'] as String? ?? 'Admin');
      }
    }
    return null;
  }

  static Future<int> _getQueuePosition(
      FirebaseFirestore firestore, String userId) async {
    final queueSnap = await firestore
        .collection(_collectionAdminChats)
        .where('status', isEqualTo: statusInQueue)
        .orderBy('queueJoinedAt', descending: false)
        .get();
    final idx = queueSnap.docs.indexWhere((d) => d.id == userId);
    return idx >= 0 ? idx + 1 : queueSnap.docs.length + 1;
  }

  static Future<void> _setAdminBusy(
      FirebaseFirestore firestore, String adminId, String userId) async {
    await firestore.collection(_collectionAdminStatus).doc(adminId).set({
      'status': 'busy',
      'currentChatUserId': userId,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stream pesan untuk satu user
  static Stream<List<SupportMessageModel>> streamMessages(String userId) {
    return FirebaseFirestore.instance
        .collection(_collectionAdminChats)
        .doc(userId)
        .collection(_subcollectionMessages)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => SupportMessageModel.fromFirestore(d)).toList());
  }

  /// Stream ticket/sesi untuk satu user
  static Stream<SupportTicketModel?> streamTicket(String userId) {
    return FirebaseFirestore.instance
        .collection(_collectionAdminChats)
        .doc(userId)
        .snapshots()
        .map((snap) =>
            snap.exists ? SupportTicketModel.fromFirestore(snap) : null);
  }

  /// Admin: set status online saat buka panel
  static Future<void> setAdminOnline(String adminId, String displayName) async {
    try {
      await FirebaseFirestore.instance
          .collection(_collectionAdminStatus)
          .doc(adminId)
          .set({
        'status': 'online',
        'displayName': displayName,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // ignore: avoid_print
      log('SupportChatService.setAdminOnline error: $e');
    }
  }

  /// Admin: set status offline saat tutup/keluar
  static Future<void> setAdminOffline(String adminId) async {
    try {
      await FirebaseFirestore.instance
          .collection(_collectionAdminStatus)
          .doc(adminId)
          .set({
        'status': 'offline',
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // ignore: avoid_print
      log('SupportChatService.setAdminOffline error: $e');
    }
  }

  /// Admin: ambil chat dari antrian (sambungkan ke admin)
  static Future<bool> adminTakeChat(String adminId, String adminName,
      String userId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final chatRef = firestore.collection(_collectionAdminChats).doc(userId);
      final messagesRef = chatRef.collection(_subcollectionMessages);

      final batch = firestore.batch();
      batch.set(chatRef, {
        'status': statusConnected,
        'assignedAdminId': adminId,
        'assignedAdminName': adminName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      batch.set(messagesRef.doc(), {
        'senderUid': _botUid,
        'senderType': senderBot,
        'text': 'Anda terhubung dengan $adminName. Silakan sampaikan keluhan Anda.',
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
      });

      await batch.commit();
      await _setAdminBusy(firestore, adminId, userId);
      return true;
    } catch (e) {
      // ignore: avoid_print
      log('SupportChatService.adminTakeChat error: $e');
      return false;
    }
  }

  /// Admin: kirim pesan ke user
  static Future<bool> adminSendMessage(
      String adminId, String adminName, String userId, String text) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final chatRef = firestore.collection(_collectionAdminChats).doc(userId);
      final messagesRef = chatRef.collection(_subcollectionMessages);

      final batch = firestore.batch();
      batch.set(messagesRef.doc(), {
        'senderUid': adminId,
        'senderType': senderAdmin,
        'text': text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
      });
      batch.set(chatRef, {
        'lastMessage': text.trim(),
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
      return true;
    } catch (e) {
      // ignore: avoid_print
      log('SupportChatService.adminSendMessage error: $e');
      return false;
    }
  }

  /// Admin: tutup chat (set status closed, admin kembali online)
  static Future<bool> adminCloseChat(String adminId, String userId) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final chatRef = firestore.collection(_collectionAdminChats).doc(userId);
      final messagesRef = chatRef.collection(_subcollectionMessages);

      final batch = firestore.batch();
      batch.set(chatRef, {
        'status': statusClosed,
        'assignedAdminId': null,
        'assignedAdminName': null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(messagesRef.doc(), {
        'senderUid': _botUid,
        'senderType': senderBot,
        'text': 'Chat telah ditutup. Terima kasih telah menghubungi kami. Ketik pesan baru untuk memulai lagi.',
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
      });
      await batch.commit();

      await firestore.collection(_collectionAdminStatus).doc(adminId).set({
        'status': 'online',
        'currentChatUserId': null,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      // ignore: avoid_print
      log('SupportChatService.adminCloseChat error: $e');
      return false;
    }
  }

  /// Stream antrian (user dengan status in_queue)
  static Stream<List<SupportTicketModel>> streamQueue() {
    return FirebaseFirestore.instance
        .collection(_collectionAdminChats)
        .where('status', isEqualTo: statusInQueue)
        .orderBy('queueJoinedAt', descending: false)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => SupportTicketModel.fromFirestore(d)).toList());
  }

  /// Stream chat yang sedang dilayani admin tertentu
  static Stream<String?> streamAdminCurrentChat(String adminId) {
    return FirebaseFirestore.instance
        .collection(_collectionAdminStatus)
        .doc(adminId)
        .snapshots()
        .map((snap) {
      final d = snap.data();
      return d?['currentChatUserId'] as String?;
    });
  }

  /// Hitung posisi antrian untuk user (untuk update real-time)
  static Future<int> getQueuePosition(String userId) async {
    final snap = await FirebaseFirestore.instance
        .collection(_collectionAdminChats)
        .where('status', isEqualTo: statusInQueue)
        .orderBy('queueJoinedAt', descending: false)
        .get();
    final idx = snap.docs.indexWhere((d) => d.id == userId);
    return idx >= 0 ? idx + 1 : 0;
  }
}
