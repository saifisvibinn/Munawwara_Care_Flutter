import 'dart:math' as math;

/// Bounding boxes around a map point for Explore (Overpass, Nominatim).
class ExploreGeo {
  ExploreGeo._();

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
}
