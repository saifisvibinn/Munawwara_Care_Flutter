/// Compile-time backend URL when [.env] is unavailable (native killed-state
/// HTTP, cold start before prefs are cached).
///
/// Set via `--dart-define=API_BASE_URL=...` (mirrored in Android
/// [BuildConfig.API_BASE_URL]). For local dev without bundling `.env` in assets,
/// use `flutter run --dart-define-from-file=.env`.
const String kDefaultProductionApiBaseUrl =
    String.fromEnvironment('API_BASE_URL');

/// SharedPreferences key (no `flutter.` prefix — Dart plugin adds it on Android).
const String kNativeApiBaseUrlPrefsKey = 'api_base_url';
