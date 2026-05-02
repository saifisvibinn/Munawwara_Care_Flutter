import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  static const _prodBaseUrl =
      'https://mcbackendapp-199324116788.europe-west8.run.app/api';

  // ─── Backend URL ─────────────────────────────────────────────────────────────
  // `API_BASE_URL` in .env (see comments there). Falls back to production.
  // Optional: `API_ANDROID_HOST=10.0.2.2` replaces the hostname on Android only
  // (emulator → host machine); port and path stay the same.
  static String get baseUrl {
    final fromEnv = dotenv.env['API_BASE_URL']?.trim();
    String url = (fromEnv != null && fromEnv.isNotEmpty) ? fromEnv : _prodBaseUrl;

    if (Platform.isAndroid) {
      final hostOverride = dotenv.env['API_ANDROID_HOST']?.trim();
      if (hostOverride != null && hostOverride.isNotEmpty) {
        try {
          final uri = Uri.parse(url);
          url = uri.replace(host: hostOverride).toString();
        } catch (_) {}
      }
    }
    return url;
  }

  /// Host root for this API (no `/api` suffix): uploads, static files, etc.
  static String get apiOrigin {
    return _normalizeHttpOrigin(
      baseUrl.replaceFirst(RegExp(r'/api/?$'), ''),
    );
  }

  /// Socket.IO server origin (scheme + host + port, no path).
  /// Set `SOCKET_BASE_URL` when realtime runs on a different host than REST
  /// (e.g. Cloud Run REST only — use your Node URL that mounts socket.io).
  static String get socketOrigin {
    final explicit = dotenv.env['SOCKET_BASE_URL']?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return _normalizeHttpOrigin(explicit);
    }
    return apiOrigin;
  }

  /// Normalizes origin for Dart Socket.IO / WebSocket (avoids `:0` port bugs on
  /// some Android builds; keeps explicit default ports).
  static String _normalizeHttpOrigin(String raw) {
    var o = raw.trim();
    if (o.endsWith('/')) o = o.substring(0, o.length - 1);
    try {
      var uri = Uri.parse(o);
      if (uri.scheme != 'http' && uri.scheme != 'https') return o;
      if (uri.host.isEmpty) return o;
      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      return '${uri.scheme}://${uri.host}:$port';
    } catch (_) {
      return o;
    }
  }

  static Dio? _dioInstance;
  static Future<void> Function()? _onUnauthorized;

  static void setUnauthorizedCallback(Future<void> Function() callback) {
    _onUnauthorized = callback;
  }

  static Dio get dio {
    if (_dioInstance == null) {
      _dioInstance = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'application/json'},
        ),
      );

      // Add interceptor for 401 errors
      _dioInstance!.interceptors.add(
        InterceptorsWrapper(
          onError: (DioException e, handler) async {
            if (e.response?.statusCode == 401) {
              if (_onUnauthorized != null) {
                await _onUnauthorized!();
              }
            }
            return handler.next(e);
          },
        ),
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
