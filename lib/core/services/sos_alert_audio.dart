import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'locale_prefs.dart';
import 'speech_service.dart';
import 'tts_cloud_api.dart';
import '../utils/app_logger.dart';

/// SOS moderator alert audio (foreground urgent chime; background urgent + speech).
class SosAlertAudio {
  SosAlertAudio._();

  static const _urgentAsset = 'assets/static/urgent_tts.wav';
  static const _assetDir = 'assets/audio/sos';
  static const _dedupeWindow = Duration(seconds: 30);
  static const _bundledClaimPrefsKey = 'sos_bundled_claim_v2';
  static const _mainHandledPrefsKey = 'sos_main_handled_v1';

  static final Map<String, DateTime> _syncGateAt = {};
  static final Set<String> _keysInFlight = {};
  static final Map<String, int> _mainHandledAtMs = {};

  /// True when the app UI is in the foreground.
  static bool get isAppInForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// Stops playback and clears gates (language change, SOS cancel).
  static Future<void> stopAndReset() async {
    _keysInFlight.clear();
    _syncGateAt.clear();
    _mainHandledAtMs.clear();
    await SpeechService.stop();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_bundledClaimPrefsKey);
      await prefs.remove(_mainHandledPrefsKey);
    } catch (_) {}
  }

  static void resetPlayState() {
    _keysInFlight.clear();
    _syncGateAt.clear();
    _mainHandledAtMs.clear();
  }

  /// Main isolate handled SOS — background must not play language clip.
  static void markMainIsolateHandled(String storageKey) {
    if (storageKey.isEmpty) return;
    _mainHandledAtMs[storageKey] = DateTime.now().millisecondsSinceEpoch;
    unawaited(_persistMainHandled(storageKey));
  }

  static Future<void> _persistMainHandled(String storageKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _mainHandledPrefsKey,
        '$storageKey|${DateTime.now().millisecondsSinceEpoch}',
      );
    } catch (_) {}
  }

  static Future<bool> wasHandledByMainIsolate(String storageKey) async {
    if (storageKey.isEmpty) return false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final local = _mainHandledAtMs[storageKey];
    if (local != null && nowMs - local <= _dedupeWindow.inMilliseconds) {
      return true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs
          .reload(); // FIX: Ensure background isolate sees main isolate's claim
      final raw = prefs.getString(_mainHandledPrefsKey) ?? '';
      if (raw.isEmpty) return false;
      final parts = raw.split('|');
      if (parts.length < 2) return false;
      return parts[0] == storageKey &&
          nowMs - (int.tryParse(parts[1]) ?? 0) <= _dedupeWindow.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  /// Sync gate — must run before any await (prevents socket+FCM double play).
  static bool _tryAcquireSyncGate(String storageKey) {
    if (storageKey.isEmpty) return false;
    if (_keysInFlight.contains(storageKey)) {
      AppLogger.i('[SosAlertAudio] Sync gate: in flight $storageKey');
      return false;
    }
    final now = DateTime.now();
    final last = _syncGateAt[storageKey];
    if (last != null && now.difference(last) < _dedupeWindow) {
      AppLogger.i('[SosAlertAudio] Sync gate: deduped $storageKey');
      return false;
    }
    _keysInFlight.add(storageKey);
    _syncGateAt[storageKey] = now;
    return true;
  }

  static void _releaseSyncGate(String storageKey) {
    _keysInFlight.remove(storageKey);
  }

  static Future<bool> _tryClaimBundledPlayback(String storageKey) async {
    if (storageKey.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs
          .reload(); // FIX: Ensure background isolate sees foreground clears
      final raw = prefs.getString(_bundledClaimPrefsKey) ?? '';
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (raw.isNotEmpty) {
        final parts = raw.split('|');
        if (parts.length >= 2) {
          final id = parts[0];
          final ms = int.tryParse(parts[1]) ?? 0;
          if (id == storageKey && nowMs - ms <= _dedupeWindow.inMilliseconds) {
            AppLogger.i(
              '[SosAlertAudio] Prefs deduped (cross-isolate) $storageKey',
            );
            return false;
          }
        }
      }
      await prefs.setString(_bundledClaimPrefsKey, '$storageKey|$nowMs');
      return true;
    } catch (e) {
      AppLogger.w('[SosAlertAudio] Bundled claim failed: $e');
      return false;
    }
  }

  static Future<String> _resolveBackgroundLanguage() async {
    return TtsCloudApi.normalizeLang(await LocalePrefs.readLanguageCode());
  }

  /// Foreground: in-app urgent chime only (no language MP3).
  static Future<void> playForegroundUrgentOnly({
    required String storageKey,
  }) async {
    if (storageKey.isEmpty || !isAppInForeground) return;

    markMainIsolateHandled(storageKey);
    if (!_tryAcquireSyncGate(storageKey)) return;

    try {
      await SpeechService.stop();
      AppLogger.i('[SosAlertAudio] Foreground urgent: $_urgentAsset');
      await SpeechService.playAsset(assetPath: _urgentAsset, isUrgent: true);
    } finally {
      _releaseSyncGate(storageKey);
    }
  }

  /// Background: urgent wav then one language MP3 (prefs language at play time).
  static Future<void> playBackgroundSequence({
    required String storageKey,
  }) async {
    if (storageKey.isEmpty) return;

    if (await wasHandledByMainIsolate(storageKey)) {
      AppLogger.i(
        '[SosAlertAudio] Skip background sequence (main handled) $storageKey',
      );
      return;
    }

    if (!_tryAcquireSyncGate(storageKey)) return;

    try {
      if (!await _tryClaimBundledPlayback(storageKey)) return;

      await SpeechService.stop();

      AppLogger.i('[SosAlertAudio] Background urgent: $_urgentAsset');
      await SpeechService.playAsset(assetPath: _urgentAsset, isUrgent: true);

      if (await wasHandledByMainIsolate(storageKey)) return;

      await Future.delayed(const Duration(seconds: 3));

      final lang = await _resolveBackgroundLanguage();
      final path = assetPathForLang(lang);
      AppLogger.i(
        '[SosAlertAudio] Background language (lang=$lang, path=$path)',
      );
      await SpeechService.playAsset(assetPath: path, isUrgent: true);
    } finally {
      _releaseSyncGate(storageKey);
    }
  }

  /// Asset path for [lang] (falls back to English file).
  static String assetPathForLang(String lang) {
    final code = TtsCloudApi.normalizeLang(lang);
    return '$_assetDir/$code.mp3';
  }
}
