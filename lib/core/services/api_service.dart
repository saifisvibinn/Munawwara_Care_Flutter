import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  // ─── Backend URL ─────────────────────────────────────────────────────────────
  // Use `API_BASE_URL` from .env when available; fall back to the
  // production Cloud Run URL. For local dev, set API_BASE_URL to
  // 'http://192.168.x.x:5000/api' in your .env.
  static String get baseUrl =>
      dotenv.env['API_BASE_URL'] ??
      'https://mcbackendapp-199324116788.europe-west8.run.app/api';

  static Dio? _dioInstance;

  static Dio get dio {
    if (_dioInstance == null) {
      _dioInstance = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Content-Type': 'application/json'},
        ),
      );
      // Persist the active URL so background isolates (e.g. CallKit decline
      // handlers) can read it without dotenv being available.
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setString('api_base_url', baseUrl),
      );
    }
    return _dioInstance!;
  }

  // ── Token Management ──────────────────────────────────────────────────────────

  static Future<void> setAuthToken(String token) async {
    dio.options.headers['Authorization'] = 'Bearer $token';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
  }

  static Future<void> clearAuthToken() async {
    dio.options.headers.remove('Authorization');
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
      dio.options.headers['Authorization'] = 'Bearer $token';
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
