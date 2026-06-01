import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/muslim_models.dart';

/// Local strings for du'a/azkār titles and hadith book names (UmmahAPI is English-only).
class DuaI18nRepository {
  static DuaI18nRepository? _instance;
  static Future<DuaI18nRepository> load() async {
    if (_instance != null) return _instance!;
    final raw = await rootBundle.loadString('assets/muslim/dua_i18n.json');
    _instance = DuaI18nRepository._fromJson(json.decode(raw) as Map<String, dynamic>);
    return _instance!;
  }

  static DuaI18nRepository? get maybeLoaded => _instance;

  DuaI18nRepository._fromJson(Map<String, dynamic> json)
      : _titles = (json['titles'] as Map<String, dynamic>).map(
          (key, value) => MapEntry(
            key,
            Map<String, String>.from(value as Map),
          ),
        ),
        _collectors = (json['collectors'] as Map<String, dynamic>).map(
          (lang, value) => MapEntry(
            lang,
            Map<String, String>.from(value as Map),
          ),
        );

  final Map<String, Map<String, String>> _titles;
  final Map<String, Map<String, String>> _collectors;

  String title(DuaItem dua, String languageCode) {
    final key = '${dua.category}_${dua.id}';
    final entry = _titles[key];
    if (entry == null) return dua.title ?? '';
    return entry[languageCode] ?? entry['en'] ?? dua.title ?? '';
  }

  String localizeSource(String source, String languageCode) {
    if (source.isEmpty || languageCode == 'en') return source;
    final map = _collectors[languageCode] ?? _collectors['en'];
    if (map == null) return source;

    var result = source;
    final entries = map.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in entries) {
      result = result.replaceAll(entry.key, entry.value);
    }
    return result;
  }
}
