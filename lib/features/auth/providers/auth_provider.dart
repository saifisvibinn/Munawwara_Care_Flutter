import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/api_service.dart';
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
  final String?
  moderatorRequestStatus; // 'pending', 'approved', 'rejected', or null
  final bool promotedToModeratorPending;

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
    this.moderatorRequestStatus,
    this.promotedToModeratorPending = false,
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
    String? moderatorRequestStatus,
    bool? promotedToModeratorPending,
    bool clearError = false,
    bool clearPhoneNumber = false,
    bool clearEmail = false,
    bool clearPromotionFlag = false,
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
      moderatorRequestStatus:
          moderatorRequestStatus ?? this.moderatorRequestStatus,
      promotedToModeratorPending: clearPromotionFlag
          ? false
          : (promotedToModeratorPending ?? this.promotedToModeratorPending),
    );
  }
}

// ── Auth Notifier ─────────────────────────────────────────────────────────────
// Uses Riverpod 3.x Notifier API (StateNotifier was removed in v3)

class AuthNotifier extends Notifier<AuthState> {
  static const _deviceBindingIdKey = 'device_binding_id';

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

      if (token != null) {
        ApiService.dio.options.headers['Authorization'] = 'Bearer $token';
        state = AuthState(
          isRestoringSession: false,
          token: token,
          role: role,
          userId: userId,
          fullName: fullName,
        );

        // Check if role has changed on server (e.g., pilgrim promoted to moderator)
        await _checkRoleSync();
      } else {
        state = const AuthState(isRestoringSession: false);
      }
      AppLogger.d('AuthNotifier: restore complete');
    } catch (e, st) {
      // If shared preferences fails for any reason, we still want to clear the
      // restoring flag so the UI can proceed. Log the error to console.
      AppLogger.e('AuthNotifier restoreSession error: $e\n$st');
      state = const AuthState(isRestoringSession: false);
    }
  }

  // ── Check Role Sync ─────────────────────────────────────────────────────────
  // Verifies if local role matches server role. If not, signs out user.
  Future<void> _checkRoleSync() async {
    try {
      final localRole = state.role;
      if (localRole == null) return;

      AppLogger.d('Checking role sync: local=$localRole');

      // Fetch fresh profile from server
      final response = await ApiService.dio.get('/auth/me');
      final data = response.data as Map<String, dynamic>;
      final serverRole = data['user_type'] as String?;

      AppLogger.d('Role sync check: local=$localRole, server=$serverRole');

      // If roles don't match, user has been promoted/changed
      if (serverRole != null && serverRole != localRole) {
        if (localRole == 'pilgrim' && serverRole == 'moderator') {
          AppLogger.i(
            'Role upgraded pilgrim -> moderator. Refreshing session.',
          );
          await _refreshSessionAfterPromotion();
          return;
        }

        AppLogger.i(
          'Role mismatch detected ($localRole -> $serverRole). Logging out.',
        );
        await logout();
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;

      // Stale local session: token is invalid/expired or user no longer exists.
      // Keep auth state consistent by forcing logout and fresh login.
      if (statusCode == 401 || statusCode == 404) {
        AppLogger.w(
          'Role sync failed with status $statusCode. Clearing stale session.',
        );
        await logout();
        return;
      }

      // Other failures are likely transient network/server issues.
      AppLogger.w('Role sync check failed (network error): ${e.message}');
    } catch (e) {
      AppLogger.e('Role sync check error: $e');
    }
  }

  Future<void> _refreshSessionAfterPromotion() async {
    try {
      final response = await ApiService.dio.post('/auth/refresh-session');
      final data = response.data as Map<String, dynamic>;

      final newToken = data['token'] as String;
      final newRole = data['role'] as String;
      final newUserId = data['user_id'] as String;
      final newFullName = data['full_name'] as String;

      await _persistSession(newToken, newRole, newUserId, newFullName);

      state = state.copyWith(
        token: newToken,
        role: newRole,
        userId: newUserId,
        fullName: newFullName,
        moderatorRequestStatus:
            (data['moderator_request_status'] as String?) ?? 'approved',
        promotedToModeratorPending: true,
      );
    } on DioException catch (e) {
      AppLogger.w('Failed to refresh promoted session: ${e.message}');
      await logout();
    } catch (e) {
      AppLogger.e('Failed to refresh promoted session: $e');
      await logout();
    }
  }

  Future<void> syncRoleWithServer() async {
    await _checkRoleSync();
  }

  void acknowledgeModeratorPromotion() {
    state = state.copyWith(clearPromotionFlag: true);
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

  // ── Register Pilgrim ────────────────────────────────────────────────────────
  Future<bool> registerPilgrim({
    required String fullName,
    required String nationalId,
    required String phoneNumber,
    required String password,
    String? medicalHistory,
    int? age,
    String? gender,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final body = <String, dynamic>{
        'full_name': fullName,
        'national_id': nationalId,
        'phone_number': phoneNumber,
        'password': password,
      };
      if (medicalHistory != null && medicalHistory.isNotEmpty) {
        body['medical_history'] = medicalHistory;
      }
      if (age != null) body['age'] = age;
      if (gender != null) body['gender'] = gender;

      final response = await ApiService.dio.post('/auth/register', data: body);
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
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
      return false;
    }
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

      return true;
    } on DioException catch (e) {
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
  Future<void> fetchProfile() async {
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
        moderatorRequestStatus: data['moderator_request_status'] as String?,
      );
      // Persist updated full_name to prefs
      if (data['full_name'] != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_full_name', data['full_name'] as String);
      }
    } on DioException catch (_) {
      // Silent — profile fetch failures shouldn't disrupt UX
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

  // ── Update FCM Token ────────────────────────────────────────────────────────
  Future<void> updateFcmToken(String fcmToken) async {
    try {
      // Only hit the backend when the token has actually changed.
      const lastTokenKey = 'last_registered_fcm_token';
      final prefs = await SharedPreferences.getInstance();
      final lastToken = prefs.getString(lastTokenKey);
      if (lastToken == fcmToken) {
        AppLogger.d('FCM token unchanged — skipping backend registration');
        return;
      }

      await ApiService.dio.put(
        '/auth/fcm-token',
        data: {'fcm_token': fcmToken},
      );
      await prefs.setString(lastTokenKey, fcmToken);
      AppLogger.i('✅ FCM token registered with backend');
    } catch (e) {
      AppLogger.e('⚠️ Failed to register FCM token: $e');
    }
  }

  // ── Add Email ───────────────────────────────────────────────────────────────
  Future<bool> addEmail(String email) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await ApiService.dio.post(
        '/auth/add-email',
        data: {'email': email.trim()},
      );
      state = state.copyWith(
        isLoading: false,
        email: email.trim(),
        emailVerified: false,
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
      return false;
    }
  }

  // ── Send Email Verification ─────────────────────────────────────────────────
  Future<bool> sendEmailVerification() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await ApiService.dio.post('/auth/send-email-verification');
      state = state.copyWith(isLoading: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
      return false;
    }
  }

  // ── Verify Email ────────────────────────────────────────────────────────────
  Future<bool> verifyEmail(String code) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await ApiService.dio.post(
        '/auth/verify-email',
        data: {'code': code.trim()},
      );
      state = state.copyWith(isLoading: false, emailVerified: true);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
      return false;
    }
  }

  // ── Request Moderator Status ────────────────────────────────────────────────
  Future<bool> requestModerator() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await ApiService.dio.post('/auth/request-moderator');
      state = state.copyWith(
        isLoading: false,
        moderatorRequestStatus: 'pending',
      );
      return true;
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
      return false;
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
