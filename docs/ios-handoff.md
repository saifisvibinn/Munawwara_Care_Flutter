# Munawwara Care — iOS Handoff & Project Reference

**Purpose:** Complete project context and step-by-step handoff for the agent (or developer) implementing the iOS version.  
**App:** Munawwara Care — group safety and coordination for Hajj & Umrah.  
**Current version:** `1.1.3+13` (`pubspec.yaml`)  
**Last updated:** June 13, 2026  
**Android status:** Production-track (Google Play internal testing, release `com.munawwaracare.android`)  
**iOS status:** Native layer + toolchain verified — `flutter build ios --no-codesign` succeeds on branch `IOS`  
**Git branch:** `IOS` (pushed to `origin/IOS`)

> Compliance and policy notes in this document are engineering aids only — not legal advice.

---

## Implementation progress (branch `IOS`)

| Item | Status |
|------|--------|
| Bundle ID `com.munawwaracare.ios` | Done in `project.pbxproj` |
| `Runner.entitlements` (aps-environment development) | Done |
| `LocationChannelHandler.swift` (SLC + heartbeat) | Done |
| `AppDelegate.swift` (PushKit + CallKit plugin) | Done |
| `GoogleService-Info.plist.example` | Done — copy real file from Firebase |
| iOS device-care steps (location + notifications) | Done in `oem_settings_service.dart` |
| VoIP token cached locally (`ios_voip_push_token`) | Done — backend upload pending |
| CocoaPods dependency conflict (Firebase vs MLKit) | **Done** — upgraded `firebase_*`, `google_mlkit_*`, `mobile_scanner` |
| `pod install` + release build on Mac | **Done** — see Step 3 below |
| Firebase `GoogleService-Info.plist` on disk | **You** — download from Firebase Console |
| Apple Developer Program + APNs key in Firebase | **You** — required for push |
| Xcode signing + first `flutter run` on iPhone | **You** — connect device via USB |
| Backend `voip_token` endpoint | **Future** — for killed-state VoIP pushes |

---

## Mac agent — start here

Send this file to the Mac agent. Work on branch **`IOS`**.

### Apple Developer enrollment — first or last?

**Enrollment can be one of the last steps** if the goal is only: *build, install, and smoke-test the app on a physical iPhone.*

**Enrollment must happen before** testing push notifications, killed-state CallKit/VoIP calls, TestFlight, or App Store.

| With **free Apple ID** only | With **paid Apple Developer Program** ($99/year) |
|-----------------------------|--------------------------------------------------|
| `flutter run` on your iPhone | Everything in free tier, plus: |
| Login, maps, chat, UI | FCM push (SOS, chat, call signals) |
| Agora calls while app is **foreground** | VoIP PushKit when app is **background/killed** |
| Location **While Using** | TestFlight + App Store |
| App expires on device ~every **7 days** | Stable provisioning profiles |

### Recommended order on the MacBook

```
Step 1 — Clone / checkout (no enrollment needed)
  git fetch origin
  git checkout IOS
  cd Munawwara_Care_Flutter

Step 2 — Environment
  cp .env.example .env
  # Set API_BASE_URL, AGORA_APP_ID, GOOGLE_MAPS_API_KEY (same as Android)

Step 3 — Flutter + CocoaPods (no enrollment needed)
  flutter config --no-enable-swift-package-manager
  # Required when the repo lives under a path with spaces (e.g. "Munawwara Care").
  # SPM fails to resolve pubspec.yaml with URL-encoded spaces.

  flutter precache --ios
  flutter pub get

  # CocoaPods on this Mac needs a Logger preload (Ruby 2.6). Use the project wrapper:
  export PATH="$(pwd)/scripts:$PATH"
  cd ios && pod install && cd ..

  # Dependency fix already applied in pubspec.yaml (June 13, 2026):
  # - firebase_core ^3.13 / firebase_messaging ^15.2 → Firebase iOS SDK 11.x
  # - google_mlkit_* ^0.13.1, mobile_scanner ^7.2 → MLKitVision 10.x / GoogleDataTransport 10.x

  # Verify compile (no signing):
  flutter build ios --no-codesign
  # ✓ Verified: builds Runner.app (~174 MB)

  # Xcode warnings (June 13, 2026):
  # - App icons: dart run flutter_launcher_icons (orphan legacy PNGs removed from AppIcon.appiconset)
  # - Pod deprecations: ios/Podfile post_install sets GCC_WARN_INHIBIT_ALL_WARNINGS + SWIFT_SUPPRESS_WARNINGS
  # - Runner: CLANG_WARN_OBJC_IMPLICIT_OWNERSHIP=NO (mobile_scanner header), -Wl,-no_warn_duplicate_libraries
  # - Local fork: plugins/flutter_callkit_incoming Swift polish (keyWindow, notification presentation)

Step 4 — First device run (free Apple ID OK)
  export PATH="$(pwd)/scripts:$PATH"
  # Connect iPhone via USB, trust device
  flutter devices
  flutter run -d <iphone-device-id>
  # In Xcode if signing fails: Runner → Signing → Team → your Apple ID

Step 5 — Smoke test without push
  - Moderator login + pilgrim QR/code login
  - Map, chat, profile, session restore after kill
  - Voice call while app is open (foreground)

Step 6 — Firebase iOS app (can do before or after enroll)
  Firebase Console → project munawwaracare-5353a
  → Add iOS app, bundle ID com.munawwaracare.ios
  → Download GoogleService-Info.plist
  → Save to ios/Runner/GoogleService-Info.plist
  (Template: ios/Runner/GoogleService-Info.plist.example)

Step 7 — Apple Developer Program (before push/calls/store)
  Enroll at https://developer.apple.com/programs/
  → Create App ID com.munawwaracare.ios
  → Enable Push Notifications + Background Modes
  → Create APNs Auth Key (.p8)

Step 8 — Wire push (requires Step 7)
  Firebase → Project Settings → Cloud Messaging → upload APNs .p8 key
  Xcode → Runner → Signing & Capabilities → select paid Team
  Enable Push Notifications + Background Modes (Location, VoIP, Audio, Remote notifications)
  Rebuild: flutter run -d <iphone>

Step 9 — Test push + calls (physical device only, not Simulator)
  - PUT /api/auth/fcm-token → 200 in backend logs after login
  - SOS alert to moderator
  - Incoming call: foreground → background → killed (killed needs VoIP + backend voip_token later)

Step 10 — TestFlight / App Store (requires Step 7)
  flutter build ios --release --dart-define=API_BASE_URL=...
  Xcode → Product → Archive → Distribute
```

### One-line summary for the Mac agent

> Run the app first with a free Apple ID; enroll in Apple Developer **before** push, killed-state calls, and TestFlight — not before the first `flutter run`.

---

## Table of contents

1. [What this app is](#1-what-this-app-is)
2. [Monorepo layout](#2-monorepo-layout)
3. [Technology stack](#3-technology-stack)
4. [User roles and flows](#4-user-roles-and-flows)
5. [Flutter app architecture](#5-flutter-app-architecture)
6. [Feature inventory](#6-feature-inventory)
7. [Backend (`mc_backend_app`)](#7-backend-mc_backend_app)
8. [Real-time, push, and calling](#8-real-time-push-and-calling)
9. [Location tracking (Tameny)](#9-location-tracking-tameny)
10. [Security and configuration](#10-security-and-configuration)
11. [Android reference (what iOS must match)](#11-android-reference-what-ios-must-match)
12. [iOS current state](#12-ios-current-state)
13. [iOS gaps — must implement](#13-ios-gaps--must-implement)
14. [Apple & Firebase setup checklist](#14-apple--firebase-setup-checklist)
15. [Native iOS implementation guide](#15-native-ios-implementation-guide)
16. [Dart code — platform branches](#16-dart-code--platform-branches)
17. [Build and release commands](#17-build-and-release-commands)
18. [App Store Connect checklist](#18-app-store-connect-checklist)
19. [Testing matrix](#19-testing-matrix)
20. [Do not break (critical safeguards)](#20-do-not-break-critical-safeguards)
21. [Suggested implementation order](#21-suggested-implementation-order)
22. [Related documentation index](#22-related-documentation-index)

---

## 1. What this app is

Munawwara Care connects **pilgrims** (Hajj/Umrah participants) with **moderators** (group leaders / guides) for:

| Capability | Pilgrim | Moderator |
|------------|---------|-----------|
| Group membership | View | Create, manage, provision |
| Live GPS map | Self + moderator beacon | All pilgrims in group |
| SOS alert | Trigger (hold button) | Receive, handle, resolve |
| Voice calls | Initiate / receive (Agora audio) | Initiate to group / individual |
| Chat | Group + individual threads | Group + individual |
| Meetpoints / suggested areas | View, navigate | Create, pin |
| Resources (hotels, buses, docs) | View | Manage via web moderator portal |
| Islamic Corner (prayer, du'a, etc.) | Yes | N/A on mobile |
| Live translate (on-device ML) | Yes | N/A |
| Device care onboarding | Battery / notification guidance | Lighter variant |

**Positioning for stores:** “Group safety / coordination for Hajj & Umrah” — **not** a medical device. SOS routes to the assigned moderator, not emergency services (disclaimer in-app and privacy policy).

**Support contact:** `munawwaracare@gmail.com` (in-app forms + store listings).

**Privacy policy URL (in-app WebView):** <https://saifisvibinn.github.io/munawwara-privacy/>  
**Repo draft:** `docs/privacy-policy.md` — must stay in sync with live site.

---

## 2. Monorepo layout

```
Durrah care mob app/
├── Flutter_Munawwara/          # ← THIS REPO — Flutter mobile app (Android + iOS target)
│   ├── lib/                    # Dart source
│   ├── android/                # Production-ready Android native layer
│   ├── ios/                    # Scaffold only — needs full native work
│   ├── plugins/
│   │   └── flutter_callkit_incoming/   # LOCAL FORK (path dependency)
│   ├── assets/                 # translations, fonts, SOS audio, static images
│   └── docs/                   # Feature & policy documentation
├── mc_backend_app/             # Node.js / Express / Socket.IO / MongoDB API
└── mc_mod_front/               # Moderator web dashboard (optional context; not iOS scope)
```

**Git:** Flutter app is its own repo under `Flutter_Munawwara/.git` (branch `main`).

---

## 3. Technology stack

| Layer | Technology |
|-------|------------|
| Mobile UI | Flutter 3, Dart SDK `^3.11.0` |
| State | Riverpod 3 (`ConsumerWidget`, `StateNotifierProvider`) |
| Routing | GoRouter 17 |
| HTTP | Dio 5 |
| Real-time | Socket.IO (`socket_io_client`) |
| Voice media | Agora RTC (`agora_rtc_engine`) — **audio only**, no video |
| Push | Firebase Cloud Messaging (`firebase_messaging`) |
| Local notifications | `flutter_local_notifications` 19 |
| Incoming calls UI | `flutter_callkit_incoming` (local fork) |
| Maps | `flutter_map` + OpenStreetMap tiles (not Google Maps SDK on map) |
| i18n | `easy_localization` — 8 locales (see `docs/app-languages.md`) |
| Secure storage | `flutter_secure_storage` (Keychain on iOS) |
| Env | `flutter_dotenv` — `.env` (gitignored) |
| Backend | Node.js, Express, Mongoose, Redis, Cloud Run (`europe-west3`) |
| Push server | Firebase Admin SDK → FCM |
| DB | MongoDB Atlas |

**Note:** `lib/app_architecture.md` mentions WebRTC historically; the live calling stack uses **Agora**, not `flutter_webrtc`. Trust `docs/voice-calls-architecture.md` for calling.

---

## 4. User roles and flows

### 4.1 Authentication

| Role | Login method | Route after splash |
|------|--------------|-------------------|
| **Moderator** | Email + password | `/moderator-dashboard` |
| **Pilgrim** | One-time QR / join code (device-bound) | `/pilgrim-dashboard` |

**Key files:**

- `lib/features/auth/providers/auth_provider.dart` — session, profile, FCM registration
- `lib/features/auth/screens/login_screen.dart`
- `lib/features/splash/screens/splash_screen.dart` — startup coordinator, optional device-care onboarding
- `lib/core/services/secure_session_store.dart` — JWT in Keychain / EncryptedSharedPreferences

**Device binding:** Pilgrim accounts bind to a `device_binding_id` (UUID). Re-provision if code used on another device.

**Session restore:** On cold start, `SecureSessionStore.migrateFromSharedPreferencesIfNeeded()` then `authProvider` restores JWT from secure storage.

### 4.2 Device care onboarding

`lib/features/auth/screens/device_care_onboarding_screen.dart` — guides users through notification and battery settings. Heavy **Android OEM** logic via `oem_settings_service.dart`. On iOS, show simplified guidance (Settings → Notifications, Background App Refresh, Location Always) without OEM method channels.

### 4.3 Navigation routes

Defined in `lib/core/router/app_router.dart`:

| Path | Screen |
|------|--------|
| `/` | Splash |
| `/login` | Login |
| `/forgot-password` | Forgot password (moderators) |
| `/device-care-onboarding` | Device care |
| `/pilgrim-dashboard` | Pilgrim home |
| `/moderator-dashboard` | Moderator home |
| `/privacy-policy` | Privacy WebView |
| `/about` | About + version |
| `/contact-support` | Support form |
| `/request-account-deletion` | Deletion form |

`AppRouter.navigatorKey` is used by CallKit accept handler to push `VoiceCallScreen` without waiting for dashboard rebuild.

---

## 5. Flutter app architecture

### 5.1 Bootstrap sequence (`main.dart`)

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `NativeCallCoordinator.registerEarlyListeners()` — **before** `runApp`
3. `SystemChrome.setEnabledSystemUIMode(edgeToEdge)`
4. `applyDeviceOrientationPolicy()` — portrait on phones
5. `prepareCoreRuntime()` — Firebase, EasyLocalization, `.env` load, secure storage migration
6. `FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler)`
7. `ProviderContainer` + `CallingScope.riverpod` global ref for killed-state handlers
8. `runApp` → `EasyLocalization` → `MaterialApp.router`

On auth success: `ensureFcmTokenRegistered()` + `TamenyLocationService.initialize(serverUrl, authToken)`.

### 5.2 Directory structure

```
lib/
├── main.dart
├── core/
│   ├── bootstrap/          # app_startup, mobile_messaging_bootstrap
│   ├── config/             # backend_config, app_locales
│   ├── env/                # env_check (throws if API_BASE_URL missing)
│   ├── map/                # OSM tiles, marker clustering
│   ├── providers/          # theme, app version
│   ├── router/             # GoRouter
│   ├── services/           # api, socket, notifications, callkit, location, etc.
│   ├── theme/
│   ├── utils/
│   └── widgets/
└── features/
    ├── auth/
    ├── calling/              # ⚠️ FRAGILE — read voice-calls-architecture.md first
    ├── legal/                # privacy, about, support forms
    ├── moderator/
    ├── muslim/               # Islamic Corner hub
    ├── pilgrim/
    ├── shared/               # messages, chat theme
    └── splash/
```

### 5.3 State management pattern

- **Riverpod** `StateNotifierProvider` for feature state (`authProvider`, `callProvider`, `pilgrimProvider`, `moderatorProvider`, `messageProvider`, …)
- **Immutable state classes** with `copyWith`
- **AppDataCache** (`SharedPreferences`) for offline hydration — notifiers call `hydrateFromCache()` before network
- **Socket listeners** registered only at dashboard screen level; child widgets receive data via constructor params

See `docs/data-sync.md` for moderator mutation → refresh pattern (`syncAfterMutation`).

### 5.4 Design baseline

- `ScreenUtilInit` design size: **393 × 852**
- Fonts: Lexend (UI), Amiri (Arabic), bundled under `assets/fonts/`
- Themes: `lib/core/theme/app_theme.dart` (light + dark)
- Errors in forms: `SelectableText.rich` (red), not SnackBars (workspace rule)

---

## 6. Feature inventory

### 6.1 Pilgrim dashboard tabs

| Index | Tab | Key files |
|-------|-----|-----------|
| 0 | Home (SOS, weather, group card) | `widgets/home_tab/` |
| 1 | Map | `widgets/map_tab/pilgrim_map_tab.dart` |
| 2 | Islamic Corner | `features/muslim/screens/islamic_corner_hub_screen.dart` |
| 3 | Inbox / chat | `group_inbox_screen.dart` |
| 4 | Profile / settings | `pilgrim_profile_screen.dart` |

### 6.2 Moderator dashboard

Monolithic orchestrator: `moderator_dashboard_screen.dart` (~large file). Sub-features:

- Group management, pilgrim map, SOS panel (`sos_alert_coordinator.dart`)
- Provisioning (QR / join codes), bus attendance, reminders
- Individual + group messaging, call history, explore POIs

### 6.3 SOS lifecycle (pilgrim → moderator)

1. Pilgrim holds SOS button → `POST /api/sos/trigger`
2. Moderators receive socket `sos_alert` + FCM + bundled language audio (`assets/audio/sos/{code}.mp3`)
3. Moderator taps Handle → `sos-handling` → pilgrim UI shows “reviewing”
4. Optional auto-call after 60s → voice call to group moderators
5. Resolve → `sos-resolved` → pilgrim panel dismissed

### 6.4 Voice calls

**Read `docs/voice-calls-architecture.md` in full before any change.**

Stack: Socket.IO signaling + REST fallbacks + FCM wakeups + Agora RTC audio + native CallKit UI.

Key Dart files:

| File | Role |
|------|------|
| `call_provider.dart` | State machine, Agora join/leave, ring watchdog |
| `call_signaling.dart` | REST `/offer`, `/answer`, `/decline`, socket emits |
| `native_call_coordinator.dart` | CallKit events → Riverpod + navigation |
| `call_navigation.dart` | `openVoiceCallScreen(bypassNavigatingGuard: …)` |
| `callkit_service.dart` | FCM parse → show native incoming call |
| `mobile_messaging_bootstrap.dart` | FCM routing for call control messages |
| `voice_call_screen.dart` | In-call UI; `PopScope` prevents back-gesture leak |

### 6.5 Islamic Corner / Muslim module

See `docs/muslim-corner-handoff.md`. Uses external **UmmahAPI** (`https://ummahapi.com/api`). Qibla compass on Prayer Times screen has a **known open bug** — see `docs/qibla-compass.md`.

### 6.6 Live translate

On-device: `google_mlkit_translation`, `google_mlkit_language_id`, `speech_to_text`. See `docs/live_translate_integration_guide.md`.

### 6.7 Legal / support

- `POST /api/support/request` — support and account deletion emails
- See `docs/support-requests.md`, `docs/app-version-and-about.md`

### 6.8 Languages

8 UI locales: `en`, `ar`, `ur`, `fr`, `id`, `tr`, `fa`, `ms`. See `docs/app-languages.md`.

---

## 7. Backend (`mc_backend_app`)

### 7.1 Deployment

- **Hosting:** Google Cloud Run, region `europe-west3`
- **Example production URL** (verify current): `https://mc-backend-44890250266.europe-west3.run.app/api`
- **Firebase project:** `munawwaracare-5353a`

### 7.2 Auth

- JWT in `Authorization: Bearer <token>`
- Roles: `admin`, `moderator`, `pilgrim` (stored as `user_type` on unified `User` model)
- FCM token: `PUT /api/auth/fcm-token` body `{ "fcm_token": "..." }`

### 7.3 Key REST areas

| Area | Routes / controllers |
|------|---------------------|
| Auth | `auth_controller.js`, `auth_routes.js` |
| Groups / pilgrims | `group_controller.js` |
| Messages | `message_controller.js` |
| SOS | SOS trigger + lifecycle services |
| Calls | `call_history_controller.js` — offer, answer, decline, check-active |
| Location | `location_controller.js`, `location_routes.js` |
| Support | `support_routes.js` → emails support inbox |
| POI / explore | `poi` routes, MongoDB seed |

Full reference: `mc_backend_app/docs/API_DOCUMENTATION.md`

### 7.4 Socket.IO

Central file: `mc_backend_app/sockets/socket_manager.js`

Important events: `group_updated`, `sos_alert`, `sos-handling`, `sos-resolved`, `new_message`, `mod_nav_beacon`, call signaling events.

### 7.5 Push notifications

`mc_backend_app/services/pushNotificationService.js` — FCM multicast, data-only messages for calls/SOS.

**Current limitation for iOS calls:** Backend sends incoming calls via **standard FCM data messages** to `user.fcm_token`. For reliable iOS incoming calls when app is killed, Apple expects **VoIP Push (PushKit)**. Client-side PushKit is **implemented** in `AppDelegate.swift` (branch `IOS`); remaining gaps:

1. Backend has **no `voip_token` field** — only `fcm_token`
2. Dart does not yet upload VoIP token to backend (cached locally as `ios_voip_push_token`)

---

## 8. Real-time, push, and calling

### 8.1 FCM message types (data payload `type` field)

Handled in `notification_service.dart` and `mobile_messaging_bootstrap.dart`:

| type | Purpose |
|------|---------|
| `incoming_call` | Show CallKit / native incoming UI |
| `call_answered` | Caller joins Agora when callee accepted |
| `call_declined` | Dismiss ringing |
| `call_cancel` / `call_ended` | Teardown |
| `sos_alert` | Moderator urgent alert |
| `sos_alert_cancelled` | Dismiss SOS tray |
| `new_message` / `meetpoint` | Chat refresh fallback |
| TTS / reminder types | Cloud TTS playback paths |

### 8.2 Android-specific call native layer

- `IncomingCallService.kt` — foreground service for ringing
- `CallDismissHelper.kt` — decline posts to `/call-history/decline` when killed
- Local plugin fork: `plugins/flutter_callkit_incoming` — **Android HTTP decline fix**

iOS uses **system CallKit** via the same plugin's Swift code — but requires `AppDelegate` PushKit + AVAudioSession setup per `plugins/flutter_callkit_incoming/PUSHKIT.md`.

### 8.3 CallKit plugin (local fork)

```yaml
# pubspec.yaml
dependency_overrides:
  flutter_callkit_incoming:
    path: ./plugins/flutter_callkit_incoming
```

**Why forked:** Android `BroadcastReceiver` posts decline to backend when pilgrim declines from system UI while app is killed. iOS side is upstream plugin Swift — customize in fork if needed.

**iOS rule from plugin README:** Incoming calls **only work on real devices**, not Simulator.

---

## 9. Location tracking (Tameny)

`lib/core/services/tameny_location_service.dart` — branded “Tameny” tracking toggle in pilgrim UI.

### 9.1 Three layers (Android today)

| Layer | Android | iOS (planned in Dart, **native missing**) |
|-------|---------|---------------------------------------------|
| Foreground / backgrounded | `flutter_background_service` | Same plugin (verify iOS config) |
| App killed | WorkManager every 60 min (`LocationHeartbeatWorker.kt`) | **Significant Location Changes** via method channel |
| Credentials for native HTTP | `SharedPreferences` mirror + `NativePrefsBridge` | `UserDefaults` via `com.munawwaracare/location` channel |

### 9.2 Dart method channel (iOS — not implemented)

Channel: `com.munawwaracare/location`

| Method | Called from | Expected native behavior |
|--------|-------------|--------------------------|
| `startSignificantLocationChanges` | `tameny_location_service.dart` | `CLLocationManager.startMonitoringSignificantLocationChanges()` |
| `stopSignificantLocationChanges` | same | Stop monitoring |
| `saveCredentials` | `native_prefs_bridge.dart` | Store `token` + `serverUrl` in UserDefaults for background uploads |

**No Swift handler exists** under `ios/Runner/` today. Calls fail silently (caught, `debugPrint` only).

### 9.3 Permissions

`Info.plist` already declares:

- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `UIBackgroundModes`: `location`, `audio`, `remote-notification`, `voip`

Dart requests **Always** on iOS when enabling tracking (`tameny_location_service._requestPermissions`).

**App Store:** Background location requires strong justification in review notes and App Privacy details. In-app Arabic disclosure dialog exists (`_showProminentDisclosure`).

---

## 10. Security and configuration

### 10.1 Environment variables (`.env`)

Copy from `.env.example`:

```env
API_BASE_URL=https://your-api.example.com/api
AGORA_APP_ID=
GOOGLE_MAPS_API_KEY=
# Optional:
# SOCKET_BASE_URL=https://your-realtime-host.example.com
# API_ANDROID_HOST=10.0.2.2   # Android emulator only
```

Loaded at startup in `app_startup.dart`. `env_check.dart` **throws** if `API_BASE_URL` resolves empty.

### 10.2 API URL resolution

See `docs/backend-config.md` and `docs/backend-url-setup-guide.md`.

Order: `.env` → `--dart-define=API_BASE_URL` → Android `BuildConfig` (native killed-state). iOS has **no** native `BuildConfig` equivalent — rely on `.env`, dart-define, and `ApiService.cacheNativeBridgePrefs()` writing to SharedPreferences.

### 10.3 Secure session storage

See `docs/secure-session-storage.md`.

- JWT: **Keychain only** (`flutter_secure_storage`)
- `user_id` mirrored to prefs for Android native — iOS native should read from UserDefaults via location channel after `saveCredentials`

### 10.4 API keys in client

- Agora App ID in `.env` / dart-define
- Google Maps key — used where needed; map tiles are OSM with `userAgentPackageName = 'com.munawwaracare.app'` in `app_map_tiles.dart`
- Restrict keys in cloud consoles per platform bundle ID

---

## 11. Android reference (what iOS must match)

### 11.1 Package / application ID

| Platform | ID | Status |
|----------|-----|--------|
| Android | `com.munawwaracare.android` | Production |
| iOS | `com.munawwaracare.ios` | Done (branch `IOS`) |

### 11.2 Android method channels (implement iOS equivalents where applicable)

| Channel | Methods | iOS needed? |
|---------|---------|-------------|
| `com.munawwaracare.android/incoming_call` | `stopRinging` | No — CallKit handles |
| `com.munawwaracare.android/oem_settings` | battery, autostart, notification settings | No — use iOS Settings URLs / copy |
| `com.munawwaracare.android/notification_tray` | dismiss by tag | Optional — iOS notification APIs |
| `com.munawwaracare/workmanager` | periodic location | No — use Significant Location Changes |
| `com.munawwaracare/location` | SLC + saveCredentials | **Yes — required** |

### 11.3 Android-only features (skip or substitute on iOS)

| Feature | File | iOS approach |
|---------|------|--------------|
| In-app Play updates | `splash_screen.dart` (`in_app_update`) | App Store updates only |
| OEM battery / autostart wizards | `oem_settings_service.dart` | Simplified onboarding copy |
| WorkManager location heartbeat | `LocationHeartbeatWorker.kt` | Significant Location Changes |
| Full-screen intent call UI | Android manifest | CallKit full-screen |
| `battery_optimization_helper.dart` | REQUEST_IGNORE_BATTERY_OPTIMIZATIONS | N/A |

### 11.4 Firebase config (Android done)

`android/app/google-services.json` → project `munawwaracare-5353a`, package `com.munawwaracare.android`.

**iOS:** Add iOS app in same Firebase project → download `GoogleService-Info.plist` → `ios/Runner/GoogleService-Info.plist`.

---

## 12. iOS current state

### 12.1 What exists

| Item | Path / value |
|------|----------------|
| Xcode project | `ios/Runner.xcodeproj`, `ios/Runner.xcworkspace` |
| Min deployment | iOS **15.5** (`ios/Podfile`) |
| Display name | Munawwara Care (`Info.plist`) |
| Permission strings | Location, camera, mic, speech, photo library |
| Background modes | location, audio, remote-notification, voip |
| Portrait | Phone portrait only |
| App icons | `flutter_launcher_icons` with `ios: true` |
| Scene delegate | `SceneDelegate.swift` (Flutter template) |
| AppDelegate | PushKit + CallKit + location channel registered |

### 12.2 What is missing

| Item | Impact |
|------|--------|
| `GoogleService-Info.plist` | Firebase / FCM won't initialize on device |
| Real bundle ID + signing | Bundle ID done — Xcode Team signing still needed for device |
| `.entitlements` (push, background) | Done — `Runner.entitlements` |
| PushKit + VoIP in AppDelegate | Done (branch `IOS`) |
| APNs key in Firebase Console | FCM won't deliver to iOS until configured |
| Location method channel Swift | Done — `LocationChannelHandler.swift` |
| `pod install` on Mac | Done — use `scripts/pod` wrapper (see Step 3) |
| Physical device testing | Simulator inadequate for calls / push |

---

## 13. iOS gaps — remaining work

**Already done on branch `IOS` (in repo):** bundle ID, entitlements, AppDelegate PushKit, location channel, iOS device-care steps, VoIP token local cache.

### Priority 0 — Mac agent manual setup

1. Mac + Xcode + physical iPhone
2. `git checkout IOS` → `flutter pub get` → `cd ios && pod install`
3. `.env` with `API_BASE_URL` and keys
4. First `flutter run` (free Apple ID OK for smoke test)
5. Firebase → `GoogleService-Info.plist` in `ios/Runner/`
6. **Apple Developer Program** — before push/calls/store (can be after first run)
7. APNs `.p8` in Firebase + Xcode signing with paid Team

### Priority 1 — Verify on device

1. FCM token registration (`PUT /api/auth/fcm-token` → 200)
2. Push notifications (SOS, chat) — requires enrollment + APNs
3. CallKit incoming calls — foreground first, then background/killed
4. Tameny tracking → Always location → SLC heartbeat (`source: ios_significant_change` in backend logs)
5. **`flutter_background_service` iOS** — verify foreground notification while tracking

### Priority 2 — Backend + polish

1. **Backend:** `voip_token` field + upload endpoint (killed-state VoIP calls)
2. Restrict Agora / Google API keys for `com.munawwaracare.ios`
3. Test 8 locales + RTL (`ar`, `ur`, `fa`)
4. Verify `PopScope` on `voice_call_screen.dart` blocks swipe-back during active call

### Priority 3 — App Store

1. App Store Connect app record, screenshots, privacy nutrition labels
2. TestFlight internal testing
3. App Review demo accounts (moderator + fresh pilgrim code)
4. Privacy policy URL live and matching `docs/privacy-policy.md`

---

## 14. Apple & Firebase setup checklist

### 14.1 Apple Developer Portal

- [ ] Enroll in Apple Developer Program
- [ ] Create App ID (explicit bundle ID)
- [ ] Enable capabilities: Push Notifications, Background Modes (Location updates, Voice over IP, Audio, Remote notifications)
- [ ] Create APNs Auth Key (.p8) — download once, store securely
- [ ] Create Development + Distribution provisioning profiles
- [ ] (Optional) VoIP Services Certificate — plugin docs mention; Auth Key often sufficient with modern FCM

### 14.2 Firebase Console (`munawwaracare-5353a`)

- [ ] Add iOS app with final bundle ID
- [ ] Download `GoogleService-Info.plist` → `ios/Runner/`
- [ ] Project Settings → Cloud Messaging → upload APNs Auth Key
- [ ] Verify FCM works: log `globalFcmToken` after login (`mobile_messaging_bootstrap.dart`)

### 14.3 Xcode (`Runner` target)

- [ ] Set Team + bundle identifier
- [ ] Add `GoogleService-Info.plist` to target membership
- [ ] Signing & Capabilities: match entitlements to Info.plist background modes
- [ ] Build Phases: ensure Firebase script if using FlutterFire CLI (project uses manual plist today)

---

## 15. Native iOS implementation guide

### 15.1 AppDelegate template (starting point)

Use the plugin's reference implementation:

- `plugins/flutter_callkit_incoming/PUSHKIT.md`
- Upstream: `flutter_callkit_incoming` example `AppDelegate.swift` on GitHub

Minimum additions to current `ios/Runner/AppDelegate.swift`:

1. Import CallKit / PushKit / AVFoundation
2. Conform to `PKPushRegistryDelegate`
3. Register for VoIP pushes
4. Forward device token to `SwiftFlutterCallkitIncomingPlugin`
5. On VoIP notification, parse payload and call `showCallkitIncoming`
6. Register `com.munawwaracare/location` method channel (can be separate `LocationChannelHandler.swift`)

### 15.2 Significant Location Changes (sketch)

```swift
// Pseudocode — implement in Runner, not copy-paste without error handling
class LocationChannelHandler: NSObject, CLLocationManagerDelegate {
  let manager = CLLocationManager()
  let channel: FlutterMethodChannel

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "saveCredentials":
      // UserDefaults standard: token, serverUrl
    case "startSignificantLocationChanges":
      manager.requestAlwaysAuthorization()
      manager.startMonitoringSignificantLocationChanges()
    case "stopSignificantLocationChanges":
      manager.stopMonitoringSignificantLocationChanges()
    default: result(FlutterMethodNotImplemented)
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    // Read token + serverUrl from UserDefaults
    // POST location to API (URLSession background task)
  }
}
```

Mirror Android `LocationHeartbeatWorker.kt` API contract and auth header format.

### 15.3 Backend consideration for VoIP

Today `User` model stores single `fcm_token`. Options:

| Option | Pros | Cons |
|--------|------|------|
| A. Store VoIP token in same field on iOS only | No schema change | Breaks if both tokens needed |
| B. Add `voip_token` field | Clean separation | Backend + auth upload changes |
| C. Send VoIP pushes via FCM with `apns-push-type: voip` using FCM token | Uses existing token | Requires server-side APNs voip headers; still needs PushKit on client |

**Recommend Option B** for production iOS call reliability. Coordinate with `mc_backend_app` agent.

---

## 16. Dart code — platform branches

Files with meaningful `Platform.isAndroid` / `Platform.isIOS` logic:

| File | Behavior |
|------|----------|
| `callkit_service.dart` | `dismissNativeIncoming` — Android only |
| `tameny_location_service.dart` | WorkManager vs iOS SLC |
| `native_prefs_bridge.dart` | iOS `saveCredentials` channel |
| `oem_settings_service.dart` | Almost entirely Android — guard all UI |
| `battery_optimization_helper.dart` | Android only |
| `location_permission_service.dart` | Android OEM settings shortcut |
| `splash_screen.dart` | `in_app_update` Android only |
| `notification_service.dart` | Platform-specific permission + tray dismiss |
| `mobile_messaging_bootstrap.dart` | Both platforms for FCM |
| `auth_provider.dart` | FCM registration both platforms |
| `speech_service.dart` | Both platforms |
| `api_service.dart` | `API_ANDROID_HOST` emulator rewrite — N/A on iOS |

**Rule:** Do not remove Android branches when adding iOS code. Use `Platform.isIOS` / `defaultTargetPlatform` explicitly.

---

## 17. Build and release commands

### 17.1 Development (on Mac)

```bash
cd Flutter_Munawwara
cp .env.example .env   # fill API_BASE_URL, AGORA_APP_ID, etc.
flutter pub get
cd ios && pod install && cd ..
flutter run -d <iphone-device-id>
```

### 17.2 Release build

```bash
flutter build ios --release \
  --dart-define=API_BASE_URL=https://mc-backend-44890250266.europe-west3.run.app/api
```

Then archive in Xcode → Organizer → Distribute to TestFlight / App Store.

### 17.3 Versioning

`pubspec.yaml` `version: 1.1.2+12`:

- `1.1.2` → `CFBundleShortVersionString`
- `12` → `CFBundleVersion`

Bump before each TestFlight upload.

---

## 18. App Store Connect checklist

Parallel to `docs/google-play-policy-review.md`:

| Item | Notes |
|------|-------|
| App Privacy labels | Location (precise + background), audio, contact info, health-related fields, device ID |
| Privacy policy URL | <https://saifisvibinn.github.io/munawwara-privacy/> |
| Support URL / email | <munawwaracare@gmail.com> |
| Age rating | Not directed at children under 13 |
| Demo access | Moderator login + fresh pilgrim QR/code |
| Background location review notes | Pilgrim safety / SOS / group coordination — cite in-app disclosure |
| Brand authorization | Written permission from Munawwara Care brand owner |
| Screenshots | Show map, SOS, calls, location disclosure |
| No IAP / ads | Financial features: No |
| Export compliance | Standard HTTPS encryption — typically "No" for custom encryption |

---

## 19. Testing matrix

### 19.1 Smoke (first iOS build)

- [ ] App launches without `API_BASE_URL` crash
- [ ] Moderator email login → dashboard
- [ ] Pilgrim QR/code login → dashboard
- [ ] Session survives kill + reopen (Keychain)
- [ ] `PUT /api/auth/fcm-token` returns 200 in backend logs
- [ ] Map shows pilgrim location
- [ ] Group chat send/receive

### 19.2 Push & calls (physical device only)

- [ ] Foreground FCM notification received
- [ ] Background FCM wakes app for SOS
- [ ] Incoming call rings via CallKit (app foreground)
- [ ] Incoming call rings (app background)
- [ ] Incoming call rings (app **killed**) — **requires VoIP PushKit**
- [ ] Accept → Agora audio both directions
- [ ] Decline → backend `call-history` updated
- [ ] Caller receives `call_answered` FCM when callee on backgrounded pilgrim device
- [ ] No Agora leak after swipe-back attempt on `VoiceCallScreen`

### 19.3 Location

- [ ] Location permission While Using → map works
- [ ] Enable Tameny tracking → Always permission prompt
- [ ] Background location updates with app backgrounded
- [ ] Significant location change after kill (500m+ move or simulate via Xcode)

### 19.4 Regression safeguards

After any calling change, re-run tests in `docs/voice-calls-architecture.md` §4 (four structural safeguards).

---

## 20. Do not break (critical safeguards)

### 20.1 Voice calling

**Read `docs/voice-calls-architecture.md` before touching:**

- `call_provider.dart`
- `native_call_coordinator.dart`
- `call_navigation.dart` — especially `bypassNavigatingGuard: true`
- `callkit_service.dart`
- `mobile_messaging_bootstrap.dart`
- `voice_call_screen.dart` — `PopScope` guard
- Backend: `call_history_controller.js`, `call_decline_service.js`

### 20.2 Known resolved bugs (do not reintroduce)

1. **Navigation deadlock** — CallKit accept must use `bypassNavigatingGuard: true`
2. **Stale call records** — server auto-expires ringing/in-progress > 5 min
3. **Ring poll** — must filter by `callRecordId`
4. **Background callee** — `call_answered` FCM backup when socket dead

### 20.3 Local plugin fork

Do not switch to pub.dev `flutter_callkit_incoming` without merging Android decline-over-HTTP fix from `plugins/flutter_callkit_incoming/android/`.

---

## 21. Suggested implementation order

```
Phase 1 — Toolchain (Day 1)
  Mac, Xcode, Apple Dev, device, bundle ID, signing, pod install

Phase 2 — Firebase baseline (Day 1–2)
  GoogleService-Info.plist, APNs key, FCM token on login

Phase 3 — Core app (Day 2–3)
  flutter run on device, login both roles, map, chat, profile

Phase 4 — Push notifications (Day 3–4)
  Foreground/background FCM, SOS alert, chat notifications

Phase 5 — CallKit + PushKit (Day 4–7)  ⚠️ hardest
  AppDelegate VoIP, token upload, backend voip_token if needed
  Full call matrix on real devices

Phase 6 — Background location (Day 7–9)
  Location method channel, SLC uploads, App Store justification text

Phase 7 — TestFlight (Day 9–10)
  Archive, upload, internal testers, fix review blockers

Phase 8 — App Store (ongoing)
  Metadata, privacy labels, reviewer notes, submission
```

---

## 22. Related documentation index

| Document | Topic |
|----------|-------|
| `docs/voice-calls-architecture.md` | **Mandatory** before calling work |
| `docs/google-play-policy-review.md` | Android store checklist (mirror for App Store) |
| `docs/privacy-policy.md` | Privacy content source |
| `docs/backend-config.md` | API URL resolution |
| `docs/backend-url-setup-guide.md` | Step-by-step env setup |
| `docs/secure-session-storage.md` | Keychain / JWT |
| `docs/app-languages.md` | i18n + SOS audio |
| `docs/data-sync.md` | Moderator real-time sync |
| `docs/support-requests.md` | In-app support API |
| `docs/app-version-and-about.md` | Version display |
| `docs/muslim-corner-handoff.md` | Islamic Corner module |
| `docs/qibla-compass.md` | Known Qibla bug |
| `docs/bus-attendance-realtime.md` | Bus attendance feature |
| `docs/live_translate_integration_guide.md` | ML translate |
| `lib/app_architecture.md` | High-level architecture (some details dated) |
| `plugins/flutter_callkit_incoming/PUSHKIT.md` | VoIP setup |
| `mc_backend_app/docs/API_DOCUMENTATION.md` | Full REST reference |

---

## Quick reference card (for the next agent)

| Question | Answer |
|----------|--------|
| Where is the Flutter app? | `Flutter_Munawwara/` |
| Current iOS bundle ID? | `com.munawwaracare.ios` |
| Android package? | `com.munawwaracare.android` |
| Firebase project? | `munawwaracare-5353a` |
| Min iOS version? | 15.5 |
| State management? | Riverpod 3 |
| Voice media? | Agora audio (not WebRTC) |
| Incoming calls plugin? | Local fork `plugins/flutter_callkit_incoming` |
| Biggest remaining gap? | Firebase plist + Apple Dev enrollment + device smoke test |
| Apple enrollment first? | **No** for first run; **yes** before push/killed calls/TestFlight |
| Which branch? | `IOS` |
| Repo folder name? | `Munawwara_Care_Flutter` (parent path has a space — disable SPM) |
| CocoaPods on this Mac? | Use `export PATH="$(pwd)/scripts:$PATH"` then `pod install` |
| Can I develop on Windows only? | **No** — need Mac for build/sign/device test |
| First file to edit for calls? | `ios/Runner/AppDelegate.swift` + read `voice-calls-architecture.md` |
| Support email? | <munawwaracare@gmail.com> |
| Production API example? | See `.env.example` / `backend-url-setup-guide.md` |

---

*End of iOS handoff document. Update this file when iOS milestones are completed (bundle ID, PushKit, TestFlight, etc.).*
