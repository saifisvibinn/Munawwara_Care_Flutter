import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../utils/app_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CallKitService — Shows native incoming call screen (like WhatsApp)
// Uses Android ConnectionService / iOS CallKit under the hood.
// Works even when app is killed, screen off, or locked.
// ─────────────────────────────────────────────────────────────────────────────

class CallKitService {
  static final CallKitService instance = CallKitService._();
  CallKitService._();

  static const _uuid = Uuid();
  static const _pendingCallerIdKey = 'pending_call_caller_id';
  static const _pendingCallerNameKey = 'pending_call_caller_name';
  static const _pendingCallerRoleKey = 'pending_call_caller_role';
  static const _pendingChannelNameKey = 'pending_call_channel_name';
  static const _pendingCreatedAtMsKey = 'pending_call_created_at_ms';
  static const _pendingCallUuidKey = 'pending_call_uuid';

  // Track the current call UUID so we can end it later
  String? _currentCallId;
  String? get currentCallId => _currentCallId;

  /// Timestamp of the last showIncomingCall invocation — used to reject
  /// rapid duplicate invocations that slip past the _currentCallId guard.
  DateTime? _lastShowTime;

  /// Show a native incoming call screen.
  /// Call this from both foreground and background FCM handlers.
  Future<void> showIncomingCall({
    required String callerId,
    required String callerName,
    required String channelName,
    String? callerRole,
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

    // ── Guard 2: Timestamp-based dedup (5 s window) ─────────────────────
    final now = DateTime.now();
    if (_lastShowTime != null && now.difference(_lastShowTime!).inSeconds < 5) {
      AppLogger.w('📞 [CallKit] showIncomingCall called within 5 s — ignoring');
      return;
    }

    // ── Guard 3: Check actual system state for active calls ─────────────
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

    await _savePendingIncomingCall(
      callerId: callerId,
      callerName: callerName,
      callerRole: callerRole ?? '',
      channelName: channelName,
    );

    final params = CallKitParams(
      id: _currentCallId!,
      nameCaller: callerName,
      appName: 'Munawwara Care',
      handle: callerRole ?? 'Voice Call',
      type: 0, // 0 = audio call, 1 = video call
      duration: 30000, // Ring for 30 seconds max
      textAccept: 'Accept',
      textDecline: 'Decline',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: false,
        subtitle: 'Missed Call',
        callbackText: 'Call Back',
      ),
      extra: <String, dynamic>{
        'callerId': callerId,
        'callerName': callerName,
        'callerRole': callerRole ?? '',
        'channelName': channelName,
      },
      headers: <String, dynamic>{},
      android: const AndroidParams(
        isCustomNotification: false,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0D1B2A',
        actionColor: '#F97316', // AppColors.primary
        textColor: '#FFFFFF',
        isShowFullLockedScreen: true,
        incomingCallNotificationChannelName: 'Incoming Calls',
        isShowCallID: false,
      ),
      ios: const IOSParams(
        iconName: 'AppIcon',
        supportsVideo: false,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        ringtonePath: 'system_ringtone_default',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
    AppLogger.i('📞 Native incoming call screen shown for $callerName');
  }

  /// End/dismiss the current incoming call UI.
  Future<void> endCurrentCall() async {
    if (_currentCallId != null) {
      await FlutterCallkitIncoming.endCall(_currentCallId!);
    }
    // Also end ALL calls as belt-and-suspenders (catches stale calls)
    await FlutterCallkitIncoming.endAllCalls();
    _currentCallId = null;
    await clearPendingIncomingCall();
  }

  /// End all calls (cleanup).
  Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
    _currentCallId = null;
    await clearPendingIncomingCall();
  }

  /// Clear Dart-side call tracking without touching native call UI.
  /// Useful when we receive terminal CallKit events and only need to reset
  /// local dedup/guard state.
  Future<void> clearLocalCallTracking() async {
    _currentCallId = null;
    _lastShowTime = null;
    await clearPendingIncomingCall();
  }

  static Future<void> _savePendingIncomingCall({
    required String callerId,
    required String callerName,
    required String callerRole,
    required String channelName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingCallerIdKey, callerId);
    await prefs.setString(_pendingCallerNameKey, callerName);
    await prefs.setString(_pendingCallerRoleKey, callerRole);
    await prefs.setString(_pendingChannelNameKey, channelName);
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
  }

  /// Process an FCM message and show incoming call if it's a call notification.
  /// Returns true if it was a call message and was handled.
  static Future<bool> handleFcmMessage(RemoteMessage message) async {
    final data = message.data;
    final type = data['type'];

    if (type == 'call_cancel') {
      AppLogger.i('📞 FCM call_cancel detected — dismissing native call UI');
      // 1. Try ending by persisted UUID (most reliable cross-isolate approach)
      try {
        final prefs = await SharedPreferences.getInstance();
        final uuid = prefs.getString(_pendingCallUuidKey);
        if (uuid != null && uuid.isNotEmpty) {
          AppLogger.i('📞 Ending call by persisted UUID: $uuid');
          await FlutterCallkitIncoming.endCall(uuid);
        }
      } catch (e) {
        AppLogger.e('📞 endCall(uuid) failed: $e');
      }
      // 2. Belt-and-suspenders: also endAllCalls
      try {
        await FlutterCallkitIncoming.endAllCalls();
      } catch (e) {
        AppLogger.e('📞 endAllCalls() failed: $e');
      }
      // 3. Retry after short delay (Samsung OneUI sometimes needs this)
      try {
        await Future.delayed(const Duration(milliseconds: 500));
        await FlutterCallkitIncoming.endAllCalls();
      } catch (_) {}
      await clearPendingIncomingCall();
      return true;
    }

    if (type != 'incoming_call') return false;

    final callerId = data['callerId'] ?? '';
    final callerName = data['callerName'] ?? data['title'] ?? 'Unknown';
    final callerRole = data['callerRole'] ?? '';
    final channelName = data['channelName'] ?? '';

    AppLogger.i('📞 FCM incoming_call detected — showing native call screen');
    AppLogger.i('   Caller: $callerName ($callerId)');
    AppLogger.i('   Channel: $channelName');

    await CallKitService.instance.showIncomingCall(
      callerId: callerId,
      callerName: callerName,
      channelName: channelName,
      callerRole: callerRole,
    );

    return true;
  }
}
