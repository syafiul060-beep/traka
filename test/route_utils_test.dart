import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:traka/services/route_utils.dart';

void main() {
  group('RouteUtils', () {
    group('distanceToPolyline', () {
      test('returns infinity for empty polyline', () {
        expect(
          RouteUtils.distanceToPolyline(
            const LatLng(-3.3, 114.6),
            [],
          ),
          double.infinity,
        );
      });

      test('returns distance to single point', () {
        const point = LatLng(-3.3, 114.6);
        const polyline = [LatLng(-3.3, 114.6)];
        expect(RouteUtils.distanceToPolyline(point, polyline), 0);
      });

      test('returns distance to segment', () {
        // Titik di tengah segmen: (-3.31, 114.59) ke (-3.33, 114.61)
        const point = LatLng(-3.32, 114.60);
        const polyline = [
          LatLng(-3.31, 114.59),
          LatLng(-3.33, 114.61),
        ];
        final distance = RouteUtils.distanceToPolyline(point, polyline);
        expect(distance, lessThan(5000)); // Harus dekat (< 5 km)
        expect(distance, greaterThanOrEqualTo(0));
      });
    });

    group('isPointNearPolyline', () {
      test('returns false for empty polyline', () {
        expect(
          RouteUtils.isPointNearPolyline(
            const LatLng(-3.3, 114.6),
            [],
          ),
          false,
        );
      });

      test('returns true when point is on polyline', () {
        const point = LatLng(-3.32, 114.60);
        const polyline = [
          LatLng(-3.31, 114.59),
          LatLng(-3.33, 114.61),
        ];
        expect(
          RouteUtils.isPointNearPolyline(point, polyline, toleranceMeters: 20000),
          true,
        );
      });
    });

    group('doesRoutePassThrough', () {
      test('returns false for empty driver route', () {
        expect(
          RouteUtils.doesRoutePassThrough(
            [],
            const LatLng(-3.3, 114.6),
            const LatLng(-3.35, 114.65),
          ),
          false,
        );
      });
    });
  });
}
