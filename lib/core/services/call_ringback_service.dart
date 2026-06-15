import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:audioplayers/audioplayers.dart' hide AVAudioSessionCategory;
import 'package:flutter/widgets.dart';

import '../utils/app_logger.dart';

/// Looped ringback for in-app outgoing and incoming pre-connect phases.
class CallRingbackService {
  CallRingbackService._();

  static final AudioPlayer _player = AudioPlayer();
  static bool _playing = false;

  static Future<void> start() async {
    if (_playing) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    try {
      await _configureAudioSession();
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      // Asset must exist at assets/static/ringbacktone.m4a (see pubspec.yaml).
      await _player.play(AssetSource('static/ringbacktone.m4a'));
      _playing = true;
    } catch (e) {
      // Missing asset or audio focus — non-fatal; call still works.
      AppLogger.w('[CallRingback] start failed (ignored): $e');
      _playing = false;
    }
  }

  static Future<void> stop() async {
    if (!_playing) {
      try {
        await _player.stop();
      } catch (_) {}
      await _deactivateAudioSession();
      return;
    }

    _playing = false;
    try {
      await _player.stop();
    } catch (e) {
      AppLogger.w('[CallRingback] stop failed: $e');
    }
    await _deactivateAudioSession();
  }

  static Future<void> _deactivateAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e) {
      AppLogger.w('[CallRingback] AudioSession deactivate failed: $e');
    }
  }

  static Future<void> _configureAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions:
              AVAudioSessionSetActiveOptions.none,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.voiceCommunication,
          ),
          androidAudioFocusGainType:
              AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );
      await session.setActive(true);
    } catch (e) {
      AppLogger.w('[CallRingback] AudioSession config failed: $e');
    }
  }
}
