# Secure session storage

JWT and session identifiers are stored with `flutter_secure_storage` (Android
EncryptedSharedPreferences, iOS Keychain). Non-sensitive app state remains in
`SharedPreferences`.

## What is stored where

| Data | Storage | Notes |
|------|---------|--------|
| `auth_token` (JWT) | Secure only | Never written to `SharedPreferences` |
| `user_id`, `user_role`, `user_full_name` | Secure (primary) | Dart reads via `SecureSessionStore` |
| `user_id` | Prefs mirror | Written by `syncNativeMirrorPrefs()` for Android native CallKit / killed-state HTTP |
| `device_binding_id` | Secure | One-time login device binding |
| `api_base_url`, `pending_call_*`, locale, FCM dedupe | `SharedPreferences` | Not auth secrets |

## Key classes

- [`lib/core/services/secure_session_store.dart`](../lib/core/services/secure_session_store.dart) — encrypted read/write API
- [`lib/core/services/api_service.dart`](../lib/core/services/api_service.dart) — token on `Dio`, `cacheNativeBridgePrefs()`
- [`lib/features/auth/providers/auth_provider.dart`](../lib/features/auth/providers/auth_provider.dart) — login, restore, logout

## Upgrade migration

On first launch after this change, `prepareCoreRuntime()` runs
`SecureSessionStore.migrateFromSharedPreferencesIfNeeded()`:

1. Copies legacy plaintext `auth_token`, `user_id`, `user_role`, `user_full_name`, and `device_binding_id` from prefs into secure storage
2. Removes those keys from `SharedPreferences`
3. Mirrors `user_id` for native code

Existing users stay logged in without re-entering credentials.

## Native Android

Kotlin reads `flutter.user_id` and `flutter.api_base_url` from
`FlutterSharedPreferences` when the app is killed. Dart keeps the mirror in sync
after login and session restore. **JWT is not mirrored.**

## Manual test checklist

1. Fresh install → login → API calls succeed
2. Kill app → reopen → session restores from secure storage
3. Logout → secure keys cleared; mirror `user_id` removed from prefs
4. Upgrade from old build (token only in prefs) → still logged in after update
5. Android: decline incoming call with app killed (after one normal launch post-login)

## Related docs

- [backend-url-setup-guide.md](./backend-url-setup-guide.md) — API URL configuration (separate from auth storage)
