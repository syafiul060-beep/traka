/// Pemetaan provinsi Indonesia ke pulau (untuk filter rute antar provinsi).
/// Nama provinsi disesuaikan dengan kemungkinan nilai dari geocoding (administrativeArea).
class ProvinceIsland {
  ProvinceIsland._();

  /// Nama pulau (untuk referensi).
  static const String sumatera = 'Sumatera';
  static const String jawa = 'Jawa';
  static const String kalimantan = 'Kalimantan';
  static const String sulawesi = 'Sulawesi';
  static const String baliNusaTenggara = 'Bali & Nusa Tenggara';
  static const String maluku = 'Maluku';
  static const String papua = 'Papua';

  /// Setiap provinsi bisa punya beberapa nama (geocoding bisa pakai nama resmi atau singkatan).
  static const Map<String, String> _provinceToIsland = {
    // Sumatera
    'Aceh': sumatera,
    'Nanggroe Aceh Darussalam': sumatera,
    'NAD': sumatera,
    'Sumatera Utara': sumatera,
    'Sumatra Utara': sumatera,
    'Sumatera Barat': sumatera,
    'Sumatra Barat': sumatera,
    'Riau': sumatera,
    'Kepulauan Riau': sumatera,
    'Jambi': sumatera,
    'Sumatera Selatan': sumatera,
    'Sumatra Selatan': sumatera,
    'Bangka Belitung': sumatera,
    'Bengkulu': sumatera,
    'Lampung': sumatera,
    // Jawa
    'Banten': jawa,
    'DKI Jakarta': jawa,
    'Jakarta': jawa,
    'Daerah Khusus Ibukota Jakarta': jawa,
    'Jawa Barat': jawa,
    'Jawa Tengah': jawa,
    'Jawa Timur': jawa,
    'Daerah Istimewa Yogyakarta': jawa,
    'DI Yogyakarta': jawa,
    'Yogyakarta': jawa,
    // Kalimantan
    'Kalimantan Barat': kalimantan,
    'Kalimantan Tengah': kalimantan,
    'Kalimantan Selatan': kalimantan,
    'Kalimantan Timur': kalimantan,
    'Kalimantan Utara': kalimantan,
    // Sulawesi
    'Sulawesi Utara': sulawesi,
    'Sulawesi Barat': sulawesi,
    'Sulawesi Tengah': sulawesi,
    'Sulawesi Selatan': sulawesi,
    'Sulawesi Tenggara': sulawesi,
    'Gorontalo': sulawesi,
    // Bali & Nusa Tenggara
    'Bali': baliNusaTenggara,
    'Nusa Tenggara Barat': baliNusaTenggara,
    'NTB': baliNusaTenggara,
    'Nusa Tenggara Timur': baliNusaTenggara,
    'NTT': baliNusaTenggara,
    // Maluku
    'Maluku': maluku,
    'Maluku Utara': maluku,
    // Papua
    'Papua': papua,
    'Papua Barat': papua,
    'Papua Selatan': papua,
    'Papua Tengah': papua,
    'Papua Pegunungan': papua,
    'Papua Barat Daya': papua,
  };

  /// Daftar provinsi per pulau (nama yang dipakai untuk filter; satu per provinsi).
  static const Map<String, List<String>> _islandToProvinces = {
    sumatera: [
      'Aceh',
      'Sumatera Utara',
      'Sumatera Barat',
      'Riau',
      'Kepulauan Riau',
      'Jambi',
      'Sumatera Selatan',
      'Bangka Belitung',
      'Bengkulu',
      'Lampung',
    ],
    jawa: [
      'Banten',
      'DKI Jakarta',
      'Jawa Barat',
      'Jawa Tengah',
      'Jawa Timur',
      'Daerah Istimewa Yogyakarta',
    ],
    kalimantan: [
      'Kalimantan Barat',
      'Kalimantan Tengah',
      'Kalimantan Selatan',
      'Kalimantan Timur',
      'Kalimantan Utara',
    ],
    sulawesi: [
      'Sulawesi Utara',
      'Sulawesi Barat',
      'Sulawesi Tengah',
      'Sulawesi Selatan',
      'Sulawesi Tenggara',
      'Gorontalo',
    ],
    baliNusaTenggara: ['Bali', 'Nusa Tenggara Barat', 'Nusa Tenggara Timur'],
    maluku: ['Maluku', 'Maluku Utara'],
    papua: [
      'Papua',
      'Papua Barat',
      'Papua Selatan',
      'Papua Tengah',
      'Papua Pegunungan',
      'Papua Barat Daya',
    ],
  };

  /// Mengembalikan nama pulau untuk provinsi [provinceName], atau null jika tidak dikenal.
  static String? getIslandForProvince(String? provinceName) {
    if (provinceName == null || provinceName.trim().isEmpty) return null;
    final normalized = provinceName.trim();
    return _provinceToIsland[normalized];
  }

  /// Mengembalikan daftar nama provinsi di pulau yang sama dengan [provinceName].
  /// Digunakan untuk filter autocomplete tujuan (rute antar provinsi - sesama pulau).
  static List<String>? getProvincesInSameIsland(String? provinceName) {
    final island = getIslandForProvince(provinceName);
    if (island == null) return null;
    return List<String>.from(_islandToProvinces[island] ?? []);
  }

  /// Cek apakah [placemarkProvince] (dari geocoding) satu pulau dengan driver.
  /// [provincesInIsland] = daftar provinsi di pulau driver (dari [getProvincesInSameIsland]).
  static bool isProvinceInList(
    String? placemarkProvince,
    List<String> provincesInIsland,
  ) {
    if (placemarkProvince == null || placemarkProvince.trim().isEmpty) {
      return false;
    }
    if (provincesInIsland.isEmpty) return false;
    final islandPlace = getIslandForProvince(placemarkProvince.trim());
    if (islandPlace == null) return false;
    final driverIsland = getIslandForProvince(provincesInIsland.first);
    return driverIsland == islandPlace;
  }
}
