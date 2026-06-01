import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';
import '../../features/pilgrim/models/explore_place.dart';
import '../utils/app_logger.dart';
import 'api_service.dart';
import 'app_data_cache.dart';
import 'explore_geo.dart';
import 'secure_session_store.dart';

/// Explore POIs near a map center via backend cache and Nominatim.
class ExplorePlacesService {
  ExplorePlacesService._();

  static const _userAgent = 'MunawwaraCare/1.0 (pilgrim explore; Flutter)';

  static final Dio _nominatimDio = Dio(
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

  static String _categoryFromNominatim(String? cls, String? typ) {
    if (cls == 'amenity') {
      if (typ == 'pharmacy') return 'pharmacy';
      if (typ == 'restaurant' ||
          typ == 'fast_food' ||
          typ == 'cafe' ||
          typ == 'food_court') {
        return 'food';
      }
      if (typ == 'place_of_worship') return 'mosque';
      if (typ == 'hospital' || typ == 'clinic') return 'hospital';
      if (typ == 'toilets') return 'toilet';
      if (typ == 'drinking_water') return 'drinking_water';
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

  /// POIs near [centerLat],[centerLng] (Backend API).
  static Future<List<ExplorePlace>> fetchNearbyPlaces({
    required double centerLat,
    required double centerLng,
  }) async {
    Future<List<ExplorePlace>> fromCache() async {
      try {
        final uid = await SecureSessionStore.getUserId();
        if (uid == null) return [];
        final cached = AppDataCache.jsonMap(
          await AppDataCache.readData(uid, AppDataCache.exploreNearbyPoisFile),
        );
        if (cached == null || cached['success'] != true) return [];
        final list = cached['data'];
        if (list is! List<dynamic>) return [];
        final out = <ExplorePlace>[];
        for (final e in list) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final loc = m['location'];
          if (loc is! Map || loc['coordinates'] is! List) continue;
          final coords = loc['coordinates'] as List;
          if (coords.length < 2) continue;
          final lon = double.tryParse('${coords[0]}');
          final lat = double.tryParse('${coords[1]}');
          if (lat == null || lon == null) continue;
          out.add(ExplorePlace(
            sourceRef: m['sourceRef']?.toString() ?? '',
            name: m['name']?.toString() ?? '',
            categoryKey: m['categoryKey']?.toString() ?? 'landmarks',
            latitude: lat,
            longitude: lon,
            brandName: m['brandName']?.toString(),
          ));
        }
        return out;
      } catch (_) {
        return [];
      }
    }

    try {
      final radius = ExploreGeo.defaultRadiusKm * 1000; // in meters
      final limit = 50;
      
      final resp = await ApiService.dio.get<Map<String, dynamic>>(
        '/pois/nearby',
        queryParameters: {
          'lat': centerLat,
          'lng': centerLng,
          'radius': radius,
          'limit': limit,
        },
      );

      final data = resp.data;
      if (data == null || data['success'] != true) return [];

      // Cache last good result for offline Explore.
      try {
        final uid = await SecureSessionStore.getUserId();
        if (uid != null) {
          await AppDataCache.write(uid, AppDataCache.exploreNearbyPoisFile, data);
        }
      } catch (_) {}
      
      final poisData = data['data'] as List<dynamic>? ?? [];
      final out = <ExplorePlace>[];
      
      for (final e in poisData) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        
        final loc = m['location'];
        if (loc is! Map || loc['coordinates'] is! List) continue;
        
        final coords = loc['coordinates'] as List;
        if (coords.length < 2) continue;
        
        final lon = double.tryParse('${coords[0]}');
        final lat = double.tryParse('${coords[1]}');
        
        if (lat == null || lon == null) continue;

        out.add(ExplorePlace(
          sourceRef: m['sourceRef']?.toString() ?? '',
          name: m['name']?.toString() ?? '',
          categoryKey: m['categoryKey']?.toString() ?? 'landmarks',
          latitude: lat,
          longitude: lon,
          brandName: m['brandName']?.toString(),
        ));
      }
      
      return out;
    } on DioException catch (e, st) {
      AppLogger.e('ExplorePlacesService.fetchNearbyPlaces', e, st);
      if (ApiService.isOfflineFailure(e)) {
        final cached = await fromCache();
        if (cached.isNotEmpty) return cached;
      }
      rethrow;
    } catch (e, st) {
      AppLogger.e('ExplorePlacesService.fetchNearbyPlaces', e, st);
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
      final resp = await _nominatimDio.get<dynamic>(
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
