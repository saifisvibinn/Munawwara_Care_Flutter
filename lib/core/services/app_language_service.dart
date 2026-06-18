import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../config/app_locales.dart';
import 'api_service.dart';
import 'callkit_service.dart';
import 'locale_prefs.dart';
import 'sos_alert_audio.dart';

/// Persists and applies in-app language changes (profile settings).
class AppLanguageService {
  AppLanguageService._();

  static AppLanguageOption? optionForCode(String code) {
    for (final lang in AppLocales.profileLanguages) {
      if (lang.code == code) return lang;
    }
    return null;
  }

  static String nativeNameForCode(String code) {
    return optionForCode(code)?.nativeName ?? code.toUpperCase();
  }

  static Future<void> apply(BuildContext context, String code) async {
    await context.setLocale(Locale(code));
    await LocalePrefs.saveLanguageCode(code);
    await SosAlertAudio.stopAndReset();
    unawaited(
      CallKitService.refreshCachedSupportDisplayName(languageCode: code),
    );
    await syncToBackend(code);
  }

  /// Aligns MongoDB [User.language] with the in-app locale so FCM titles match UI.
  static Future<void> syncToBackendIfNeeded({String? profileLanguage}) async {
    final local = (await LocalePrefs.readLanguageCode()).trim().toLowerCase();
    if (local.isEmpty) return;

    final profile = profileLanguage?.trim().toLowerCase() ?? '';
    if (profile.isNotEmpty && profile == local) return;

    await syncToBackend(local);
  }

  static Future<void> syncToBackend(String code) async {
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) return;
    if (!await ApiService.hasStoredAuthToken()) return;

    try {
      await ApiService.ensureAuthHeaderFromPrefs();
      await ApiService.dio.put(
        '/auth/update-language',
        data: {'language': normalized},
      );
    } catch (_) {
      // Non-fatal — local language is already applied.
    }
  }
}
