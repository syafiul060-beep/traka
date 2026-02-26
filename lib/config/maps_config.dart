/// Konfigurasi Google Maps & Directions API.
/// Aktifkan "Directions API" di Google Cloud Console untuk rute perjalanan.
class MapsConfig {
  MapsConfig._();

  /// API key untuk Google Directions API (sama dengan Maps SDK).
  /// Di production bisa pakai --dart-define atau Remote Config.
  static const String directionsApiKey =
      'AIzaSyAZ8nJZwU7lrxsDN1MZTbUCJaApUwY6b4M';
}
