import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service untuk mengirim saran & masukan ke admin.
/// Data disimpan di Firestore app_feedback.
class FeedbackService {
  static const _collection = 'app_feedback';

  /// Kirim saran/masukan dari pengguna.
  /// [text] isi feedback, [type] saran|masukan|keluhan.
  static Future<bool> submit({
    required String text,
    String type = 'saran',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    try {
      await FirebaseFirestore.instance.collection(_collection).add({
        'text': trimmed,
        'type': type,
        'userId': user.uid,
        'userEmail': user.email,
        'userName': user.displayName,
        'source': 'app',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
