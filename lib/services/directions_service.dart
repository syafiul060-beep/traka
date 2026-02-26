import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../config/maps_config.dart';

/// Cache untuk hasil Directions API (hemat biaya API).
final Map<String, ({DirectionsResult result, DateTime expiredAt})> _routeCache = {};
final Map<String, ({List<DirectionsResult> results, DateTime expiredAt})> _altRouteCache = {};
const Duration _cacheDuration = Duration(hours: 1);

String _cacheKey(double oLat, double oLng, double dLat, double dLng) =>
    '${oLat.toStringAsFixed(4)}_${oLng.toStringAsFixed(4)}_${dLat.toStringAsFixed(4)}_${dLng.toStringAsFixed(4)}';

void _evictExpiredCache() {
  final now = DateTime.now();
  _routeCache.removeWhere((_, v) => v.expiredAt.isBefore(now));
  _altRouteCache.removeWhere((_, v) => v.expiredAt.isBefore(now));
}

/// Hasil dari Directions API: polyline + jarak + waktu.
class DirectionsResult {
  final List<LatLng> points;
  final double distanceKm;
  final String distanceText;
  final int durationSeconds;
  final String durationText;

  const DirectionsResult({
    required this.points,
    required this.distanceKm,
    required this.distanceText,
    required this.durationSeconds,
    required this.durationText,
  });
}

/// Mendapatkan rute (polyline) dari Google Directions API.
class DirectionsService {
  static const String _baseUrl =
      'https://maps.googleapis.com/maps/api/directions/json';

  /// Ambil rute lengkap (polyline + jarak + waktu) dari origin ke destination.
  /// Hasil di-cache 1 jam per origin-destination (hemat API).
  static Future<DirectionsResult?> getRoute({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    _evictExpiredCache();
    final key = _cacheKey(originLat, originLng, destLat, destLng);
    final cached = _routeCache[key];
    if (cached != null && cached.expiredAt.isAfter(DateTime.now())) {
      return cached.result;
    }

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'origin': '$originLat,$originLng',
        'destination': '$destLat,$destLng',
        'mode': 'driving',
        'key': MapsConfig.directionsApiKey,
      },
    );
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') return null;
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return null;
      final route = routes.first as Map<String, dynamic>;
      final overview = route['overview_polyline'] as Map<String, dynamic>?;
      final encoded = overview?['points'] as String?;
      if (encoded == null || encoded.isEmpty) return null;
      final points = _decodePolyline(encoded);

      double distanceKm = 0;
      String distanceText = '-';
      int durationSeconds = 0;
      String durationText = '-';
      final legs = route['legs'] as List<dynamic>?;
      if (legs != null && legs.isNotEmpty) {
        final leg = legs.first as Map<String, dynamic>;
        final dist = leg['distance'] as Map<String, dynamic>?;
        final dur = leg['duration'] as Map<String, dynamic>?;
        if (dist != null) {
          distanceKm = ((dist['value'] as num?) ?? 0) / 1000;
          distanceText =
              (dist['text'] as String?) ??
              '${distanceKm.toStringAsFixed(1)} km';
        }
        if (dur != null) {
          durationSeconds = (dur['value'] as num?)?.toInt() ?? 0;
          durationText = (dur['text'] as String?) ?? '-';
        }
      }

      final result = DirectionsResult(
        points: points,
        distanceKm: distanceKm,
        distanceText: distanceText,
        durationSeconds: durationSeconds,
        durationText: durationText,
      );
      _routeCache[key] = (result: result, expiredAt: DateTime.now().add(_cacheDuration));
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Ambil semua alternatif rute dari origin ke destination.
  /// Hasil di-cache 1 jam per origin-destination (hemat API).
  static Future<List<DirectionsResult>> getAlternativeRoutes({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    _evictExpiredCache();
    final key = _cacheKey(originLat, originLng, destLat, destLng);
    final cached = _altRouteCache[key];
    if (cached != null && cached.expiredAt.isAfter(DateTime.now())) {
      return cached.results;
    }

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'origin': '$originLat,$originLng',
        'destination': '$destLat,$destLng',
        'mode': 'driving',
        'alternatives': 'true', // Request alternatif rute
        'key': MapsConfig.directionsApiKey,
      },
    );
    try {
      final response = await http.get(uri);
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status != 'OK') return [];
      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return [];

      final results = <DirectionsResult>[];
      for (final routeData in routes) {
        final route = routeData as Map<String, dynamic>;
        final overview = route['overview_polyline'] as Map<String, dynamic>?;
        final encoded = overview?['points'] as String?;
        if (encoded == null || encoded.isEmpty) continue;
        final points = _decodePolyline(encoded);

        double distanceKm = 0;
        String distanceText = '-';
        int durationSeconds = 0;
        String durationText = '-';
        final legs = route['legs'] as List<dynamic>?;
        if (legs != null && legs.isNotEmpty) {
          final leg = legs.first as Map<String, dynamic>;
          final dist = leg['distance'] as Map<String, dynamic>?;
          final dur = leg['duration'] as Map<String, dynamic>?;
          if (dist != null) {
            distanceKm = ((dist['value'] as num?) ?? 0) / 1000;
            distanceText =
                (dist['text'] as String?) ??
                '${distanceKm.toStringAsFixed(1)} km';
          }
          if (dur != null) {
            durationSeconds = (dur['value'] as num?)?.toInt() ?? 0;
            durationText = (dur['text'] as String?) ?? '-';
          }
        }

        results.add(
          DirectionsResult(
            points: points,
            distanceKm: distanceKm,
            distanceText: distanceText,
            durationSeconds: durationSeconds,
            durationText: durationText,
          ),
        );
      }
      if (results.isNotEmpty) {
        _altRouteCache[key] = (results: results, expiredAt: DateTime.now().add(_cacheDuration));
      }
      return results;
    } catch (_) {
      return [];
    }
  }

  /// Ambil polyline saja (untuk backward compatibility).
  static Future<List<LatLng>?> getRoutePolyline({
    required double originLat,
    required double originLng,
    required double destLat,
    required double destLng,
  }) async {
    final result = await getRoute(
      originLat: originLat,
      originLng: originLng,
      destLat: destLat,
      destLng: destLng,
    );
    return result?.points;
  }

  static List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int lat = 0;
    int lng = 0;
    while (index < encoded.length) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;
      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;
      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }
}
