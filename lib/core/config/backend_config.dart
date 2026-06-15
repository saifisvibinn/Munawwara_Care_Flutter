/// Compile-time config via `--dart-define=KEY=value` or
/// `flutter run --dart-define-from-file=.env`.
///
/// See `docs/env-and-release-builds.md`.
const String kDefaultProductionApiBaseUrl =
    String.fromEnvironment('API_BASE_URL');

/// SharedPreferences key (no `flutter.` prefix — Dart plugin adds it on Android).
const String kNativeApiBaseUrlPrefsKey = 'api_base_url';
