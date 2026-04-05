import 'dart:math' as math;

class QiblaMath {
  // Exact Kaaba coordinates used for accurate Qibla bearing calculations.
  static const double kaabaLat = 21.422487;
  static const double kaabaLng = 39.826206;

  /// Great-circle bearing from (lat1,lng1) to Kaaba in degrees [0,360).
  ///
  /// theta = atan2(
  ///   sin(dLon) * cos(lat2),
  ///   cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
  /// )
  static double bearingToKaaba(double lat, double lng) {
    final lat1 = _degToRad(lat);
    final lat2 = _degToRad(kaabaLat);
    final dLon = _degToRad(kaabaLng - lng);

    final y = math.sin(dLon) * math.cos(lat2);
    final x =
        math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    final theta = math.atan2(y, x);
    return normalize360(_radToDeg(theta));
  }

  static double distanceToKaabaKm(double lat, double lng) {
    const earthRadiusKm = 6371.0;
    final dLat = _degToRad(kaabaLat - lat);
    final dLon = _degToRad(kaabaLng - lng);
    final lat1 = _degToRad(lat);
    final lat2 = _degToRad(kaabaLat);

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double normalize360(double angle) {
    final n = angle % 360.0;
    return n < 0 ? n + 360.0 : n;
  }

  /// Returns shortest signed delta from [from] to [to] in degrees [-180,180].
  static double shortestDelta(double from, double to) {
    final delta = (to - from + 540.0) % 360.0 - 180.0;
    return delta;
  }

  /// Low-pass smoothing for circular angles.
  static double smoothAngle(double current, double next, double alpha) {
    final d = shortestDelta(current, next);
    return normalize360(current + alpha * d);
  }

  static String cardinal(double deg) {
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    final i = ((normalize360(deg) / 45).round()) % 8;
    return dirs[i];
  }

  static double _degToRad(double deg) => deg * math.pi / 180.0;

  static double _radToDeg(double rad) => rad * 180.0 / math.pi;
}
