import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

import 'caller_gender_cache.dart';
import '../../features/shared/widgets/pilgrim_gender_avatar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../config/backend_config.dart';
import 'api_service.dart';
import 'secure_session_store.dart';
import '../utils/app_logger.dart';

/// Shown on CallKit / prefs when a pilgrim receives a moderator call (native asset path).
const String kCallKitSupportAvatarAsset = 'assets/static/app_icon.png';

/// Transparent mark for in-app UI (inbox, headers, in-call branding).
const String kSupportBrandAvatarAsset = 'assets/static/inapp_icon.png';
const String kDefaultSupportDisplayName = 'Munawwara Care';
const String kSupportDisplayNamePrefsKey = 'support_display_name';
const String _kSupportDisplayNameTranslationKey = 'call_support_display_name';
const String _kTranslationsAssetPath = 'assets/translations';
const String kPendingCallRecordIdKey = 'pending_call_record_id';
const String kNativeApiBaseUrlFallback = kDefaultProductionApiBaseUrl;

// ─────────────────────────────────────────────────────────────────────────────
// CallKitService — Shows native incoming call screen (like WhatsApp)
// Uses Android ConnectionService / iOS CallKit under the hood.
// Works even when app is killed, screen off, or locked.
// ─────────────────────────────────────────────────────────────────────────────

class CallKitService {
  static final CallKitService instance = CallKitService._();
  CallKitService._();

  static const MethodChannel _nativeIncomingChannel = MethodChannel(
    'com.munawwaracare.android/incoming_call',
  );

  static const _uuid = Uuid();
  static const _pendingCallerIdKey = 'pending_call_caller_id';
  static const _pendingCallerNameKey = 'pending_call_caller_name';
  static const _pendingCallerRoleKey = 'pending_call_caller_role';
  static const _pendingCallerGenderKey = 'pending_call_caller_gender';
  static const _pendingCallerProfilePictureKey =
      'pending_call_caller_profile_picture';
  static const _pendingChannelNameKey = 'pending_call_channel_name';
  static const _pendingCreatedAtMsKey = 'pending_call_created_at_ms';
  static const _pendingCallUuidKey = 'pending_call_uuid';
  static const _pendingCallRecordIdKey = kPendingCallRecordIdKey;
  static const _pendingOutgoingStopReasonKey = 'pending_outgoing_stop_reason';

  /// FCM may send call control under [type] or [notification_type].
  static String? fcmCallControlType(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    if (type == 'call_declined' ||
        type == 'call_cancel' ||
        type == 'call_ended' ||
        type == 'call_answered') {
      return type;
    }
    final notificationType = data['notification_type']?.toString() ?? '';
    if (notificationType == 'call_declined' ||
        notificationType == 'call_cancel' ||
        notificationType == 'call_ended' ||
        notificationType == 'call_answered') {
      return notificationType;
    }
    return null;
  }

  static Future<void> persistPendingOutgoingStop(String reason) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingOutgoingStopReasonKey, reason);
  }

  static Future<String?> consumePendingOutgoingStop() async {
    final prefs = await SharedPreferences.getInstance();
    final reason = prefs.getString(_pendingOutgoingStopReasonKey);
    if (reason != null && reason.isNotEmpty) {
      await prefs.remove(_pendingOutgoingStopReasonKey);
    }
    return reason;
  }

  // Track the current call UUID so we can end it later
  String? _currentCallId;
  String? get currentCallId => _currentCallId;

  /// Native CallKit / Android notification id (matches [SharedPreferences] when
  /// Dart-side [_currentCallId] was cleared after tray hide).
  Future<String?> peekCallKitNotificationId() async {
    if (_currentCallId != null && _currentCallId!.isNotEmpty) return _currentCallId;
    final prefs = await SharedPreferences.getInstance();
    final fromPrefs = prefs.getString(_pendingCallUuidKey);
    if (fromPrefs != null && fromPrefs.isNotEmpty) return fromPrefs;
    return null;
  }

  /// Timestamp of the last showIncomingCall invocation — used to reject
  /// rapid duplicate invocations that slip past the _currentCallId guard.
  DateTime? _lastShowTime;

  /// Last ring we surfaced — blocks duplicate socket+FCM for the same attempt.
  String? _lastShownCallRecordId;
  String? _lastShownChannelName;

  /// Show a native incoming call screen.
  /// Call this from both foreground and background FCM handlers.
  ///
  /// [skipServerVerify] — set to `true` when called from the FCM background
  /// handler. In that context `ApiService.dio` is not initialised (no base URL
  /// or auth headers in the background isolate), so the HTTP check would
  /// silently fail and suppress the ring. The FCM message itself IS the
  /// server's signal that the call is active, so the extra round-trip is
  /// redundant anyway.
  Future<void> showIncomingCall({
    required String callerId,
    required String callerName,
    required String channelName,
    String? callerRole,
    String? callRecordId,
    String? displayName,
    String? callerGender,
    String? callerProfilePicture,
    bool skipServerVerify = false,
  }) async {
    // ── Guard 1: Dart-side flag (with stale-state recovery) ─────────────
    if (_currentCallId != null) {
      try {
        final activeCalls = await FlutterCallkitIncoming.activeCalls();
        final hasActiveNativeCall =
            activeCalls is List && activeCalls.isNotEmpty;
        if (!hasActiveNativeCall) {
          AppLogger.w(
            '📞 [CallKit] Stale _currentCallId detected with no active native call — resetting local tracking',
          );
          await clearLocalCallTracking();
        } else {
          AppLogger.w(
            '📞 [CallKit] _currentCallId already set and native call active — ignoring duplicate',
          );
          return;
        }
      } catch (e) {
        AppLogger.e('📞 [CallKit] stale-check activeCalls() failed: $e');
        return;
      }
    }

    // ── Guard 2: Same call attempt (record / channel) ───────────────────
    final recordKey = callRecordId?.trim() ?? '';
    if (recordKey.isNotEmpty && recordKey == _lastShownCallRecordId) {
      AppLogger.w(
        '📞 [CallKit] duplicate callRecordId=$recordKey — ignoring',
      );
      return;
    }
    if (channelName.isNotEmpty &&
        channelName == _lastShownChannelName &&
        _lastShowTime != null &&
        DateTime.now().difference(_lastShowTime!).inSeconds < 45) {
      AppLogger.w(
        '📞 [CallKit] duplicate channel=$channelName — ignoring',
      );
      return;
    }

    // ── Guard 3: Timestamp-based dedup (5 s window) ─────────────────────
    final now = DateTime.now();
    if (_lastShowTime != null && now.difference(_lastShowTime!).inSeconds < 5) {
      AppLogger.w('📞 [CallKit] showIncomingCall called within 5 s — ignoring');
      return;
    }

    // ── Guard 4: Server must still be ringing this caller ───────────────
    // Skipped when called from FCM background handler — ApiService.dio is not
    // initialised in the background isolate and the FCM is itself proof the
    // server initiated this call.
    if (!skipServerVerify) {
      final callerKey = callerId.trim();
      if (callerKey.isNotEmpty) {
        final allowed = await verifyIncomingCallActive(
          callerId: callerKey,
          callRecordId: recordKey.isEmpty ? null : recordKey,
        );
        if (!allowed) {
          return;
        }
      }
    }

    // ── Guard 5: Check actual system state for active calls ─────────────
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls is List && activeCalls.isNotEmpty) {
        AppLogger.w(
          '📞 [CallKit] System reports ${activeCalls.length} active call(s) — ending stale calls first',
        );
        await FlutterCallkitIncoming.endAllCalls();
        // Small delay so the system UI fully dismisses
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      AppLogger.e('📞 [CallKit] activeCalls() check failed: $e');
    }

    _currentCallId = _uuid.v4();
    _lastShowTime = now;
    _lastShownCallRecordId = recordKey.isEmpty ? null : recordKey;
    _lastShownChannelName = channelName.isEmpty ? null : channelName;

    final prefs = await SharedPreferences.getInstance();
    final role = (await SecureSessionStore.getRole()) ?? '';
    final useSupportBranding = role == 'pilgrim';
    final nativeCallerLine = useSupportBranding
        ? await _resolveSupportDisplayName(displayName)
        : (displayName?.trim().isNotEmpty == true ? displayName!.trim() : callerName);
    final isPilgrimCaller = _isPilgrimCallerRole(callerRole);
    var resolvedGender = CallerGenderCache.normalize(callerGender);
    if (!useSupportBranding && callerId.trim().isNotEmpty) {
      final fromCache = await CallerGenderCache.resolve(callerId);
      resolvedGender ??= fromCache;
    }
    var resolvedProfilePicture = callerProfilePicture?.trim();
    if (!useSupportBranding &&
        isPilgrimCaller &&
        (resolvedProfilePicture == null || resolvedProfilePicture.isEmpty) &&
        callerId.trim().isNotEmpty) {
      resolvedProfilePicture =
          await CallerGenderCache.resolveProfilePicture(callerId);
    }
    final avatar = _resolveCallKitAvatar(
      useSupportBranding: useSupportBranding,
      isPilgrimCaller: isPilgrimCaller,
      resolvedGender: resolvedGender,
      profilePictureUrl: resolvedProfilePicture,
    );
    final Map<String, dynamic> avatarHeaders = {};
    if (avatar.startsWith('http')) {
      final token = await SecureSessionStore.getToken();
      if (token != null && token.isNotEmpty) {
        avatarHeaders['Authorization'] = 'Bearer $token';
      }
    }
    AppLogger.i(
      '📞 CallKit avatar role=$role caller=$callerId pilgrim=$isPilgrimCaller '
      'fcmGender=${callerGender ?? "—"} resolved=${resolvedGender ?? "—"} '
      'avatar=${avatar.startsWith("http") ? "url" : avatar}',
    );
    final apiBaseUrl = prefs.getString(kNativeApiBaseUrlPrefsKey) ??
        kNativeApiBaseUrlFallback;

    await _savePendingIncomingCall(
      callerId: callerId,
      callerName: nativeCallerLine,
      callerRole: callerRole ?? '',
      channelName: channelName,
      callRecordId: callRecordId,
      apiBaseUrl: apiBaseUrl,
      callerGender: resolvedGender ?? callerGender,
      callerProfilePicture: resolvedProfilePicture ?? callerProfilePicture,
    );

    final androidParams = AndroidParams(
      isCustomNotification: false,
      // Keep only [avatar] in the large ring; isShowLogo + logoUrl duplicates the same asset uptop.
      isShowLogo: false,
      logoUrl: null,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#0B1220',
      actionColor: '#F97316',
      textColor: '#FFFFFF',
      isShowFullLockedScreen: true,
      incomingCallNotificationChannelName: 'Incoming Calls',
      isShowCallID: true,
    );

    final params = CallKitParams(
      id: _currentCallId!,
      nameCaller: nativeCallerLine,
      appName: 'Munawwara Care',
      avatar: avatar,
      handle: callerRole ?? 'Voice Call',
      type: 0, // 0 = audio call, 1 = video call
      duration: 35000, // 35s CallKit ring; server timeout is 45s (10s gap)
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: false, // backend sends the single missed-call FCM
        isShowCallback: false,
        subtitle: 'Missed Call',
        callbackText: 'Call Back',
      ),
      extra: <String, dynamic>{
        'callerId': callerId,
        'callerName': nativeCallerLine,
        'peerCallerName': callerName,
        'callerRole': callerRole ?? '',
        'channelName': channelName,
        'apiBaseUrl': apiBaseUrl,
        if (callRecordId != null && callRecordId.isNotEmpty)
          'callRecordId': callRecordId,
        if (callerGender != null && callerGender.trim().isNotEmpty)
          'callerGender': callerGender.trim(),
      },
      headers: avatarHeaders,
      android: androidParams,
      ios: const IOSParams(
        iconName: 'AppIcon',
        supportsVideo: false,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'voiceChat',
        // Let CallKit activate AVAudioSession on answer (Apple VoIP guidance).
        audioSessionActive: false,
        configureAudioSession: false,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
    AppLogger.i('📞 Native incoming call screen shown ($nativeCallerLine)');
  }

  static Future<void> cacheSupportDisplayNameFromBundle() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(kSupportDisplayNamePrefsKey);
      if (cached != null && cached.isNotEmpty) {
        return;
      }
      await prefs.setString(
        kSupportDisplayNamePrefsKey,
        kDefaultSupportDisplayName,
      );
    } catch (_) {}
  }

  static Future<void> refreshCachedSupportDisplayName({
    String languageCode = 'en',
  }) async {
    final label = await readSupportDisplayNameFromAssets(
      languageCode: languageCode,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kSupportDisplayNamePrefsKey, label);
    } catch (_) {}
  }

  static Future<String> readSupportDisplayNameFromAssets({
    String languageCode = 'en',
  }) async {
    final candidates = <String>{
      languageCode,
      'en',
    };
    for (final code in candidates) {
      try {
        final raw = await rootBundle.loadString(
          '$_kTranslationsAssetPath/$code.json',
        );
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final value = map[_kSupportDisplayNameTranslationKey]?.toString().trim();
        if (value != null && value.isNotEmpty) {
          return value;
        }
      } catch (_) {}
    }
    return kDefaultSupportDisplayName;
  }

  static Future<String> _resolveSupportDisplayName(String? fcmDisplayName) async {
    final fromFcm = fcmDisplayName?.trim();
    if (fromFcm != null && fromFcm.isNotEmpty) return fromFcm;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(kSupportDisplayNamePrefsKey);
      if (cached != null && cached.isNotEmpty) return cached;
    } catch (_) {}

    return readSupportDisplayNameFromAssets(
      languageCode: await _preferredLanguageCode(),
    );
  }

  static Future<String> _preferredLanguageCode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('locale');
      if (stored != null && stored.isNotEmpty) {
        return stored.split(RegExp('[-_]')).first;
      }
    } catch (_) {}
    return 'en';
  }

  static bool isIncomingCallFcm(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    if (type == 'incoming_call') return true;
    final notificationType = data['notification_type']?.toString() ?? '';
    return notificationType == 'incoming_call';
  }

  /// Android: `endCall` alone does not remove the incoming-call tray notification;
  /// the plugin expects [FlutterCallkitIncoming.hideCallkitIncoming] to run
  /// [clearIncomingNotification] (see Kotlin `hideCallkitIncoming`).
  static Future<void> _hideIncomingTrayForId(String id) async {
    if (id.isEmpty) return;
    try {
      await FlutterCallkitIncoming.hideCallkitIncoming(
        CallKitParams(
          id: id,
          nameCaller: '',
          appName: 'Munawwara Care',
          handle: '',
          type: 0,
        ),
      );
    } catch (e) {
      AppLogger.w('📞 [CallKit] hideCallkitIncoming failed: $e');
    }
  }

  /// Hides the Android incoming notification only — keeps SharedPreferences so
  /// a cold-start accept can still read `channelName` / caller from prefs.
  static Future<void> hideIncomingTrayFromPersistedUuidOnly() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uuid = prefs.getString(_pendingCallUuidKey);
      if (uuid != null && uuid.isNotEmpty) {
        await _hideIncomingTrayForId(uuid);
      }
    } catch (e) {
      AppLogger.w('📞 hideIncomingTrayFromPersistedUuidOnly: $e');
    }
  }

  Future<String?> _resolveActiveCallId() async {
    if (_currentCallId != null && _currentCallId!.isNotEmpty) {
      return _currentCallId;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final fromPrefs = prefs.getString(_pendingCallUuidKey);
      if (fromPrefs != null && fromPrefs.isNotEmpty) return fromPrefs;
    } catch (_) {}
    return null;
  }

  /// Hides the Android incoming notification after the user **accepts** (we do
  /// not send [endCall] here — that is for decline/teardown).
  ///
  /// Does **not** clear SharedPreferences: the persisted CallKit UUID must stay
  /// until [endCurrentCall] runs when the conversation ends (local hang-up or
  /// remote `call-end`). Otherwise Android keeps a stale "incoming/upcoming"
  /// notification because [hideCallkitIncoming] cannot be matched to an id.
  Future<void> dismissIncomingCallNotification() async {
    final id = await _resolveActiveCallId();
    if (id != null && id.isNotEmpty) {
      await _hideIncomingTrayForId(id);
    }
    _currentCallId = null;
    _lastShowTime = null;
    _lastShownCallRecordId = null;
    _lastShownChannelName = null;
  }

  /// End/dismiss the current incoming call UI.
  Future<void> endCurrentCall() async {
    await dismissNativeIncoming();
    final id = await _resolveActiveCallId();
    if (id != null && id.isNotEmpty) {
      await _hideIncomingTrayForId(id);
      try {
        await FlutterCallkitIncoming.endCall(id);
      } catch (e) {
        AppLogger.w('📞 [CallKit] endCall failed: $e');
      }
    }
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {
      AppLogger.w('📞 [CallKit] endAllCalls failed: $e');
    }
    _currentCallId = null;
    _lastShowTime = null;
    _lastShownCallRecordId = null;
    _lastShownChannelName = null;
    await clearPendingIncomingCall();
  }

  /// End all calls (cleanup).
  Future<void> endAllCalls() async {
    await dismissNativeIncoming();
    try {
      final raw = await FlutterCallkitIncoming.activeCalls();
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            final cid = item['id']?.toString();
            if (cid != null && cid.isNotEmpty) {
              await _hideIncomingTrayForId(cid);
            }
          }
        }
      }
    } catch (e) {
      AppLogger.w('📞 [CallKit] activeCalls before endAllCalls: $e');
    }
    await FlutterCallkitIncoming.endAllCalls();
    _currentCallId = null;
    _lastShowTime = null;
    _lastShownCallRecordId = null;
    _lastShownChannelName = null;
    await clearPendingIncomingCall();
  }

  /// Clear Dart-side call tracking without touching native call UI.
  /// Useful when we receive terminal CallKit events and only need to reset
  /// local dedup/guard state.
  Future<void> clearLocalCallTracking() async {
    _currentCallId = null;
    _lastShowTime = null;
    _lastShownCallRecordId = null;
    _lastShownChannelName = null;
    await clearPendingIncomingCall();
  }

  /// Drops stale dedup guards when native UI shows no active call (fixes
  /// "no ring" after a crashed or stuck CallKit session).
  Future<void> recoverStaleIncomingCallGuards() async {
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      final hasActive =
          activeCalls is List && activeCalls.isNotEmpty;
      if (!hasActive) {
        await clearLocalCallTracking();
        AppLogger.i(
          '📞 [CallKit] Cleared stale incoming-call guards (no native call)',
        );
      }
    } catch (e) {
      AppLogger.w('📞 [CallKit] recoverStaleIncomingCallGuards failed: $e');
    }
  }

  /// Server says this exact call attempt is still ringing (fail-closed on error).
  static Future<bool> verifyIncomingCallActive({
    required String callerId,
    String? callRecordId,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final params = <String, dynamic>{'callerId': callerId};
        final expected = callRecordId?.trim() ?? '';
        if (expected.isNotEmpty) {
          params['callRecordId'] = expected;
        }
        final response = await ApiService.dio.get(
          '/call-history/check-active',
          queryParameters: params,
        );
        final active = response.data?['active'] == true;
        if (!active) {
          AppLogger.w(
            '📞 [CallKit] check-active inactive for $callerId '
            '(status=${response.data?['status']}) — skip ring',
          );
          return false;
        }
        return true;
      } catch (e) {
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        AppLogger.w(
          '📞 [CallKit] check-active failed for $callerId — skip ring: $e',
        );
        return false;
      }
    }
    return false;
  }

  /// Whether [callerId] has any ringing/in-progress row (ignore record id).
  static Future<bool> isCallerActiveOnServer(String callerId) async {
    try {
      final response = await ApiService.dio.get(
        '/call-history/check-active',
        queryParameters: {'callerId': callerId},
      );
      return response.data?['active'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Core-Telecom + plugin incoming UI (Android); no-op on other platforms.
  static Future<void> dismissNativeIncoming({
    String? callerId,
    String? callRecordId,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _nativeIncomingChannel.invokeMethod<void>('stopRinging', {
        if (callerId != null && callerId.isNotEmpty) 'callerId': callerId,
        if (callRecordId != null && callRecordId.isNotEmpty)
          'callRecordId': callRecordId,
      });
    } catch (e) {
      AppLogger.w('📞 [CallKit] dismissNativeIncoming failed: $e');
    }
  }

  static Future<void> _savePendingIncomingCall({
    required String callerId,
    required String callerName,
    required String callerRole,
    required String channelName,
    String? callRecordId,
    String? apiBaseUrl,
    String? callerGender,
    String? callerProfilePicture,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingCallerIdKey, callerId);
    await prefs.setString(_pendingCallerNameKey, callerName);
    await prefs.setString(_pendingCallerRoleKey, callerRole);
    final gender = callerGender?.trim() ?? '';
    if (gender.isNotEmpty) {
      await prefs.setString(_pendingCallerGenderKey, gender);
    } else {
      await prefs.remove(_pendingCallerGenderKey);
    }
    final profilePicture = callerProfilePicture?.trim() ?? '';
    if (profilePicture.isNotEmpty) {
      await prefs.setString(_pendingCallerProfilePictureKey, profilePicture);
    } else {
      await prefs.remove(_pendingCallerProfilePictureKey);
    }
    await prefs.setString(_pendingChannelNameKey, channelName);
    final resolvedApiBaseUrl = apiBaseUrl?.trim();
    if (resolvedApiBaseUrl != null && resolvedApiBaseUrl.isNotEmpty) {
      await prefs.setString(kNativeApiBaseUrlPrefsKey, resolvedApiBaseUrl);
    }
    if (callRecordId != null && callRecordId.isNotEmpty) {
      await prefs.setString(_pendingCallRecordIdKey, callRecordId);
    } else {
      await prefs.remove(_pendingCallRecordIdKey);
    }
    await prefs.setInt(
      _pendingCreatedAtMsKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    // Persist the CallKit UUID so a different background isolate can dismiss
    // this exact call (needed for call_cancel from killed state).
    final uuid = CallKitService.instance._currentCallId;
    if (uuid != null && uuid.isNotEmpty) {
      await prefs.setString(_pendingCallUuidKey, uuid);
    }
  }

  static Future<Map<String, String>?> readPendingIncomingCall() async {
    final prefs = await SharedPreferences.getInstance();
    final callerId = prefs.getString(_pendingCallerIdKey) ?? '';
    final callerName = prefs.getString(_pendingCallerNameKey) ?? '';
    final callerRole = prefs.getString(_pendingCallerRoleKey) ?? '';
    final channelName = prefs.getString(_pendingChannelNameKey) ?? '';

    if (callerId.isEmpty && channelName.isEmpty) return null;

    return {
      'callerId': callerId,
      'callerName': callerName,
      'callerRole': callerRole,
      'channelName': channelName,
      'callRecordId': prefs.getString(_pendingCallRecordIdKey) ?? '',
      'callerGender': prefs.getString(_pendingCallerGenderKey) ?? '',
      'callerProfilePicture':
          prefs.getString(_pendingCallerProfilePictureKey) ?? '',
      'createdAtMs': (prefs.getInt(_pendingCreatedAtMsKey) ?? 0).toString(),
    };
  }

  static Future<Map<String, String>?> readRecentPendingIncomingCall({
    int maxAgeSeconds = 90,
  }) async {
    final pending = await readPendingIncomingCall();
    if (pending == null) return null;

    final createdAtMs = int.tryParse(pending['createdAtMs'] ?? '0') ?? 0;
    if (createdAtMs <= 0) return pending;

    final ageMs = DateTime.now().millisecondsSinceEpoch - createdAtMs;
    if (ageMs > maxAgeSeconds * 1000) {
      await clearPendingIncomingCall();
      return null;
    }
    return pending;
  }

  static Future<void> clearPendingIncomingCall() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingCallerIdKey);
    await prefs.remove(_pendingCallerNameKey);
    await prefs.remove(_pendingCallerRoleKey);
    await prefs.remove(_pendingChannelNameKey);
    await prefs.remove(_pendingCreatedAtMsKey);
    await prefs.remove(_pendingCallUuidKey);
    await prefs.remove(_pendingCallRecordIdKey);
    await prefs.remove(_pendingCallerGenderKey);
    await prefs.remove(_pendingCallerProfilePictureKey);
  }

  static Future<bool> _isCancelForCurrentIncoming(String cancelRecordId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getString(_pendingCallRecordIdKey) ?? '';
      if (pending.isEmpty) return true;
      return pending == cancelRecordId;
    } catch (_) {
      return true;
    }
  }

  /// Process an FCM message and show incoming call if it's a call notification.
  /// Returns true if it was a call message and was handled.
  static Future<bool> handleFcmMessage(RemoteMessage message) async {
    final data = message.data;
    final controlType = fcmCallControlType(data);

    if (controlType == 'call_cancel') {
      final cancelRecordId = data['callRecordId']?.toString() ?? '';
      final callerId = data['callerId']?.toString() ?? '';
      if (cancelRecordId.isNotEmpty &&
          !await _isCancelForCurrentIncoming(cancelRecordId)) {
        if (callerId.isNotEmpty &&
            await isCallerActiveOnServer(callerId)) {
          AppLogger.w(
            '📞 Ignoring stale FCM call_cancel record=$cancelRecordId '
            '(caller still has newer active call)',
          );
          return true;
        }
        AppLogger.w(
          '📞 Stale FCM call_cancel record=$cancelRecordId — dismissing ghost ring',
        );
      }
      AppLogger.i('📞 FCM call_cancel — clearing native + Dart call state');
      await dismissNativeIncoming(
        callerId: callerId,
        callRecordId: cancelRecordId.isEmpty ? null : cancelRecordId,
      );
      try {
        await CallKitService.instance.endAllCalls();
      } catch (e) {
        AppLogger.e('📞 call_cancel endAllCalls failed: $e');
      }
      return true;
    }

    if (controlType == 'call_declined') {
      AppLogger.i('📞 FCM call_declined detected — stopping outgoing ring');
      await persistPendingOutgoingStop('declined');
      try {
        await CallKitService.instance.endCurrentCall();
      } catch (e) {
        AppLogger.e('📞 call_declined endCurrentCall failed: $e');
      }
      return true;
    }

    if (controlType == 'call_ended') {
      AppLogger.i('📞 FCM call_ended detected — stopping active call');
      await persistPendingOutgoingStop('ended');
      try {
        await CallKitService.instance.endCurrentCall();
      } catch (e) {
        AppLogger.e('📞 call_ended endCurrentCall failed: $e');
      }
      return true;
    }

    if (!isIncomingCallFcm(data)) return false;

    final callerId = data['callerId'] ?? '';
    final callerName = data['callerName'] ?? data['title'] ?? 'Unknown';
    final callerRole = data['callerRole'] ?? '';
    final channelName = data['channelName'] ?? '';
    final callRecordId = data['callRecordId']?.toString() ?? '';
    final displayName = data['displayName']?.toString() ??
        data['callerDisplayName']?.toString();
    final callerGender = data['callerGender']?.toString();
    final callerProfilePicture = data['callerProfilePicture']?.toString();

    AppLogger.i('📞 FCM incoming_call detected — showing native call screen');
    AppLogger.i('   Caller: $callerName ($callerId)');
    AppLogger.i('   Channel: $channelName');

    try {
      await CallKitService.instance.showIncomingCall(
        callerId: callerId,
        callerName: callerName,
        channelName: channelName,
        callerRole: callerRole,
        callRecordId: callRecordId.isNotEmpty ? callRecordId : null,
        displayName: displayName,
        callerGender: callerGender,
        callerProfilePicture: callerProfilePicture,
        // FCM IS the server's signal — skip the redundant check-active HTTP
        // call which fails in the background isolate (ApiService not init'd).
        skipServerVerify: true,
      );
    } catch (e, st) {
      AppLogger.e('📞 FCM incoming_call showIncomingCall failed: $e\n$st');
      return false;
    }

    return true;
  }
}

bool _isPilgrimCallerRole(String? role) {
  final normalized = role?.toLowerCase().trim() ?? '';
  return normalized == 'pilgrim';
}

/// Pilgrim callers: custom [profilePictureUrl] or gender default asset.
/// Pilgrim callees (moderator ring): Munawwara support icon.
String _resolveCallKitAvatar({
  required bool useSupportBranding,
  required bool isPilgrimCaller,
  required String? resolvedGender,
  required String? profilePictureUrl,
}) {
  if (useSupportBranding) {
    return kCallKitSupportAvatarAsset;
  }
  if (isPilgrimCaller) {
    final picture = profilePictureUrl?.trim();
    if (picture != null && picture.isNotEmpty) {
      return picture;
    }
    return PilgrimGenderAvatar.assetPathForGender(resolvedGender);
  }
  return PilgrimGenderAvatar.assetPathForGender(resolvedGender);
}
