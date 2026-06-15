# Environment & release builds

**Context:** `.env` is **not** bundled in `pubspec.yaml` assets (avoids shipping dev URLs/keys in store builds). Use dart-define for release; use `--dart-define-from-file=.env` for local dev.

**Branches:** The `IOS` branch and `main` should both use this pattern. If `main` lags behind, cherry-pick the env files listed below.

---

## Resolution order (Dart)

For `API_BASE_URL`, `AGORA_APP_ID`, `UMMAH_API_KEY`, `GOOGLE_MAPS_API_KEY`:

1. **`--dart-define=KEY=value`** (compile-time; preferred for release)
2. **`.env`** only if `dotenv.load()` succeeded at startup
3. Empty → required keys throw at startup; optional keys log a warning

Implementation: `lib/core/env/app_env.dart` (`envValue`, `agoraAppId`, `ummahApiKey`, etc.)

## Android native (unchanged)

`android/app/build.gradle.kts` parses `--dart-define=API_BASE_URL=...` → `BuildConfig.API_BASE_URL` for killed-state call decline/answer when SharedPreferences are empty.

---

## Local development

```bash
cp .env.example .env
# Edit .env — API_BASE_URL, AGORA_APP_ID, UMMAH_API_KEY, etc.

flutter run --dart-define-from-file=.env
```

Minimum (API only):

```bash
flutter run --dart-define=API_BASE_URL=https://your-api.example.com/api
```

**Voice calls and Islamic Corner (UmmahAPI)** need Agora and Ummah keys in the same file or as extra defines:

```bash
flutter run \
  --dart-define=API_BASE_URL=https://your-api.example.com/api \
  --dart-define=AGORA_APP_ID=your-agora-id \
  --dart-define=UMMAH_API_KEY=your-ummah-key
```

---

## Release / CI (Play Store & App Store)

```bash
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://mc-backend-44890250266.europe-west3.run.app/api \
  --dart-define=AGORA_APP_ID=your-agora-id \
  --dart-define=UMMAH_API_KEY=your-ummah-key
```

Same flags for `apk`, `ipa`, `ios`. **Do not** re-add `.env` to `pubspec.yaml` assets.

Or use a CI-only env file (not committed):

```bash
flutter build appbundle --release --dart-define-from-file=.env.production
```

---

## Files

| File | Role |
|------|------|
| `lib/core/env/app_env.dart` | dart-define + dotenv resolution for integration keys |
| `lib/core/env/dotenv_safe.dart` | Safe dotenv reads when `.env` not loaded |
| `lib/core/config/backend_config.dart` | `API_BASE_URL` compile-time constant |
| `lib/core/services/api_service.dart` | Runtime API URL + native prefs cache |
| `lib/core/services/agora_rtc_service.dart` | Uses `agoraAppId` |
| `lib/features/muslim/providers/muslim_providers.dart` | Uses `ummahApiKey` |
| `lib/core/env/env_check.dart` | Startup validation |
| `android/app/build.gradle.kts` | `BuildConfig.API_BASE_URL` |
| `.env.example` | Developer template (gitignored `.env`) |

---

## Verify

- [ ] App launches; logs show `api_base_url=...` (no `NotInitializedError`)
- [ ] Voice call connects (Agora App ID set)
- [ ] Islamic Corner prayer times load (Ummah API key set)
- [ ] Release build cold-starts on device without `.env` in assets

---

## Related

- [backend-url-setup-guide.md](./backend-url-setup-guide.md) — first-time setup
- [google-play-policy-review.md](./google-play-policy-review.md) — Play Console
- [ios-app-store-review.md](./ios-app-store-review.md) — App Store (branch `IOS`)
