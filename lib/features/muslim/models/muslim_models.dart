import '../constants/asma_arabic_translations.dart';

class PrayerTimesData {
  final String date;
  final Map<String, String> prayerTimes;
  final CurrentPrayerStatus currentStatus;
  final HijriDate? hijri;

  const PrayerTimesData({
    required this.date,
    required this.prayerTimes,
    required this.currentStatus,
    this.hijri,
  });

  factory PrayerTimesData.fromJson(Map<String, dynamic> json) {
    final timesRaw = json['prayer_times'] as Map<String, dynamic>? ?? {};
    final times = timesRaw.map((k, v) => MapEntry(k, v.toString()));
    return PrayerTimesData(
      date: json['date']?.toString() ?? '',
      prayerTimes: times,
      currentStatus: CurrentPrayerStatus.fromJson(
        json['current_status'] as Map<String, dynamic>? ?? {},
      ),
      hijri: json['hijri'] != null
          ? HijriDate.fromJson(json['hijri'] as Map<String, dynamic>)
          : null,
    );
  }
}

class CurrentPrayerStatus {
  final String currentPrayer;
  final String nextPrayer;
  final int minutesUntilNext;
  final String timeUntilNext;

  const CurrentPrayerStatus({
    required this.currentPrayer,
    required this.nextPrayer,
    required this.minutesUntilNext,
    required this.timeUntilNext,
  });

  factory CurrentPrayerStatus.fromJson(Map<String, dynamic> json) {
    return CurrentPrayerStatus(
      currentPrayer: json['current_prayer']?.toString() ?? 'none',
      nextPrayer: json['next_prayer']?.toString() ?? '',
      minutesUntilNext: (json['minutes_until_next'] as num?)?.toInt() ?? 0,
      timeUntilNext: json['time_until_next']?.toString() ?? '',
    );
  }
}

class HijriDate {
  final String formatted;
  final String date;
  final int day;
  final int month;
  final String monthName;
  final int year;

  const HijriDate({
    required this.formatted,
    required this.date,
    required this.day,
    required this.month,
    required this.monthName,
    required this.year,
  });

  factory HijriDate.fromJson(Map<String, dynamic> json) {
    return HijriDate(
      formatted: json['formatted']?.toString() ?? '',
      date: json['date']?.toString() ?? '',
      day: (json['day'] as num?)?.toInt() ?? 0,
      month: (json['month'] as num?)?.toInt() ?? 0,
      monthName: json['month_name']?.toString() ?? '',
      year: (json['year'] as num?)?.toInt() ?? 0,
    );
  }
}

class TodayHijriData {
  final HijriDate hijri;
  final String gregorianFormatted;

  const TodayHijriData({
    required this.hijri,
    required this.gregorianFormatted,
  });

  factory TodayHijriData.fromJson(Map<String, dynamic> json) {
    final greg = json['gregorian'] as Map<String, dynamic>? ?? {};
    return TodayHijriData(
      hijri: HijriDate.fromJson(json['hijri'] as Map<String, dynamic>? ?? {}),
      gregorianFormatted: greg['formatted']?.toString() ?? '',
    );
  }
}

class QiblaData {
  final double qiblaDirection;
  final String compassBearing;
  final double distanceKm;
  final String? message;

  const QiblaData({
    required this.qiblaDirection,
    required this.compassBearing,
    required this.distanceKm,
    this.message,
  });

  factory QiblaData.fromJson(Map<String, dynamic> json) {
    return QiblaData(
      qiblaDirection: (json['qibla_direction'] as num?)?.toDouble() ?? 0,
      compassBearing: json['compass_bearing']?.toString() ?? '',
      distanceKm: (json['distance_km'] as num?)?.toDouble() ?? 0,
      message: json['message']?.toString(),
    );
  }
}

class DuaItem {
  final int id;
  final String category;
  final String? title;
  final String arabic;
  final String transliteration;
  final String translation;
  final String source;
  final int repeat;

  const DuaItem({
    required this.id,
    required this.category,
    this.title,
    required this.arabic,
    required this.transliteration,
    required this.translation,
    required this.source,
    required this.repeat,
  });

  factory DuaItem.fromJson(Map<String, dynamic> json) {
    return DuaItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      category: json['category']?.toString() ?? '',
      title: json['title']?.toString(),
      arabic: json['arabic']?.toString() ?? '',
      transliteration: json['transliteration']?.toString() ?? '',
      translation: json['translation']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      repeat: (json['repeat'] as num?)?.toInt().clamp(1, 999) ?? 1,
    );
  }
}

class DuaCategory {
  final String id;
  final String name;
  final String description;
  final int count;

  const DuaCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.count,
  });

  factory DuaCategory.fromJson(Map<String, dynamic> json) {
    return DuaCategory(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}
class AsmaName {
  final int number;
  final String nameArabic;
  final String transliteration;
  final String meaning;

  const AsmaName({
    required this.number,
    required this.nameArabic,
    required this.transliteration,
    required this.meaning,
  });

  factory AsmaName.fromJson(Map<String, dynamic> json) {
    return AsmaName(
      number: (json['number'] as num?)?.toInt() ?? 0,
      nameArabic:
          json['name_arabic']?.toString() ?? json['arabic']?.toString() ?? '',
      transliteration: json['transliteration']?.toString() ?? '',
      meaning:
          json['meaning']?.toString() ?? json['english']?.toString() ?? '',
    );
  }

  String localizedMeaning(String lang) {
    if (lang == 'ar') {
      return asmaArabicMeanings[number] ?? meaning;
    }
    return meaning;
  }

  Map<String, dynamic> toJson() => {
    'number': number,
    'name_arabic': nameArabic,
    'transliteration': transliteration,
    'meaning': meaning,
  };
}
