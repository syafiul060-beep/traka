import 'package:geocoding/geocoding.dart';

/// Format placemark dengan gaya familiar Indonesia (Jl., Kec., Kab., Prov.).
class PlacemarkFormatter {
  PlacemarkFormatter._();

  /// Normalisasi nama jalan/gang ke singkatan Indonesia.
  static String _normalizeThoroughfare(String? th) {
    if (th == null || th.trim().isEmpty) return '';
    final t = th.trim();
    final lower = t.toLowerCase();
    if (lower.startsWith('jalan ')) return 'Jl. ${t.substring(6)}';
    if (lower.startsWith('jl. ') || lower.startsWith('jl ')) return t;
    if (lower.startsWith('gang ')) return 'Gg. ${t.substring(5)}';
    if (lower.startsWith('gg. ') || lower.startsWith('gg ')) return t;
    return t;
  }

  /// Tambah prefix Kec. jika belum ada (untuk kecamatan).
  static String _withKecPrefix(String? s) {
    if (s == null || s.trim().isEmpty) return '';
    final t = s.trim();
    final lower = t.toLowerCase();
    if (lower.startsWith('kec. ')) return t;
    if (lower.startsWith('kecamatan ')) return 'Kec. ${t.substring(10)}';
    return 'Kec. $t';
  }

  /// Format lengkap untuk autocomplete/detail (nama tempat, jalan, kelurahan, kecamatan, kabupaten, provinsi).
  static String formatDetail(Placemark p) {
    final name = (p.name ?? '').trim();
    final thoroughfare = _normalizeThoroughfare(p.thoroughfare);
    final subLocality = (p.subLocality ?? '').trim(); // Kelurahan/Desa
    final locality = (p.locality ?? '').trim(); // Kecamatan
    final subAdmin = (p.subAdministrativeArea ?? '').trim(); // Kabupaten/Kota
    final admin = (p.administrativeArea ?? '').trim(); // Provinsi

    final parts = <String>[];

    if (name.isNotEmpty) parts.add(name);
    if (thoroughfare.isNotEmpty && thoroughfare != name) parts.add(thoroughfare);
    if (subLocality.isNotEmpty) parts.add(subLocality);
    // Kecamatan - skip jika sama dengan kelurahan (hindari duplikat)
    if (locality.isNotEmpty &&
        locality.toLowerCase() != subLocality.toLowerCase()) {
      parts.add(_withKecPrefix(locality));
    }
    if (subAdmin.isNotEmpty && subAdmin != admin) parts.add(subAdmin);
    if (admin.isNotEmpty) parts.add(admin);

    return parts.isEmpty ? 'Lokasi dipilih' : parts.join(', ');
  }

  /// Format singkat untuk lokasi asal (kecamatan, kabupaten, provinsi).
  static String formatShort(Placemark p) {
    final locality = (p.locality ?? '').trim();
    final subAdmin = (p.subAdministrativeArea ?? '').trim();
    final admin = (p.administrativeArea ?? '').trim();

    final parts = <String>[];
    if (locality.isNotEmpty) parts.add(_withKecPrefix(locality));
    if (subAdmin.isNotEmpty && subAdmin != admin) parts.add(subAdmin);
    if (admin.isNotEmpty) parts.add(admin);

    return parts.isEmpty ? 'Lokasi saat ini' : parts.join(', ');
  }

  /// Format untuk daftar pilihan (nama, jalan, kelurahan, kecamatan, kabupaten, provinsi).
  static String formatForList(Placemark p) {
    return formatDetail(p);
  }
}
