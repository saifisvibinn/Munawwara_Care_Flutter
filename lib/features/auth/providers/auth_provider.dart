import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../pilgrim/models/insurance_company.dart';
import '../models/wakel_info.dart';
import '../../../core/bootstrap/mobile_messaging_bootstrap.dart'
    show kIosVoipPushTokenPrefsKey;
import '../../../core/services/api_service.dart';
import '../../../core/services/app_data_cache.dart';
import '../../../core/services/fcm_token_helper.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/secure_session_store.dart';
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
  final String? profilePicture;
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
  final String? alternativePhoneNumber;
  final String? morafeqName;
  final String? morafeqPhone;
  final String? morafeqEmail;
  final String? tasheraNumber;
  final InsuranceCompany? insuranceCompany;
  final WakelInfo? wakelInfo;

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
    this.profilePicture,
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
    this.alternativePhoneNumber,
    this.morafeqName,
    this.morafeqPhone,
    this.morafeqEmail,
    this.tasheraNumber,
    this.insuranceCompany,
    this.wakelInfo,
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
    String? profilePicture,
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
    String? alternativePhoneNumber,
    String? morafeqName,
    String? morafeqPhone,
    String? morafeqEmail,
    String? tasheraNumber,
    InsuranceCompany? insuranceCompany,
    WakelInfo? wakelInfo,
    bool clearError = false,
    bool clearPhoneNumber = false,
    bool clearEmail = false,
    bool clearAge = false,
    bool clearGender = false,
    bool clearMedicalHistory = false,
    bool clearProfilePicture = false,
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
      profilePicture: clearProfilePicture ? null : (profilePicture ?? this.profilePicture),
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
      alternativePhoneNumber:
          alternativePhoneNumber ?? this.alternativePhoneNumber,
      morafeqName: morafeqName ?? this.morafeqName,
      morafeqPhone: morafeqPhone ?? this.morafeqPhone,
      morafeqEmail: morafeqEmail ?? this.morafeqEmail,
      tasheraNumber: tasheraNumber ?? this.tasheraNumber,
      insuranceCompany: insuranceCompany ?? this.insuranceCompany,
      wakelInfo: wakelInfo ?? this.wakelInfo,
    );
  }
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────
// Uses Riverpod 3.x Notifier API (StateNotifier was removed in v3)

class AuthNotifier extends Notifier<AuthState> {
  Completer<void>? _remoteValidationCompleter;
  Future<void>? _fcmRegistrationInFlight;
  static String? Function()? _fcmTokenGetter;

  /// Reuses the token obtained during [bindMobileMessagingServices] when set.
  static void setFcmTokenGetter(String? Function() getter) {
    _fcmTokenGetter = getter;
  }

  @override
  AuthState build() {
    _restoreSession();
    return const AuthState(isRestoringSession: true);
  }

  // ── Restore session on startup ──────────────────────────────────────────────
  /// Phase A: prefs + disk cache only — unblocks splash without network.
  Future<void> _restoreSession() async {
    try {
      AppLogger.d('AuthNotifier: restoring session (cached)');
      final token = await SecureSessionStore.getToken();
      final role = await SecureSessionStore.getRole();
      final userId = await SecureSessionStore.getUserId();
      final fullName = await SecureSessionStore.getFullName();

      if (token == null || token.isEmpty) {
        state = const AuthState(isRestoringSession: false);
        AppLogger.d('AuthNotifier: restore complete (no token)');
        return;
      }

      ApiService.dio.options.headers['Authorization'] = 'Bearer $token';
      state = AuthState(
        isRestoringSession: false,
        token: token,
        role: role,
        userId: userId,
        fullName: fullName,
      );
      await _mergeAuthMeFromCache(userId);
      await SecureSessionStore.syncNativeMirrorPrefs();
      AppLogger.d('AuthNotifier: cached session ready — validating in background');
      _remoteValidationCompleter = Completer<void>();
      unawaited(
        _validateSessionRemotely(token, role, userId, fullName).whenComplete(
          _completeRemoteValidation,
        ),
      );
    } catch (e, st) {
      AppLogger.e('AuthNotifier restoreSession error: $e\n$st');
      state = const AuthState(isRestoringSession: false);
      _completeRemoteValidation();
    }
  }

  void _completeRemoteValidation() {
    final c = _remoteValidationCompleter;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
    _remoteValidationCompleter = null;
  }

  /// Awaited by splash before navigation when a token exists.
  Future<void> waitForRemoteSessionValidation() async {
    final pending = _remoteValidationCompleter;
    if (pending != null) {
      await pending.future;
    }
  }

  /// Phase B: network validation before splash navigates away.
  Future<void> _validateSessionRemotely(
    String token,
    String? role,
    String? userId,
    String? fullName,
  ) async {
    try {
      final response = await ApiService.dio.get('/auth/me');
      final raw = response.data;
      final data = raw is Map<String, dynamic>
          ? raw
          : (raw is Map
                ? Map<String, dynamic>.from(raw)
                : <String, dynamic>{});

      final resolvedRole = (data['role'] ?? data['user_type'] ?? role)
          ?.toString();
      final resolvedId = (data['_id'] ?? data['id'] ?? userId)?.toString();
      final resolvedName = (data['full_name'] ?? fullName)?.toString();

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
        profilePicture: data['profile_picture'] as String?,
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
        alternativePhoneNumber: data['alternative_phone_number']?.toString(),
        morafeqName: data['morafeq_name']?.toString(),
        morafeqPhone: data['morafeq_phone']?.toString(),
        morafeqEmail: data['morafeq_email']?.toString(),
        tasheraNumber: data['tashera_number']?.toString(),
        insuranceCompany: data['insurance_company_id'] != null
            ? InsuranceCompany.fromJson(
                Map<String, dynamic>.from(data['insurance_company_id']),
              )
            : null,
        wakelInfo: data['wakel_id'] != null
            ? WakelInfo.fromJson(
                Map<String, dynamic>.from(data['wakel_id']),
              )
            : null,
      );

      if (data['full_name'] != null) {
        await SecureSessionStore.setFullName(data['full_name'] as String);
      }
      if (resolvedId != null && resolvedId.isNotEmpty) {
        await SecureSessionStore.setUserId(resolvedId);
      }
      if (resolvedRole != null && resolvedRole.isNotEmpty) {
        await SecureSessionStore.setRole(resolvedRole);
      }
      await SecureSessionStore.syncNativeMirrorPrefs();

      final cacheId = resolvedId ?? userId;
      if (cacheId != null && cacheId.isNotEmpty) {
        await AppDataCache.write(cacheId, AppDataCache.authMeFile, data);
      }
      AppLogger.d('AuthNotifier: remote session validated');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401) {
        AppLogger.w('AuthNotifier: /auth/me 401 during background validate');
        if (await ApiService.hasStoredAuthToken()) {
          await _invalidateSessionLocally();
        }
        return;
      }
      if (code == 404) {
        AppLogger.w(
          'AuthNotifier: /auth/me 404 during background validate — clearing session',
        );
        await _invalidateSessionLocally();
        return;
      }
      AppLogger.w(
        'AuthNotifier: /auth/me failed (HTTP $code) — keeping offline session',
      );
    } catch (e, st) {
      AppLogger.e('AuthNotifier validateSessionRemotely error: $e\n$st');
    }
  }

  /// Called from [bindMobileMessagingServices] after first frame.
  Future<void> requestNotificationPermissionsForStartup() =>
      _requestNotificationPermissions();

  Future<void> _mergeAuthMeFromCache(String? userId) async {
    if (userId == null || userId.isEmpty) return;
    final raw = await AppDataCache.readData(userId, AppDataCache.authMeFile);
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    state = state.copyWith(
      fullName: (data['full_name'] ?? state.fullName)?.toString(),
      email: data['email'] as String? ?? state.email,
      profilePicture: data['profile_picture'] as String? ?? state.profilePicture,
      emailVerified: data['email_verified'] as bool? ?? state.emailVerified,
      phoneNumber: data['phone_number'] as String? ?? state.phoneNumber,
      age: (data['age'] as num?)?.toInt() ?? state.age,
      gender: data['gender'] as String? ?? state.gender,
      medicalHistory:
          data['medical_history'] as String? ?? state.medicalHistory,
      hotelName: data['hotel_name'] as String? ?? state.hotelName,
      roomNumber: data['room_number'] as String? ?? state.roomNumber,
      busInfo: data['bus_info'] as String? ?? state.busInfo,
      visaNumber: data['visa']?['visa_number']?.toString() ?? state.visaNumber,
      visaStatus: data['visa']?['status']?.toString() ?? state.visaStatus,
      nationalId: data['national_id']?.toString() ?? state.nationalId,
      language: data['language']?.toString() ?? state.language,
      ethnicity: data['ethnicity']?.toString() ?? state.ethnicity,
      alternativePhoneNumber: data['alternative_phone_number']?.toString() ??
          state.alternativePhoneNumber,
      morafeqName: data['morafeq_name']?.toString() ?? state.morafeqName,
      morafeqPhone: data['morafeq_phone']?.toString() ?? state.morafeqPhone,
      morafeqEmail: data['morafeq_email']?.toString() ?? state.morafeqEmail,
      tasheraNumber:
          data['tashera_number']?.toString() ?? state.tasheraNumber,
      insuranceCompany: data['insurance_company_id'] != null
          ? InsuranceCompany.fromJson(
              Map<String, dynamic>.from(data['insurance_company_id']),
            )
          : state.insuranceCompany,
      wakelInfo: data['wakel_id'] != null
          ? WakelInfo.fromJson(
              Map<String, dynamic>.from(data['wakel_id']),
            )
          : state.wakelInfo,
    );
  }

  /// Merge `/auth/me` fields from disk when token exists (e.g. offline cold start).
  Future<void> hydrateFromCache() async {
    if (!await ApiService.hasStoredAuthToken()) return;
    final uid = state.userId ?? await SecureSessionStore.getUserId();
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
    await prefs.remove('last_registered_voip_token');
    state = const AuthState(isRestoringSession: false);
  }

  Future<void> _requestNotificationPermissions() async {
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await NotificationService.instance.ensureInitialized();
        AppLogger.d('AuthNotifier: requesting notification permissions');
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          announcement: false,
          badge: true,
          carPlay: false,
          criticalAlert: false,
          provisional: false,
          sound: true,
        );

        // Request local notification permissions
        await NotificationService.instance.requestPermissions();
      } catch (e) {
        AppLogger.e('AuthNotifier permission request failed: $e');
      }
    }
  }

  /// Permissions + FCM run after navigation so login never stalls on slow GMS.
  void _schedulePostLoginSetup() {
    unawaited(_runPostLoginSetup());
  }

  Future<void> _runPostLoginSetup() async {
    try {
      await _requestNotificationPermissions();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('last_registered_fcm_token');
      await prefs.remove('last_registered_voip_token');
      await ensureFcmTokenRegistered();
      await ensureVoipTokenRegistered();
    } catch (e, st) {
      AppLogger.e('AuthNotifier post-login setup failed: $e\n$st');
    }
  }

  Future<void> _persistSession(
    String token,
    String role,
    String userId,
    String fullName,
  ) async {
    await ApiService.setAuthToken(token);
    await SecureSessionStore.setSessionProfile(
      role: role,
      userId: userId,
      fullName: fullName,
    );
    await SecureSessionStore.syncNativeMirrorPrefs();
    await ApiService.cacheNativeBridgePrefs();
  }

  Future<String> _getOrCreateDeviceId() async {
    final existing = await SecureSessionStore.getDeviceBindingId();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final generated = const Uuid().v4();
    await SecureSessionStore.setDeviceBindingId(generated);
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

      await fetchProfile();

      _schedulePostLoginSetup();

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

      await fetchProfile();

      _schedulePostLoginSetup();

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
        profilePicture: data['profile_picture'] as String?,
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
        alternativePhoneNumber: data['alternative_phone_number']?.toString(),
        morafeqName: data['morafeq_name']?.toString(),
        morafeqPhone: data['morafeq_phone']?.toString(),
        morafeqEmail: data['morafeq_email']?.toString(),
        tasheraNumber: data['tashera_number']?.toString(),
        insuranceCompany: data['insurance_company_id'] != null
            ? InsuranceCompany.fromJson(
                Map<String, dynamic>.from(data['insurance_company_id']),
              )
            : null,
        wakelInfo: data['wakel_id'] != null
            ? WakelInfo.fromJson(
                Map<String, dynamic>.from(data['wakel_id']),
              )
            : null,
      );
      if (data['full_name'] != null) {
        await SecureSessionStore.setFullName(data['full_name'] as String);
      }
      final uid = data['_id']?.toString() ?? data['id']?.toString();
      if (uid != null && uid.isNotEmpty) {
        await SecureSessionStore.setUserId(uid);
        await AppDataCache.write(uid, AppDataCache.authMeFile, data);
      }
      final r = data['role']?.toString() ?? data['user_type']?.toString();
      if (r != null && r.isNotEmpty) {
        await SecureSessionStore.setRole(r);
      }
      await SecureSessionStore.syncNativeMirrorPrefs();
      return true;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 401 || code == 404) {
        AppLogger.w('fetchProfile: invalid session (HTTP $code)');
        if (await ApiService.hasStoredAuthToken()) {
          await logout();
        }
        return false;
      }
      final uid = state.userId ?? await SecureSessionStore.getUserId();
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

      await SecureSessionStore.setFullName(newName);

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

  // ── Update profile picture ──────────────────────────────────────────────────
  Future<bool> updateProfilePicture(File file) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: fileName),
      });
      final response = await ApiService.dio.put(
        '/auth/profile-picture',
        data: formData,
      );
      final data = response.data as Map<String, dynamic>;
      final payload = data['data'] as Map<String, dynamic>? ?? data;
      final newPicUrl = payload['profile_picture'] as String?;

      state = state.copyWith(
        isLoading: false,
        profilePicture: newPicUrl,
        clearError: true,
      );

      final uid = state.userId;
      if (uid != null && uid.isNotEmpty) {
        final cachedData = await AppDataCache.readData(uid, AppDataCache.authMeFile);
        if (cachedData is Map) {
          final updatedCached = Map<String, dynamic>.from(cachedData);
          updatedCached['profile_picture'] = newPicUrl;
          await AppDataCache.write(uid, AppDataCache.authMeFile, updatedCached);
        }
      }

      await fetchProfile();
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
      await ApiService.dio.post(
        '/auth/forgot-password',
        data: {'email': email},
      );
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
        data: {'email': email, 'code': code, 'new_password': newPassword},
      );
      state = state.copyWith(isLoading: false);
      return (response.data as Map<String, dynamic>)['message']?.toString();
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
      return null;
    }
  }

  /// Ensures the backend has a current FCM token (calls, TTS, chat pushes).
  Future<void> ensureFcmTokenRegistered() async {
    if (!state.isAuthenticated) return;
    final inFlight = _fcmRegistrationInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final registration = _registerFcmTokenAfterLogin();
    _fcmRegistrationInFlight = registration;
    try {
      await registration;
    } finally {
      if (identical(_fcmRegistrationInFlight, registration)) {
        _fcmRegistrationInFlight = null;
      }
    }
  }

  /// Upload device push token right after login when the JWT is guaranteed valid.
  Future<void> _registerFcmTokenAfterLogin() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }
    String? fcm = _fcmTokenGetter?.call();
    if (fcm == null || fcm.isEmpty) {
      try {
        fcm = await obtainFcmRegistrationToken();
      } catch (e) {
        AppLogger.w('AuthNotifier: FCM getToken failed: $e');
        return;
      }
    }
    if (fcm == null || fcm.isEmpty) {
      return;
    }
    await updateFcmToken(fcm);
  }

  // ── Update FCM Token ────────────────────────────────────────────────────────
  Future<void> updateFcmToken(String fcmToken) async {
    if (!await ApiService.hasStoredAuthToken()) {
      AppLogger.d('Skip FCM register — not logged in');
      return;
    }
    try {
      await ApiService.ensureAuthHeaderFromPrefs();
      final prefs = await SharedPreferences.getInstance();
      final lastRegistered = prefs.getString('last_registered_fcm_token');
      if (lastRegistered == fcmToken) {
        return;
      }

      AppLogger.d(
        'Attempting to register FCM token with backend: '
        '${fcmToken.substring(0, min(20, fcmToken.length))}...',
      );

      final response = await ApiService.dio.put(
        '/auth/fcm-token',
        data: {'fcm_token': fcmToken},
      );

      await prefs.setString('last_registered_fcm_token', fcmToken);

      AppLogger.i(
        '✅ FCM token registered with backend successfully. '
        'Status: ${response.statusCode}',
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      AppLogger.e(
        '⚠️ Failed to register FCM token API error: $code - ${e.response?.data}',
      );
      if (code == 401) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('last_registered_fcm_token');
      }
    } catch (e) {
      AppLogger.e('⚠️ Failed to register FCM token unknown error: $e');
    }
  }

  /// Uploads the locally-cached iOS PushKit VoIP token (if any) after login.
  /// No-op on non-iOS platforms or when no token has been issued yet.
  Future<void> ensureVoipTokenRegistered() async {
    if (!Platform.isIOS) return;
    if (!state.isAuthenticated) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(kIosVoipPushTokenPrefsKey);
      if (token == null || token.isEmpty) return;
      await updateVoipToken(token);
    } catch (e) {
      AppLogger.w('ensureVoipTokenRegistered failed: $e');
    }
  }

  // ── Update iOS VoIP (PushKit) Token ─────────────────────────────────────────
  /// Uploads the iOS PushKit VoIP token so the backend can deliver incoming
  /// calls via APNs VoIP pushes (reliable while backgrounded/terminated).
  /// Stored separately from the FCM token — never send one to the other's API.
  Future<void> updateVoipToken(String voipToken) async {
    if (voipToken.isEmpty) return;
    if (!await ApiService.hasStoredAuthToken()) {
      AppLogger.d('Skip VoIP register — not logged in');
      return;
    }
    try {
      await ApiService.ensureAuthHeaderFromPrefs();
      final prefs = await SharedPreferences.getInstance();
      final lastRegistered = prefs.getString('last_registered_voip_token');
      if (lastRegistered == voipToken) {
        return;
      }

      AppLogger.d(
        'Attempting to register VoIP token with backend: '
        '${voipToken.substring(0, min(20, voipToken.length))}...',
      );

      final response = await ApiService.dio.put(
        '/auth/voip-token',
        data: {'voip_token': voipToken},
      );

      await prefs.setString('last_registered_voip_token', voipToken);

      AppLogger.i(
        '✅ VoIP token registered with backend successfully. '
        'Status: ${response.statusCode}',
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      AppLogger.e(
        '⚠️ Failed to register VoIP token API error: $code - ${e.response?.data}',
      );
      if (code == 401) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('last_registered_voip_token');
      }
    } catch (e) {
      AppLogger.e('⚠️ Failed to register VoIP token unknown error: $e');
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

    // Clear cached push tokens so the next login always re-registers
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_registered_fcm_token');
    await prefs.remove('last_registered_voip_token');

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
