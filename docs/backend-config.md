# Backend API URL configuration

> **Step-by-step setup:** see [backend-url-setup-guide.md](./backend-url-setup-guide.md)

The Munawwara Care Flutter app resolves `API_BASE_URL` from multiple layers so
native killed-state HTTP (call decline/answer) and Dart networking stay aligned
without hardcoding production URLs in source.

## Resolution order (Dart / main app)

1. **`API_BASE_URL` in `.env`** — loaded via `flutter_dotenv` at startup
   (`lib/core/bootstrap/app_startup.dart`).
2. **`--dart-define=API_BASE_URL=...`** — compile-time fallback in
   `lib/core/config/backend_config.dart` (`String.fromEnvironment`).
3. Optional **`API_ANDROID_HOST`** — replaces hostname on Android emulators only.

`ApiService.cacheNativeCallPrefs()` writes the resolved URL to SharedPreferences
(`flutter.api_base_url`) so native Android code can use it when the Dart engine
is not running.

## Android native paths

When prefs are empty (cold start before first app open), native code uses
`BuildConfig.API_BASE_URL`, populated from the same `--dart-define` flag in
`android/app/build.gradle.kts` → `BackendConfig.kt`.

If both prefs and `BuildConfig` are empty, native decline/answer HTTP is skipped
with a log warning (no hardcoded production fallback).

## Local development

```bash
cp .env.example .env
# Edit .env — set API_BASE_URL and integration keys
flutter run
```

`.env` is gitignored. `.env.example` uses placeholders only.

## Release / CI builds

Pass the production URL at build time (recommended when `.env` is not on the CI
machine):

```bash
flutter build apk --release \
  --dart-define=API_BASE_URL=https://your-production-host.example.com/api
```

Use the same flag for `appbundle`, `ios`, etc.

## Validation

`lib/core/env/env_check.dart` throws at startup if `ApiService.baseUrl` is empty
(missing both `.env` and `dart-define`).

## Related files

| File | Role |
|------|------|
| `lib/core/config/backend_config.dart` | Dart `String.fromEnvironment` |
| `lib/core/services/api_service.dart` | Runtime URL + prefs cache |
| `android/app/build.gradle.kts` | Parses `dart-defines` → `BuildConfig` |
| `android/.../BackendConfig.kt` | Native compile-time URL |
| `.env.example` | Developer template (no real URLs) |
