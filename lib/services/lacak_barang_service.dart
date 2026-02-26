import 'package:geocoding/geocoding.dart';

import 'app_config_service.dart';

/// Service untuk Lacak Barang (kirim barang).
/// Menentukan tier harga berdasarkan provinsi asal dan tujuan.
class LacakBarangService {
  /// Tier 1: dalam provinsi (7500)
  /// Tier 2: beda provinsi (10000)
  /// Tier 3: lebih dari 1 provinsi (15000)
  static const int tierDalamProvinsi = 1;
  static const int tierBedaProvinsi = 2;
  static const int tierLebihDari1Provinsi = 3;

  /// Ambil nama provinsi dari koordinat (administrativeArea).
  static Future<String?> getProvinceFromLatLng(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return null;
      final area = placemarks.first.administrativeArea;
      return area?.trim().isNotEmpty == true ? area : null;
    } catch (_) {
      return null;
    }
  }

  /// Tentukan tier berdasarkan provinsi asal (pickup) dan tujuan (receiver).
  /// [originLat], [originLng]: titik jemput barang (pengirim/pickup).
  /// [destLat], [destLng]: lokasi penerima.
  /// Return: (tier, feeRupiah). Tier 1 = sama provinsi, 2 = beda provinsi, 3 = lebih dari 1 provinsi.
  static Future<(int tier, int feeRupiah)> getTierAndFee({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final originProvince = await getProvinceFromLatLng(originLat, originLng);
    final destProvince = await getProvinceFromLatLng(destLat, destLng);

    int tier = tierBedaProvinsi; // default
    if (originProvince != null && destProvince != null) {
      if (originProvince == destProvince) {
        tier = tierDalamProvinsi;
      } else {
        tier = tierBedaProvinsi;
        // TODO: Tier 3 (lebih dari 1 provinsi) butuh analisis rute. Untuk MVP pakai tier 2.
      }
    }

    final fee = await AppConfigService.getLacakBarangFeeRupiah(tier);
    return (tier, fee);
  }

  /// Product ID untuk IAP: traka_lacak_barang_7500, traka_lacak_barang_10000, traka_lacak_barang_15000.
  static String productIdForFee(int feeRupiah) => 'traka_lacak_barang_$feeRupiah';
}
