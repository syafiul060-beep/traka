import 'package:cloud_firestore/cloud_firestore.dart';

/// Status sesi support: bot (auto-reply) | in_queue | connected | closed
class SupportTicketModel {
  final String userId;
  final String status; // bot | in_queue | connected | closed
  final int queuePosition;
  final String? assignedAdminId;
  final String? assignedAdminName;
  final DateTime? queueJoinedAt;
  final String? displayName;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final DateTime? updatedAt;

  const SupportTicketModel({
    required this.userId,
    required this.status,
    this.queuePosition = 0,
    this.assignedAdminId,
    this.assignedAdminName,
    this.queueJoinedAt,
    this.displayName,
    this.lastMessage,
    this.lastMessageAt,
    this.updatedAt,
  });

  factory SupportTicketModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return SupportTicketModel(
      userId: doc.id,
      status: (d['status'] as String?) ?? 'bot',
      queuePosition: (d['queuePosition'] as int?) ?? 0,
      assignedAdminId: d['assignedAdminId'] as String?,
      assignedAdminName: d['assignedAdminName'] as String?,
      queueJoinedAt: (d['queueJoinedAt'] as Timestamp?)?.toDate(),
      displayName: d['displayName'] as String?,
      lastMessage: d['lastMessage'] as String?,
      lastMessageAt: (d['lastMessageAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get isBot => status == 'bot';
  bool get isInQueue => status == 'in_queue';
  bool get isConnected => status == 'connected';
  bool get isClosed => status == 'closed';
}
