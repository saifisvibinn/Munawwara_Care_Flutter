import 'package:shared_preferences/shared_preferences.dart';

/// Persists the app UI language for background isolates (FCM TTS, CallKit).
class LocalePrefs {
  LocalePrefs._();

  static const String key = 'locale';

  static Future<void> saveLanguageCode(String code) async {
    final c = code.trim().toLowerCase();
    if (c.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, c);
  }

  /// Language for cloud TTS when FCM does not include [lang].
  static Future<String> readLanguageCode({String fallback = 'en'}) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(key)?.trim();
    if (stored != null && stored.isNotEmpty) return stored;
    return fallback;
  }
}
