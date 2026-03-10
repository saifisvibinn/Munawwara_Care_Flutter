import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  // Callback invoked by the 401 interceptor so that the router layer
  // (which depends on ApiService) can register navigation without
  // creating a circular import.
  static void Function()? _onSessionExpired;

  static void setSessionExpiredCallback(void Function() callback) {
    _onSessionExpired = callback;
  }

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
      _dioInstance!.interceptors.add(
        InterceptorsWrapper(
          onError: (DioException e, ErrorInterceptorHandler handler) {
            if (e.response?.statusCode == 401) {
              // Clear credentials then redirect to login.
              clearAuthToken();
              _onSessionExpired?.call();
            }
            handler.next(e);
          },
        ),
      );
    }
    return _dioInstance!;
  }

  // ── Token Management ──────────────────────────────────────────────────────────

  static const _secureStorage = FlutterSecureStorage();
  static const _tokenKey = 'auth_token';

  static Future<void> setAuthToken(String token) async {
    dio.options.headers['Authorization'] = 'Bearer $token';
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  static Future<void> clearAuthToken() async {
    dio.options.headers.remove('Authorization');
    await _secureStorage.delete(key: _tokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token'); // remove legacy plaintext copy if present
    await prefs.remove('user_role');
    await prefs.remove('user_id');
    await prefs.remove('user_full_name');
  }

  /// Restore session token from secure storage on app start.
  /// Migrates any legacy token stored in SharedPreferences to secure storage.
  static Future<String?> restoreSession() async {
    String? token = await _secureStorage.read(key: _tokenKey);
    if (token == null) {
      // Migration: check SharedPreferences for a token written by an older
      // version of the app and move it to secure storage.
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString('auth_token');
      if (legacy != null) {
        await _secureStorage.write(key: _tokenKey, value: legacy);
        await prefs.remove('auth_token');
        token = legacy;
      }
    }
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
