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
    try {
      await ApiService.dio.put(
        '/auth/update-language',
        data: {'language': code},
      );
    } catch (_) {
      // Non-fatal — local language is already applied.
    }
  }
}
