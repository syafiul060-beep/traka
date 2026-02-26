import 'package:cloud_firestore/cloud_firestore.dart';

/// Service untuk driver favorit penumpang.
/// Disimpan di users/{uid}.favoriteDriverIds (array).
class FavoriteDriverService {
  static const String _collectionUsers = 'users';
  static const String _fieldFavoriteDriverIds = 'favoriteDriverIds';

  /// Cek apakah driver termasuk favorit.
  static Future<bool> isFavorite(String passengerUid, String driverUid) async {
    final doc = await FirebaseFirestore.instance
        .collection(_collectionUsers)
        .doc(passengerUid)
        .get();
    final ids = doc.data()?[_fieldFavoriteDriverIds];
    if (ids is! List) return false;
    return ids.contains(driverUid);
  }

  /// Stream daftar driver favorit (untuk real-time).
  static Stream<List<String>> streamFavoriteDriverIds(String passengerUid) {
    return FirebaseFirestore.instance
        .collection(_collectionUsers)
        .doc(passengerUid)
        .snapshots()
        .map((snap) {
      final ids = snap.data()?[_fieldFavoriteDriverIds];
      if (ids is! List) return <String>[];
      return ids.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    });
  }

  /// Tambah driver ke favorit.
  static Future<bool> addFavorite(String passengerUid, String driverUid) async {
    try {
      await FirebaseFirestore.instance
          .collection(_collectionUsers)
          .doc(passengerUid)
          .update({
        _fieldFavoriteDriverIds: FieldValue.arrayUnion([driverUid]),
      });
      return true;
    } catch (e) {
      if (e.toString().contains('NOT_FOUND') ||
          e.toString().contains('no document')) {
        await FirebaseFirestore.instance
            .collection(_collectionUsers)
            .doc(passengerUid)
            .set({
          _fieldFavoriteDriverIds: [driverUid],
        }, SetOptions(merge: true));
        return true;
      }
      return false;
    }
  }

  /// Hapus driver dari favorit.
  static Future<bool> removeFavorite(
      String passengerUid, String driverUid) async {
    try {
      await FirebaseFirestore.instance
          .collection(_collectionUsers)
          .doc(passengerUid)
          .update({
        _fieldFavoriteDriverIds: FieldValue.arrayRemove([driverUid]),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Toggle favorit.
  static Future<bool> toggleFavorite(
      String passengerUid, String driverUid, bool currentlyFavorite) async {
    return currentlyFavorite
        ? removeFavorite(passengerUid, driverUid)
        : addFavorite(passengerUid, driverUid);
  }
}
