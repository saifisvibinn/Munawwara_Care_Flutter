import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/backend_config.dart';
import '../../core/services/agora_rtc_service.dart';
import '../../core/services/callkit_service.dart';
import 'call_navigation.dart';
import '../../core/services/secure_session_store.dart';
import '../../core/utils/app_logger.dart';
import 'calling_scope.dart';
import 'providers/call_provider.dart';
import 'screens/voice_call_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NativeCallCoordinator
//
// Owns everything that bridges Android/iOS CallKit ↔ Riverpod ↔ navigation.
// Keeps [main.dart] free of call-specific globals except assigning
// [CallingScope.riverpod].
// ─────────────────────────────────────────────────────────────────────────────

/// Whether a [VoiceCallScreen] push from native accept is in progress.
bool _navigatingToCall = false;

bool get isNavigatingToCall => _navigatingToCall;

Map<String, String>? _pendingAcceptedCall;

const String _pendingAcceptFileName = 'pending_call_accept.json';

String? _documentsPath;

Future<File> _pendingAcceptFile() async {
  final dir = await getApplicationDocumentsDirectory();
  _documentsPath = dir.path;
  return File('${dir.path}/$_pendingAcceptFileName');
}

File? _pendingAcceptFileSync() {
  final path = _documentsPath;
  if (path == null) return null;
  return File('$path/$_pendingAcceptFileName');
}

Future<void> _persistPendingAcceptToFile(Map<String, String> payload) async {
  try {
    final file = await _pendingAcceptFile();
    file.writeAsStringSync(jsonEncode(payload));
    AppLogger.i(
      '[NativeCallCoordinator] pending accept persisted to file',
    );
  } catch (e) {
    AppLogger.e('[NativeCallCoordinator] pending accept persist failed: $e');
  }
}

Map<String, String>? _parsePendingAcceptPayload(Object? decoded) {
  if (decoded is! Map) return null;
  final channel = decoded['channelName']?.toString() ?? '';
  if (channel.isEmpty) return null;
  return Map<String, String>.from(
    decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
  );
}

Future<Map<String, String>?> _readPendingAcceptFromFile() async {
  try {
    final file = await _pendingAcceptFile();
    if (!file.existsSync()) return null;
    final text = file.readAsStringSync();
    return _parsePendingAcceptPayload(jsonDecode(text));
  } catch (_) {
    return null;
  }
}

Map<String, String>? _readPendingAcceptFromFileSync() {
  try {
    final file = _pendingAcceptFileSync();
    if (file == null || !file.existsSync()) return null;
    final text = file.readAsStringSync();
    return _parsePendingAcceptPayload(jsonDecode(text));
  } catch (_) {
    return null;
  }
}

Future<void> _clearPendingAcceptFile() async {
  try {
    final file = await _pendingAcceptFile();
    if (file.existsSync()) {
      file.deleteSync();
    }
  } catch (_) {}
}

/// Queued native decline/timeout before Riverpod is ready ([consumePendingDeclined]).
class PendingDecline {
  const PendingDecline({required this.callerId, this.noAnswer = false});
  final String callerId;
  final bool noAnswer;
}

PendingDecline? _pendingDeclined;

Map<String, String>? consumePendingAcceptedCall() {
  if (_pendingAcceptedCall != null) {
    final data = _pendingAcceptedCall;
    _pendingAcceptedCall = null;
    return data;
  }
  final fromFile = _readPendingAcceptFromFileSync();
  _pendingAcceptedCall = null;
  return fromFile;
}

PendingDecline? consumePendingDeclined() {
  final p = _pendingDeclined;
  _pendingDeclined = null;
  return p;
}

/// Drops queued native decline before a new outgoing ring (SOS callback).
void clearQueuedNativeDecline() {
  _pendingDeclined = null;
}

abstract final class NativeCallCoordinator {
  /// Subscribe to CallKit **before** async Firebase init so cold-start accept
  /// events are not dropped.
  static void registerEarlyListeners() {
    FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;
      AppLogger.i('📞 CallKit event: ${event.event}');

      final eventName = event.event.toString().toLowerCase();
      if (eventName.contains('start') && eventName.contains('call')) {
        AppLogger.i('✅ Call START event treated as ACCEPT');
        await _handleAcceptedCallEvent(event);
        return;
      }

      switch (event.event) {
        case Event.actionCallAccept:
          await _handleAcceptedCallEvent(event);
          break;

        case Event.actionCallDecline:
          AppLogger.w('❌ Call DECLINED from native call screen');
          final declineCallerId = await _resolveCallerIdFromEvent(event);
          _pendingAcceptedCall = null;
          unawaited(_clearPendingAcceptFile());
          final c = CallingScope.riverpod;
          if (c != null) {
            final notifier = c.read(callProvider.notifier);
            final currentState = c.read(callProvider);
            if (currentState.status == CallStatus.ringing) {
              notifier.declineCall();
            } else if (currentState.status == CallStatus.calling ||
                currentState.status == CallStatus.connecting ||
                currentState.status == CallStatus.connected) {
              AppLogger.w(
                '❌ Ignoring stale CallKit decline while '
                '${currentState.status} (outgoing/active session)',
              );
            } else if (declineCallerId.isNotEmpty) {
              AppLogger.w(
                '❌ Decline via HTTP fallback (cold-start, state=${currentState.status})',
              );
              notifier.declineCallFromCallerId(declineCallerId);
            }
          } else if (declineCallerId.isNotEmpty) {
            _pendingDeclined = PendingDecline(callerId: declineCallerId);
            AppLogger.w(
              '❌ Decline queued (container not ready) for callerId=$declineCallerId',
            );
            await _sendBackgroundDecline(declineCallerId, noAnswer: false);
            await CallKitService.instance.endCurrentCall();
          }
          break;

        case Event.actionCallTimeout:
          AppLogger.w('⏰ Call TIMEOUT from native call screen');
          final timeoutCallerId = await _resolveCallerIdFromEvent(event);
          _pendingAcceptedCall = null;
          unawaited(_clearPendingAcceptFile());
          final c = CallingScope.riverpod;
          if (c != null) {
            final currentState = c.read(callProvider);
            if (currentState.status == CallStatus.ringing) {
              c.read(callProvider.notifier).declineCallAsNoAnswer();
            } else if (timeoutCallerId.isNotEmpty) {
              AppLogger.w(
                '⏰ Timeout via HTTP fallback (cold-start, state=${currentState.status})',
              );
              c
                  .read(callProvider.notifier)
                  .declineCallFromCallerId(timeoutCallerId, noAnswer: true);
            }
          } else if (timeoutCallerId.isNotEmpty) {
            _pendingDeclined =
                PendingDecline(callerId: timeoutCallerId, noAnswer: true);
            AppLogger.w(
              '⏰ Timeout decline queued (container not ready) for callerId=$timeoutCallerId',
            );
            await _sendBackgroundDecline(timeoutCallerId, noAnswer: true);
            await CallKitService.instance.endCurrentCall();
          }
          break;

        case Event.actionCallToggleAudioSession:
          final body = event.body;
          final isActivate = body is Map && body['isActivate'] == true;
          if (isActivate) {
            unawaited(AgoraRtcService.instance.onCallKitAudioSessionActivated());
            final c = CallingScope.riverpod;
            if (c != null &&
                c.read(callProvider).status == CallStatus.ringing) {
              AppLogger.i(
                '📞 CallKit audio session active while ringing — accepting',
              );
              unawaited(c.read(callProvider.notifier).acceptCall());
              _navigatingToCall = true;
              _navigateToVoiceCallScreen();
            }
          }
          break;

        case Event.actionCallEnded:
          AppLogger.i('📵 Call ENDED from native call screen');
          final endedCallerId = await _resolveCallerIdFromEvent(event);
          final c = CallingScope.riverpod;
          if (c != null) {
            final notifier = c.read(callProvider.notifier);
            final currentState = c.read(callProvider);
            // iOS dismisses the incoming CallKit UI with actionCallEnded right
            // after accept — must not decline/end the session we just started.
            if (isNavigatingToCall ||
                _pendingAcceptedCall != null ||
                currentState.status == CallStatus.connecting ||
                currentState.status == CallStatus.connected) {
              AppLogger.i(
                '📵 Ignoring CallKit ended during accept/active call '
                '(status=${currentState.status})',
              );
              break;
            }
            switch (currentState.status) {
              case CallStatus.ringing:
                notifier.declineCall();
              case CallStatus.calling:
                if (notifier.shouldIgnoreStaleCallKitTeardown()) {
                  AppLogger.w(
                    '📵 Ignoring stale CallKit end during outgoing grace',
                  );
                } else {
                  unawaited(notifier.cancelOutgoingRing());
                }
              case CallStatus.connecting:
              case CallStatus.connected:
                notifier.endCall();
              default:
                break;
            }
          } else if (endedCallerId.isNotEmpty && c == null) {
            if (_pendingAcceptedCall == null) {
              _pendingDeclined = PendingDecline(callerId: endedCallerId);
              AppLogger.w(
                '📵 Ended mapped to queued decline (container not ready) for callerId=$endedCallerId',
              );
              await _sendBackgroundDecline(endedCallerId, noAnswer: false);
            }
            await CallKitService.instance.endCurrentCall();
          }
          _pendingAcceptedCall = null;
          unawaited(_clearPendingAcceptFile());
          await CallKitService.instance.clearLocalCallTracking();
          break;

        default:
          break;
      }
    });
  }

  /// Clears durable accept payload after [call-answer] is emitted.
  static Future<void> clearPendingAcceptFileAfterAnswer() async {
    await _clearPendingAcceptFile();
    AppLogger.i(
      '[NativeCallCoordinator] pending accept consumed and file cleared',
    );
  }

  /// If user accepted from native UI before Flutter ran, restore pending join.
  static Future<void> recoverAcceptedCallOnStartup() async {
    try {
      final fromFile = await _readPendingAcceptFromFile();
      if (fromFile != null) {
        _pendingAcceptedCall = fromFile;
        AppLogger.i(
          '📞 Startup recovery: restored pending accepted call from file',
        );
        return;
      }

      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls is List && activeCalls.isNotEmpty) {
        final pending = await CallKitService.readRecentPendingIncomingCall(
          maxAgeSeconds: 90,
        );
        if (pending != null && (pending['channelName'] ?? '').isNotEmpty) {
          _pendingAcceptedCall = {
            'callerId': pending['callerId'] ?? '',
            'callerName': (pending['callerName'] ?? '').isNotEmpty
                ? (pending['callerName'] ?? 'Unknown')
                : 'Unknown',
            'channelName': pending['channelName'] ?? '',
            'callerRole': pending['callerRole'] ?? '',
          };
          AppLogger.i(
            '📞 Startup recovery: restored pending accepted call from persisted CallKit payload',
          );
        }
      } else {
        await CallKitService.readRecentPendingIncomingCall(maxAgeSeconds: 90);
      }
    } catch (e) {
      AppLogger.e('📞 Startup recovery failed: $e');
    }
  }

  /// FCM foreground: call control (`call_declined`, `call_cancel`, `call_ended`, `call_answered`).
  static void handleForegroundCallControl(Map<String, dynamic> data) {
    final dataType = CallKitService.fcmCallControlType(data);
    if (dataType == null) return;

    if (dataType == 'call_answered') {
      AppLogger.w('📞 FCM call_answered received foreground');
      final c = CallingScope.riverpod;
      if (c != null) {
        final notifier = c.read(callProvider.notifier);
        notifier.handleFcmCallAnswered(
          answererId: data['callerId']?.toString(),
          callRecordId: data['callRecordId']?.toString(),
        );
      }
      return;
    }

    AppLogger.w('📵 FCM $dataType — stopping call');
    final endReason = switch (dataType) {
      'call_cancel' => 'cancelled',
      'call_ended' => 'ended',
      _ => 'declined',
    };
    if (dataType == 'call_cancel') {
      unawaited(
        CallKitService.dismissNativeIncoming(
          callerId: data['callerId']?.toString(),
          callRecordId: data['callRecordId']?.toString(),
        ),
      );
    }
    final c = CallingScope.riverpod;
    if (c != null) {
      final notifier = c.read(callProvider.notifier);
      final cs = c.read(callProvider);
      if (cs.isInCall) {
        if (notifier.shouldIgnoreStaleCallControlFcm(dataType)) {
          AppLogger.w(
            '📵 Ignoring stale FCM $dataType during outgoing grace',
          );
          return;
        }
        notifier.stopLocalCallSession(endReason: endReason);
        return;
      }
    }

    unawaited(CallKitService.persistPendingOutgoingStop(endReason));
    unawaited(CallKitService.instance.endCurrentCall());
  }
}

Future<void> _handleAcceptedCallEvent(CallEvent event) async {
  AppLogger.i('✅ Call ACCEPTED from native call screen');

  String channelName = _extractCallEventValue(event, 'channelName');
  String callerId = _extractCallEventValue(event, 'callerId');
  String callerName = _extractCallEventValue(event, 'callerName');
  String callerRole = _extractCallEventValue(event, 'callerRole');

  if (channelName.isEmpty || callerId.isEmpty) {
    final pending = await CallKitService.readRecentPendingIncomingCall(
      maxAgeSeconds: 90,
    );
    if (pending != null) {
      channelName = channelName.isNotEmpty
          ? channelName
          : (pending['channelName'] ?? '');
      callerId = callerId.isNotEmpty ? callerId : (pending['callerId'] ?? '');
      callerName = callerName.isNotEmpty
          ? callerName
          : (pending['callerName'] ?? '');
      callerRole = callerRole.isNotEmpty
          ? callerRole
          : (pending['callerRole'] ?? '');
      AppLogger.i('📞 Accept payload recovered from persisted pending call');
    }
  }

  final acceptPayload = {
    'callerId': callerId,
    'callerName': callerName.isNotEmpty ? callerName : 'Unknown',
    'channelName': channelName,
    'callerRole': callerRole,
  };
  await _persistPendingAcceptToFile(acceptPayload);
  _pendingAcceptedCall = acceptPayload;

  AppLogger.i(
    '📞 Accept parsed: callerId=$callerId, channel=$channelName, name=$callerName',
  );

  final c = CallingScope.riverpod;
  if (c != null && channelName.isNotEmpty) {
    final notifier = c.read(callProvider.notifier);
    final currentState = c.read(callProvider);

    if (currentState.status == CallStatus.ringing) {
      _navigatingToCall = true;
      notifier.acceptCall();
      _navigateToVoiceCallScreen();
    } else if (!currentState.isInCall) {
      _navigatingToCall = true;
      notifier.acceptCallFromFcm(
        callerId: callerId,
        callerName: callerName.isNotEmpty ? callerName : 'Unknown',
        channelName: channelName,
      );
      _navigateToVoiceCallScreen();
    }
  }
}

Future<String> _resolveCallerIdFromEvent(CallEvent event) async {
  final fromEvent = _extractCallEventValue(event, 'callerId');
  if (fromEvent.isNotEmpty) return fromEvent;

  final pending = await CallKitService.readRecentPendingIncomingCall(
    maxAgeSeconds: 120,
  );
  return pending?['callerId'] ?? '';
}

String _extractCallEventValue(CallEvent event, String key) {
  final body = event.body;
  if (body is! Map) return '';

  dynamic value = body[key];

  if (value == null) {
    final extra = body['extra'];
    if (extra is Map) value = extra[key];
  }

  if (value == null) {
    final nestedBody = body['body'];
    if (nestedBody is Map) {
      value = nestedBody[key];
      if (value == null) {
        final nestedExtra = nestedBody['extra'];
        if (nestedExtra is Map) value = nestedExtra[key];
      }
    }
  }

  if (value == null) {
    final data = body['data'];
    if (data is Map) {
      value = data[key];
      if (value == null) {
        final dataExtra = data['extra'];
        if (dataExtra is Map) value = dataExtra[key];
      }
    }
  }

  return value?.toString() ?? '';
}

void _navigateToVoiceCallScreen() {
  _tryPushVoiceCall(attemptsLeft: 15);
}

void _tryPushVoiceCall({required int attemptsLeft}) {
  if (attemptsLeft <= 0) {
    _navigatingToCall = false;
    AppLogger.w(
      '📞 All navigation retries exhausted — relying on dashboard fallback',
    );
    return;
  }
  if (VoiceCallScreen.isActive) {
    _navigatingToCall = false;
    AppLogger.d('📞 VoiceCallScreen already active — skipping push');
    return;
  }
  final pushed = openVoiceCallScreen(bypassNavigatingGuard: true);
  if (pushed != null) {
    unawaited(
      pushed.then((_) {
        _navigatingToCall = false;
      }),
    );
    AppLogger.i(
      '📞 Navigated to VoiceCallScreen (attempt ${16 - attemptsLeft})',
    );
    return;
  }
  Future.delayed(const Duration(milliseconds: 400), () {
    _tryPushVoiceCall(attemptsLeft: attemptsLeft - 1);
  });
}

Future<void> _sendBackgroundDecline(
  String callerId, {
  bool noAnswer = false,
}) async {
  if (callerId.isEmpty) return;
  try {
    String baseUrl = kDefaultProductionApiBaseUrl;
    String declinerId = '';
    String callRecordId = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('api_base_url');
      if (cached != null && cached.isNotEmpty) baseUrl = cached;
      declinerId =
          (await SecureSessionStore.getUserId()) ??
          prefs.getString('user_id') ??
          '';
      callRecordId = prefs.getString('pending_call_record_id') ?? '';
    } catch (_) {}

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    await dio.post('/call-history/decline', data: {
      'callerId': callerId,
      if (declinerId.isNotEmpty) 'declinerId': declinerId,
      if (callRecordId.isNotEmpty) 'callRecordId': callRecordId,
      if (noAnswer) 'noAnswer': true,
    });
    AppLogger.w(
      '[NativeCall] Background HTTP decline sent to $callerId url=$baseUrl',
    );
  } catch (e) {
    AppLogger.e('Failed to send background decline: $e');
  }
}
