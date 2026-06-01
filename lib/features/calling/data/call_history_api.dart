import 'package:dio/dio.dart';

import '../../../core/services/api_service.dart';
import '../../../core/utils/app_logger.dart';

/// REST helpers for voice call history (shared by [CallHistoryScreen] and badges).
class CallHistoryApi {
  CallHistoryApi._();

  static Future<List<Map<String, dynamic>>> fetchCallHistory() async {
    final resp = await ApiService.dio.get('/call-history');
    final raw = resp.data;
    final list = raw is List ? raw : <dynamic>[];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Unread incoming missed calls (`receiver_id` = user, `status` = missed, `is_read` = false).
  static Future<int> fetchUnreadMissedCount() async {
    try {
      final r = await ApiService.dio.get('/call-history/unread-count');
      final c = r.data is Map ? (r.data as Map)['count'] : null;
      if (c is int) return c;
      return int.tryParse('$c') ?? 0;
    } on DioException catch (e) {
      AppLogger.w('[CallHistoryApi] unread-count failed: $e');
      return 0;
    }
  }

  static Future<void> markMissedCallsRead() async {
    await ApiService.dio.put('/call-history/mark-read');
  }

  /// Clears the user's call history (server-side).
  ///
  /// Backend endpoint is expected to exist; if not, caller should handle errors.
  static Future<void> clearCallHistory() async {
    await ApiService.dio.delete('/call-history');
  }
}
