import 'package:dio/dio.dart';

import '../models/muslim_models.dart';

const _baseUrl = 'https://ummahapi.com/api';

class UmmahApiService {
  UmmahApiService(this._dio);

  final Dio _dio;

  Future<T> _unwrap<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(Map<String, dynamic> data) parse,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$_baseUrl$path',
      queryParameters: query,
    );
    final body = response.data;
    if (body == null || body['success'] != true) {
      throw DioException(
        requestOptions: response.requestOptions,
        message: 'UmmahAPI request failed',
      );
    }
    final data = body['data'];
    if (data is! Map<String, dynamic>) {
      throw DioException(
        requestOptions: response.requestOptions,
        message: 'Unexpected UmmahAPI payload',
      );
    }
    return parse(data);
  }

  Future<List<T>> _unwrapList<T>(
    String path, {
    Map<String, dynamic>? query,
    required T Function(Map<String, dynamic> item) parseItem,
    required String listKey,
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      '$_baseUrl$path',
      queryParameters: query,
    );
    final body = response.data;
    if (body == null || body['success'] != true) {
      throw DioException(
        requestOptions: response.requestOptions,
        message: 'UmmahAPI request failed',
      );
    }
    final data = body['data'];
    if (data is Map<String, dynamic>) {
      final list = data[listKey] as List<dynamic>? ?? [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(parseItem)
          .toList(growable: false);
    }
    if (data is List<dynamic>) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(parseItem)
          .toList(growable: false);
    }
    return [];
  }

  Future<PrayerTimesData> fetchPrayerTimes({
    required double lat,
    required double lng,
    String method = 'Egyptian',
    String madhab = 'Hanafi',
  }) {
    return _unwrap(
      '/prayer-times',
      query: {
        'lat': lat,
        'lng': lng,
        'method': method,
        'madhab': madhab,
      },
      parse: PrayerTimesData.fromJson,
    );
  }

  Future<TodayHijriData> fetchTodayHijri() {
    return _unwrap('/today-hijri', parse: TodayHijriData.fromJson);
  }



  Future<List<DuaItem>> fetchDuasByCategory(String categoryId) {
    return _unwrapList(
      '/duas/category/$categoryId',
      listKey: 'duas',
      parseItem: DuaItem.fromJson,
    );
  }

  Future<List<DuaCategory>> fetchDuaCategories() {
    return _unwrapList(
      '/duas/categories',
      listKey: 'categories',
      parseItem: DuaCategory.fromJson,
    );
  }

  Future<List<AsmaName>> fetchAsmaUlHusna() {
    return _unwrapList(
      '/asma-ul-husna',
      listKey: 'names',
      parseItem: AsmaName.fromJson,
    );
  }

  Future<List<AsmaName>> searchAsmaUlHusna(String query) {
    return _unwrapList(
      '/asma-ul-husna/search',
      query: {'q': query},
      listKey: 'names',
      parseItem: AsmaName.fromJson,
    );
  }
}
