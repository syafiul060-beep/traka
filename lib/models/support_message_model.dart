import 'package:cloud_firestore/cloud_firestore.dart';

/// Model pesan di live chat support (admin_chats/{userId}/messages).
/// senderType: 'user' | 'admin' | 'bot'
class SupportMessageModel {
  final String id;
  final String senderUid;
  final String senderType; // user | admin | bot
  final String text;
  final DateTime? createdAt;
  final String status;

  const SupportMessageModel({
    required this.id,
    required this.senderUid,
    required this.senderType,
    required this.text,
    this.createdAt,
    this.status = 'sent',
  });

  factory SupportMessageModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return SupportMessageModel(
      id: doc.id,
      senderUid: (d['senderUid'] as String?) ?? '',
      senderType: (d['senderType'] as String?) ?? 'user',
      text: (d['text'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      status: (d['status'] as String?) ?? 'sent',
    );
  }

  /// Deteksi pengirim: fallback ke senderUid jika senderType hilang (data lama).
  bool get isFromBot =>
      senderType == 'bot' || senderUid == 'bot';
  bool get isFromAdmin => senderType == 'admin';
  bool get isFromUser =>
      (senderType == 'user' || senderType.isEmpty) && senderUid != 'bot';
}
