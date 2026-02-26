import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/chat_message_model.dart';
import '../utils/app_logger.dart';
import 'chat_filter_service.dart';

/// Service untuk chat user dengan admin.
/// Pesan disimpan di: admin_chats/{userId}/messages.
/// userId = uid user (penumpang/driver) yang chat dengan admin.
class AdminChatService {
  static const String _collectionAdminChats = 'admin_chats';
  static const String _subcollectionMessages = 'messages';

  /// Alasan pesan diblokir (untuk tampilkan ke user).
  static String? lastBlockedReason;

  /// Kirim pesan teks dari user ke admin.
  /// Juga update doc admin_chats/{userId} agar admin bisa list chat terbaru.
  static Future<bool> sendMessage(String userId, String text) async {
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

      // Ambil displayName dari users collection untuk list admin
      String displayName = user.displayName ?? user.email ?? '';
      try {
        final userDoc = await firestore.collection('users').doc(userId).get();
        final d = userDoc.data();
        if (d != null && (d['displayName'] as String?)?.isNotEmpty == true) {
          displayName = d['displayName'] as String;
        }
      } catch (_) {}

      final batch = firestore.batch();
      final messageData = {
        'senderUid': user.uid,
        'text': text.trim(),
        'type': 'text',
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'sent',
      };
      final newMsgRef = messagesRef.doc();
      batch.set(newMsgRef, messageData);

      batch.set(chatRef, {
        'userId': userId,
        'displayName': displayName,
        'lastMessage': text.trim(),
        'lastMessageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      return true;
    } catch (e) {
      // ignore: avoid_print
      log('AdminChatService.sendMessage error', e);
      return false;
    }
  }

  /// Stream pesan untuk satu user (untuk tampilan chat room).
  static Stream<List<ChatMessageModel>> streamMessages(String userId) {
    return FirebaseFirestore.instance
        .collection(_collectionAdminChats)
        .doc(userId)
        .collection(_subcollectionMessages)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => ChatMessageModel.fromFirestore(d)).toList(),
        );
  }

  /// Ambil info user (displayName, photoUrl) dari users collection.
  static Future<Map<String, dynamic>> getUserInfo(String uid) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final d = doc.data();
    if (d == null) return {'displayName': null, 'photoUrl': null};
    return {
      'displayName': d['displayName'] as String?,
      'photoUrl': d['photoUrl'] as String?,
    };
  }
}
