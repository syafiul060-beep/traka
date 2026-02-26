import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/promotion_model.dart';

/// Service untuk konten promosi/iklan.
class PromotionService {
  static const String _collection = 'promotions';

  /// Stream promosi aktif untuk role tertentu (penumpang/driver).
  /// Filter published/expired dan target di client.
  static Stream<List<PromotionModel>> streamActivePromotions(String role) {
    return FirebaseFirestore.instance
        .collection(_collection)
        .orderBy('priority', descending: true)
        .orderBy('publishedAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      return snap.docs
          .map((d) => PromotionModel.fromFirestore(d))
          .where((p) {
            if (!p.isActive(now)) return false;
            if (role == 'penumpang') return p.isForPenumpang;
            if (role == 'driver') return p.isForDriver;
            return true;
          })
          .toList();
    });
  }

  /// Ambil satu promosi by ID.
  static Future<PromotionModel?> getById(String id) async {
    final doc = await FirebaseFirestore.instance
        .collection(_collection)
        .doc(id)
        .get();
    if (!doc.exists) return null;
    return PromotionModel.fromFirestore(doc);
  }
}
