package com.munawwaracare.android

/**
 * Backend URL for native code paths when Flutter SharedPreferences are empty
 * (cold start / killed app before prefs are cached from Dart).
 *
 * Value comes from `--dart-define=API_BASE_URL=...` at build time
 * ([BuildConfig.API_BASE_URL]). Keep in sync with `.env` and
 * `lib/core/config/backend_config.dart`.
 */
object BackendConfig {
    val API_BASE_URL_FALLBACK: String
        get() = BuildConfig.API_BASE_URL
}
