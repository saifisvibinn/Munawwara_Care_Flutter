import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/callkit_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/router/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../main.dart'
    show
        consumePendingAcceptedCall,
        consumePendingDeclinedCallerId,
        isNavigatingToCall;
import '../screens/voice_call_screen.dart';

/// Read at first use (after dotenv.load has run in main).
String get _agoraAppId => dotenv.env['AGORA_APP_ID'] ?? '';

// ─────────────────────────────────────────────────────────────────────────────
// Call State
// ─────────────────────────────────────────────────────────────────────────────

enum CallStatus { idle, calling, ringing, connected, ended }

class CallState {
  final CallStatus status;
  final String? remoteUserId;
  final String? remoteUserName;
  final bool isMuted;
  final bool isSpeakerOn;
  final int durationSeconds;
  final String?
  endReason; // 'declined' | 'busy' | 'ended' | 'cancelled' | 'error'

  const CallState({
    this.status = CallStatus.idle,
    this.remoteUserId,
    this.remoteUserName,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.durationSeconds = 0,
    this.endReason,
  });

  bool get isInCall =>
      status == CallStatus.calling ||
      status == CallStatus.ringing ||
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
    bool? isMuted,
    bool? isSpeakerOn,
    int? durationSeconds,
    String? endReason,
  }) {
    return CallState(
      status: status ?? this.status,
      remoteUserId: remoteUserId ?? this.remoteUserId,
      remoteUserName: remoteUserName ?? this.remoteUserName,
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

  /// Moderator initiates an internet call to [remoteUserId].
  Future<void> startCall({
    required String remoteUserId,
    required String remoteUserName,
  }) async {
    if (state.isInCall) return;
    state = CallState(
      status: CallStatus.calling,
      remoteUserId: remoteUserId,
      remoteUserName: remoteUserName,
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
      SocketService.emit('call-offer', {
        'to': remoteUserId,
        'channelName': channelName,
      });
      // Start polling so we detect decline even when the pilgrim's app is killed
      // and the HTTP decline from the background isolate fails for any reason.
      _startRingPoll(remoteUserId);
    } catch (e) {
      _stopRingPoll();
      _cleanup();
      state = CallState(
        status: CallStatus.ended,
        endReason: 'error',
        remoteUserId: state.remoteUserId,
        remoteUserName: state.remoteUserName,
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
          state = CallState(
            status: CallStatus.ended,
            endReason: status == 'none' ? 'declined' : status,
            remoteUserId: state.remoteUserId,
            remoteUserName: state.remoteUserName,
          );
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
    state = state.copyWith(status: CallStatus.connected, durationSeconds: 0);

    try {
      await [Permission.microphone].request();
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
      if (fromId != null && fromId.isNotEmpty) {
        _emitWhenConnected('call-answer', {'to': fromId});
        // HTTP fallback — critical for killed/background state where socket
        // is not yet connected, so socket-only signaling can be delayed/lost.
        _notifyCallAnswerViaHttp(fromId);
      } else {
        AppLogger.e(
          '[CallProvider] Cannot signal call-answer: missing caller id (fromId=$fromId)',
        );
      }
      _pendingChannelName = null;
      _pendingFromId = null;
      _startTimer();
    } catch (e) {
      _cleanup();
      state = CallState(
        status: CallStatus.ended,
        endReason: 'error',
        remoteUserId: state.remoteUserId,
        remoteUserName: state.remoteUserName,
      );
      _scheduleReset();
    }
  }

  /// Decline an incoming call.
  void declineCall() {
    final remoteId = state.remoteUserId;
    if (remoteId != null) {
      _emitWhenConnected('call-declined', {'to': remoteId});
      // HTTP fallback — critical for killed/background state where socket
      // is not yet connected, so the socket emit above is a silent no-op.
      _notifyCallDeclineViaHttp(remoteId);
    }
    // Dismiss native call screen
    CallKitService.instance.endCurrentCall();
    _cleanup();
    state = CallState(
      status: CallStatus.ended,
      endReason: 'declined',
      remoteUserId: state.remoteUserId,
      remoteUserName: state.remoteUserName,
    );
    _scheduleReset();
  }

  /// Decline a call when we only have the caller id (killed-state fallback).
  void declineCallFromCallerId(String callerId) {
    if (callerId.isNotEmpty) {
      _emitWhenConnected('call-declined', {'to': callerId});
      _notifyCallDeclineViaHttp(callerId);
    }
    CallKitService.instance.endCurrentCall();
    _cleanup();
    state = CallState(
      status: CallStatus.ended,
      endReason: 'declined',
      remoteUserId: callerId,
      remoteUserName: state.remoteUserName,
    );
    _scheduleReset();
  }

  /// End an in-progress call.
  void endCall() {
    _stopRingPoll();
    if (state.remoteUserId != null) {
      SocketService.emit('call-end', {'to': state.remoteUserId});
    }
    // Dismiss native call screen
    CallKitService.instance.endCurrentCall();
    _cleanup();
    state = CallState(
      status: CallStatus.ended,
      endReason: 'ended',
      remoteUserId: state.remoteUserId,
      remoteUserName: state.remoteUserName,
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
          remoteUserName: callerName,
        );
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
      remoteUserName: callerName,
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
    final callerId = consumePendingDeclinedCallerId();
    if (callerId != null && callerId.isNotEmpty) {
      AppLogger.i(
        '[CallProvider] Found pending declined call for caller=$callerId',
      );
      declineCallFromCallerId(callerId);
    }
  }

  void toggleMute() {
    final muted = !state.isMuted;
    _engine?.muteLocalAudioStream(muted);
    state = state.copyWith(isMuted: muted);
  }

  Future<void> toggleSpeaker() async {
    final on = !state.isSpeakerOn;
    await _engine?.setEnableSpeakerphone(on);
    state = state.copyWith(isSpeakerOn: on);
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
      SocketService.emit('call-busy', {'to': payload['from']});
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
      remoteUserName: callerName,
    );
  }

  void _onAnswer(dynamic data) {
    _stopRingPoll(); // call was answered — stop polling
    _startTimer();
    state = state.copyWith(status: CallStatus.connected, durationSeconds: 0);
  }

  void _onRemoteDecline(dynamic _) {
    _stopRingPoll();
    CallKitService.instance.endCurrentCall();
    final prevName = state.remoteUserName;
    final prevId = state.remoteUserId;
    _cleanup();
    state = CallState(
      status: CallStatus.ended,
      endReason: 'declined',
      remoteUserId: prevId,
      remoteUserName: prevName,
    );
    _scheduleReset();
  }

  void _onRemoteEnd(dynamic _) {
    CallKitService.instance.endCurrentCall();
    final prevName = state.remoteUserName;
    final prevId = state.remoteUserId;
    _cleanup();
    state = CallState(
      status: CallStatus.ended,
      endReason: 'ended',
      remoteUserId: prevId,
      remoteUserName: prevName,
    );
    _scheduleReset();
  }

  void _onRemoteCancel(dynamic _) {
    CallKitService.instance.endCurrentCall();
    final prevName = state.remoteUserName;
    final prevId = state.remoteUserId;
    _cleanup();
    state = CallState(
      status: CallStatus.ended,
      endReason: 'cancelled',
      remoteUserId: prevId,
      remoteUserName: prevName,
    );
    _scheduleReset();
  }

  void _onRemoteBusy(dynamic _) {
    CallKitService.instance.endCurrentCall();
    final prevName = state.remoteUserName;
    final prevId = state.remoteUserId;
    _cleanup();
    state = CallState(
      status: CallStatus.ended,
      endReason: 'busy',
      remoteUserId: prevId,
      remoteUserName: prevName,
    );
    _scheduleReset();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ════════════════════════════════════════════════════════════════════════════

  void _emitWhenConnected(String event, Map<String, dynamic> payload) {
    if (SocketService.isConnected) {
      SocketService.emit(event, payload);
      return;
    }

    AppLogger.w('[CallProvider] Socket not connected, queueing "$event" emit');
    void sendOnce() {
      SocketService.emit(event, payload);
      SocketService.offConnected(sendOnce);
      AppLogger.i('[CallProvider] Queued "$event" emit sent after reconnect');
    }

    SocketService.onConnected(sendOnce);
  }

  /// HTTP fallback: notify the moderator (caller) that the call was answered.
  /// Used when the app cold-starts from killed state and the socket is not
  /// connected yet.  Fire-and-forget — errors are logged but don't block the
  /// call flow.
  void _notifyCallAnswerViaHttp(String callerId) {
    final selfId = SocketService.connectedUserId;
    ApiService.dio
        .post(
          '/call-history/answer',
          data: {'callerId': callerId, 'answererId': selfId ?? ''},
        )
        .then(
          (_) =>
              AppLogger.i('[CallProvider] HTTP call-answer sent to $callerId'),
        )
        .catchError(
          (e) => AppLogger.e('[CallProvider] HTTP call-answer failed: $e'),
        );
  }

  /// HTTP fallback: notify the moderator (caller) that the call was declined.
  void _notifyCallDeclineViaHttp(String callerId) {
    final selfId = SocketService.connectedUserId;
    ApiService.dio
        .post(
          '/call-history/decline',
          data: {'callerId': callerId, 'declinerId': selfId ?? ''},
        )
        .then(
          (_) => AppLogger.i(
            '[CallProvider] HTTP call-declined sent to $callerId',
          ),
        )
        .catchError(
          (e) => AppLogger.e('[CallProvider] HTTP call-declined failed: $e'),
        );
  }

  Future<void> _setupEngine() async {
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
          _engine?.setEnableSpeakerphone(true);
          _engine?.muteLocalAudioStream(false);
          _engine?.muteAllRemoteAudioStreams(false);
          _engine?.adjustRecordingSignalVolume(400);
          _engine?.adjustPlaybackSignalVolume(400);
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          AppLogger.i('[Agora] Remote user $remoteUid joined');
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
    _engine?.leaveChannel();
    _engine?.release();
    _engine = null;
    _pendingChannelName = null;
    _pendingFromId = null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final callProvider = NotifierProvider<CallNotifier, CallState>(
  CallNotifier.new,
);
