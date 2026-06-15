import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../utils/app_logger.dart';
import 'agora_rtc_service.dart';

/// Bridges iOS CallKit `didActivate` / `didDeactivate` to Dart + Agora.
///
/// Apple: do not start call audio until the system elevates AVAudioSession
/// ([CXProviderDelegate.provider(_:didActivate:)]).
abstract final class CallKitAudioBridge {
  static const MethodChannel _channel =
      MethodChannel('com.munawwaracare/callkit_audio');

  static bool _activated = false;
  static Completer<void>? _waiter;

  /// Set from [main] to route native decline without circular imports.
  static void Function(Map<String, dynamic> payload)? onNativeCallDeclined;

  /// Register before async startup so native didActivate is not missed.
  static void registerEarly() {
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'audioSessionActivated':
          await _onActivated(source: 'native');
        case 'audioSessionDeactivated':
          _onDeactivated();
        case 'callDeclined':
          final raw = call.arguments;
          final payload = raw is Map
              ? Map<String, dynamic>.from(raw)
              : <String, dynamic>{};
          AppLogger.i('[CallKitAudio] Native decline payload=$payload');
          onNativeCallDeclined?.call(payload);
        default:
          break;
      }
    });
  }

  /// Plugin event-channel fallback (same moment as native didActivate).
  static Future<void> onPluginAudioSessionActivated() async {
    if (!Platform.isIOS) return;
    await _onActivated(source: 'plugin');
  }

  static void onPluginAudioSessionDeactivated() {
    if (!Platform.isIOS) return;
    _onDeactivated();
  }

  static Future<void> _onActivated({required String source}) async {
    _activated = true;
    AppLogger.i('[CallKitAudio] Session activated ($source)');
    await AgoraRtcService.instance.onCallKitAudioSessionActivated();
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
    _waiter = null;
  }

  static void _onDeactivated() {
    _activated = false;
    AppLogger.i('[CallKitAudio] Session deactivated');
    unawaited(AgoraRtcService.instance.onCallKitAudioSessionDeactivated());
  }

  static void reset() {
    _activated = false;
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(StateError('call ended'));
    }
    _waiter = null;
  }

  /// Wait for CallKit audio only when a native call UI session is active.
  static Future<void> ensureReadyBeforeMediaJoin() async {
    if (!Platform.isIOS) return;

    final hasCallKitSession = await _hasActiveCallKitSession();
    if (!hasCallKitSession) {
      return;
    }

    if (_activated) {
      await AgoraRtcService.instance.onCallKitAudioSessionActivated();
      return;
    }

    _waiter = Completer<void>();
    try {
      await _waiter!.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      AppLogger.w(
        '[CallKitAudio] Activation timeout — joining Agora with handoff fallback',
      );
      await AgoraRtcService.instance.onCallKitAudioSessionActivated();
    } catch (_) {
      // reset / call ended while waiting
    } finally {
      _waiter = null;
    }
  }

  static Future<bool> _hasActiveCallKitSession() async {
    try {
      final raw = await FlutterCallkitIncoming.activeCalls();
      return raw is List && raw.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
