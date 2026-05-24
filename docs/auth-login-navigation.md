# Auth login navigation

## Problem (fixed)

After a successful login API response, the app saved the JWT but stayed on the login
screen until the process was killed and reopened. Splash then routed to the dashboard
because the session was already on disk.

## Cause

`AuthNotifier.login` and `loginWithOneTimeToken` **awaited** notification permission
prompts and `FirebaseMessaging.getToken()` before returning `true`. On some release
APKs (slow GMS, permission sheets, or FCM stalls), that work never finished, so
`LoginScreen._goAfterAuth()` never ran.

## Fix

- Return success immediately after `_persistSession` and auth state update.
- Run `_requestNotificationPermissions` + `_registerFcmTokenAfterLogin` in the
  background via `_schedulePostLoginSetup()`.
- Cap `getToken()` with a 12s timeout so background setup cannot hang forever.

## FCM after login (calls / pushes)

Relogin did not register `PUT /api/auth/fcm-token` on the server, so incoming calls
had no FCM fallback when the socket ACK timed out.

`ensureFcmTokenRegistered()` runs after navigation, on dashboard open, and when auth
becomes authenticated in `main.dart`.

## Files

- `lib/features/auth/providers/auth_provider.dart` — post-login setup scheduling
- `lib/features/auth/screens/login_screen.dart` — calls `_goAfterAuth()` when login returns `true`
