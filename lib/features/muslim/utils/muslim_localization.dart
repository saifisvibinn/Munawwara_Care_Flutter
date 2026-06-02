import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

import '../data/dua_i18n_repository.dart';
import '../models/muslim_models.dart';

bool muslimPrefersArabicContent(String languageCode) =>
    languageCode == 'ar' || languageCode == 'ur';

/// Du'a/azkār cards: Arabic locale shows Arabic text only (no Latin/English).
bool hideDuaEnglishAuxiliary(String languageCode) => languageCode == 'ar';

String localizedDuaTitle(DuaItem dua, String languageCode) {
  final repo = DuaI18nRepository.maybeLoaded;
  if (repo != null) return repo.title(dua, languageCode);
  return dua.title ?? '';
}

String localizedDuaSource(DuaItem dua, String languageCode) {
  final repo = DuaI18nRepository.maybeLoaded;
  if (repo != null) return repo.localizeSource(dua.source, languageCode);
  return dua.source;
}

bool muslimPrefersArabicContentFromContext(BuildContext context) =>
    muslimPrefersArabicContent(context.locale.languageCode);

String _trOrFallback(String key, String fallback) {
  final value = key.tr();
  return value == key ? fallback : value;
}


String localizedDuaCategoryName(DuaCategory category) =>
    _trOrFallback('muslim_dua_cat_${category.id}_name', category.name);

String localizedDuaCategoryDescription(DuaCategory category) =>
    _trOrFallback('muslim_dua_cat_${category.id}_desc', category.description);


/// Prayer id from UmmahAPI (e.g. fajr, dhuhr) → localized display name.
String localizedPrayerName(String key) {
  final id = key.trim().toLowerCase();
  if (id.isEmpty || id == 'none') return '';
  final fallback = id[0].toUpperCase() + id.substring(1);
  return _trOrFallback('muslim_prayer_$id', fallback);
}

String formatMinutesCountdownLocalized(int minutes) {
  if (minutes <= 0) return 'muslim_countdown_now'.tr();
  if (minutes < 60) {
    return 'muslim_countdown_min'.tr(args: ['$minutes']);
  }
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (m == 0) return 'muslim_countdown_h'.tr(args: ['$h']);
  return 'muslim_countdown_hm'.tr(args: ['$h', '$m']);
}

DateTime? parsePrayerIsoDate(String isoDate) {
  final parts = isoDate.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

/// 12-hour time with locale-appropriate AM/PM (or 24h where standard).
String formatPrayerTimeLocalized(String time24, Locale locale) {
  final parts = time24.split(':');
  if (parts.length < 2) return time24;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return time24;
  final dt = DateTime(2000, 1, 1, hour, minute);
  return DateFormat.jm(locale.toString()).format(dt);
}

String formatGregorianDateLocalized({
  required Locale locale,
  required String isoDate,
  required String apiFallback,
}) {
  final parsed = parsePrayerIsoDate(isoDate);
  if (parsed != null) {
    return DateFormat.yMMMMEEEEd(locale.toString()).format(parsed);
  }
  if (apiFallback.isNotEmpty) return apiFallback;
  return isoDate;
}

String formatHijriDateLocalized(HijriDate hijri) {
  if (hijri.day > 0 && hijri.month > 0 && hijri.year > 0) {
    final month = _trOrFallback(
      'muslim_hijri_month_${hijri.month}',
      hijri.monthName,
    );
    return 'muslim_hijri_date'.tr(
      namedArgs: {
        'day': '${hijri.day}',
        'month': month,
        'year': '${hijri.year}',
      },
    );
  }
  return hijri.formatted;
}

List<String> localizedQiblaCardinals() => [
      'muslim_qibla_north'.tr(),
      'muslim_qibla_east'.tr(),
      'muslim_qibla_south'.tr(),
      'muslim_qibla_west'.tr(),
    ];
