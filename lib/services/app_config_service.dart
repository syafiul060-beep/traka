import 'package:cloud_firestore/cloud_firestore.dart';

/// Service untuk membaca konfigurasi aplikasi dari app_config/settings.
class AppConfigService {
  static const String _collection = 'app_config';

  /// Biaya Lacak Barang (Rp) berdasarkan tier provinsi.
  /// Tier: 1 = dalam provinsi (7500), 2 = beda provinsi (10000), 3 = lebih dari 1 provinsi (15000).
  static Future<int> getLacakBarangFeeRupiah(int tier) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc('settings')
          .get();
      final d = doc.data();
      if (tier == 1) {
        final v = d?['lacakBarangDalamProvinsiRupiah'];
        if (v != null) {
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (n != null && n >= 7500) return n;
        }
        return 7500;
      }
      if (tier == 2) {
        final v = d?['lacakBarangBedaProvinsiRupiah'];
        if (v != null) {
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (n != null && n >= 10000) return n;
        }
        return 10000;
      }
      if (tier == 3) {
        final v = d?['lacakBarangLebihDari1ProvinsiRupiah'];
        if (v != null) {
          final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
          if (n != null && n >= 15000) return n;
        }
        return 15000;
      }
    } catch (_) {}
    return tier == 1 ? 7500 : tier == 2 ? 10000 : 15000;
  }

  /// Biaya Lacak Driver (Rp). Dibaca dari Firestore; default 3000, min 3000.
  /// Google Play tidak mendukung harga di bawah Rp 3.000.
  static Future<int> getLacakDriverFeeRupiah() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection(_collection)
          .doc('settings')
          .get();
      final v = doc.data()?['lacakDriverFeeRupiah'];
      if (v != null) {
        final n = (v is num) ? v.toInt() : int.tryParse(v.toString());
        if (n != null && n > 0) {
          return n < 3000 ? 3000 : n;
        }
      }
    } catch (_) {}
    return 3000;
  }
}
