import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../providers/moderator_provider.dart';

/// Spreads pilgrim markers that share almost the same GPS fix into a small
/// ring so pins stay readable (spiderfy-style layout).
class PilgrimMarkerLayout {
  PilgrimMarkerLayout._();

  /// Max distance (m) between two pilgrims to treat them as overlapping.
  static const double clusterDistanceM = 14;

  /// Radius (m) of the ring used when a cluster has 2+ members.
  static const double ringRadiusM = 16;

  static List<({PilgrimInGroup pilgrim, LatLng point})> pointsForMarkers(
    List<PilgrimInGroup> located,
  ) {
    if (located.isEmpty) return [];
    final n = located.length;
    final parent = List<int>.generate(n, (i) => i);

    int find(int i) {
      if (parent[i] != i) parent[i] = find(parent[i]);
      return parent[i];
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[rb] = ra;
    }

    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        if (_distanceMeters(
              located[i].lat!,
              located[i].lng!,
              located[j].lat!,
              located[j].lng!,
            ) <=
            clusterDistanceM) {
          union(i, j);
        }
      }
    }

    final clusters = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      clusters.putIfAbsent(find(i), () => []).add(i);
    }

    final out = <({PilgrimInGroup pilgrim, LatLng point})>[];
    for (final members in clusters.values) {
      members.sort((a, b) => located[a].id.compareTo(located[b].id));
      if (members.length == 1) {
        final p = located[members.first];
        out.add((pilgrim: p, point: LatLng(p.lat!, p.lng!)));
      } else {
        var sumLat = 0.0;
        var sumLng = 0.0;
        for (final idx in members) {
          sumLat += located[idx].lat!;
          sumLng += located[idx].lng!;
        }
        final meanLat = sumLat / members.length;
        final meanLng = sumLng / members.length;
        final mlen = members.length;
        final cosLat =
            math.cos(meanLat * math.pi / 180).abs().clamp(0.2, 1.0);
        for (var t = 0; t < mlen; t++) {
          final angle = -math.pi / 2 + (2 * math.pi * t) / mlen;
          final p = located[members[t]];
          final dLat = ringRadiusM * math.cos(angle) / 111320;
          final dLng =
              ringRadiusM * math.sin(angle) / (111320 * cosLat);
          out.add((
            pilgrim: p,
            point: LatLng(meanLat + dLat, meanLng + dLng),
          ));
        }
      }
    }
    return out;
  }

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }
}
