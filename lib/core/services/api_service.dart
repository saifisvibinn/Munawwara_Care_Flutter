import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // ─── Backend URL ─────────────────────────────────────────────────────────────
  // Deployed Cloud Run backend — works from any network.
  // For local development, change to: 'http://192.168.x.x:5000/api'
  static const String baseUrl = 'https://mcbackendapp-199324116788.europe-west8.run.app/api';

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  static Dio get dio => _dio;

  // ── Token Management ──────────────────────────────────────────────────────────

  static Future<void> setAuthToken(String token) async {
    _dio.options.headers['Authorization'] = 'Bearer $token';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  static Future<void> clearAuthToken() async {
    _dio.options.headers.remove('Authorization');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('user_role');
    await prefs.remove('user_id');
    await prefs.remove('user_full_name');
  }

  /// Restore session token from SharedPreferences on app start.
  static Future<String?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    }
    return token;
  }

  // ── Parse human-readable error from DioException response ────────────────────
  static String parseError(DioException e) {
    final data = e.response?.data;
    if (data == null) return 'Network error. Please check your connection.';
    if (data is Map) {
      // Validation error format: { errors: { field: "message" } }
      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        return errors.values.first.toString();
      }
      // General message
      final msg = data['message'];
      if (msg != null) return msg.toString();
    }
    return 'Something went wrong. Please try again.';
  }
}
