import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';

import '../../features/pilgrim/models/explore_place.dart';
import '../utils/app_logger.dart';
import 'explore_brand_logo.dart';
import 'explore_geo.dart';

/// Explore POIs near a map center via **OSM** (Overpass + Nominatim).
/// [centerLat]/[centerLng] should be the pilgrim’s position (or a chosen
/// fallback such as the Kaaba).
class ExplorePlacesService {
  ExplorePlacesService._();

  static const _userAgent = 'MunawwaraCare/1.0 (pilgrim explore; Flutter)';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 28),
      headers: {'User-Agent': _userAgent},
    ),
  );

  static List<ExplorePlace> _withinMaxDistance(
    List<ExplorePlace> list,
    double centerLat,
    double centerLng,
  ) {
    final maxM = ExploreGeo.maxResultDistanceKm * 1000;
    return list.where((p) {
      final m = Geolocator.distanceBetween(
        centerLat,
        centerLng,
        p.latitude,
        p.longitude,
      );
      return m <= maxM;
    }).toList();
  }

  static String? _categoryFromTags(Map<String, String> t) {
    final amenity = t['amenity'] ?? '';
    if (amenity == 'pharmacy') return 'pharmacy';
    if (amenity == 'restaurant' ||
        amenity == 'fast_food' ||
        amenity == 'cafe' ||
        amenity == 'food_court') {
      return 'food';
    }
    final shop = t['shop'] ?? '';
    if (shop == 'mall' ||
        shop == 'department_store' ||
        shop == 'supermarket' ||
        shop == 'convenience') {
      return 'shopping';
    }
    if (t['tourism'] == 'attraction' ||
        t.containsKey('historic') ||
        amenity == 'place_of_worship') {
      return 'landmarks';
    }
    return null;
  }

  static ExplorePlace? _fromOverpassElement(Map<String, dynamic> el) {
    final tags = (el['tags'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ??
        const <String, String>{};
    final cat = _categoryFromTags(tags);
    if (cat == null) return null;

    double? lat;
    double? lon;
    if (el['type'] == 'node') {
      lat = (el['lat'] as num?)?.toDouble();
      lon = (el['lon'] as num?)?.toDouble();
    } else {
      final c = el['center'];
      if (c is Map) {
        lat = (c['lat'] as num?)?.toDouble();
        lon = (c['lon'] as num?)?.toDouble();
      }
    }
    if (lat == null || lon == null) return null;

    final name = tags['name:en'] ??
        tags['name'] ??
        tags['name:ar'] ??
        tags['name:latin'] ??
        '';
    if (name.trim().isEmpty) return null;

    final type = el['type'] as String? ?? 'x';
    final id = el['id'];
    final brand = tags['brand']?.trim();
    final operator = tags['operator']?.trim();
    final brandName = (brand != null && brand.isNotEmpty) ? brand : operator;
    final bn = (brandName != null && brandName.isNotEmpty) ? brandName : null;
    final String? cardUrl = cat == 'landmarks'
        ? null
        : ExploreBrandLogo.chainLogoUrl(brand: bn, venueName: name.trim());
    return ExplorePlace(
      sourceRef: '$type/$id',
      name: name.trim(),
      categoryKey: cat,
      latitude: lat,
      longitude: lon,
      brandName: bn,
      cardImageUrl: cardUrl,
    );
  }

  static String _categoryFromNominatim(String? cls, String? typ) {
    if (cls == 'amenity') {
      if (typ == 'pharmacy') return 'pharmacy';
      if (typ == 'restaurant' ||
          typ == 'fast_food' ||
          typ == 'cafe' ||
          typ == 'food_court') {
        return 'food';
      }
      if (typ == 'place_of_worship') return 'landmarks';
    }
    if (cls == 'shop') {
      if (typ == 'mall' ||
          typ == 'department_store' ||
          typ == 'supermarket' ||
          typ == 'convenience') {
        return 'shopping';
      }
    }
    if (cls == 'tourism' || cls == 'historic' || cls == 'leisure') {
      return 'landmarks';
    }
    return 'landmarks';
  }

  static String _shortDisplayName(String raw) {
    final first = raw.split(',').first.trim();
    return first.isEmpty ? raw.trim() : first;
  }

  /// POIs near [centerLat],[centerLng] (Overpass).
  static Future<List<ExplorePlace>> fetchNearbyPlaces({
    required double centerLat,
    required double centerLng,
  }) async {
    final osm = await _fetchNearbyOsm(centerLat, centerLng);
    return _withinMaxDistance(osm, centerLat, centerLng);
  }

  static Future<List<ExplorePlace>> _fetchNearbyOsm(
    double centerLat,
    double centerLng,
  ) async {
    final b = ExploreGeo.bboxSwne(
      centerLat,
      centerLng,
      ExploreGeo.defaultRadiusKm,
    );
    final south = b[0];
    final west = b[1];
    final north = b[2];
    final east = b[3];

    final query = '''
[out:json][timeout:25];
(
  node["amenity"~"restaurant|fast_food|cafe|food_court"]($south,$west,$north,$east);
  node["amenity"="pharmacy"]($south,$west,$north,$east);
  node["shop"~"mall|department_store|supermarket|convenience"]($south,$west,$north,$east);
  node["tourism"="attraction"]($south,$west,$north,$east);
  node["historic"]($south,$west,$north,$east);
  node["amenity"="place_of_worship"]($south,$west,$north,$east);
);
out center 90;
''';

    try {
      final resp = await _dio.post<String>(
        'https://overpass-api.de/api/interpreter',
        data: query,
        options: Options(
          contentType: 'text/plain',
          responseType: ResponseType.plain,
        ),
      );
      final body = resp.data;
      if (body == null || body.isEmpty) return [];
      final map = jsonDecode(body) as Map<String, dynamic>;
      final elements = map['elements'] as List<dynamic>? ?? [];
      final out = <ExplorePlace>[];
      final seen = <String>{};
      for (final e in elements) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final p = _fromOverpassElement(m);
        if (p == null) continue;
        final key =
            '${p.latitude.toStringAsFixed(4)}_${p.longitude.toStringAsFixed(4)}_${p.name}';
        if (seen.add(key)) out.add(p);
      }
      return out;
    } catch (e, st) {
      AppLogger.e('ExplorePlacesService._fetchNearbyOsm', e, st);
      rethrow;
    }
  }

  /// Search near [centerLat],[centerLng] (Nominatim).
  static Future<List<ExplorePlace>> searchNearby(
    String q, {
    required double centerLat,
    required double centerLng,
  }) async {
    final query = q.trim();
    if (query.length < 2) return [];

    final osm = await _searchNearbyOsm(query, centerLat, centerLng);
    return _withinMaxDistance(osm, centerLat, centerLng);
  }

  static Future<List<ExplorePlace>> _searchNearbyOsm(
    String query,
    double centerLat,
    double centerLng,
  ) async {
    final viewbox = ExploreGeo.nominatimViewbox(
      centerLat,
      centerLng,
      ExploreGeo.searchRadiusKm,
    );
    try {
      final resp = await _dio.get<dynamic>(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: <String, dynamic>{
          'format': 'json',
          'limit': 18,
          'q': query,
          'viewbox': viewbox,
          'bounded': '1',
        },
        options: Options(responseType: ResponseType.json),
      );
      final raw = resp.data;
      final list = raw is List<dynamic> ? raw : <dynamic>[];
      final out = <ExplorePlace>[];
      final seen = <String>{};
      for (final e in list) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final lat = double.tryParse('${m['lat']}');
        final lon = double.tryParse('${m['lon']}');
        if (lat == null || lon == null) continue;
        final disp = m['display_name'] as String? ?? '';
        if (disp.isEmpty) continue;
        final name = _shortDisplayName(disp);
        final cls = m['class'] as String?;
        final typ = m['type'] as String?;
        final cat = _categoryFromNominatim(cls, typ);
        final osmType = m['osm_type'] as String? ?? 'place';
        final osmId = m['osm_id'];
        final ref = '$osmType/$osmId';
        if (!seen.add(ref)) continue;
        out.add(ExplorePlace(
          sourceRef: ref,
          name: name,
          categoryKey: cat,
          latitude: lat,
          longitude: lon,
          brandName: null,
          cardImageUrl: null,
        ));
      }
      return out;
    } catch (e, st) {
      AppLogger.e('ExplorePlacesService._searchNearbyOsm', e, st);
      rethrow;
    }
  }

  static double distanceKm(
    double fromLat,
    double fromLng,
    ExplorePlace p,
  ) {
    final m = Geolocator.distanceBetween(
      fromLat,
      fromLng,
      p.latitude,
      p.longitude,
    );
    return m / 1000.0;
  }
}
