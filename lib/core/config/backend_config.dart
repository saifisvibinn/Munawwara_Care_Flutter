/// Single source of truth for backend URLs used when [.env] is unavailable
/// (native killed-state HTTP, cold start before prefs are cached).
///
/// Keep in sync with [Flutter_Munawwara/.env] `API_BASE_URL` and
/// [BackendConfig.kt] on Android.
const String kDefaultProductionApiBaseUrl =
    String.fromEnvironment('API_BASE_URL');

/// SharedPreferences key (no `flutter.` prefix — Dart plugin adds it on Android).
const String kNativeApiBaseUrlPrefsKey = 'api_base_url';
