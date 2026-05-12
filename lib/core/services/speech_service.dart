import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../utils/app_logger.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SpeechService
// Hybrid TTS: Cloud MP3 (just_audio) primary → flutter_tts fallback.
//
// Usage (foreground & background):
//   await SpeechService.playRobust(audioUrl: url, backupText: text, lang: 'ur');
//   await SpeechService.stop();
//
// Urgent repetition (background handler):
//   await SpeechService.playUrgentLoop(audioUrl: url, backupText: text, lang: 'ur');
// ─────────────────────────────────────────────────────────────────────────────

enum _CloudPlayResult { success, failed, cancelled }

class SpeechService {
  SpeechService._(); // static-only class

  // Shared dismiss flag key (written by UI, read by background loop).
  static const _dismissedKey = 'speech_service_tts_dismissed';
  static const _lastSpokenIdKey = 'speech_service_last_spoken_id_v1';
  static const _lastSpokenMsKey = 'speech_service_last_spoken_ms_v1';

  /// Incremented on every [stop]. In-flight cloud/local play compares to the
  /// epoch captured after the opening [stop] in [playRobust]; a mismatch
  /// means the user hit Stop (or a new play preempted) — do not run TTS
  /// fallback for an aborted cloud attempt.
  static int _playbackEpoch = 0;

  // Active player reference — allows stop() to interrupt cloud playback.
  static AudioPlayer? _activePlayer;
  static FlutterTts? _activeTts;

  // ── Public: play once (cloud with local fallback) ─────────────────────────

  /// Attempts to stream [audioUrl] (GCS MP3). Falls back to [flutter_tts]
  /// speaking [backupText] if:
  ///   • [audioUrl] is null
  ///   • the cloud URL fails to buffer within 5 s
  ///   • any [PlayerException] is thrown
  ///
  /// [lang] is a BCP-47 short code ('en', 'ar', 'ur') used for the
  /// flutter_tts fallback language selection.
  @pragma('vm:entry-point')
  static Future<void> playRobust({
    required String? audioUrl,
    required String backupText,
    String lang = 'en',
    bool isUrgent = false,
    String? messageKey,
    Duration dedupeWindow = const Duration(seconds: 20),
  }) async {
    if (messageKey != null && messageKey.isNotEmpty) {
      final shouldSpeak = await _claimMessageSpeakOnce(
        messageKey,
        window: dedupeWindow,
      );
      if (!shouldSpeak) {
        AppLogger.i('[Speech] Deduped messageKey=$messageKey — skipping');
        return;
      }
    }

    // Avoid overlapping playback: always stop current speech/audio first.
    await stop();

    final playEpoch = _playbackEpoch;

    await _configureAudioSession(isUrgent: isUrgent);

    if (_playbackEpoch != playEpoch) return;

    if (audioUrl != null && audioUrl.isNotEmpty) {
      final cloud = await _tryCloudPlay(audioUrl, playEpoch);
      if (cloud == _CloudPlayResult.success) return;
      if (cloud == _CloudPlayResult.cancelled) return;
    }

    if (_playbackEpoch != playEpoch) return;

    // Cloud unavailable or skipped — use device TTS
    AppLogger.i('[Speech] Using local flutter_tts fallback');
    await _speakLocal(backupText, lang, playEpoch);
  }

  // ── Public: urgent repetition loop (background handler) ──────────────────

  /// Plays the TTS 3 times, 2 minutes apart, while holding a CPU WakeLock.
  /// Breaks early if the user taps "Dismiss" (checked via SharedPreferences).
  @pragma('vm:entry-point')
  static Future<void> playUrgentLoop({
    required String? audioUrl,
    required String backupText,
    String lang = 'en',
  }) async {
    // Clear any stale dismiss flag from a previous urgent message.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dismissedKey, false);
    } catch (_) {}

    // Acquire WakeLock to keep CPU alive through the full 3×2-min window.
    bool wakelockEnabled = false;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await WakelockPlus.enable();
        wakelockEnabled = true;
        AppLogger.i('[Speech] WakeLock acquired for urgent loop');
      }
    } catch (e) {
      AppLogger.w('[Speech] Could not acquire WakeLock: $e');
    }

    try {
      for (int i = 0; i < 3; i++) {
        // ── Check dismiss before each play ────────────────────────────────
        if (await _isDismissed()) {
          AppLogger.i('[Speech] Loop dismissed at iteration $i — stopping');
          break;
        }

        AppLogger.i('[Speech] Urgent loop iteration ${i + 1}/3');
        await playRobust(
          audioUrl: audioUrl,
          backupText: backupText,
          lang: lang,
          isUrgent: true,
        );

        // Don't wait after the last repetition
        if (i < 2) {
          // Wait 2 min, but poll for dismiss every 10 s to stay responsive
          for (int s = 0; s < 120; s += 10) {
            await Future.delayed(const Duration(seconds: 10));
            if (await _isDismissed()) {
              AppLogger.i('[Speech] Dismissed during wait — breaking loop');
              return;
            }
          }
        }
      }
    } finally {
      if (wakelockEnabled) {
        try {
          await WakelockPlus.disable();
          AppLogger.i('[Speech] WakeLock released');
        } catch (_) {}
      }
    }
  }

  // ── Public: stop ──────────────────────────────────────────────────────────

  /// Stops any in-progress cloud playback or TTS speech and marks dismissed.
  static Future<void> stop() async {
    _playbackEpoch++;

    try {
      await _activePlayer?.stop();
      _activePlayer?.dispose();
      _activePlayer = null;
    } catch (_) {}

    try {
      await _activeTts?.stop();
      _activeTts = null;
    } catch (_) {}

    // Set dismiss flag so any ongoing background loop breaks early
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_dismissedKey, true);
    } catch (_) {}
  }

  // ── Internal: cloud playback ──────────────────────────────────────────────

  static Future<_CloudPlayResult> _tryCloudPlay(
    String url,
    int playEpoch,
  ) async {
    final player = AudioPlayer();
    _activePlayer = player;

    try {
      AppLogger.i('[Speech] Loading cloud audio: $url');

      // 5-second timeout for initial buffer. On slow networks this prevents
      // the pilgrim waiting indefinitely before hearing anything.
      await player.setUrl(url).timeout(const Duration(seconds: 5));
      if (_playbackEpoch != playEpoch) {
        AppLogger.i('[Speech] Cloud load cancelled (stop)');
        return _CloudPlayResult.cancelled;
      }

      await player.play();

      // Require playback to actually start promptly. Some devices/networks
      // can hang after setUrl/play without ever emitting completed.
      await player.playingStream
          .firstWhere((isPlaying) => isPlaying == true)
          .timeout(const Duration(seconds: 4));
      if (_playbackEpoch != playEpoch) {
        AppLogger.i('[Speech] Cloud start cancelled (stop)');
        return _CloudPlayResult.cancelled;
      }

      // Wait for real completion only — `idle` can appear too early on some
      // streams and would skip cloud audio in favour of device TTS wrongly.
      await player.processingStateStream
          .firstWhere((s) => s == ProcessingState.completed)
          .timeout(const Duration(seconds: 120));

      AppLogger.i('[Speech] ✓ Cloud audio playback complete');
      return _CloudPlayResult.success;
    } on TimeoutException {
      if (_playbackEpoch != playEpoch) {
        AppLogger.i('[Speech] Cloud wait cancelled (stop)');
        return _CloudPlayResult.cancelled;
      }
      AppLogger.w('[Speech] Cloud audio timed out — using local TTS');
      return _CloudPlayResult.failed;
    } on PlayerException catch (e) {
      if (_playbackEpoch != playEpoch) {
        AppLogger.i('[Speech] Cloud player cancelled (stop)');
        return _CloudPlayResult.cancelled;
      }
      AppLogger.w(
        '[Speech] Cloud PlayerException (${e.message}) — using local TTS',
      );
      return _CloudPlayResult.failed;
    } catch (e) {
      if (_playbackEpoch != playEpoch) {
        AppLogger.i('[Speech] Cloud playback cancelled (stop)');
        return _CloudPlayResult.cancelled;
      }
      AppLogger.w('[Speech] Cloud audio error ($e) — using local TTS');
      return _CloudPlayResult.failed;
    } finally {
      try {
        await player.stop();
        player.dispose();
      } catch (_) {}
      if (_activePlayer == player) _activePlayer = null;
    }
  }

  // ── Internal: local TTS fallback ─────────────────────────────────────────

  /// Configures [tts] for [shortLang] (`en`, `ar`, …). Call before
  /// [FlutterTts.speak]. Returns false when no engine is available.
  static Future<bool> bindFlutterTtsLocale(
    FlutterTts tts,
    String shortLang,
  ) async {
    final rawEngines = await tts.getEngines;
    final engines =
        rawEngines is List ? List<String>.from(rawEngines) : <String>[];
    if (engines.isEmpty) {
      AppLogger.w('[Speech] No TTS engines installed — skipping speech');
      return false;
    }

    final langToTry = _bcp47ForLang(shortLang);
    final langResult = await tts.isLanguageAvailable(langToTry);
    final langOk = langResult == 1 || langResult == true;

    if (langOk) {
      await tts.setLanguage(langToTry);
    } else {
      final enResult = await tts.isLanguageAvailable('en-US');
      if (enResult == 1 || enResult == true) {
        await tts.setLanguage('en-US');
      } else {
        await tts.setLanguage('en');
      }
    }

    await tts.awaitSpeakCompletion(true);
    await tts.setVolume(1.0);
    await tts.setSpeechRate(0.4);
    await tts.setPitch(1.0);
    return true;
  }

  @pragma('vm:entry-point')
  static Future<void> _speakLocal(
    String text,
    String lang,
    int playEpoch,
  ) async {
    if (text.isEmpty) return;
    if (_playbackEpoch != playEpoch) return;

    final tts = FlutterTts();
    _activeTts = tts;

    try {
      final langToTry = _bcp47ForLang(lang);
      final ready = await bindFlutterTtsLocale(tts, lang);
      if (!ready) return;
      if (_playbackEpoch != playEpoch) return;

      AppLogger.i('[Speech] Local TTS: "$text" (lang=$langToTry)');
      await tts.speak(text);
    } catch (e) {
      AppLogger.e('[Speech] Local TTS error: $e');
    } finally {
      try {
        await tts.stop();
      } catch (_) {}
      if (_activeTts == tts) _activeTts = null;
    }
  }

  // ── Internal: audio session config ───────────────────────────────────────

  /// Configures the audio session so the TTS/audio:
  ///  - Ducks other audio (e.g. music, podcast) — does NOT interrupt calls
  ///  - Speaks at spoken voice category on iOS
  static Future<void> _configureAudioSession({bool isUrgent = false}) async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
          avAudioSessionRouteSharingPolicy:
              AVAudioSessionRouteSharingPolicy.defaultPolicy,
          avAudioSessionSetActiveOptions:
              AVAudioSessionSetActiveOptions.none,
          androidAudioAttributes: const AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.assistanceAccessibility,
          ),
          androidAudioFocusGainType: isUrgent
              ? AndroidAudioFocusGainType.gainTransient
              : AndroidAudioFocusGainType.gainTransientMayDuck,
          androidWillPauseWhenDucked: false,
        ),
      );
    } catch (e) {
      AppLogger.w('[Speech] AudioSession config failed (non-fatal): $e');
    }
  }

  // ── Internal: helpers ─────────────────────────────────────────────────────

  static String _bcp47ForLang(String lang) {
    return switch (lang.toLowerCase()) {
      'ar' => 'ar-XA',
      'ur' => 'ur-IN',
      'fr' => 'fr-FR',
      'id' => 'id-ID',
      'tr' => 'tr-TR',
      _ => 'en-US',
    };
  }

  static Future<bool> _isDismissed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_dismissedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _claimMessageSpeakOnce(
    String messageKey, {
    required Duration window,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastId = prefs.getString(_lastSpokenIdKey);
      final lastMs = prefs.getInt(_lastSpokenMsKey) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      final isSameRecent =
          lastId == messageKey && (nowMs - lastMs) <= window.inMilliseconds;
      if (isSameRecent) return false;

      await prefs.setString(_lastSpokenIdKey, messageKey);
      await prefs.setInt(_lastSpokenMsKey, nowMs);
      return true;
    } catch (e) {
      AppLogger.w('[Speech] Dedupe storage failed (non-fatal): $e');
      return true; // fail-open: better to speak than to miss an urgent alert
    }
  }

  // ── Public: mark dismissed (called from UI dismiss button) ───────────────

  /// Call this when the pilgrim taps "Dismiss" or "Stop" on a TTS notification.
  static Future<void> markDismissed() async {
    await stop(); // also stops any active audio
  }
}
