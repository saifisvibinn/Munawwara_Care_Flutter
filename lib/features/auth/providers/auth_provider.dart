import 'dart:math';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/app_data_cache.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/utils/app_logger.dart';

// ── Auth State ────────────────────────────────────────────────────────────────

class AuthState {
  final bool isLoading;
  final bool isRestoringSession;
  final String? error;
  final String? token;
  final String? role;
  final String? userId;
  final String? fullName;
  final String? email;
  final bool emailVerified;
  final String? phoneNumber;
  final int? age;
  final String? gender;
  final String? medicalHistory;
  final String? hotelName;
  final String? roomNumber;
  final String? busInfo;
  final String? visaNumber;
  final String? visaStatus;
  final String? nationalId;
  final String? language;
  final String? ethnicity;

  const AuthState({
    this.isLoading = false,
    this.isRestoringSession = false,
    this.error,
    this.token,
    this.role,
    this.userId,
    this.fullName,
    this.email,
    this.emailVerified = false,
    this.phoneNumber,
    this.age,
    this.gender,
    this.medicalHistory,
    this.hotelName,
    this.roomNumber,
    this.busInfo,
    this.visaNumber,
    this.visaStatus,
    this.nationalId,
    this.language,
    this.ethnicity,
  });

  bool get isAuthenticated => token != null;

  AuthState copyWith({
    bool? isLoading,
    bool? isRestoringSession,
    String? error,
    String? token,
    String? role,
    String? userId,
    String? fullName,
    String? email,
    bool? emailVerified,
    String? phoneNumber,
    int? age,
    String? gender,
    String? medicalHistory,
    String? hotelName,
    String? roomNumber,
    String? busInfo,
    String? visaNumber,
    String? visaStatus,
    String? nationalId,
    String? language,
    String? ethnicity,
    bool clearError = false,
    bool clearPhoneNumber = false,
    bool clearEmail = false,
    bool clearAge = false,
    bool clearGender = false,
    bool clearMedicalHistory = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isRestoringSession: isRestoringSession ?? this.isRestoringSession,
      error: clearError ? null : (error ?? this.error),
      token: token ?? this.token,
      role: role ?? this.role,
      userId: userId ?? this.userId,
      fullName: fullName ?? this.fullName,
      email: clearEmail ? null : (email ?? this.email),
      emailVerified: emailVerified ?? this.emailVerified,
      phoneNumber: clearPhoneNumber ? null : (phoneNumber ?? this.phoneNumber),
      age: clearAge ? null : (age ?? this.age),
      gender: clearGender ? null : (gender ?? this.gender),
      medicalHistory: clearMedicalHistory
          ? null
          : (medicalHistory ?? this.medicalHistory),
      hotelName: hotelName ?? this.hotelName,
      roomNumber: roomNumber ?? this.roomNumber,
      busInfo: busInfo ?? this.busInfo,
      visaNumber: visaNumber ?? this.visaNumber,
      visaStatus: visaStatus ?? this.visaStatus,
      nationalId: nationalId ?? this.nationalId,
      language: language ?? this.language,
      ethnicity: ethnicity ?? this.ethnicity,
    );
  }
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────
// Uses Riverpod 3.x Notifier API (StateNotifier was removed in v3)

class AuthNotifier extends Notifier<AuthState> {
  static const _deviceBindingIdKey = 'device_binding_id';

  /// Called once from main.dart after the FCM token is obtained.
  /// Kept for compatibility but no longer relied upon — see _registerFcmToken().
  static void setFcmTokenGetter(String? Function() getter) {}

  @override
  AuthState build() {
    _restoreSession();
    return const AuthState(isRestoringSession: true);
  }

  // ── Restore session on startup ──────────────────────────────────────────────
  Future<void> _restoreSession() async {
    try {
      AppLogger.d('AuthNotifier: restoring session');
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final role = prefs.getString('user_role');
      final userId = prefs.getString('user_id');
      final fullName = prefs.getString('user_full_name');

      if (token == null || token.isEmpty) {
        state = const AuthState(isRestoringSession: false);
        AppLogger.d('AuthNotifier: restore complete (no token)');
        return;
      }

      ApiService.dio.options.headers['Authorization'] = 'Bearer $token';

      try {
        final response = await ApiService.dio.get('/auth/me');
        final raw = response.data;
        final data = raw is Map<String, dynamic>
            ? raw
            : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});

        final resolvedRole =
            (data['role'] ?? data['user_type'] ?? role)?.toString();
        final resolvedId =
            (data['_id'] ?? data['id'] ?? userId)?.toString();
        final resolvedName =
            (data['full_name'] ?? fullName)?.toString();

        if (userId != null &&
            userId.isNotEmpty &&
            resolvedId != null &&
            resolvedId.isNotEmpty &&
            userId != resolvedId) {
          AppLogger.w(
            'AuthNotifier: stored user id does not match /auth/me — clearing session',
          );
          await _invalidateSessionLocally();
          return;
        }

        state = AuthState(
          isRestoringSession: false,
          token: token,
          role: resolvedRole,
          userId: resolvedId,
          fullName: resolvedName,
          email: data['email'] as String?,
          emailVerified: data['email_verified'] as bool? ?? false,
          phoneNumber: data['phone_number'] as String?,
          age: (data['age'] as num?)?.toInt(),
          gender: data['gender'] as String?,
          medicalHistory: data['medical_history'] as String?,
          hotelName: data['hotel_name'] as String?,
          roomNumber: data['room_number'] as String?,
          busInfo: data['bus_info'] as String?,
          visaNumber: data['visa']?['visa_number']?.toString(),
          visaStatus: data['visa']?['status']?.toString(),
          nationalId: data['national_id']?.toString(),
          language: data['language']?.toString(),
          ethnicity: data['ethnicity']?.toString(),
        );

        if (data['full_name'] != null) {
          await prefs.setString('user_full_name', data['full_name'] as String);
        }
        if (resolvedId != null && resolvedId.isNotEmpty) {
          await prefs.setString('user_id', resolvedId);
        }
        if (resolvedRole != null && resolvedRole.isNotEmpty) {
          await prefs.setString('user_role', resolvedRole);
        }

        final cacheId = resolvedId ?? userId;
        if (cacheId != null && cacheId.isNotEmpty) {
          await AppDataCache.write(cacheId, AppDataCache.authMeFile, data);
        }

        await _registerFcmToken();
      } on DioException catch (e) {
        final code = e.response?.statusCode;
        if (code == 401) {
          AppLogger.w('AuthNotifier: /auth/me 401 during restore');
          final prefsAfter = await SharedPreferences.getInstance();
          if (prefsAfter.getString('auth_token') != null) {
            await _invalidateSessionLocally();
          } else {
            state = const AuthState(isRestoringSession: false);
          }
          AppLogger.d('AuthNotifier: restore complete (401)');
          return;
        }
        if (code == 404) {
          AppLogger.w(
            'AuthNotifier: /auth/me 404 during restore — account likely removed',
          );
          await _invalidateSessionLocally();
          AppLogger.d('AuthNotifier: restore complete (404)');
          return;
        }

        AppLogger.w(
          'AuthNotifier: /auth/me failed during restore (HTTP $code) — keeping offline session',
        );
        state = AuthState(
          isRestoringSession: false,
          token: token,
          role: role,
          userId: userId,
          fullName: fullName,
        );
        await _mergeAuthMeFromCache(userId);
        await _registerFcmToken();
      }

      AppLogger.d('AuthNotifier: restore complete');
    } catch (e, st) {
      AppLogger.e('AuthNotifier restoreSession error: $e\n$st');
      state = const AuthState(isRestoringSession: false);
    }
  }

  Future<void> _mergeAuthMeFromCache(String? userId) async {
    if (userId == null || userId.isEmpty) return;
    final raw = await AppDataCache.readData(userId, AppDataCache.authMeFile);
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    state = state.copyWith(
      fullName: (data['full_name'] ?? state.fullName)?.toString(),
      email: data['email'] as String? ?? state.email,
      emailVerified: data['email_verified'] as bool? ?? state.emailVerified,
      phoneNumber: data['phone_number'] as String? ?? state.phoneNumber,
      age: (data['age'] as num?)?.toInt() ?? state.age,
      gender: data['gender'] as String? ?? state.gender,
      medicalHistory: data['medical_history'] as String? ?? state.medicalHistory,
      hotelName: data['hotel_name'] as String? ?? state.hotelName,
      roomNumber: data['room_number'] as String? ?? state.roomNumber,
      busInfo: data['bus_info'] as String? ?? state.busInfo,
      visaNumber: data['visa']?['visa_number']?.toString() ?? state.visaNumber,
      visaStatus: data['visa']?['status']?.toString() ?? state.visaStatus,
      nationalId: data['national_id']?.toString() ?? state.nationalId,
      language: data['language']?.toString() ?? state.language,
      ethnicity: data['ethnicity']?.toString() ?? state.ethnicity,
    );
  }

  /// Merge `/auth/me` fields from disk when token exists (e.g. offline cold start).
  Future<void> hydrateFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('auth_token') == null) return;
    final uid = state.userId ?? prefs.getString('user_id');
    await _mergeAuthMeFromCache(uid);
  }

  /// Clear local auth without calling the server (user record already gone or 401 handled).
  Future<void> _invalidateSessionLocally() async {
    try {
      SocketService.disconnect();
    } catch (_) {}
    await ApiService.clearAuthToken();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_registered_fcm_token');
    state = const AuthState(isRestoringSession: false);
  }

  // ── Register FCM token with the backend ────────────────────────────────────
  // Fetches the current FCM token directly from Firebase and sends it to the
  // backend. Self-contained — no dependency on main.dart or any global state.
  Future<void> _registerFcmToken() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await updateFcmToken(fcmToken);
      } else {
        AppLogger.w('⚠️ FCM token is null — device may not support FCM');
      }
    } catch (e) {
      AppLogger.e('⚠️ Failed to get FCM token from Firebase: $e');
    }
  }



  Future<void> _persistSession(
    String token,
    String role,
    String userId,
    String fullName,
  ) async {
    await ApiService.setAuthToken(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
    await prefs.setString('user_id', userId);
    await prefs.setString('user_full_name', fullName);
  }

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_deviceBindingIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final generated = const Uuid().v4();
    await prefs.setString(_deviceBindingIdKey, generated);
    return generated;
  }

  // ── Login ───────────────────────────────────────────────────────────────────
  Future<bool> login({
    required String identifier,
    required String password,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    final normalizedIdentifier = identifier.trim();

    try {
      final response = await ApiService.dio.post(
        '/auth/login',
        data: {'identifier': normalizedIdentifier, 'password': password},
      );
      final data = response.data as Map<String, dynamic>;

      await _persistSession(
        data['token'] as String,
        data['role'] as String,
        data['user_id'] as String,
        data['full_name'] as String,
      );

      state = state.copyWith(
        isLoading: false,
        token: data['token'] as String,
        role: data['role'] as String,
        userId: data['user_id'] as String,
        fullName: data['full_name'] as String,
      );

      // Register FCM token immediately after login
      await _registerFcmToken();

      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
      return false;
    }
  }

  Future<bool> loginWithOneTimeToken({required String token}) async {
    final normalizedToken = token.trim();
    if (normalizedToken.isEmpty) {
      state = state.copyWith(error: 'Login code is required');
      return false;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final deviceId = await _getOrCreateDeviceId();
      final response = await ApiService.dio.post(
        '/auth/pilgrim/one-time-login',
        data: {'token': normalizedToken, 'device_id': deviceId},
      );
      final data = response.data as Map<String, dynamic>;

      await _persistSession(
        data['token'] as String,
        data['role'] as String,
        data['user_id'] as String,
        data['full_name'] as String,
      );

      state = state.copyWith(
        isLoading: false,
        token: data['token'] as String,
        role: data['role'] as String,
        userId: data['user_id'] as String,
        fullName: data['full_name'] as String,
      );

      // Register FCM token immediately after one-time login
      await _registerFcmToken();

      return true;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;

      // 410 = code expired, 409 = code already used
      // These are not auth errors — extract the server message directly
      // without triggering the global 401 logout interceptor.
      if (statusCode == 410 || statusCode == 409 || statusCode == 422) {
        final serverMessage = ApiService.parseError(e);
        state = state.copyWith(isLoading: false, error: serverMessage);
        return false;
      }

      // 401 with no existing session = invalid token (wrong code entered)
      if (statusCode == 401) {
        state = state.copyWith(
          isLoading: false,
          error: ApiService.parseError(e),
        );
        return false;
      }

      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'One-time login failed. Please try again.',
      );
      AppLogger.e('One-time login error: $e');
      return false;
    }
  }

  // ── Fetch profile ───────────────────────────────────────────────────────────
  /// Returns `false` when the session is invalid (401/404), after [logout] runs if needed.
  Future<bool> fetchProfile() async {
    if (!state.isAuthenticated) return false;
    await hydrateFromCache();
    try {
      final response = await ApiService.dio.get('/auth/me');
      final data = response.data as Map<String, dynamic>;
      state = state.copyWith(
        fullName: data['full_name'] as String?,
        email: data['email'] as String?,
        emailVerified: data['email_verified'] as bool? ?? false,
        phoneNumber: data['phone_number'] as String?,
        age: (data['age'] as num?)?.toInt(),
        gender: data['gender'] as String?,
        medicalHistory: data['medical_history'] as String?,
        hotelName: data['hotel_name'] as String?,
        roomNumber: data['room_number'] as String?,
        busInfo: data['bus_info'] as String?,
        visaNumber: data['visa']?['visa_number']?.toString(),
        visaStatus: data['visa']?['status']?.toString(),
        nationalId: data['national_id']?.toString(),
        language: data['language']?.toString(),
        ethnicity: data['ethnicity']?.toString(),
      );
      final prefs = await SharedPreferences.getInstance();
      if (data['full_name'] != null) {
        await prefs.setString('user_full_name', data['full_name'] as String);
      }
      final uid = data['_id']?.toString() ?? data['id']?.toString();
      if (uid != null && uid.isNotEmpty) {
        await prefs.setString('user_id', uid);
        await AppDataCache.write(uid, AppDataCache.authMeFile, data);
      }
      final r = data['role']?.toString() ?? data['user_type']?.toString();
      if (r != null && r.isNotEmpty) {
        await prefs.setString('user_role', r);
      }
      return true;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 404) {
        AppLogger.w('fetchProfile: invalid session (HTTP $code)');
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getString('auth_token') != null) {
          await logout();
        }
        return false;
      }
      final prefs = await SharedPreferences.getInstance();
      final uid = state.userId ?? prefs.getString('user_id');
      await _mergeAuthMeFromCache(uid);
      return true;
    }
  }

  // ── Update profile ──────────────────────────────────────────────────────────
  Future<bool> updateProfile({
    required String fullName,
    String? phoneNumber,
    int? age,
    String? gender,
    String? medicalHistory,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final body = <String, dynamic>{'full_name': fullName};
      if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
        body['phone_number'] = phoneNumber.trim();
      }
      if (age != null) body['age'] = age;
      if (gender != null && gender.isNotEmpty) body['gender'] = gender;
      // Always send medical_history so user can clear it by leaving it empty
      body['medical_history'] = medicalHistory ?? '';

      final response = await ApiService.dio.put(
        '/auth/update-profile',
        data: body,
      );
      final userData =
          (response.data as Map<String, dynamic>)['user']
              as Map<String, dynamic>;

      final newName = userData['full_name'] as String? ?? fullName;
      final newPhone = userData['phone_number'] as String?;
      final newAge = (userData['age'] as num?)?.toInt();
      final newGender = userData['gender'] as String?;
      final newMedical = userData['medical_history'] as String?;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_full_name', newName);

      state = state.copyWith(
        isLoading: false,
        fullName: newName,
        phoneNumber: newPhone,
        age: newAge,
        gender: newGender,
        medicalHistory: newMedical,
        clearError: true,
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
      return false;
    }
  }

  // ── Forgot Password ────────────────────────────────────────────────────────
  Future<bool> requestPasswordReset(String email) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await ApiService.dio.post('/auth/forgot-password', data: {'email': email});
      state = state.copyWith(isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
      return false;
    }
  }

  Future<String?> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await ApiService.dio.post(
        '/auth/reset-password',
        data: {
          'email': email,
          'code': code,
          'new_password': newPassword,
        },
      );
      state = state.copyWith(isLoading: false);
      return (response.data as Map<String, dynamic>)['message']?.toString();
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
      return null;
    }
  }

  // ── Update FCM Token ────────────────────────────────────────────────────────
  Future<void> updateFcmToken(String fcmToken) async {
    try {
      AppLogger.d('Attempting to register FCM token with backend: ${fcmToken.substring(0, min(20, fcmToken.length))}...');
      
      final response = await ApiService.dio.put(
        '/auth/fcm-token',
        data: {'fcm_token': fcmToken},
      );
      
      // Save it locally just for reference, though we no longer short-circuit
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_registered_fcm_token', fcmToken);
      
      AppLogger.i('✅ FCM token registered with backend successfully. Status: ${response.statusCode}');
    } on DioException catch (e) {
      AppLogger.e('⚠️ Failed to register FCM token API error: ${e.response?.statusCode} - ${e.response?.data}');
    } catch (e) {
      AppLogger.e('⚠️ Failed to register FCM token unknown error: $e');
    }
  }

  // ── Logout ──────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      // Call backend to clear FCM token
      await ApiService.dio.post('/auth/logout');
    } catch (e) {
      // Log error but continue with logout
      AppLogger.e('Logout API call failed', e);
    }

    // Disconnect socket
    SocketService.disconnect();

    // Clear local auth token and state
    await ApiService.clearAuthToken();

    // Clear cached FCM token so the next login always re-registers
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_registered_fcm_token');

    state = const AuthState();
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
