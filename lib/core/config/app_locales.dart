import 'package:flutter/material.dart';

/// Supported app UI languages (EasyLocalization + profile pickers).
class AppLocales {
  AppLocales._();

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('ar'),
    Locale('ur'),
    Locale('fr'),
    Locale('id'),
    Locale('tr'),
    Locale('fa'),
    Locale('ms'),
  ];

  static const List<String> liveTranslateLanguageCodes = [
    'en',
    'ar',
    'ur',
    'tr',
    'id',
    'fr',
    'fa',
    'ms',
  ];

  static const Set<String> rtlLanguageCodes = {'ar', 'ur', 'fa'};

  /// Whether [code] uses right-to-left text direction.
  static bool isRtl(String code) => rtlLanguageCodes.contains(code);

  /// Profile / login picker entries (native display names).
  static const List<AppLanguageOption> profileLanguages = [
    AppLanguageOption(
      code: 'en',
      menuLabel: 'English',
      nativeName: 'English',
      flag: '🇬🇧',
    ),
    AppLanguageOption(
      code: 'ar',
      menuLabel: 'العربية',
      nativeName: 'العربية',
      flag: '🇸🇦',
    ),
    AppLanguageOption(
      code: 'ur',
      menuLabel: 'اردو',
      nativeName: 'اردو',
      flag: '🇵🇰',
    ),
    AppLanguageOption(
      code: 'fr',
      menuLabel: 'Français',
      nativeName: 'Français',
      flag: '🇫🇷',
    ),
    AppLanguageOption(
      code: 'id',
      menuLabel: 'Bahasa',
      nativeName: 'Bahasa Indonesia',
      flag: '🇮🇩',
    ),
    AppLanguageOption(
      code: 'tr',
      menuLabel: 'Türkçe',
      nativeName: 'Türkçe',
      flag: '🇹🇷',
    ),
    AppLanguageOption(
      code: 'fa',
      menuLabel: 'فارسی',
      nativeName: 'فارسی',
      flag: '🇮🇷',
    ),
    AppLanguageOption(
      code: 'ms',
      menuLabel: 'Bahasa Melayu',
      nativeName: 'Bahasa Melayu',
      flag: '🇲🇾',
    ),
  ];

  /// Login screen menu: display label → locale.
  static Map<String, Locale> get loginMenuLocales => {
    for (final lang in profileLanguages)
      lang.menuLabel: Locale(lang.code),
  };

  static Locale localeForCode(String code) {
    return supportedLocales.firstWhere(
      (locale) => locale.languageCode == code,
      orElse: () => const Locale('en'),
    );
  }
}

class AppLanguageOption {
  final String code;
  final String menuLabel;
  final String nativeName;
  final String flag;

  const AppLanguageOption({
    required this.code,
    required this.menuLabel,
    required this.nativeName,
    required this.flag,
  });
}
