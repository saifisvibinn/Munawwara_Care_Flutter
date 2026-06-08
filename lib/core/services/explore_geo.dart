import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Pilgrimage service city used for Explore coverage checks.
class ExploreServiceHub {
  const ExploreServiceHub({
    required this.name,
    required this.center,
  });

  final String name;
  final LatLng center;
}

/// Bounding boxes around a map point for Explore (Overpass, Nominatim).
class ExploreGeo {
  ExploreGeo._();

  /// Mecca (Kaaba), Medina, and Jeddah — Explore POI coverage hubs.
  static const List<ExploreServiceHub> serviceHubs = [
    ExploreServiceHub(
      name: 'Mecca',
      center: LatLng(21.422487, 39.826206),
    ),
    ExploreServiceHub(
      name: 'Medina',
      center: LatLng(24.467233, 39.611121),
    ),
    ExploreServiceHub(
      name: 'Jeddah',
      center: LatLng(21.543333, 39.172778),
    ),
  ];

  /// Default map anchor when GPS is unavailable (Kaaba).
  static const LatLng defaultAnchor = LatLng(21.422487, 39.826206);

  /// Max distance from any [serviceHubs] center to count as in coverage (m).
  static const double serviceHubRadiusM = 200000;

  /// Default radius for “nearby” POI search (km).
  static const double defaultRadiusKm = 7.0;

  /// Slightly larger view for text search.
  static const double searchRadiusKm = 9.0;

  /// Hard cap: drop hits farther than this from the anchor (km).
  static const double maxResultDistanceKm = 12.0;

  /// [south, west, north, east] — Overpass `(...)(south,west,north,east)`.
  static List<double> bboxSwne(double lat, double lon, double radiusKm) {
    const latKm = 110.574;
    final cosLat = math.cos(lat * math.pi / 180).abs().clamp(0.12, 1.0);
    final lonKm = 111.320 * cosLat;
    final dLat = radiusKm / latKm;
    final dLon = radiusKm / lonKm;
    final south = (lat - dLat).clamp(-85.0, 85.0);
    final north = (lat + dLat).clamp(-85.0, 85.0);
    final west = (lon - dLon).clamp(-180.0, 180.0);
    final east = (lon + dLon).clamp(-180.0, 180.0);
    return [south, west, north, east];
  }

  /// Nominatim `viewbox`: west, north, east, south.
  static String nominatimViewbox(double lat, double lon, double radiusKm) {
    final b = bboxSwne(lat, lon, radiusKm);
    final south = b[0];
    final west = b[1];
    final north = b[2];
    final east = b[3];
    return '$west,$north,$east,$south';
  }

  /// Whether [lat],[lon] is within [serviceHubRadiusM] of any service hub.
  static bool isWithinServiceHubs(double lat, double lon) {
    for (final hub in serviceHubs) {
      final d = distanceMeters(
        lat,
        lon,
        hub.center.latitude,
        hub.center.longitude,
      );
      if (d <= serviceHubRadiusM) return true;
    }
    return false;
  }

  /// Haversine distance between two WGS-84 points (meters).
  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusM = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusM * c;
  }
}
