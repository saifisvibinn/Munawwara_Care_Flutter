import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';

/// Short incoming-message sounds (separate from [SpeechService] / just_audio).
/// Stopping this player before TTS avoids Android audio-focus clashes that
/// were cutting cloud MP3 and forcing device fallback.
class IncomingChatSfx {
  IncomingChatSfx._();

  static final AudioPlayer _player = AudioPlayer();

  static Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  static void playUrgentAlarm() {
    unawaited(_playAsset('static/urgent_tts.wav'));
  }

  static void playNormalPop() {
    unawaited(_playAsset('static/in_app.mp3'));
  }

  static Future<void> _playAsset(String path) async {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    try {
      await stop();
      await _player.play(AssetSource(path));
    } catch (_) {}
  }

  static Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
