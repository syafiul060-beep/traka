import 'package:shared_preferences/shared_preferences.dart';

/// Data rute yang di-persist
class PersistedRoute {
  final double originLat;
  final double originLng;
  final double destLat;
  final double destLng;
  final String originText;
  final String destText;
  final DateTime backgroundSince;
  final bool fromJadwal;

  /// Index rute alternatif yang dipilih (0 = rute pertama, 1 = rute kedua, ...).
  final int selectedRouteIndex;

  const PersistedRoute({
    required this.originLat,
    required this.originLng,
    required this.destLat,
    required this.destLng,
    required this.originText,
    required this.destText,
    required this.backgroundSince,
    required this.fromJadwal,
    this.selectedRouteIndex = 0,
  });
}

/// Menyimpan rute aktif ke disk agar tetap ada saat aplikasi ditutup.
class RoutePersistenceService {
  static const _keyPrefix = 'traka_active_route_';
  static const _keyOriginLat = '${_keyPrefix}origin_lat';
  static const _keyOriginLng = '${_keyPrefix}origin_lng';
  static const _keyDestLat = '${_keyPrefix}dest_lat';
  static const _keyDestLng = '${_keyPrefix}dest_lng';
  static const _keyOriginText = '${_keyPrefix}origin_text';
  static const _keyDestText = '${_keyPrefix}dest_text';
  static const _keyBackgroundSince = '${_keyPrefix}background_since_ms';
  static const _keyFromJadwal = '${_keyPrefix}from_jadwal';
  static const _keySelectedRouteIndex = '${_keyPrefix}selected_route_index';
  static const Duration _maxDuration = Duration(hours: 1);

  /// Simpan data rute. Panggil segera saat rute aktif (sebelum app ditutup).
  /// [backgroundSince] = null artinya app masih di foreground (baru disimpan).
  static Future<void> save({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
    required String originText,
    required String destText,
    required bool fromJadwal,
    int selectedRouteIndex = 0,
    DateTime? backgroundSince,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyOriginLat, originLat);
    await prefs.setDouble(_keyOriginLng, originLng);
    await prefs.setDouble(_keyDestLat, destLat);
    await prefs.setDouble(_keyDestLng, destLng);
    await prefs.setString(_keyOriginText, originText);
    await prefs.setString(_keyDestText, destText);
    await prefs.setBool(_keyFromJadwal, fromJadwal);
    await prefs.setInt(_keySelectedRouteIndex, selectedRouteIndex);
    await prefs.setInt(
      _keyBackgroundSince,
      backgroundSince?.millisecondsSinceEpoch ?? 0,
    );
  }

  /// Update hanya timestamp background (dipanggil saat app ke background).
  static Future<void> updateBackgroundSince(DateTime when) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyBackgroundSince, when.millisecondsSinceEpoch);
  }

  /// Load rute yang disimpan. Mengembalikan null jika tidak ada atau sudah > 1 jam.
  static Future<PersistedRoute?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final originLat = prefs.getDouble(_keyOriginLat);
    final originLng = prefs.getDouble(_keyOriginLng);
    final destLat = prefs.getDouble(_keyDestLat);
    final destLng = prefs.getDouble(_keyDestLng);
    final originText = prefs.getString(_keyOriginText);
    final destText = prefs.getString(_keyDestText);
    final sinceMs = prefs.getInt(_keyBackgroundSince);
    final fromJadwal = prefs.getBool(_keyFromJadwal) ?? false;
    final selectedRouteIndex = prefs.getInt(_keySelectedRouteIndex) ?? 0;

    if (originLat == null ||
        originLng == null ||
        destLat == null ||
        destLng == null) {
      await clear();
      return null;
    }

    // sinceMs == 0 atau null = app ditutup saat masih di foreground → restore
    if (sinceMs != null && sinceMs > 0) {
      final backgroundSince = DateTime.fromMillisecondsSinceEpoch(sinceMs);
      final elapsed = DateTime.now().difference(backgroundSince);
      if (elapsed >= _maxDuration) {
        await clear();
        return null;
      }
    }

    final backgroundSince = sinceMs != null && sinceMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(sinceMs)
        : DateTime.now();

    return PersistedRoute(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
      originText: originText ?? '',
      destText: destText ?? '',
      backgroundSince: backgroundSince,
      fromJadwal: fromJadwal,
      selectedRouteIndex: selectedRouteIndex >= 0 ? selectedRouteIndex : 0,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyOriginLat);
    await prefs.remove(_keyOriginLng);
    await prefs.remove(_keyDestLat);
    await prefs.remove(_keyDestLng);
    await prefs.remove(_keyOriginText);
    await prefs.remove(_keyDestText);
    await prefs.remove(_keyBackgroundSince);
    await prefs.remove(_keyFromJadwal);
    await prefs.remove(_keySelectedRouteIndex);
  }
}
