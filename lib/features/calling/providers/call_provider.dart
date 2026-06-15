// Voice-call stack (Flutter side):
// • [NativeCallCoordinator] — CallKit events, cold-start pending accept, FCM
//   call_cancel / call_declined (foreground), navigation to [VoiceCallScreen].
// • [CallSignaling] — socket emits with reconnect queue + HTTP answer/decline.
// • [CallKitService] — native incoming UI + prefs for UUID / dismiss.
// • [CallNotifier] (this file) — Riverpod state + Agora join/leave lifecycle.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:proximity_screen_lock/proximity_screen_lock.dart';

import '../../auth/providers/auth_provider.dart';
import '../../moderator/services/sos_alert_coordinator.dart';
import '../../../core/router/app_router.dart';
import '../../../core/services/agora_rtc_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/caller_gender_cache.dart';
import '../../../core/services/callkit_audio_bridge.dart';
import '../../../core/services/callkit_service.dart';
import '../../../core/services/call_ringback_service.dart';
import '../../../core/services/secure_session_store.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/standard_snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../call_signaling.dart';
import '../call_navigation.dart';
import '../native_call_coordinator.dart';
import '../screens/voice_call_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Call State
// ─────────────────────────────────────────────────────────────────────────────

enum CallStatus { idle, calling, ringing, connecting, connected, ended }

class CallState {
  final CallStatus status;
  final String? remoteUserId;
  final String? remoteUserName;

  /// When non-null (pilgrim incoming), use for in-app ringing UI instead of [remoteUserName].
  final String? incomingDisplayName;

  /// Pilgrim SOS: parallel ring to all group moderators until one answers.
  final bool isGroupRingingOut;

  /// Pilgrim receiving a moderator call: show support name + app logo in-app (not peer personal name).
  final bool displayPeerAsSupportBranding;

  /// Moderator → pilgrim outbound: [PilgrimGenderAvatar] uses this (null = male default asset).
  final String? remotePeerGender;

  /// Custom pilgrim portrait when available (`profile_picture` from API).
  final String? remotePeerProfilePicture;
  final bool isMuted;
  final bool isSpeakerOn;
  final int durationSeconds;
  final String?
  endReason; // 'declined' | 'busy' | 'ended' | 'cancelled' | 'error'
  final int cooldownSeconds;

  const CallState({
    this.status = CallStatus.idle,
    this.remoteUserId,
    this.remoteUserName,
    this.incomingDisplayName,
    this.isGroupRingingOut = false,
    this.displayPeerAsSupportBranding = false,
    this.remotePeerGender,
    this.remotePeerProfilePicture,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.durationSeconds = 0,
    this.endReason,
    this.cooldownSeconds = 0,
  });

  bool get isInCall =>
      status == CallStatus.calling ||
      status == CallStatus.ringing ||
      status == CallStatus.connecting ||
      status == CallStatus.connected;

  String get formattedDuration {
    final m = durationSeconds ~/ 60;
    final s = durationSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  CallState copyWith({
    CallStatus? status,
    String? remoteUserId,
    String? remoteUserName,
    String? incomingDisplayName,
    bool? clearIncomingDisplayName,
    bool? isGroupRingingOut,
    bool? displayPeerAsSupportBranding,
    String? remotePeerGender,
    String? remotePeerProfilePicture,
    bool? isMuted,
    bool? isSpeakerOn,
    int? durationSeconds,
    String? endReason,
    int? cooldownSeconds,
  }) {
    return CallState(
      status: status ?? this.status,
      remoteUserId: remoteUserId ?? this.remoteUserId,
      remoteUserName: remoteUserName ?? this.remoteUserName,
      incomingDisplayName: clearIncomingDisplayName == true
          ? null
          : (incomingDisplayName ?? this.incomingDisplayName),
      isGroupRingingOut: isGroupRingingOut ?? this.isGroupRingingOut,
      displayPeerAsSupportBranding:
          displayPeerAsSupportBranding ?? this.displayPeerAsSupportBranding,
      remotePeerGender: remotePeerGender ?? this.remotePeerGender,
      remotePeerProfilePicture:
          remotePeerProfilePicture ?? this.remotePeerProfilePicture,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      endReason: endReason ?? this.endReason,
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Call Notifier – signaling + Agora media (join only after answer)
// ─────────────────────────────────────────────────────────────────────────────

class CallNotifier extends Notifier<CallState> {
  static const _outgoingReceiverIdKey = 'outgoing_call_receiver_id';
  static const _outgoingIsGroupKey = 'outgoing_call_is_group';

  String? _pendingChannelName;
  String? _pendingFromId;
  String? _outgoingChannelName;
  String? _activeIncomingCallRecordId;
  Future<void>? _outgoingCleanupInFlight;
  Timer? _callTimer;
  Timer? _ringPollTimer; // polls backend while outgoing call is ringing
  Timer? _sessionWatchdogTimer;
  Timer? _connectingTimeoutTimer;
  Timer? _iosCallKitRingPollTimer;
  bool _iosSawCallKitRing = false;
  int _iosEmptyActiveCallsStreak = 0;
  bool _declineSignalingInFlight = false;
  DateTime? _outgoingCallStartedAt;

  static const int _sessionWatchdogSeconds = 40;
  static const int _connectingTimeoutSeconds = 30;

  /// Resume reconcile must not tear down a call-offer still being registered.
  static const int _ghostReconcileOutgoingGraceSeconds = 20;

  /// Ignore stale CallKit/FCM teardown right after placing an outgoing call.
  static const int _outgoingCallKitGraceSeconds = 5;

  /// Ring poll must see server `active` once, or wait this long, before ending.
  static const int _ringPollInactiveGraceSeconds = 5;

  bool _ringPollSawServerActive = false;
  static const int _ghostReconcileActiveRetries = 3;
  static const Duration _ghostReconcileRetryDelay =
      Duration(milliseconds: 400);

  @override
  CallState build() {
    _wireAgoraHandlers();
    _registerSocketListeners();
    return const CallState();
  }

  void _wireAgoraHandlers() {
    final agora = AgoraRtcService.instance;
    agora.onRemoteUserJoined = (_) => _onRemoteUserJoinedMedia();
    agora.onRemoteUserOffline = (_, _) {
      if (state.status == CallStatus.connected) {
        endCall();
      }
    };
    agora.onMediaJoinFailed = (message) {
      AppLogger.e('[CallProvider] Agora media failed: $message');
      if (state.status == CallStatus.connecting ||
          state.status == CallStatus.calling) {
        unawaited(forceIdleCallSession(endReason: 'error'));
      }
    };
    agora.onConnectionFailed = () {
      if (state.status != CallStatus.connected &&
          state.status != CallStatus.connecting) {
        return;
      }
      final remoteId = state.remoteUserId;
      if (remoteId != null && remoteId.isNotEmpty) {
        CallSignaling.emitWhenConnected('call-end', {'to': remoteId});
      }
      unawaited(forceIdleCallSession(endReason: 'error'));
      final ctx = AppRouter.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        StandardSnackBar.showError(
          ctx,
          'Call connection lost. Please try again.',
        );
      }
    };
  }

  // ── Register socket listeners ─────────────────────────────────────────────
  void _registerSocketListeners() {
    AppLogger.d('[CallProvider] Registering socket listeners');
    SocketService.on('call-offer', _onIncomingOffer);
    SocketService.on('call-answer', _onAnswer);
    SocketService.on('call-declined', _onRemoteDecline);
    SocketService.on('call-end', _onRemoteEnd);
    SocketService.on('call-cancel', _onRemoteCancel);
    SocketService.on('call-busy', _onRemoteBusy);
  }

  /// Re-register after the socket reconnects (called from SocketService.connect).
  void reRegisterListeners() => _registerSocketListeners();

  // ════════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ════════════════════════════════════════════════════════════════════════════

  /// Pilgrim SOS: ring every moderator in [moderators] in parallel (server
  /// fans out); first answer wins. Uses one Agora [channelName].
  Future<void> startGroupModeratorCall(
    List<Map<String, String>> moderators,
  ) async {
    if (!await prepareForOutgoingCall()) return;
    final ids = moderators
        .map((m) => m['id'] ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;

    final supportLabel = 'call_support_display_name'.tr();

    state = CallState(
      status: CallStatus.calling,
      remoteUserId: ids.first,
      remoteUserName: supportLabel,
      isGroupRingingOut: true,
      displayPeerAsSupportBranding: true,
    );
    _outgoingCallStartedAt = DateTime.now();
    _syncPreConnectRingback(CallStatus.calling);
    unawaited(_persistOutgoingCall(remoteUserId: ids.first, isGroup: true));

    try {
      await [Permission.microphone].request();
      final channelName = 'call_${DateTime.now().millisecondsSinceEpoch}';
      _outgoingChannelName = channelName;
      AppLogger.i('[CallProvider] Group moderator ring on $channelName → $ids');
      CallSignaling.emitWhenConnected('call-offer-group', {
        'targets': ids,
        'channelName': channelName,
      });
      _startRingPoll(ids.first);
      _startSessionWatchdog();
    } catch (e) {
      await forceIdleCallSession(endReason: 'error');
    }
  }

  /// Moderator initiates an internet call to [remoteUserId].
  /// Pilgrim one-to-one ring (e.g. SOS auto-route): show support branding, not
  /// the moderator’s personal name or raw id in UI.
  Future<void> startCall({
    required String remoteUserId,
    required String remoteUserName,
    String? remotePeerGender,
    String? remotePeerProfilePicture,
  }) async {
    if (!await prepareForOutgoingCall()) return;
    final isPilgrimCaller =
        ref.read(authProvider).role?.toLowerCase() == 'pilgrim';
    final displayName = isPilgrimCaller
        ? 'call_support_display_name'.tr()
        : remoteUserName;
    state = CallState(
      status: CallStatus.calling,
      remoteUserId: remoteUserId,
      remoteUserName: displayName,
      isGroupRingingOut: false,
      displayPeerAsSupportBranding: isPilgrimCaller,
      remotePeerGender: isPilgrimCaller ? null : remotePeerGender,
      remotePeerProfilePicture:
          isPilgrimCaller ? null : remotePeerProfilePicture,
    );
    _outgoingCallStartedAt = DateTime.now();
    _syncPreConnectRingback(CallStatus.calling);
    unawaited(_persistOutgoingCall(remoteUserId: remoteUserId, isGroup: false));

    try {
      await [Permission.microphone].request();
      final channelName = 'call_${DateTime.now().millisecondsSinceEpoch}';
      _outgoingChannelName = channelName;
      AppLogger.i(
        '[CallProvider] → Placing call-offer to $remoteUserId on $channelName',
      );
      final placedResult = await CallSignaling.placeOutgoingOffer(
        remoteUserId: remoteUserId,
        channelName: channelName,
        preferHttpOnly: isPilgrimCaller,
      );
      if (placedResult == null) {
        AppLogger.e(
          '[CallProvider] call-offer failed (HTTP + socket unavailable)',
        );
        await forceIdleCallSession(endReason: 'error');
        return;
      }
      final callRecordId = (placedResult == 'socket' || placedResult == 'http_success')
          ? null
          : placedResult;
      if (!isPilgrimCaller) {
        unawaited(SosAlertCoordinator.afterModeratorPlacedCall(remoteUserId));
      }
      // Start polling so we detect decline even when the pilgrim's app is killed
      // and the HTTP decline from the background isolate fails for any reason.
      _startRingPoll(remoteUserId, callRecordId: callRecordId);
      _startSessionWatchdog();
    } catch (e) {
      await forceIdleCallSession(endReason: 'error');
    }
  }

  /// Stale native/FCM events from a prior incoming ring must not tear down a
  /// new SOS callback placed seconds ago.
  bool shouldIgnoreStaleCallKitTeardown() {
    if (state.status != CallStatus.calling) return false;
    final started = _outgoingCallStartedAt;
    if (started == null) return false;
    return DateTime.now().difference(started) <
        const Duration(seconds: _outgoingCallKitGraceSeconds);
  }

  /// Stale `call_declined` / `call_cancel` FCM from the previous leg.
  bool shouldIgnoreStaleCallControlFcm(String? dataType) {
    if (state.status != CallStatus.calling) return false;
    if (dataType == 'call_ended') return false;
    return shouldIgnoreStaleCallKitTeardown();
  }

  // ── Ring poll: moderator polls backend every 3 s while outgoing call rings ──
  void _startRingPoll(String remoteUserId, {String? callRecordId}) {
    _stopRingPoll();
    _ringPollSawServerActive = false;
    // Capture the caller's own user ID from SharedPreferences for the query.
    // The endpoint expects callerId = the person WHO INITIATED the call.
    _ringPollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      // Stop polling if call is no longer in the "calling" state.
      if (state.status != CallStatus.calling) {
        _stopRingPoll();
        return;
      }
      try {
        final myId = await _getMyUserId();
        if (myId == null) return;
        final resp = await ApiService.dio.get(
          '/call-history/check-active',
          queryParameters: {
            'callerId': myId,
            if (callRecordId != null && callRecordId.isNotEmpty) 'callRecordId': callRecordId,
          },
        );
        final active = resp.data['active'] as bool? ?? false;
        final status = resp.data['status']?.toString() ?? 'none';
        AppLogger.d('[RingPoll] active=$active status=$status myId=$myId');
        if (active) {
          _ringPollSawServerActive = true;
          return;
        }
        final started = _outgoingCallStartedAt;
        final withinGrace = started != null &&
            DateTime.now().difference(started) <
                const Duration(seconds: _ringPollInactiveGraceSeconds);
        if (!_ringPollSawServerActive && withinGrace) {
          AppLogger.d(
            '[RingPoll] Server inactive during grace — waiting for call row',
          );
          return;
        }
        // If the call is no longer ringing/in-progress on the backend, treat it
        // as declined (covers killed-app decline + timeout).
        if (!active && state.status == CallStatus.calling) {
          AppLogger.w(
            '[RingPoll] Call no longer active ($status) — stopping ring',
          );
          final isMod = ref.read(authProvider).role?.toLowerCase() != 'pilgrim';
          if (isMod) {
            unawaited(
              SosAlertCoordinator.afterModeratorEndedCall(remoteUserId),
            );
          }
          await forceIdleCallSession(
            endReason: status == 'none' ? 'declined' : status,
          );
        }
      } catch (e) {
        AppLogger.e('[RingPoll] Error: $e');
      }
    });
  }

  void _stopRingPoll() {
    _ringPollTimer?.cancel();
    _ringPollTimer = null;
  }

  void _syncPreConnectRingback(CallStatus status) {
    if (status == CallStatus.calling) {
      unawaited(CallRingbackService.start());
      return;
    }
    unawaited(CallRingbackService.stop());
  }

  Future<String?> _getMyUserId() async {
    try {
      return await SecureSessionStore.getUserId();
    } catch (_) {
      return null;
    }
  }

  Timer? _cooldownTimer;

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    state = state.copyWith(cooldownSeconds: seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.cooldownSeconds > 0) {
        state = state.copyWith(cooldownSeconds: state.cooldownSeconds - 1);
      } else {
        timer.cancel();
      }
    });
  }

  void _scheduleReset({int delaySeconds = 3}) {
    Future.delayed(Duration(seconds: delaySeconds), () {
      if (state.status == CallStatus.ended) {
        state = CallState(cooldownSeconds: state.cooldownSeconds);
      }
    });
  }

  void _cleanup() {
    _callTimer?.cancel();
    _callTimer = null;
    _stopIosCallKitRingPoll();
    _syncPreConnectRingback(CallStatus.ended);
    _pendingChannelName = null;
    _pendingFromId = null;
    _outgoingChannelName = null;
    _outgoingCallStartedAt = null;
    _activeIncomingCallRecordId = null;
    CallSignaling.clearPendingOutgoingEmits();
    CallKitAudioBridge.reset();
    unawaited(_clearOutgoingCallPersistence());
    // Deactivate proximity sensor so the screen behaves normally after the call.
    ProximityScreenLock.setActive(false).catchError(
      (e) => AppLogger.w('📞 Failed to deactivate proximity lock: $e'),
    );
  }

  Future<void> _leaveMediaAndNativeTeardown({required bool awaitCompletion}) async {
    final leaveFuture = AgoraRtcService.instance.leaveChannel();
    final teardownFuture = _tearDownCallKitInBackground();
    if (awaitCompletion) {
      await leaveFuture;
      await teardownFuture;
      await CallKitService.resetCallAudio();
    } else {
      unawaited(leaveFuture);
      unawaited(teardownFuture);
    }
  }

  /// Idempotent teardown — use for cancel, decline, timeout, and watchdog.
  ///
  /// Updates Riverpod to [CallStatus.ended] immediately so the in-app UI
  /// responds on tap; native CallKit cleanup runs in the background.
  Future<void> forceIdleCallSession({
    required String endReason,
    bool goIdleImmediately = false,
    int scheduleResetDelaySeconds = 3,
    bool awaitTeardown = false,
  }) async {
    _stopRingPoll();
    _stopSessionWatchdog();
    _stopConnectingTimeout();
    _cleanup();
    state = state.copyWith(
      status: CallStatus.ended,
      endReason: endReason,
      isGroupRingingOut: false,
    );

    // Always enforce a 10s cooldown after a call ends
    _startCooldown(10);

    if (goIdleImmediately) {
      state = CallState(cooldownSeconds: state.cooldownSeconds);
    } else {
      _scheduleReset(delaySeconds: scheduleResetDelaySeconds);
    }

    await _leaveMediaAndNativeTeardown(awaitCompletion: awaitTeardown);
  }

  Future<void> _tearDownCallKitInBackground() async {
    try {
      await CallKitService.instance.endAllCalls();
    } catch (e) {
      AppLogger.w('[CallProvider] forceIdle endAllCalls failed: $e');
    }
  }

  Future<bool> _isCallActiveOnServer(String callerId) async {
    final id = callerId.trim();
    if (id.isEmpty) return false;
    try {
      final resp = await ApiService.dio.get(
        '/call-history/check-active',
        queryParameters: {'callerId': id},
      );
      return resp.data?['active'] == true;
    } catch (e) {
      AppLogger.w('[CallProvider] check-active failed: $e');
      return true;
    }
  }

  /// Before placing a call: reset local state and clear stale server ringing.
  Future<bool> prepareForOutgoingCall() async {
    if (_outgoingCleanupInFlight != null) {
      await _outgoingCleanupInFlight;
    }

    clearQueuedNativeDecline();
    await CallKitService.consumePendingOutgoingStop();
    try {
      await CallKitService.instance.endAllCalls();
      await CallKitService.instance.clearLocalCallTracking();
    } catch (e) {
      AppLogger.w('[CallProvider] prepareForOutgoing CallKit cleanup: $e');
    }

    CallSignaling.clearPendingOutgoingEmits();

    if (state.isInCall) {
      await forceIdleCallSession(
        endReason: 'cancelled',
        goIdleImmediately: true,
      );
    }

    final myId = await _getMyUserId() ?? '';
    if (myId.isNotEmpty && await _isCallActiveOnServer(myId)) {
      AppLogger.w(
        '[CallProvider] Stale server ring for caller — cancel-all before new call',
      );
      await CallSignaling.notifyCancelHttp(myId);
      await _waitForServerCallInactive(myId);
    }

    return ensureReadyForNewCall();
  }

  Future<void> _waitForServerCallInactive(String callerId) async {
    for (var i = 0; i < 16; i++) {
      if (!await _isCallActiveOnServer(callerId)) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    AppLogger.w(
      '[CallProvider] Server still shows active after cancel — placing call anyway',
    );
  }

  /// Clears ghost [isInCall] when server says the session ended.
  Future<bool> ensureReadyForNewCall() async {
    if (!state.isInCall) return true;

    final myId = await _getMyUserId() ?? '';
    final checkCallerId = state.status == CallStatus.calling
        ? myId
        : (state.remoteUserId ?? _pendingFromId ?? '');

    if (checkCallerId.isEmpty) {
      AppLogger.w('[CallProvider] Ghost in-call with no caller id — forceIdle');
      await forceIdleCallSession(
        endReason: 'cancelled',
        goIdleImmediately: true,
      );
      return true;
    }

    final active = await _isCallActiveOnServer(checkCallerId);
    if (!active) {
      AppLogger.w(
        '[CallProvider] Ghost in-call (server inactive) — forceIdle before new call',
      );
      await forceIdleCallSession(
        endReason: 'cancelled',
        goIdleImmediately: true,
      );
      return true;
    }

    if (state.status == CallStatus.calling && myId.isNotEmpty) {
      await CallSignaling.notifyCancelHttp(myId);
      await _waitForServerCallInactive(myId);
      if (!await _isCallActiveOnServer(myId)) {
        await forceIdleCallSession(
          endReason: 'cancelled',
          goIdleImmediately: true,
        );
        return true;
      }
    }

    AppLogger.w(
      '[CallProvider] Blocked new call — session still active on server',
    );
    return false;
  }

  void _startSessionWatchdog() {
    _stopSessionWatchdog();
    _sessionWatchdogTimer = Timer(
      const Duration(seconds: _sessionWatchdogSeconds),
      () => unawaited(_onSessionWatchdogTick()),
    );
  }

  void _stopSessionWatchdog() {
    _sessionWatchdogTimer?.cancel();
    _sessionWatchdogTimer = null;
  }

  Future<void> _onSessionWatchdogTick() async {
    if (state.status != CallStatus.calling &&
        state.status != CallStatus.ringing) {
      return;
    }

    final myId = await _getMyUserId() ?? '';
    final checkCallerId = state.status == CallStatus.calling
        ? myId
        : (state.remoteUserId ?? _pendingFromId ?? '');

    if (checkCallerId.isEmpty) {
      await forceIdleCallSession(endReason: 'cancelled');
      return;
    }

    final active = await _isCallActiveOnServer(checkCallerId);
    if (active) return;

    final reason = state.status == CallStatus.calling
        ? 'declined'
        : 'cancelled';
    AppLogger.w('[SessionWatchdog] Server inactive — forceIdle ($reason)');
    await forceIdleCallSession(endReason: reason);
  }

  /// Accept an incoming call (status must be [CallStatus.ringing]).
  Future<void> acceptCall() async {
    if (state.status != CallStatus.ringing || _pendingChannelName == null) {
      return;
    }

    final fromId = _pendingFromId;
    final channelName = _pendingChannelName!;

    if (fromId != null && fromId.isNotEmpty) {
      CallSignaling.emitWhenConnected('call-answer', {'to': fromId});
      try {
        await CallSignaling.notifyAnswerHttp(
          fromId,
          SocketService.connectedUserId,
        );
      } catch (e) {
        AppLogger.w(
          '[CallProvider] HTTP call-answer failed (socket may still deliver): $e',
        );
      }
      NativeCallCoordinator.clearPendingAcceptFileAfterAnswer();
      AppLogger.i(
        '[CallProvider] call-answer signaled before permission request',
      );
    } else {
      AppLogger.e(
        '[CallProvider] Cannot signal call-answer: missing caller id (fromId=$fromId)',
      );
    }

    _stopSessionWatchdog();
    state = state.copyWith(
      status: CallStatus.connecting,
      durationSeconds: 0,
      clearIncomingDisplayName: true,
    );
    _syncPreConnectRingback(CallStatus.connecting);
    _startConnectingTimeout();

    try {
      await [Permission.microphone].request();
      await CallKitAudioBridge.ensureReadyBeforeMediaJoin();
      AppLogger.i('[CallProvider] Joining Agora on accept: $channelName');
      await _joinMediaChannel(channelName);
      _pendingChannelName = null;
      _pendingFromId = null;
      // Android: mark call connected so native prefs use isAccepted=true; otherwise
      // endCall() routes to DECLINE and never stops CallkitNotificationService FGS.
      final callKitId = await CallKitService.instance
          .peekCallKitNotificationId();
      if (callKitId != null && callKitId.isNotEmpty) {
        try {
          await FlutterCallkitIncoming.setCallConnected(callKitId);
        } catch (e) {
          AppLogger.w('[CallProvider] setCallConnected failed: $e');
        }
      }
      await CallKitService.instance.dismissIncomingCallNotification();
    } catch (e, st) {
      AppLogger.e('[CallProvider] acceptCall failed: $e', e, st);
      unawaited(forceIdleCallSession(endReason: 'error'));
    }
  }

  /// Synchronous peer id for hang-up UI — avoids disk reads on the hot path.
  String? _peekRemotePeerId() {
    final fromState = state.remoteUserId;
    if (fromState != null && fromState.isNotEmpty) return fromState;
    final pending = _pendingFromId;
    if (pending != null && pending.isNotEmpty) return pending;
    return null;
  }

  /// Decline an incoming call.
  void declineCall() {
    unawaited(_declineCallInternal(noAnswer: false));
  }

  /// Incoming ring timed out (CallKit) — server records **missed**, not declined.
  void declineCallAsNoAnswer() {
    unawaited(_declineCallInternal(noAnswer: true));
  }

  Future<void> _declineCallInternal({required bool noAnswer}) async {
    if (_declineSignalingInFlight) return;
    _declineSignalingInFlight = true;
    try {
      final remoteId = _peekRemotePeerId();
      final recordId = _activeIncomingCallRecordId;
      await _emitDeclineSignaling(
        remoteId: remoteId,
        callRecordId: recordId,
        noAnswer: noAnswer,
      );
      await forceIdleCallSession(
        endReason: noAnswer ? 'missed' : 'declined',
        awaitTeardown: true,
      );
    } finally {
      _declineSignalingInFlight = false;
    }
  }

  Future<void> _emitDeclineSignaling({
    required String? remoteId,
    String? callRecordId,
    required bool noAnswer,
  }) async {
    var peerId = remoteId;
    if (peerId == null || peerId.isEmpty) {
      peerId = await _readPersistedOutgoingReceiverId();
    }
    if (peerId == null || peerId.isEmpty) {
      AppLogger.e('[CallProvider] decline signaling skipped — no peer id');
      return;
    }
    CallSignaling.emitWhenConnected('call-declined', {
      'to': peerId,
      if (noAnswer) 'noAnswer': true,
    });
    try {
      await CallSignaling.notifyDeclineHttp(
        peerId,
        SocketService.connectedUserId,
        callRecordId: callRecordId,
        noAnswer: noAnswer,
      );
    } catch (e) {
      AppLogger.e('[CallProvider] HTTP call-decline failed: $e');
    }
  }

  /// Decline a call when we only have the caller id (killed-state fallback).
  /// [noAnswer] — native ring timeout / no pickup (counts as missed, not declined).
  void declineCallFromCallerId(String callerId, {bool noAnswer = false}) {
    unawaited(_declineFromCallerId(callerId, noAnswer: noAnswer));
  }

  Future<void> _declineFromCallerId(
    String callerId, {
    bool noAnswer = false,
  }) async {
    if (_declineSignalingInFlight) return;
    _declineSignalingInFlight = true;
    try {
      if (callerId.isNotEmpty) {
        CallSignaling.emitWhenConnected('call-declined', {
          'to': callerId,
          if (noAnswer) 'noAnswer': true,
        });
        try {
          await CallSignaling.notifyDeclineHttp(
            callerId,
            SocketService.connectedUserId,
            callRecordId: _activeIncomingCallRecordId,
            noAnswer: noAnswer,
          );
        } catch (e) {
          AppLogger.e('[CallProvider] HTTP call-decline (callerId) failed: $e');
        }
      }
      await forceIdleCallSession(
        endReason: noAnswer ? 'missed' : 'declined',
        awaitTeardown: true,
      );
    } finally {
      _declineSignalingInFlight = false;
    }
  }

  /// End an in-progress call.
  void endCall() {
    unawaited(_endCallInternal());
  }

  Future<void> _endCallInternal() async {
    _stopRingPoll();
    final remoteId = _peekRemotePeerId();
    final isMod = ref.read(authProvider).role?.toLowerCase() != 'pilgrim';
    final wasActive =
        state.status == CallStatus.connected ||
        state.status == CallStatus.connecting;
    await forceIdleCallSession(endReason: 'ended', awaitTeardown: true);
    unawaited(
      _emitCallEndSignaling(
        remoteId: remoteId,
        isMod: isMod,
        wasActive: wasActive,
      ),
    );
  }

  Future<void> _emitCallEndSignaling({
    required String? remoteId,
    required bool isMod,
    required bool wasActive,
  }) async {
    var peerId = remoteId;
    if (peerId == null || peerId.isEmpty) {
      peerId = await _readPersistedOutgoingReceiverId();
    }
    if (peerId != null && peerId.isNotEmpty) {
      CallSignaling.emitWhenConnected('call-end', {'to': peerId});
    }
    if (isMod && wasActive && peerId != null && peerId.isNotEmpty) {
      unawaited(SosAlertCoordinator.afterModeratorEndedCall(peerId));
    }
  }

  /// Caller cancelled while still ringing — notify callee only via `call-cancel`.
  /// Never emit `call-end` here: the server treats `call-end` during `ringing`
  /// as a missed call and mis-notifies the recipient.
  Future<void> cancelOutgoingRing() async {
    final started = _outgoingCallStartedAt;
    if (started != null) {
      final elapsed = DateTime.now().difference(started);
      if (elapsed < const Duration(seconds: 3)) {
        AppLogger.i(
          '[CallProvider] cancelOutgoingRing ignored — less than 3s elapsed '
          '(${elapsed.inMilliseconds}ms)',
        );
        return;
      }
    }

    AppLogger.i(
      '[CallProvider] cancelOutgoingRing '
      'remote=${state.remoteUserId} group=${state.isGroupRingingOut}',
    );
    _stopRingPoll();
    final snapshot = state;
    final cleanup = _runOutgoingCleanup(snapshot);
    _outgoingCleanupInFlight = cleanup;
    try {
      await cleanup;
    } finally {
      if (identical(_outgoingCleanupInFlight, cleanup)) {
        _outgoingCleanupInFlight = null;
      }
    }
  }

  Future<void> _runOutgoingCleanup(CallState snapshot) async {
    await _signalOutgoingCancel(
      isGroup: snapshot.isGroupRingingOut,
      remoteId: snapshot.remoteUserId,
    );
    final remoteId = snapshot.remoteUserId;
    final isMod = ref.read(authProvider).role?.toLowerCase() != 'pilgrim';
    if (isMod && remoteId != null && remoteId.isNotEmpty) {
      unawaited(SosAlertCoordinator.afterModeratorEndedCall(remoteId));
    }
    await forceIdleCallSession(endReason: 'cancelled', goIdleImmediately: true);
  }

  /// Dismiss local ringing UI after the peer or server already signalled
  /// (FCM `call_cancel` / `call_declined`). Does not emit `call-end`.
  void stopLocalCallSession({required String endReason}) {
    unawaited(forceIdleCallSession(endReason: endReason));
  }

  /// Accept a call that arrived via FCM (background/terminated state).
  /// Called when the user taps "Accept" on the native call screen and the
  /// app was not running (so no socket call-offer was received).
  Future<void> acceptCallFromFcm({
    required String callerId,
    required String callerName,
    required String channelName,
  }) async {
    if (state.isInCall) return;

    final role = await SecureSessionStore.getRole();
    final isPilgrimCallee = role == 'pilgrim';
    final calleeDisplayName = isPilgrimCallee
        ? 'call_support_display_name'.tr()
        : callerName;

    AppLogger.i(
      '[CallProvider] Accepting FCM call from $callerName on $channelName',
    );

    // ── Verify call is still active on server before joining ──────────
    // If the caller cancelled while we were waking up from killed state,
    // joining the Agora channel is pointless. This is the safety net that
    // WhatsApp / Telegram use: always ask the server before connecting.
    final pending = await CallKitService.readPendingIncomingCall();
    final pendingRecordId = pending?['callRecordId'];
    final pendingGender = pending?['callerGender']?.trim();
    final pendingProfilePicture =
        pending?['callerProfilePicture']?.trim();
    final allowed = await CallKitService.verifyIncomingCallActive(
      callerId: callerId,
      callRecordId: pendingRecordId,
    );
    if (!allowed) {
      AppLogger.w(
        '[CallProvider] Call from $callerName is no longer active on server',
      );
      state = CallState(
        remoteUserId: callerId,
        remoteUserName: calleeDisplayName,
        displayPeerAsSupportBranding: isPilgrimCallee,
      );
      await forceIdleCallSession(endReason: 'cancelled');
      return;
    }

    _pendingChannelName = channelName;
    _pendingFromId = callerId;

    state = CallState(
      status: CallStatus.ringing,
      remoteUserId: callerId,
      remoteUserName: calleeDisplayName,
      incomingDisplayName: isPilgrimCallee ? calleeDisplayName : null,
      displayPeerAsSupportBranding: isPilgrimCallee,
      remotePeerGender:
          isPilgrimCallee ||
              pendingGender == null ||
              pendingGender.isEmpty
          ? null
          : pendingGender,
      remotePeerProfilePicture:
          isPilgrimCallee ||
              pendingProfilePicture == null ||
              pendingProfilePicture.isEmpty
          ? null
          : pendingProfilePicture,
    );
    _startSessionWatchdog();

    await acceptCall();
  }

  /// Check for calls accepted from the native call screen while app was
  /// in background. Call this on dashboard init.
  Future<void> checkPendingAcceptedCall() async {
    final pending = consumePendingAcceptedCall();
    if (pending != null && pending['channelName']?.isNotEmpty == true) {
      AppLogger.i('[CallProvider] Found pending accepted call: $pending');
      await acceptCallFromFcm(
        callerId: pending['callerId'] ?? '',
        callerName: pending['callerName'] ?? 'Unknown',
        channelName: pending['channelName'] ?? '',
      );
      // Navigate to VoiceCallScreen (the main.dart handler might already
      // be retrying, but if it gave up this is the reliable fallback).
      if (!isNavigatingToCall && !VoiceCallScreen.isActive) {
        Future.delayed(const Duration(milliseconds: 200), () {
          openVoiceCallScreen();
        });
      }
    }
  }

  Future<void> checkPendingDeclinedCall() async {
    final pending = consumePendingDeclined();
    if (pending == null || pending.callerId.isEmpty) return;
    if (state.isInCall) {
      AppLogger.w(
        '[CallProvider] Dropping queued native decline while in-call '
        '(caller=${pending.callerId})',
      );
      return;
    }
    AppLogger.i(
      '[CallProvider] Found pending declined call for caller=${pending.callerId} '
      'noAnswer=${pending.noAnswer}',
    );
    declineCallFromCallerId(pending.callerId, noAnswer: pending.noAnswer);
  }

  /// Reconcile native / persisted call state after the process was killed.
  Future<void> reconcileCallStateAfterProcessDeath() async {
    await _reconcilePendingOutgoingStopFromFcm();
    await _reconcilePendingIncomingCall();
    await _reconcileStaleOutgoingPersistence();
    await _reconcileGhostInCallState();
  }

  Future<void> _reconcileGhostInCallState() async {
    if (state.status == CallStatus.calling) {
      // Outgoing ring is owned by [_startRingPoll]. App resume / focus churn
      // can run reconcile before check-active sees the new call-offer row.
      final started = _outgoingCallStartedAt;
      if (started != null &&
          DateTime.now().difference(started) <
              const Duration(seconds: _ghostReconcileOutgoingGraceSeconds)) {
        AppLogger.d(
          '[CallProvider] Skip ghost reconcile — outgoing grace window',
        );
      }
      return;
    }
    if (state.status != CallStatus.ringing) {
      return;
    }
    final checkCallerId =
        state.remoteUserId ?? _pendingFromId ?? '';
    if (checkCallerId.isEmpty) {
      await forceIdleCallSession(
        endReason: 'cancelled',
        goIdleImmediately: true,
      );
      return;
    }
    var active = false;
    for (var i = 0; i < _ghostReconcileActiveRetries; i++) {
      active = await _isCallActiveOnServer(checkCallerId);
      if (active) break;
      if (i < _ghostReconcileActiveRetries - 1) {
        await Future<void>.delayed(_ghostReconcileRetryDelay);
      }
    }
    if (!active) {
      AppLogger.w(
        '[CallProvider] Resume reconcile — ghost ${state.status}, forceIdle',
      );
      await forceIdleCallSession(
        endReason: 'cancelled',
        goIdleImmediately: true,
      );
    }
  }

  Future<void> _reconcilePendingOutgoingStopFromFcm() async {
    final reason = await CallKitService.consumePendingOutgoingStop();
    if (reason == null) return;
    if (state.status == CallStatus.calling ||
        state.status == CallStatus.ringing) {
      stopLocalCallSession(endReason: reason);
    }
  }

  void toggleMute() {
    final muted = !state.isMuted;
    state = state.copyWith(isMuted: muted);
    unawaited(AgoraRtcService.instance.setMuted(muted));
  }

  Future<void> toggleSpeaker() async {
    final on = !state.isSpeakerOn;
    state = state.copyWith(isSpeakerOn: on);
    await AgoraRtcService.instance.setSpeakerOn(on);
  }

  /// Public wrapper to handle incoming answered events from the FCM fallback path.
  void handleFcmCallAnswered({String? answererId, String? callRecordId}) {
    AppLogger.i('[CallProvider] handleFcmCallAnswered: answerer=$answererId record=$callRecordId');
    _onAnswer({'from': answererId});
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SOCKET HANDLERS (private)
  // ════════════════════════════════════════════════════════════════════════════

  void _onIncomingOffer(dynamic data) {
    final Map<String, dynamic> payload = (data is List)
        ? Map<String, dynamic>.from(data.first as Map? ?? {})
        : Map<String, dynamic>.from(data as Map? ?? {});
    unawaited(_handleIncomingOffer(payload));
  }

  Future<void> _handleIncomingOffer(Map<String, dynamic> payload) async {
    AppLogger.d('[CallProvider] ← call-offer received: $payload');

    if (state.isInCall) {
      AppLogger.w(
        '[CallProvider] Already in call (status=${state.status}) – sending busy',
      );
      final busyTo = payload['from']?.toString();
      if (busyTo != null && busyTo.isNotEmpty) {
        CallSignaling.emitWhenConnected('call-busy', {'to': busyTo});
      }
      return;
    }

    final channelName = payload['channelName'] as String?;
    if (channelName == null) {
      AppLogger.w('[CallProvider] ✗ call-offer missing channelName, ignored');
      return;
    }

    // Duplicate guard: if we already have this exact channel pending, skip.
    if (_pendingChannelName == channelName &&
        state.status == CallStatus.ringing) {
      AppLogger.d(
        '[CallProvider] ✗ duplicate call-offer for same channel, ignored',
      );
      return;
    }

    _pendingChannelName = channelName;
    _pendingFromId = payload['from'] as String?;
    final recordId = payload['callRecordId']?.toString();
    if (recordId != null && recordId.isNotEmpty) {
      _activeIncomingCallRecordId = recordId;
    }

    final callerInfo = payload['callerInfo'] as Map?;
    final callerName = callerInfo?['name'] as String? ?? 'Unknown';
    final callerRole = callerInfo?['role'] as String?;
    final callerProfilePicture =
        callerInfo?['profile_picture']?.toString() ??
        callerInfo?['profilePicture']?.toString();
    var callerGender = CallerGenderCache.normalize(
      callerInfo?['gender']?.toString(),
    );
    final callerIdForGender = payload['from']?.toString() ?? '';
    if (callerGender == null && callerIdForGender.isNotEmpty) {
      callerGender = await CallerGenderCache.resolve(callerIdForGender);
    }
    final isPilgrim = ref.read(authProvider).role == 'pilgrim';
    final String inAppDisplayName;
    final String? supportLabel;
    if (isPilgrim) {
      supportLabel = 'call_support_display_name'.tr();
      inAppDisplayName = supportLabel;
    } else {
      supportLabel = null;
      inAppDisplayName = callerName;
    }

    final callerId = _pendingFromId ?? '';

    AppLogger.i(
      '[CallProvider] ✓ Incoming call from $callerName ($callerId) on $channelName',
    );

    await CallKitService.instance.showIncomingCall(
      callerId: callerId,
      callerName: callerName,
      channelName: channelName,
      callerRole: callerRole,
      callRecordId: recordId,
      callerGender: callerGender,
      callerProfilePicture: callerProfilePicture,
      // Socket call-offer is authoritative; avoid fail-closed check-active race.
      skipServerVerify: true,
    );

    state = CallState(
      status: CallStatus.ringing,
      remoteUserId: _pendingFromId,
      remoteUserName: inAppDisplayName,
      incomingDisplayName: supportLabel,
      displayPeerAsSupportBranding: isPilgrim,
      remotePeerGender: isPilgrim ? null : callerGender,
      remotePeerProfilePicture: isPilgrim ? null : callerProfilePicture,
    );
    _startSessionWatchdog();
    if (Platform.isIOS) {
      _startIosCallKitRingPoll();
    }
  }

  /// iOS CallKit sometimes misses [Event.actionCallAccept] / [Event.actionCallDecline]
  /// on the Flutter event channel (implicit engine race).
  void _startIosCallKitRingPoll() {
    _iosCallKitRingPollTimer?.cancel();
    _iosSawCallKitRing = false;
    _iosEmptyActiveCallsStreak = 0;
    var ticks = 0;
    _iosCallKitRingPollTimer = Timer.periodic(
      const Duration(milliseconds: 400),
      (timer) async {
        if (state.status != CallStatus.ringing) {
          timer.cancel();
          _iosCallKitRingPollTimer = null;
          return;
        }
        ticks++;
        if (ticks > 120) {
          timer.cancel();
          _iosCallKitRingPollTimer = null;
          return;
        }
        try {
          final raw = await FlutterCallkitIncoming.activeCalls();
          if (raw is! List) return;

          if (raw.isEmpty) {
            // Only treat as decline after CallKit had an active entry, then
            // cleared it for several consecutive polls (avoids false decline
            // while activeCalls is still populating right after showIncoming).
            if (_iosSawCallKitRing) {
              _iosEmptyActiveCallsStreak++;
              if (_iosEmptyActiveCallsStreak >= 3) {
                timer.cancel();
                _iosCallKitRingPollTimer = null;
                AppLogger.i(
                  '[CallProvider] iOS native decline detected '
                  '(activeCalls cleared)',
                );
                declineCall();
              }
            }
            return;
          }

          _iosSawCallKitRing = true;
          _iosEmptyActiveCallsStreak = 0;
          for (final item in raw) {
            if (item is! Map) continue;
            final accepted =
                item['isAccepted'] == true || item['accepted'] == true;
            if (!accepted) continue;
            timer.cancel();
            _iosCallKitRingPollTimer = null;
            AppLogger.i(
              '[CallProvider] iOS native accept detected (activeCalls poll)',
            );
            await acceptCall();
            if (!VoiceCallScreen.isActive && !isNavigatingToCall) {
              openVoiceCallScreen(bypassNavigatingGuard: true);
            }
            return;
          }
        } catch (e) {
          AppLogger.w('[CallProvider] iOS CallKit ring poll failed: $e');
        }
      },
    );
  }

  void _stopIosCallKitRingPoll() {
    _iosCallKitRingPollTimer?.cancel();
    _iosCallKitRingPollTimer = null;
    _iosSawCallKitRing = false;
    _iosEmptyActiveCallsStreak = 0;
  }

  void _onAnswer(dynamic data) {
    _stopRingPoll();
    _stopSessionWatchdog();
    if (state.status == CallStatus.connected && _callTimer != null) {
      return;
    }
    if (state.status == CallStatus.connecting) {
      return;
    }
    Map<String, dynamic>? map;
    if (data is Map) {
      map = Map<String, dynamic>.from(data);
    }
    final answererId = map?['from']?.toString();
    if (state.status != CallStatus.calling) {
      return;
    }
    state = state.copyWith(
      status: CallStatus.connecting,
      isGroupRingingOut: false,
      remoteUserId: (answererId != null && answererId.isNotEmpty)
          ? answererId
          : state.remoteUserId,
    );
    _syncPreConnectRingback(CallStatus.connecting);
    _startConnectingTimeout();
    unawaited(_joinMediaAsCaller());
  }

  Future<void> _joinMediaAsCaller() async {
    final channel = _outgoingChannelName;
    if (channel == null || channel.isEmpty) {
      AppLogger.e('[CallProvider] No outgoing channel for Agora join');
      return;
    }
    try {
      await [Permission.microphone].request();
      await _joinMediaChannel(channel);
    } catch (e, st) {
      AppLogger.e('[CallProvider] Caller Agora join failed: $e', e, st);
      unawaited(forceIdleCallSession(endReason: 'error'));
    }
  }

  Future<void> _joinMediaChannel(String channelName) async {
    final myId = await _getMyUserId();
    if (myId == null || myId.isEmpty) {
      throw StateError('Missing user id for Agora token');
    }
    await AgoraRtcService.instance.joinVoiceChannel(
      channelName: channelName,
      userId: myId,
    );
    await AgoraRtcService.instance.applyPostJoinAudioSettings(
      isMuted: state.isMuted,
      isSpeakerOn: state.isSpeakerOn,
    );
  }

  void _onRemoteDecline(dynamic _) {
    final snapshot = state;
    final wasLive =
        snapshot.status == CallStatus.connected || snapshot.durationSeconds > 0;
    unawaited(forceIdleCallSession(endReason: wasLive ? 'ended' : 'declined'));
  }

  void _onRemoteEnd(dynamic _) {
    unawaited(forceIdleCallSession(endReason: 'ended'));
  }

  void _onRemoteCancel(dynamic data) {
    unawaited(_handleRemoteCancel(data));
  }

  Future<void> _handleRemoteCancel(dynamic data) async {
    if (!await _shouldApplyRemoteCancel(data)) {
      AppLogger.w('[CallProvider] Ignoring stale call-cancel');
      return;
    }
    final callerId = _parseCancelCallerId(data) ?? _pendingFromId ?? '';
    final recordId = _parseCallRecordId(data);
    await CallKitService.dismissNativeIncoming(
      callerId: callerId,
      callRecordId: recordId,
    );
    await forceIdleCallSession(endReason: 'cancelled');
  }

  Future<bool> _shouldApplyRemoteCancel(dynamic data) async {
    final cancelRecordId = _parseCallRecordId(data);
    if (cancelRecordId == null || cancelRecordId.isEmpty) {
      return true;
    }
    final activeId = _activeIncomingCallRecordId;
    if (activeId == null || activeId.isEmpty) {
      return true;
    }
    if (cancelRecordId == activeId) {
      return true;
    }
    final callerId = _parseCancelCallerId(data) ?? _pendingFromId;
    if (callerId == null || callerId.isEmpty) {
      return false;
    }
    final callerStillActive = await CallKitService.isCallerActiveOnServer(
      callerId,
    );
    if (!callerStillActive) {
      return true;
    }
    final peerId = state.remoteUserId ?? _pendingFromId ?? '';
    if ((state.status == CallStatus.calling ||
            state.status == CallStatus.ringing) &&
        peerId.isNotEmpty &&
        peerId == callerId) {
      return true;
    }
    return false;
  }

  String? _parseCancelCallerId(dynamic data) {
    if (data is Map) {
      return data['from']?.toString() ?? data['callerId']?.toString();
    }
    if (data is List && data.isNotEmpty && data.first is Map) {
      final map = data.first as Map;
      return map['from']?.toString() ?? map['callerId']?.toString();
    }
    return null;
  }

  String? _parseCallRecordId(dynamic data) {
    if (data is Map) {
      return data['callRecordId']?.toString();
    }
    if (data is List && data.isNotEmpty && data.first is Map) {
      return (data.first as Map)['callRecordId']?.toString();
    }
    return null;
  }

  void _onRemoteBusy(dynamic _) {
    unawaited(forceIdleCallSession(endReason: 'busy'));
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  void _onRemoteUserJoinedMedia() {
    if (state.status != CallStatus.calling &&
        state.status != CallStatus.connecting &&
        state.status != CallStatus.connected) {
      return;
    }
    _beginConnectedTimer();
  }

  void _startConnectingTimeout() {
    _stopConnectingTimeout();
    _connectingTimeoutTimer = Timer(
      const Duration(seconds: _connectingTimeoutSeconds),
      () {
        if (state.status != CallStatus.connecting) return;
        AppLogger.w('[CallProvider] Connecting timeout — no media link');
        unawaited(forceIdleCallSession(endReason: 'error'));
      },
    );
  }

  void _stopConnectingTimeout() {
    _connectingTimeoutTimer?.cancel();
    _connectingTimeoutTimer = null;
  }

  void _beginConnectedTimer() {
    _stopSessionWatchdog();
    _stopConnectingTimeout();
    if (_callTimer != null) {
      if (state.status == CallStatus.connecting) {
        state = state.copyWith(status: CallStatus.connected);
      }
      return;
    }
    state = state.copyWith(status: CallStatus.connected, durationSeconds: 0);
    _syncPreConnectRingback(CallStatus.connected);
    _startTimer();
    // Activate proximity sensor to dim screen when phone is held to ear.
    _activateProximityLock();
  }

  void _activateProximityLock() async {
    try {
      if (await ProximityScreenLock.isProximityLockSupported()) {
        await ProximityScreenLock.setActive(true);
        AppLogger.i('📞 Proximity screen lock activated');
      }
    } catch (e) {
      AppLogger.w('📞 Failed to activate proximity lock: $e');
    }
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(durationSeconds: state.durationSeconds + 1);
    });
  }

  Future<void> _persistOutgoingCall({
    required String remoteUserId,
    required bool isGroup,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_outgoingReceiverIdKey, remoteUserId);
      await prefs.setBool(_outgoingIsGroupKey, isGroup);
    } catch (e) {
      AppLogger.w('[CallProvider] persist outgoing call failed: $e');
    }
  }

  Future<void> _clearOutgoingCallPersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_outgoingReceiverIdKey);
      await prefs.remove(_outgoingIsGroupKey);
    } catch (_) {}
  }

  Future<String?> _readPersistedOutgoingReceiverId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_outgoingReceiverIdKey);
      if (id != null && id.isNotEmpty) return id;
    } catch (_) {}
    return null;
  }

  Future<String?> _fetchActiveOutgoingCallRecordId() async {
    try {
      final myId = await _getMyUserId();
      if (myId == null || myId.isEmpty) return null;
      final resp = await ApiService.dio.get(
        '/call-history/check-active',
        queryParameters: {'callerId': myId},
      );
      final id = resp.data?['callRecordId']?.toString();
      if (id != null && id.isNotEmpty) return id;
    } catch (e) {
      AppLogger.w('[CallProvider] check-active for cancel failed: $e');
    }
    return null;
  }

  Future<void> _signalOutgoingCancel({
    required bool isGroup,
    String? remoteId,
  }) async {
    final myId = await _getMyUserId();
    if (myId == null || myId.isEmpty) {
      AppLogger.e(
        '[CallProvider] Cannot signal cancel — missing pilgrim/caller user id',
      );
      return;
    }

    final callRecordId = await _fetchActiveOutgoingCallRecordId();

    if (isGroup) {
      CallSignaling.emitWhenConnected('group-call-cancel', <String, dynamic>{});
      await CallSignaling.notifyGroupCancelHttp(
        myId,
        callRecordId: callRecordId,
      );
      return;
    }

    var to = remoteId;
    if (to == null || to.isEmpty) {
      to = _pendingFromId;
    }
    if (to == null || to.isEmpty) {
      to = await _readPersistedOutgoingReceiverId();
    }

    final socketPayload = <String, dynamic>{};
    if (to != null && to.isNotEmpty) {
      socketPayload['to'] = to;
    }
    CallSignaling.emitWhenConnected('call-cancel', socketPayload);

    // Always hit REST — even without [to] the server cancels every ringing
    // outgoing call for this caller (covers stale Riverpod state after decline→recall).
    await CallSignaling.notifyCancelHttp(
      myId,
      receiverId: to,
      callRecordId: callRecordId,
    );

    if (to == null || to.isEmpty) {
      AppLogger.w(
        '[CallProvider] Cancel sent without receiverId — server cancel-all '
        'ringing fallback (record=$callRecordId)',
      );
    }
  }

  Future<void> _reconcilePendingIncomingCall() async {
    final pending = await CallKitService.readRecentPendingIncomingCall(
      maxAgeSeconds: 60,
    );
    if (pending == null) return;

    final callerId = pending['callerId'] ?? '';
    if (callerId.isEmpty) return;

    try {
      final response = await ApiService.dio.get(
        '/call-history/check-active',
        queryParameters: {'callerId': callerId},
      );
      final active = response.data?['active'] == true;
      if (active) {
        final serverRecordId =
            response.data?['callRecordId']?.toString().trim() ?? '';
        final pendingRecordId = pending['callRecordId']?.trim() ?? '';
        if (pendingRecordId.isNotEmpty &&
            serverRecordId.isNotEmpty &&
            pendingRecordId != serverRecordId) {
          AppLogger.w(
            '[CallProvider] Pending call record mismatch '
            '(pending=$pendingRecordId server=$serverRecordId)',
          );
        } else {
          return;
        }
      }

      // CallKit may show an accepted in-call UI while Dart never got actionCallAccept.
      try {
        final raw = await FlutterCallkitIncoming.activeCalls();
        if (raw is List) {
          for (final item in raw) {
            if (item is Map &&
                (item['isAccepted'] == true || item['accepted'] == true)) {
              AppLogger.i(
                '[CallProvider] Reconcile: native CallKit accepted — joining',
              );
              if (state.status == CallStatus.ringing) {
                await acceptCall();
              } else {
                await checkPendingAcceptedCall();
              }
              return;
            }
          }
        }
      } catch (e) {
        AppLogger.w('[CallProvider] Reconcile native accept check failed: $e');
      }

      AppLogger.w(
        '[CallProvider] Pending native call is no longer active on server',
      );
      if (state.isInCall) {
        await forceIdleCallSession(endReason: 'cancelled');
      } else {
        await forceIdleCallSession(
          endReason: 'cancelled',
          goIdleImmediately: true,
        );
      }
    } catch (e) {
      AppLogger.w('[CallProvider] incoming reconcile skipped: $e');
    }
  }

  Future<void> _reconcileStaleOutgoingPersistence() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final receiverId = prefs.getString(_outgoingReceiverIdKey) ?? '';
      final isGroup = prefs.getBool(_outgoingIsGroupKey) ?? false;
      if (receiverId.isEmpty && !isGroup) return;

      final myId = await SecureSessionStore.getUserId();
      if (myId == null || myId.isEmpty) {
        await _clearOutgoingCallPersistence();
        return;
      }

      final resp = await ApiService.dio.get(
        '/call-history/check-active',
        queryParameters: {'callerId': myId},
      );
      final active = resp.data['active'] as bool? ?? false;
      if (!active) {
        await _clearOutgoingCallPersistence();
        return;
      }

      if (!state.isInCall) {
        AppLogger.w(
          '[CallProvider] Server still ringing after process death — cancelling',
        );
        await _signalOutgoingCancel(
          isGroup: isGroup,
          remoteId: receiverId.isNotEmpty ? receiverId : null,
        );
      }
      await _clearOutgoingCallPersistence();
    } catch (e) {
      AppLogger.w('[CallProvider] outgoing reconcile skipped: $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final callProvider = NotifierProvider<CallNotifier, CallState>(
  CallNotifier.new,
);
