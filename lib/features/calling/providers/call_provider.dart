// Voice-call stack (Flutter side):
// • [NativeCallCoordinator] — CallKit events, cold-start pending accept, FCM
//   call_cancel / call_declined (foreground), navigation to [VoiceCallScreen].
// • [CallSignaling] — socket emits with reconnect queue + HTTP answer/decline.
// • [CallKitService] — native incoming UI + prefs for UUID / dismiss.
// • [CallNotifier] (this file) — Riverpod state + Agora join/leave lifecycle.
import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../auth/providers/auth_provider.dart';
import '../../moderator/services/sos_alert_coordinator.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/callkit_service.dart';
import '../../../core/services/call_ringback_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/router/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../call_signaling.dart';
import '../native_call_coordinator.dart';
import '../screens/voice_call_screen.dart';

/// Read at first use (after dotenv.load has run in main).
String get _agoraAppId => dotenv.env['AGORA_APP_ID'] ?? '';

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
  final bool isMuted;
  final bool isSpeakerOn;
  final int durationSeconds;
  final String?
  endReason; // 'declined' | 'busy' | 'ended' | 'cancelled' | 'error'

  const CallState({
    this.status = CallStatus.idle,
    this.remoteUserId,
    this.remoteUserName,
    this.incomingDisplayName,
    this.isGroupRingingOut = false,
    this.displayPeerAsSupportBranding = false,
    this.remotePeerGender,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.durationSeconds = 0,
    this.endReason,
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
    bool? isMuted,
    bool? isSpeakerOn,
    int? durationSeconds,
    String? endReason,
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
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      endReason: endReason ?? this.endReason,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Call Notifier – owns the WebRTC peer connection lifecycle
// ─────────────────────────────────────────────────────────────────────────────

class CallNotifier extends Notifier<CallState> {
  static const _outgoingReceiverIdKey = 'outgoing_call_receiver_id';
  static const _outgoingIsGroupKey = 'outgoing_call_is_group';

  RtcEngine? _engine;
  String? _pendingChannelName;
  String? _pendingFromId;
  Timer? _callTimer;
  Timer? _ringPollTimer; // polls backend while outgoing call is ringing

  /// Timestamp of the last processed call-offer — reject rapid duplicates.
  DateTime? _lastOfferTime;

  @override
  CallState build() {
    _registerSocketListeners();
    return const CallState();
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
    if (state.isInCall) return;
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
    _syncPreConnectRingback(CallStatus.calling);
    unawaited(_persistOutgoingCall(remoteUserId: ids.first, isGroup: true));

    try {
      await [Permission.microphone].request();
      final channelName = 'call_${DateTime.now().millisecondsSinceEpoch}';
      AppLogger.i('[CallProvider] Group moderator ring on $channelName → $ids');
      await _setupEngine();
      await _engine!.joinChannel(
        token: '',
        channelId: channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      CallSignaling.emitWhenConnected('call-offer-group', {
        'targets': ids,
        'channelName': channelName,
      });
      _startRingPoll(ids.first);
    } catch (e) {
      _stopRingPoll();
      _cleanup();
      state = state.copyWith(
        status: CallStatus.ended,
        endReason: 'error',
        isGroupRingingOut: false,
      );
      _scheduleReset();
    }
  }

  /// Moderator initiates an internet call to [remoteUserId].
  /// Pilgrim one-to-one ring (e.g. SOS auto-route): show support branding, not
  /// the moderator’s personal name or raw id in UI.
  Future<void> startCall({
    required String remoteUserId,
    required String remoteUserName,
    String? remotePeerGender,
  }) async {
    if (state.isInCall) return;
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
    );
    _syncPreConnectRingback(CallStatus.calling);
    unawaited(
      _persistOutgoingCall(remoteUserId: remoteUserId, isGroup: false),
    );

    try {
      await [Permission.microphone].request();
      final channelName = 'call_${DateTime.now().millisecondsSinceEpoch}';
      AppLogger.i('[CallProvider] Setting up Agora engine…');
      await _setupEngine();
      AppLogger.i('[CallProvider] Joining Agora channel: $channelName');
      await _engine!.joinChannel(
        token: '',
        channelId: channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      AppLogger.i(
        '[CallProvider] → Emitting call-offer to $remoteUserId on channel $channelName',
      );
      CallSignaling.emitWhenConnected('call-offer', {
        'to': remoteUserId,
        'channelName': channelName,
      });
      if (!isPilgrimCaller) {
        unawaited(SosAlertCoordinator.afterModeratorPlacedCall(remoteUserId));
      }
      // Start polling so we detect decline even when the pilgrim's app is killed
      // and the HTTP decline from the background isolate fails for any reason.
      _startRingPoll(remoteUserId);
    } catch (e) {
      _stopRingPoll();
      _cleanup();
      state = state.copyWith(
        status: CallStatus.ended,
        endReason: 'error',
        isGroupRingingOut: false,
      );
      _scheduleReset();
    }
  }

  // ── Ring poll: moderator polls backend every 3 s while outgoing call rings ──
  void _startRingPoll(String remoteUserId) {
    _stopRingPoll();
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
          queryParameters: {'callerId': myId},
        );
        final active = resp.data['active'] as bool? ?? false;
        final status = resp.data['status']?.toString() ?? 'none';
        AppLogger.d('[RingPoll] active=$active status=$status myId=$myId');
        // If the call is no longer ringing/in-progress on the backend, treat it
        // as declined (covers killed-app decline + timeout).
        if (!active && state.status == CallStatus.calling) {
          AppLogger.w(
            '[RingPoll] Call no longer active ($status) — stopping ring',
          );
          _stopRingPoll();
          _cleanup();
          state = state.copyWith(
            status: CallStatus.ended,
            endReason: status == 'none' ? 'declined' : status,
            isGroupRingingOut: false,
          );
          // If moderator's outgoing ring ended before connect, downgrade SOS
          // from "in call" back to "being handled".
          final isMod =
              ref.read(authProvider).role?.toLowerCase() != 'pilgrim';
          if (isMod) {
            unawaited(SosAlertCoordinator.afterModeratorEndedCall(remoteUserId));
          }
          _scheduleReset();
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
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('user_id');
    } catch (_) {
      return null;
    }
  }

  /// Accept an incoming call (status must be [CallStatus.ringing]).
  Future<void> acceptCall() async {
    if (state.status != CallStatus.ringing || _pendingChannelName == null) {
      return;
    }

    final fromId = _pendingFromId;
    final channelName = _pendingChannelName!;
    state = state.copyWith(
      status: CallStatus.connected,
      durationSeconds: 0,
      clearIncomingDisplayName: true,
    );
    _syncPreConnectRingback(CallStatus.connected);

    try {
      await [Permission.microphone].request();
      // Signal the server immediately — do not wait for Agora. The backend
      // ring-timeout (30s) clears when it receives call-answer / REST answer;
      // if joinChannel runs first, a slow SDK can miss the window and the
      // caller gets "Call Not Answered" even after the callee tapped Accept.
      if (fromId != null && fromId.isNotEmpty) {
        CallSignaling.emitWhenConnected('call-answer', {'to': fromId});
        CallSignaling.notifyAnswerHttp(fromId, SocketService.connectedUserId);
      } else {
        AppLogger.e(
          '[CallProvider] Cannot signal call-answer: missing caller id (fromId=$fromId)',
        );
      }

      AppLogger.i('[CallProvider] Accepting call on channel: $channelName');
      await _setupEngine();
      await _engine!.joinChannel(
        token: '',
        channelId: channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      _pendingChannelName = null;
      _pendingFromId = null;
      _beginConnectedTimer();
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
    } catch (e) {
      _cleanup();
      state = state.copyWith(
        status: CallStatus.ended,
        endReason: 'error',
        isGroupRingingOut: false,
      );
      _scheduleReset();
    }
  }

  /// Decline an incoming call.
  void declineCall() {
    final remoteId = state.remoteUserId;
    if (remoteId != null) {
      CallSignaling.emitWhenConnected('call-declined', {'to': remoteId});
      CallSignaling.notifyDeclineHttp(remoteId, SocketService.connectedUserId);
    }
    // Dismiss native call screen
    CallKitService.instance.endCurrentCall();
    _cleanup();
    state = state.copyWith(
      status: CallStatus.ended,
      endReason: 'declined',
      isGroupRingingOut: false,
    );
    _scheduleReset();
  }

  /// Incoming ring timed out (CallKit) — server records **missed**, not declined.
  void declineCallAsNoAnswer() {
    final remoteId = state.remoteUserId;
    if (remoteId != null) {
      CallSignaling.emitWhenConnected('call-declined', {
        'to': remoteId,
        'noAnswer': true,
      });
      CallSignaling.notifyDeclineHttp(
        remoteId,
        SocketService.connectedUserId,
        noAnswer: true,
      );
    }
    CallKitService.instance.endCurrentCall();
    _cleanup();
    state = state.copyWith(
      status: CallStatus.ended,
      endReason: 'missed',
      isGroupRingingOut: false,
    );
    _scheduleReset();
  }

  /// Decline a call when we only have the caller id (killed-state fallback).
  /// [noAnswer] — native ring timeout / no pickup (counts as missed, not declined).
  void declineCallFromCallerId(String callerId, {bool noAnswer = false}) {
    if (callerId.isNotEmpty) {
      CallSignaling.emitWhenConnected('call-declined', {
        'to': callerId,
        if (noAnswer) 'noAnswer': true,
      });
      CallSignaling.notifyDeclineHttp(
        callerId,
        SocketService.connectedUserId,
        noAnswer: noAnswer,
      );
    }
    CallKitService.instance.endCurrentCall();
    _cleanup();
    state = state.copyWith(
      status: CallStatus.ended,
      endReason: noAnswer ? 'missed' : 'declined',
      remoteUserId: callerId,
      isGroupRingingOut: false,
    );
    _scheduleReset();
  }

  /// End an in-progress call.
  void endCall() {
    _stopRingPoll();
    final remoteId = state.remoteUserId;
    if (remoteId != null) {
      CallSignaling.emitWhenConnected('call-end', {'to': remoteId});
    }
    // If moderator ended an active call, signal "responding" to the pilgrim
    final isMod = ref.read(authProvider).role?.toLowerCase() != 'pilgrim';
    final wasActive = state.status == CallStatus.connected ||
        state.status == CallStatus.connecting;
    if (isMod && wasActive && remoteId != null && remoteId.isNotEmpty) {
      unawaited(SosAlertCoordinator.afterModeratorEndedCall(remoteId));
    }
    // Dismiss native call screen
    CallKitService.instance.endCurrentCall();
    _cleanup();
    state = state.copyWith(
      status: CallStatus.ended,
      endReason: 'ended',
      isGroupRingingOut: false,
    );
    _scheduleReset();
  }

  /// Caller cancelled while still ringing — notify callee only via `call-cancel`.
  /// Never emit `call-end` here: the server treats `call-end` during `ringing`
  /// as a missed call and mis-notifies the recipient.
  void cancelOutgoingRing() {
    _stopRingPoll();
    final snapshot = state;
    unawaited(
      _signalOutgoingCancel(
        isGroup: snapshot.isGroupRingingOut,
        remoteId: snapshot.remoteUserId,
      ),
    );
    // If moderator cancels outgoing ring (never connected), downgrade SOS
    // from "in call" back to "being handled".
    final remoteId = snapshot.remoteUserId;
    final isMod = ref.read(authProvider).role?.toLowerCase() != 'pilgrim';
    if (isMod && remoteId != null && remoteId.isNotEmpty) {
      unawaited(SosAlertCoordinator.afterModeratorEndedCall(remoteId));
    }
    CallKitService.instance.endCurrentCall();
    _cleanup();
    state = snapshot.copyWith(
      status: CallStatus.ended,
      endReason: 'cancelled',
      isGroupRingingOut: false,
    );
    _scheduleReset();
  }

  /// Dismiss local ringing UI after the peer or server already signalled
  /// (FCM `call_cancel` / `call_declined`). Does not emit `call-end`.
  void stopLocalCallSession({required String endReason}) {
    _stopRingPoll();
    CallKitService.instance.endCurrentCall();
    _cleanup();
    state = state.copyWith(
      status: CallStatus.ended,
      endReason: endReason,
      isGroupRingingOut: false,
    );
    _scheduleReset();
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

    final prefsEarly = await SharedPreferences.getInstance();
    final isPilgrimCallee = prefsEarly.getString('user_role') == 'pilgrim';
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
    try {
      final response = await ApiService.dio.get(
        '/call-history/check-active',
        queryParameters: {'callerId': callerId},
      );
      final isActive = response.data?['active'] == true;
      if (!isActive) {
        AppLogger.w(
          '[CallProvider] Call from $callerName is no longer active '
          '(server: ${response.data?['status']})',
        );
        await CallKitService.instance.endAllCalls();
        state = CallState(
          status: CallStatus.ended,
          endReason: 'cancelled',
          remoteUserId: callerId,
          remoteUserName: calleeDisplayName,
          displayPeerAsSupportBranding: isPilgrimCallee,
        );
        _syncPreConnectRingback(CallStatus.ended);
        _scheduleReset();
        return;
      }
    } catch (e) {
      // Network error — proceed anyway (better to try than miss a real call)
      AppLogger.w(
        '[CallProvider] Could not verify call status, proceeding: $e',
      );
    }

    _pendingChannelName = channelName;
    _pendingFromId = callerId;

    state = CallState(
      status: CallStatus.ringing,
      remoteUserId: callerId,
      remoteUserName: calleeDisplayName,
      incomingDisplayName: isPilgrimCallee ? calleeDisplayName : null,
      displayPeerAsSupportBranding: isPilgrimCallee,
    );

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
          if (VoiceCallScreen.isActive) return;
          final nav = AppRouter.navigatorKey.currentState;
          if (nav != null) {
            nav.push(
              MaterialPageRoute(builder: (_) => const VoiceCallScreen()),
            );
          }
        });
      }
    }
  }

  Future<void> checkPendingDeclinedCall() async {
    final pending = consumePendingDeclined();
    if (pending != null && pending.callerId.isNotEmpty) {
      AppLogger.i(
        '[CallProvider] Found pending declined call for caller=${pending.callerId} noAnswer=${pending.noAnswer}',
      );
      declineCallFromCallerId(pending.callerId, noAnswer: pending.noAnswer);
    }
  }

  /// Reconcile native / persisted call state after the process was killed.
  Future<void> reconcileCallStateAfterProcessDeath() async {
    await _reconcilePendingOutgoingStopFromFcm();
    await _reconcilePendingIncomingCall();
    await _reconcileStaleOutgoingPersistence();
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
    _engine?.muteLocalAudioStream(muted);
  }

  Future<void> toggleSpeaker() async {
    final on = !state.isSpeakerOn;
    state = state.copyWith(isSpeakerOn: on);
    if (_engine != null) {
      await _engine!.setEnableSpeakerphone(on);
    }
  }

  // ════════════════════════════════════════════════════════════════════════════
  // SOCKET HANDLERS (private)
  // ════════════════════════════════════════════════════════════════════════════

  void _onIncomingOffer(dynamic data) {
    AppLogger.d('[CallProvider] ← call-offer received: $data');

    // data may arrive as Map or as List([Map]) depending on socket.io
    // serialisation – normalise first so all paths use the same payload.
    final Map<String, dynamic> payload = (data is List)
        ? Map<String, dynamic>.from(data.first as Map? ?? {})
        : Map<String, dynamic>.from(data as Map? ?? {});

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
    if (_pendingChannelName == channelName) {
      AppLogger.d(
        '[CallProvider] ✗ duplicate call-offer for same channel, ignored',
      );
      return;
    }

    // Timestamp guard: reject call-offer within 5 s of the last one.
    final now = DateTime.now();
    if (_lastOfferTime != null &&
        now.difference(_lastOfferTime!).inSeconds < 5) {
      AppLogger.w('[CallProvider] ✗ call-offer within 5 s window, ignored');
      return;
    }
    _lastOfferTime = now;

    _pendingChannelName = channelName;
    _pendingFromId = payload['from'] as String?;

    final callerInfo = payload['callerInfo'] as Map?;
    final callerName = callerInfo?['name'] as String? ?? 'Unknown';
    final callerRole = callerInfo?['role'] as String?;
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

    AppLogger.i(
      '[CallProvider] ✓ Incoming call from $callerName ($_pendingFromId) on channel $channelName',
    );

    // Show NATIVE incoming call screen (like WhatsApp)
    CallKitService.instance.showIncomingCall(
      callerId: _pendingFromId ?? '',
      callerName: callerName,
      channelName: channelName,
      callerRole: callerRole,
    );

    state = CallState(
      status: CallStatus.ringing,
      remoteUserId: _pendingFromId,
      remoteUserName: inAppDisplayName,
      incomingDisplayName: supportLabel,
      displayPeerAsSupportBranding: isPilgrim,
    );
  }

  void _onAnswer(dynamic data) {
    _stopRingPoll();
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
  }

  void _onRemoteDecline(dynamic _) {
    _stopRingPoll();
    CallKitService.instance.endCurrentCall();
    final snapshot = state;
    _cleanup();
    final wasLive =
        snapshot.status == CallStatus.connected || snapshot.durationSeconds > 0;
    state = snapshot.copyWith(
      status: CallStatus.ended,
      endReason: wasLive ? 'ended' : 'declined',
      isGroupRingingOut: false,
    );
    _scheduleReset();
  }

  void _onRemoteEnd(dynamic _) {
    _stopRingPoll();
    CallKitService.instance.endCurrentCall();
    final snapshot = state;
    _cleanup();
    state = snapshot.copyWith(
      status: CallStatus.ended,
      endReason: 'ended',
      isGroupRingingOut: false,
    );
    _scheduleReset();
  }

  void _onRemoteCancel(dynamic _) {
    _stopRingPoll();
    CallKitService.instance.endCurrentCall();
    final snapshot = state;
    _cleanup();
    state = snapshot.copyWith(
      status: CallStatus.ended,
      endReason: 'cancelled',
      isGroupRingingOut: false,
    );
    _scheduleReset();
  }

  void _onRemoteBusy(dynamic _) {
    CallKitService.instance.endCurrentCall();
    final snapshot = state;
    _cleanup();
    state = snapshot.copyWith(
      status: CallStatus.ended,
      endReason: 'busy',
      isGroupRingingOut: false,
    );
    _scheduleReset();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  Future<void> _setupEngine() async {
    if (_engine != null) return; // Reuse existing engine

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(RtcEngineContext(appId: _agoraAppId));
    await _engine!.enableAudio();
    // Use default speech profile & 1-on-1 scenario for voice calls
    await _engine!.setAudioProfile(
      profile: AudioProfileType.audioProfileDefault,
      scenario: AudioScenarioType.audioScenarioDefault,
    );

    _engine!.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          AppLogger.i(
            '[Agora] ✓ Joined channel ${connection.channelId} '
            'as uid ${connection.localUid} (${elapsed}ms)',
          );
          // These must run AFTER joining the channel (not during setup),
          // otherwise the SDK returns ERR_NOT_READY (-3).
          // Must match [CallState.isSpeakerOn] or UI shows earpiece while audio is on speaker.
          _engine?.setEnableSpeakerphone(state.isSpeakerOn);
          _engine?.muteLocalAudioStream(state.isMuted);
          _engine?.muteAllRemoteAudioStreams(false);
          _engine?.adjustRecordingSignalVolume(400);
          _engine?.adjustPlaybackSignalVolume(400);
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          AppLogger.i('[Agora] Remote user $remoteUid joined');
          _onRemoteUserJoinedMedia();
        },
        onUserOffline: (connection, remoteUid, reason) {
          AppLogger.i('[Agora] Remote user $remoteUid offline: $reason');
          if (state.status == CallStatus.connected) {
            endCall();
          }
        },
        onError: (err, msg) {
          AppLogger.e('[Agora] ✗ Error: $err — $msg');
        },
        onConnectionStateChanged: (connection, stateType, reason) {
          AppLogger.d('[Agora] Connection state: $stateType reason: $reason');
        },
        onTokenPrivilegeWillExpire: (connection, token) {
          AppLogger.w('[Agora] ⚠ Token will expire');
        },
      ),
    );
  }

  void _onRemoteUserJoinedMedia() {
    if (state.status != CallStatus.calling &&
        state.status != CallStatus.connecting &&
        state.status != CallStatus.connected) {
      return;
    }
    _beginConnectedTimer();
  }

  void _beginConnectedTimer() {
    if (_callTimer != null) {
      if (state.status == CallStatus.connecting) {
        state = state.copyWith(status: CallStatus.connected);
      }
      return;
    }
    state = state.copyWith(
      status: CallStatus.connected,
      durationSeconds: 0,
    );
    _syncPreConnectRingback(CallStatus.connected);
    _startTimer();
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(durationSeconds: state.durationSeconds + 1);
    });
  }

  void _scheduleReset({int delaySeconds = 3}) {
    Future.delayed(Duration(seconds: delaySeconds), () {
      if (state.status == CallStatus.ended) {
        state = const CallState();
      }
    });
  }

  void _cleanup() {
    _callTimer?.cancel();
    _callTimer = null;
    _syncPreConnectRingback(CallStatus.ended);
    _engine?.leaveChannel();
    // Do NOT release the engine here, we reuse it for consecutive calls.
    // It will be disposed only when the app is terminated or CallProvider is disposed.
    _pendingChannelName = null;
    _pendingFromId = null;
    unawaited(_clearOutgoingCallPersistence());
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

  Future<void> _signalOutgoingCancel({
    required bool isGroup,
    String? remoteId,
  }) async {
    final myId = await _getMyUserId();
    if (isGroup) {
      CallSignaling.emitWhenConnected('group-call-cancel', <String, dynamic>{});
      if (myId != null && myId.isNotEmpty) {
        CallSignaling.notifyGroupCancelHttp(myId);
      }
      return;
    }

    var to = remoteId;
    if (to == null || to.isEmpty) {
      to = await _readPersistedOutgoingReceiverId();
    }
    if (to == null || to.isEmpty) return;

    CallSignaling.emitWhenConnected('call-cancel', {'to': to});
    if (myId != null && myId.isNotEmpty) {
      CallSignaling.notifyCancelHttp(myId, to);
    }
  }

  Future<void> _reconcilePendingIncomingCall() async {
    final pending = await CallKitService.readRecentPendingIncomingCall(
      maxAgeSeconds: 120,
    );
    if (pending == null) return;

    final callerId = pending['callerId'] ?? '';
    if (callerId.isEmpty) return;

    try {
      final response = await ApiService.dio.get(
        '/call-history/check-active',
        queryParameters: {'callerId': callerId},
      );
      if (response.data?['active'] == true) return;

      AppLogger.w(
        '[CallProvider] Pending native call is no longer active on server',
      );
      await CallKitService.instance.endCurrentCall();
      if (!state.isInCall) {
        stopLocalCallSession(endReason: 'cancelled');
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

      final myId = prefs.getString('user_id');
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
