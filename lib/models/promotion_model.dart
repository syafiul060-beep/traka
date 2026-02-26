import 'package:cloud_firestore/cloud_firestore.dart';

/// Model konten promosi/iklan untuk dibaca pengguna.
class PromotionModel {
  final String id;
  final String title;
  final String content;
  final String? imageUrl;
  final String target; // penumpang | driver | both
  final String type; // banner | article
  final int priority;
  final DateTime? publishedAt;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PromotionModel({
    required this.id,
    required this.title,
    required this.content,
    this.imageUrl,
    this.target = 'both',
    this.type = 'article',
    this.priority = 0,
    this.publishedAt,
    this.expiresAt,
    this.createdAt,
    this.updatedAt,
  });

  factory PromotionModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? {};
    return PromotionModel(
      id: doc.id,
      title: (d['title'] as String?) ?? '',
      content: (d['content'] as String?) ?? '',
      imageUrl: d['imageUrl'] as String?,
      target: (d['target'] as String?) ?? 'both',
      type: (d['type'] as String?) ?? 'article',
      priority: (d['priority'] as int?) ?? 0,
      publishedAt: (d['publishedAt'] as Timestamp?)?.toDate(),
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get isForPenumpang => target == 'penumpang' || target == 'both';
  bool get isForDriver => target == 'driver' || target == 'both';
  bool get isBanner => type == 'banner';

  bool isActive(DateTime now) {
    if (publishedAt != null && now.isBefore(publishedAt!)) return false;
    if (expiresAt != null && now.isAfter(expiresAt!)) return false;
    return true;
  }
}
