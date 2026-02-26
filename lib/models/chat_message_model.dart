import 'package:cloud_firestore/cloud_firestore.dart';

/// Status pesan seperti WhatsApp: sent (1 centang), delivered (2 centang abu), read (2 centang biru).
typedef MessageStatus = String;

/// Model satu pesan chat dalam order (orders/{orderId}/messages).
class ChatMessageModel {
  final String id;
  final String senderUid;
  final String text;
  final DateTime? createdAt;

  /// sent | delivered | read
  final MessageStatus status;

  /// Tipe pesan: 'text', 'audio', 'image', 'video'
  final String type;

  /// URL audio (jika type = 'audio')
  final String? audioUrl;

  /// Durasi audio dalam detik (jika type = 'audio')
  final int? audioDuration;

  /// URL gambar/video (jika type = 'image' atau 'video')
  final String? mediaUrl;

  /// Thumbnail untuk video (jika type = 'video')
  final String? thumbnailUrl;

  const ChatMessageModel({
    required this.id,
    required this.senderUid,
    required this.text,
    this.createdAt,
    this.status = 'sent',
    this.type = 'text',
    this.audioUrl,
    this.audioDuration,
    this.mediaUrl,
    this.thumbnailUrl,
  });

  factory ChatMessageModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return ChatMessageModel(
      id: doc.id,
      senderUid: (d['senderUid'] as String?) ?? '',
      text: (d['text'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      status: (d['status'] as String?) ?? 'sent',
      type: (d['type'] as String?) ?? 'text',
      audioUrl: d['audioUrl'] as String?,
      audioDuration: d['audioDuration'] as int?,
      mediaUrl: d['mediaUrl'] as String?,
      thumbnailUrl: d['thumbnailUrl'] as String?,
    );
  }

  bool get isText => type == 'text';
  bool get isAudio => type == 'audio';
  bool get isImage => type == 'image';
  bool get isVideo => type == 'video';
  bool get isBarcodePassenger => type == 'barcode_passenger';
  bool get isBarcodeDriver => type == 'barcode_driver';
  bool get isBarcode => isBarcodePassenger || isBarcodeDriver;
}
