import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../utils/app_logger.dart';
import 'api_service.dart';
import 'secure_session_store.dart';

/// Agora voice RTC lifecycle per
/// https://docs.agora.io/en/voice-calling/get-started/get-started-sdk?platform=flutter
class AgoraRtcService {
  AgoraRtcService._();

  static final AgoraRtcService instance = AgoraRtcService._();

  static const Duration _joinTimeout = Duration(seconds: 20);

  RtcEngine? _engine;
  String? _joinedChannelName;
  bool _isJoining = false;
  Completer<void>? _joinCompleter;

  void Function(int remoteUid)? onRemoteUserJoined;
  void Function(int remoteUid, UserOfflineReasonType reason)?
      onRemoteUserOffline;
  void Function(String message)? onMediaJoinFailed;
  void Function()? onConnectionFailed;

  String get _appId => dotenv.env['AGORA_APP_ID'] ?? '';

  bool get isInChannel =>
      _joinedChannelName != null && _joinedChannelName!.isNotEmpty;

  /// Stable uid aligned with backend [agoraUidFromUserId].
  static int uidFromUserId(String userId) {
    if (userId.isEmpty) return 0;
    var hash = 0;
    for (final codeUnit in userId.codeUnits) {
      hash = ((hash << 5) - hash + codeUnit) & 0x7fffffff;
    }
    final uid = hash % 2147483647;
    return uid == 0 ? 1 : uid;
  }

  Future<void> joinVoiceChannel({
    required String channelName,
    required String userId,
  }) async {
    final channel = channelName.trim();
    if (channel.isEmpty) {
      throw StateError('channelName is empty');
    }
    if (_isJoining) {
      AppLogger.w('[AgoraRtc] join skipped — already joining');
      return;
    }
    if (_joinedChannelName == channel) {
      AppLogger.d('[AgoraRtc] already in channel $channel');
      return;
    }

    _isJoining = true;
    try {
      if (_joinedChannelName != null && _joinedChannelName != channel) {
        await leaveChannel();
      }

      final credentials = await _fetchRtcCredentials(
        channelName: channel,
        userId: userId,
      );

      await _ensureEngine(appId: credentials.appId);

      AppLogger.i(
        '[AgoraRtc] Joining $channel as uid ${credentials.uid} '
        '(tokenLen=${credentials.token.length})',
      );

      _joinCompleter = Completer<void>();
      await _engine!.joinChannel(
        token: credentials.token,
        channelId: channel,
        uid: credentials.uid,
        options: const ChannelMediaOptions(
          channelProfile: ChannelProfileType.channelProfileCommunication,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
        ),
      );

      await _joinCompleter!.future.timeout(
        _joinTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Agora did not confirm channel join within '
            '${_joinTimeout.inSeconds}s',
          );
        },
      );
      _joinedChannelName = channel;
    } finally {
      _joinCompleter = null;
      _isJoining = false;
    }
  }

  Future<void> leaveChannel() async {
    _joinedChannelName = null;
    _joinCompleter?.completeError(StateError('leaveChannel'));
    _joinCompleter = null;
    if (_engine == null) return;
    try {
      await _engine!.leaveChannel();
      AppLogger.i('[AgoraRtc] Left channel');
    } catch (e) {
      AppLogger.w('[AgoraRtc] leaveChannel failed: $e');
    }
  }

  Future<void> setMuted(bool muted) async {
    await _engine?.muteLocalAudioStream(muted);
  }

  Future<void> setSpeakerOn(bool on) async {
    await _engine?.setEnableSpeakerphone(on);
  }

  Future<void> applyPostJoinAudioSettings({
    required bool isMuted,
    required bool isSpeakerOn,
  }) async {
    await _engine?.setEnableSpeakerphone(isSpeakerOn);
    await _engine?.muteLocalAudioStream(isMuted);
    await _engine?.muteAllRemoteAudioStreams(false);
    await _engine?.adjustRecordingSignalVolume(400);
    await _engine?.adjustPlaybackSignalVolume(400);
  }

  Future<void> renewTokenIfNeeded(String channelName, String userId) async {
    if (_joinedChannelName != channelName) return;
    await _renewTokenForCurrentChannel();
  }

  Future<void> dispose() async {
    await leaveChannel();
    if (_engine != null) {
      await _engine!.release();
      _engine = null;
    }
  }

  Future<void> _ensureEngine({String? appId}) async {
    final resolvedAppId = (appId?.trim().isNotEmpty == true)
        ? appId!.trim()
        : _appId;
    if (resolvedAppId.isEmpty) {
      throw StateError('AGORA_APP_ID is not configured');
    }

    if (_engine != null) return;

    final engine = createAgoraRtcEngine();
    await engine.initialize(
      RtcEngineContext(
        appId: resolvedAppId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );
    await engine.enableAudio();
    await engine.setAudioProfile(
      profile: AudioProfileType.audioProfileDefault,
      scenario: AudioScenarioType.audioScenarioChatroom,
    );

    engine.registerEventHandler(
      RtcEngineEventHandler(
        onJoinChannelSuccess: (connection, elapsed) {
          AppLogger.i(
            '[AgoraRtc] Joined ${connection.channelId} '
            'uid=${connection.localUid} (${elapsed}ms)',
          );
          final c = _joinCompleter;
          if (c != null && !c.isCompleted) {
            c.complete();
          }
        },
        onUserJoined: (connection, remoteUid, elapsed) {
          AppLogger.i('[AgoraRtc] Remote user $remoteUid joined');
          onRemoteUserJoined?.call(remoteUid);
        },
        onUserOffline: (connection, remoteUid, reason) {
          AppLogger.i('[AgoraRtc] Remote user $remoteUid offline: $reason');
          onRemoteUserOffline?.call(remoteUid, reason);
        },
        onError: (err, msg) {
          AppLogger.e('[AgoraRtc] Error $err: $msg');
          _failJoin('Agora error $err: $msg');
          onMediaJoinFailed?.call('Agora error $err: $msg');
        },
        onConnectionStateChanged: (connection, state, reason) {
          AppLogger.i(
            '[AgoraRtc] connection state changed: $state reason: $reason',
          );
          final inChannel = _joinedChannelName != null &&
              _joinedChannelName!.isNotEmpty;
          final lost =
              reason == ConnectionChangedReasonType.connectionChangedLost;
          final failed = state == ConnectionStateType.connectionStateFailed;
          if (failed && _joinCompleter != null && !_joinCompleter!.isCompleted) {
            _failJoin('Connection failed ($reason)');
            onMediaJoinFailed?.call('Connection failed ($reason)');
          } else if (inChannel && (failed || lost)) {
            onConnectionFailed?.call();
          }
        },
        onTokenPrivilegeWillExpire: (connection, token) {
          unawaited(_renewTokenForCurrentChannel());
        },
        onRequestToken: (connection) {
          unawaited(_renewTokenForCurrentChannel());
        },
      ),
    );
    _engine = engine;
  }

  void _failJoin(String message) {
    final c = _joinCompleter;
    if (c != null && !c.isCompleted) {
      c.completeError(StateError(message));
    }
  }

  Future<void> _renewTokenForCurrentChannel() async {
    final channelName = _joinedChannelName;
    if (channelName == null || channelName.isEmpty) return;
    try {
      final userId = await _readUserId();
      if (userId == null || userId.isEmpty) return;
      final credentials = await _fetchRtcCredentials(
        channelName: channelName,
        userId: userId,
      );
      await _engine?.renewToken(credentials.token);
      AppLogger.i(
        '[AgoraRtc] token expiring — renewed for channel $channelName',
      );
    } catch (e) {
      AppLogger.e('[AgoraRtc] Token renewal failed: $e');
    }
  }

  Future<String?> _readUserId() async {
    try {
      return await SecureSessionStore.getUserId();
    } catch (_) {
      return null;
    }
  }

  Future<({String token, int uid, String appId})> _fetchRtcCredentials({
    required String channelName,
    required String userId,
  }) async {
    final resp = await ApiService.dio.get(
      '/call-history/agora-token',
      queryParameters: {'channelName': channelName},
    );
    final data = resp.data;
    if (data is! Map) {
      throw StateError('Invalid agora-token response');
    }
    if (data['success'] == false) {
      throw StateError(
        data['message']?.toString() ?? 'Failed to fetch Agora token',
      );
    }

    final token = data['token']?.toString() ?? '';
    final uidRaw = data['uid'];
    final uid = uidRaw is int
        ? uidRaw
        : int.tryParse(uidRaw?.toString() ?? '') ?? uidFromUserId(userId);
    final serverAppId = data['appId']?.toString() ?? '';
    final localAppId = _appId;

    if (serverAppId.isNotEmpty &&
        localAppId.isNotEmpty &&
        serverAppId != localAppId) {
      AppLogger.w(
        '[AgoraRtc] App ID mismatch — using server appId for this session',
      );
    }

    final resolvedAppId =
        serverAppId.isNotEmpty ? serverAppId : localAppId;
    if (resolvedAppId.isEmpty) {
      throw StateError('AGORA_APP_ID missing on client and server');
    }

    final tokenRequired = data['tokenRequired'] == true;
    if (tokenRequired && token.isEmpty) {
      throw StateError(
        'Server did not return an Agora token — set AGORA_APP_CERTIFICATE '
        'on the backend (GCP Cloud Run env)',
      );
    }

    return (token: token, uid: uid, appId: resolvedAppId);
  }
}
