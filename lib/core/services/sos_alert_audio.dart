import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'locale_prefs.dart';
import 'speech_service.dart';
import 'tts_cloud_api.dart';
import '../utils/app_logger.dart';

/// SOS moderator alert audio: one urgent chime, then one bundled language clip.
class SosAlertAudio {
  SosAlertAudio._();

  static const _urgentAsset = 'assets/static/urgent_tts.wav';
  static const _assetDir = 'assets/audio/sos';
  static const _dedupeWindow = Duration(seconds: 30);
  static const _chimeClaimPrefsKey = 'sos_chime_claim_v1';
  static const _languagePlayedKey = 'sos_language_played_v1';
  static const _pendingLanguageKey = 'sos_pending_language_v1';

  static final Set<String> _keysInFlight = {};

  /// True when the app UI is in the foreground.
  static bool get isAppInForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// Stops playback and clears gates (language change, SOS cancel).
  static Future<void> stopAndReset() async {
    _keysInFlight.clear();
    await SpeechService.markDismissed();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_chimeClaimPrefsKey);
      await prefs.remove(_languagePlayedKey);
      await prefs.remove(_pendingLanguageKey);
      await prefs.remove('sos_language_claim_v1');
      await prefs.remove('sos_bundled_claim_v2');
      await prefs.remove('sos_main_handled_v1');
      await prefs.remove('sos_main_language_played_v1');
    } catch (_) {}
  }

  static void resetPlayState() {
    _keysInFlight.clear();
  }

  static Future<void> markLanguagePlayed(String storageKey) async {
    if (storageKey.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _languagePlayedKey,
        '$storageKey|${DateTime.now().millisecondsSinceEpoch}',
      );
      await prefs.remove(_pendingLanguageKey);
    } catch (_) {}
  }

  static Future<bool> wasLanguagePlayed(String storageKey) async {
    if (storageKey.isEmpty) return false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString(_languagePlayedKey) ?? '';
      if (raw.isEmpty) return false;
      final parts = raw.split('|');
      if (parts.length < 2) return false;
      return parts[0] == storageKey &&
          nowMs - (int.tryParse(parts[1]) ?? 0) <= _dedupeWindow.inMilliseconds;
    } catch (_) {
      return false;
    }
  }

  /// Queue language MP3 for main isolate (iOS background isolate often cannot finish).
  static Future<void> queuePendingLanguagePlay(String storageKey) async {
    if (storageKey.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _pendingLanguageKey,
        '$storageKey|${DateTime.now().millisecondsSinceEpoch}',
      );
      AppLogger.i('[SosAlertAudio] Queued pending language $storageKey');
    } catch (e) {
      AppLogger.w('[SosAlertAudio] Pending language queue failed: $e');
    }
  }

  /// Play queued language clip after resume / foreground (iOS background fallback).
  static Future<void> consumePendingLanguagePlay() async {
    if (!isAppInForeground) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString(_pendingLanguageKey) ?? '';
      if (raw.isEmpty) return;

      final parts = raw.split('|');
      if (parts.length < 2) {
        await prefs.remove(_pendingLanguageKey);
        return;
      }

      final storageKey = parts[0];
      final queuedMs = int.tryParse(parts[1]) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (nowMs - queuedMs > _dedupeWindow.inMilliseconds) {
        await prefs.remove(_pendingLanguageKey);
        return;
      }
      if (await wasLanguagePlayed(storageKey)) {
        await prefs.remove(_pendingLanguageKey);
        return;
      }

      AppLogger.i('[SosAlertAudio] Consuming pending language $storageKey');
      await playLanguageIfNeeded(storageKey: storageKey);
    } catch (e) {
      AppLogger.w('[SosAlertAudio] consumePendingLanguagePlay failed: $e');
    }
  }

  static bool _tryAcquireInFlight(String storageKey) {
    if (storageKey.isEmpty) return false;
    if (_keysInFlight.contains(storageKey)) {
      AppLogger.i('[SosAlertAudio] In flight $storageKey');
      return false;
    }
    _keysInFlight.add(storageKey);
    return true;
  }

  static void _releaseInFlight(String storageKey) {
    _keysInFlight.remove(storageKey);
  }

  static Future<bool> _tryClaimChimePlayback(String storageKey) async {
    if (storageKey.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final raw = prefs.getString(_chimeClaimPrefsKey) ?? '';
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (raw.isNotEmpty) {
        final parts = raw.split('|');
        if (parts.length >= 2) {
          final id = parts[0];
          final ms = int.tryParse(parts[1]) ?? 0;
          if (id == storageKey && nowMs - ms <= _dedupeWindow.inMilliseconds) {
            AppLogger.i('[SosAlertAudio] Chime claim deduped $storageKey');
            return false;
          }
        }
      }
      await prefs.setString(_chimeClaimPrefsKey, '$storageKey|$nowMs');
      return true;
    } catch (e) {
      AppLogger.w('[SosAlertAudio] Chime claim failed: $e');
      return false;
    }
  }

  static bool _shouldPlayInAppChime({required bool fromBackgroundIsolate}) {
    if (Platform.isAndroid) return true;
    return !fromBackgroundIsolate;
  }

  static Future<String> _resolveLanguage({required bool fromBackgroundIsolate}) {
    if (fromBackgroundIsolate) {
      return _resolveBackgroundLanguage();
    }
    return LocalePrefs.readLanguageCode().then(TtsCloudApi.normalizeLang);
  }

  static Future<String> _resolveBackgroundLanguage() async {
    return TtsCloudApi.normalizeLang(await LocalePrefs.readLanguageCode());
  }

  static const _gapBeforeLanguage = Duration(milliseconds: 500);

  static bool _shouldAbortSequence(String storageKey) =>
      !_keysInFlight.contains(storageKey);

  static Future<bool> _playLanguageClip({
    required String storageKey,
    required bool fromBackgroundIsolate,
  }) async {
    if (await wasLanguagePlayed(storageKey)) {
      AppLogger.i('[SosAlertAudio] Language already played $storageKey');
      return false;
    }
    if (_shouldAbortSequence(storageKey)) return false;
    if (await SpeechService.isDismissed()) return false;

    final lang = await _resolveLanguage(fromBackgroundIsolate: fromBackgroundIsolate);
    final path = assetPathForLang(lang);
    AppLogger.i('[SosAlertAudio] Language clip (lang=$lang, path=$path)');
    final ok = await SpeechService.playAsset(assetPath: path, isUrgent: true);
    if (ok) {
      await markLanguagePlayed(storageKey);
    } else {
      AppLogger.w('[SosAlertAudio] Language clip failed $path');
      if (fromBackgroundIsolate || Platform.isIOS) {
        await queuePendingLanguagePlay(storageKey);
      }
    }
    return ok;
  }

  /// One urgent chime (platform-dependent), then one bundled language clip.
  static Future<void> playAlertSequence({
    required String storageKey,
    bool fromBackgroundIsolate = false,
  }) async {
    if (storageKey.isEmpty) return;

    if (await wasLanguagePlayed(storageKey)) {
      AppLogger.i(
        '[SosAlertAudio] Skip sequence (language already played) $storageKey',
      );
      return;
    }

    if (!fromBackgroundIsolate && !isAppInForeground) return;

    if (fromBackgroundIsolate) {
      await queuePendingLanguagePlay(storageKey);
    }

    if (!_tryAcquireInFlight(storageKey)) return;

    try {
      await SpeechService.clearDismissed();
      await SpeechService.stop();

      final playChime = _shouldPlayInAppChime(
        fromBackgroundIsolate: fromBackgroundIsolate,
      );
      if (playChime) {
        if (await _tryClaimChimePlayback(storageKey)) {
          AppLogger.i('[SosAlertAudio] Urgent chime: $_urgentAsset');
          await SpeechService.playAsset(assetPath: _urgentAsset, isUrgent: true);
        } else {
          AppLogger.i('[SosAlertAudio] Chime skipped (deduped) $storageKey');
        }

        if (_shouldAbortSequence(storageKey)) return;
        if (await SpeechService.isDismissed()) return;
        if (await wasLanguagePlayed(storageKey)) return;

        await Future.delayed(_gapBeforeLanguage);
      } else {
        AppLogger.i(
          '[SosAlertAudio] Chime skipped (iOS background — APNS chime)',
        );
      }

      final played = await _playLanguageClip(
        storageKey: storageKey,
        fromBackgroundIsolate: fromBackgroundIsolate,
      );
      if (!played && fromBackgroundIsolate) {
        await queuePendingLanguagePlay(storageKey);
      }
    } finally {
      _releaseInFlight(storageKey);
    }
  }

  /// Foreground-only language retry when chime/background path did not finish.
  static Future<void> playLanguageIfNeeded({
    required String storageKey,
  }) async {
    if (storageKey.isEmpty || !isAppInForeground) return;
    if (await wasLanguagePlayed(storageKey)) return;
    if (!_tryAcquireInFlight(storageKey)) return;
    try {
      await SpeechService.clearDismissed();
      await _playLanguageClip(
        storageKey: storageKey,
        fromBackgroundIsolate: false,
      );
    } finally {
      _releaseInFlight(storageKey);
    }
  }

  /// Asset path for [lang] (falls back to English file).
  static String assetPathForLang(String lang) {
    final code = TtsCloudApi.normalizeLang(lang);
    return '$_assetDir/$code.mp3';
  }
}
