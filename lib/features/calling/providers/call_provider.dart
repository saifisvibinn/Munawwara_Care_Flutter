import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/services/socket_service.dart';

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

  @override
  CallState build() {
    _registerSocketListeners();
    return const CallState();
  }

  // ── Register socket listeners ─────────────────────────────────────────────
  void _registerSocketListeners() {
    debugPrint('[CallProvider] Registering socket listeners');
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
      debugPrint('[CallProvider] Setting up Agora engine…');
      await _setupEngine();
      debugPrint('[CallProvider] Joining Agora channel: $channelName');
      await _engine!.joinChannel(
        token: '',
        channelId: channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      debugPrint(
        '[CallProvider] → Emitting call-offer to $remoteUserId on channel $channelName',
      );
      SocketService.emit('call-offer', {
        'to': remoteUserId,
        'channelName': channelName,
      });
    } catch (e) {
      _cleanup();
      state = const CallState(status: CallStatus.ended, endReason: 'error');
      _scheduleReset();
    }
  }

  /// Accept an incoming call (status must be [CallStatus.ringing]).
  Future<void> acceptCall() async {
    if (state.status != CallStatus.ringing || _pendingChannelName == null) {
      return;
    }

    final fromId = _pendingFromId!;
    final channelName = _pendingChannelName!;
    state = state.copyWith(status: CallStatus.connected, durationSeconds: 0);

    try {
      await [Permission.microphone].request();
      debugPrint('[CallProvider] Accepting call on channel: $channelName');
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
      SocketService.emit('call-answer', {'to': fromId});
      _pendingChannelName = null;
      _pendingFromId = null;
      _startTimer();
    } catch (e) {
      _cleanup();
      state = const CallState(status: CallStatus.ended, endReason: 'error');
      _scheduleReset();
    }
  }

  /// Decline an incoming call.
  void declineCall() {
    if (state.remoteUserId != null) {
      SocketService.emit('call-declined', {'to': state.remoteUserId});
    }
    _cleanup();
    state = const CallState(status: CallStatus.ended, endReason: 'declined');
    _scheduleReset();
  }

  /// End an in-progress call.
  void endCall() {
    if (state.remoteUserId != null) {
      SocketService.emit('call-end', {'to': state.remoteUserId});
    }
    _cleanup();
    state = const CallState(status: CallStatus.ended, endReason: 'ended');
    _scheduleReset();
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
    debugPrint('[CallProvider] ← call-offer received: $data');

    // data may arrive as Map or as List([Map]) depending on socket.io
    // serialisation – normalise first so all paths use the same payload.
    final Map<String, dynamic> payload = (data is List)
        ? Map<String, dynamic>.from(data.first as Map? ?? {})
        : Map<String, dynamic>.from(data as Map? ?? {});

    if (state.isInCall) {
      debugPrint('[CallProvider] Already in call – sending busy');
      SocketService.emit('call-busy', {'to': payload['from']});
      return;
    }

    final channelName = payload['channelName'] as String?;
    if (channelName == null) {
      debugPrint('[CallProvider] ✗ call-offer missing channelName, ignored');
      return;
    }

    _pendingChannelName = channelName;
    _pendingFromId = payload['from'] as String?;

    final callerInfo = payload['callerInfo'] as Map?;
    final callerName = callerInfo?['name'] as String? ?? 'Unknown';

    debugPrint(
      '[CallProvider] ✓ Incoming call from $callerName ($_pendingFromId) on channel $channelName',
    );
    state = CallState(
      status: CallStatus.ringing,
      remoteUserId: _pendingFromId,
      remoteUserName: callerName,
    );
  }

  void _onAnswer(dynamic data) {
    _startTimer();
    state = state.copyWith(status: CallStatus.connected, durationSeconds: 0);
  }

  void _onRemoteDecline(dynamic _) {
    _cleanup();
    state = const CallState(status: CallStatus.ended, endReason: 'declined');
    _scheduleReset();
  }

  void _onRemoteEnd(dynamic _) {
    _cleanup();
    state = const CallState(status: CallStatus.ended, endReason: 'ended');
    _scheduleReset();
  }

  void _onRemoteCancel(dynamic _) {
    _cleanup();
    state = const CallState(status: CallStatus.ended, endReason: 'cancelled');
    _scheduleReset();
  }

  void _onRemoteBusy(dynamic _) {
    _cleanup();
    state = const CallState(status: CallStatus.ended, endReason: 'busy');
    _scheduleReset();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // PRIVATE HELPERS
  // ════════════════════════════════════════════════════════════════════════════

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
          debugPrint(
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
          debugPrint('[Agora] Remote user $remoteUid joined');
        },
        onUserOffline: (connection, remoteUid, reason) {
          debugPrint('[Agora] Remote user $remoteUid offline: $reason');
          if (state.status == CallStatus.connected) {
            endCall();
          }
        },
        onError: (err, msg) {
          debugPrint('[Agora] ✗ Error: $err — $msg');
        },
        onConnectionStateChanged: (connection, stateType, reason) {
          debugPrint('[Agora] Connection state: $stateType reason: $reason');
        },
        onTokenPrivilegeWillExpire: (connection, token) {
          debugPrint('[Agora] ⚠ Token will expire');
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
