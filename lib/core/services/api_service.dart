import 'dart:io' show Platform, SocketException;

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_data_cache.dart';

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

  /// Prevents dozens of parallel 401s (e.g. after logout) from each running
  /// the global logout + navigation handler and spamming logs.
  static bool _unauthorizedHandlerRunning = false;

  static void setUnauthorizedCallback(Future<void> Function() callback) {
    _onUnauthorized = callback;
  }

  static bool _requestHadBearerToken(RequestOptions o) {
    final h = o.headers;
    final raw = h['Authorization'] ?? h['authorization'];
    return raw is String && raw.startsWith('Bearer ');
  }

  /// True when this 401 should not trigger the global "force logout" callback.
  static bool _shouldIgnoreUnauthorizedForPath(String path) {
    return path.contains('/auth/login') ||
        path.contains('/auth/pilgrim/') ||
        path.contains('/auth/forgot-password') ||
        path.contains('/auth/reset-password') ||
        path.contains('/auth/logout');
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
              final path = e.requestOptions.path;
              if (!_shouldIgnoreUnauthorizedForPath(path) &&
                  _onUnauthorized != null &&
                  _requestHadBearerToken(e.requestOptions) &&
                  !_unauthorizedHandlerRunning) {
                _unauthorizedHandlerRunning = true;
                try {
                  await _onUnauthorized!();
                } catch (_) {
                  // Logout / navigation must not break the error chain.
                } finally {
                  _unauthorizedHandlerRunning = false;
                }
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
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_id');
    await AppDataCache.clearForUser(uid);
    dio.options.headers.remove('Authorization');
    await prefs.remove('auth_token');
    await prefs.remove('user_role');
    await prefs.remove('user_id');
    await prefs.remove('user_full_name');
  }

  /// True when the failure is likely due to no network (not 401/404 auth).
  static bool isOfflineFailure(DioException e) {
    final code = e.response?.statusCode;
    if (code == 401 || code == 404) return false;
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return true;
    }
    // Airplane mode / DNS failures often use [unknown] with no response.
    if (e.response == null && e.type == DioExceptionType.unknown) {
      return true;
    }
    if (e.response == null && e.type != DioExceptionType.cancel) {
      final msg = '${e.message} $e ${e.error}'.toLowerCase();
      if (msg.contains('failed host lookup') ||
          msg.contains('network is unreachable') ||
          msg.contains('connection refused') ||
          msg.contains('socketexception') ||
          msg.contains('software caused connection abort') ||
          msg.contains('no address associated') ||
          msg.contains('errno = 7') ||
          msg.contains('errno = 8') ||
          msg.contains('errno = 101')) {
        return true;
      }
    }
    return false;
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
