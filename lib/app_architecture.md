# Durrah Care — App Architecture Reference

> Last updated: 2026-05-08
> Stack: Flutter 3 · Riverpod 2 · Node.js/Express · MongoDB · Socket.IO · WebRTC (via flutter_webrtc)

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Repository Layout](#2-repository-layout)
3. [Flutter Frontend](#3-flutter-frontend)
   - 3.1 [Entry Point & Router](#31-entry-point--router)
   - 3.2 [Core Layer](#32-core-layer)
   - 3.3 [Feature Modules](#33-feature-modules)
   - 3.4 [State Management](#34-state-management)
   - 3.5 [Real-time Communication](#35-real-time-communication)
4. [Pilgrim Dashboard — Deep Dive & Refactor Log](#4-pilgrim-dashboard--deep-dive--refactor-log)
5. [Moderator Dashboard — Overview](#5-moderator-dashboard--overview)
6. [Calling System](#6-calling-system)
7. [Node.js Backend](#7-nodejs-backend)
8. [Data Flow Diagrams](#8-data-flow-diagrams)
9. [Key Design Decisions](#9-key-design-decisions)

---

## 1. System Overview

Durrah Care is a **Hajj pilgrim management platform**. It connects pilgrims with assigned moderators (group leaders) in real-time. Core capabilities:

| Capability | Pilgrim | Moderator |
|---|---|---|
| Group membership | View only | Create / manage / remove |
| SOS alert | Trigger | Receive + respond |
| Voice call | Receive or initiate | Initiate to group / individual |
| Live map | Self-location + moderator beacon | All pilgrim locations |
| Chat | Group + individual | Group + individual |
| Suggested areas / meetpoints | View + navigate | Create / pin |
| Qibla compass (removed) | — | No |
| Notifications | Yes | Yes |

---

## 2. Repository Layout

```
Durrah care mob app/
├── Flutter_Munawwara/        # Flutter app
│   ├── lib/
│   │   ├── main.dart         # App bootstrap, providers, ScreenUtil init
│   │   ├── core/             # Shared infrastructure (no feature logic)
│   │   └── features/         # Feature modules
│   └── assets/
│       └── translations/     # easy_localization JSON (AR, EN, FR, UR, ...)
└── mc_backend_app/           # Node.js / Express API + Socket.IO
    ├── index.js              # Server entry: Express + Socket.IO + MongoDB
    ├── controllers/          # REST route handlers
    ├── models/               # Mongoose schemas
    ├── routes/               # Express routers
    ├── sockets/              # socket_manager.js — all real-time logic
    ├── services/             # Business helpers (FCM, etc.)
    └── middleware/           # JWT auth, role guards
```

---

## 3. Flutter Frontend

### 3.1 Entry Point & Router

**`main.dart`** bootstraps:
- `ScreenUtilInit` (375 x 812 design baseline)
- `EasyLocalization` (8 language JSON files under `assets/translations/`: en, ar, ur, fr, id, tr, fa, ms)
- `ProviderScope` (Riverpod root)
- `GoRouter` (declarative routing, role-based guards)

Routes are defined in `lib/core/router/`. The root redirect checks `authProvider` role:
- `/login` → `LoginScreen`
- `/pilgrim` → `PilgrimDashboardScreen`
- `/moderator` → `ModeratorDashboardScreen`
- `/location-onboarding` → `LocationPermissionScreen`

### 3.2 Core Layer

```
lib/core/
├── env/                   # .env loader (API base URL, socket URL)
├── map/
│   ├── app_map_tiles.dart          # Base tile layers, zoom clamps, fallback center (Mecca)
│   └── app_map_marker_cluster.dart # Shared clustering layer (flutter_map_marker_cluster)
├── providers/             # App-wide Riverpod providers (theme, locale)
├── router/                # GoRouter definition + guards
├── services/
│   ├── api_service.dart            # Dio singleton — base URL, JWT injection, refresh
│   ├── socket_service.dart         # Socket.IO singleton wrapper (on/off/emit/connect)
│   ├── notification_service.dart   # FCM + flutter_local_notifications
│   ├── callkit_service.dart        # Native call-kit bridge (incoming call UI on locked screen)
│   ├── app_data_cache.dart         # SharedPreferences persistence layer
│   ├── explore_places_service.dart # POI fetch from cached backend endpoint
│   ├── explore_geo.dart            # Haversine distance helpers
│   └── location_permission_service.dart
├── theme/
│   └── app_colors.dart             # Semantic color tokens (light + dark)
├── utils/
│   └── app_logger.dart             # Leveled logger (D/I/W/E) — no-op in release
└── widgets/
    ├── standard_snackbar.dart
    ├── in_app_popup.dart
    ├── reminder_popup.dart
    ├── custom_dialog.dart
    ├── map_circle_fab.dart
    └── qr_scanner_view.dart
```

### 3.3 Feature Modules

Each feature follows the same internal layout:

```
features/<feature>/
├── models/      # Pure Dart data classes (fromJson / toJson)
├── providers/   # Riverpod StateNotifier + state class
├── screens/     # Full-page ConsumerStatefulWidgets
└── widgets/     # Reusable sub-widgets scoped to this feature
```

**Feature inventory:**

| Module | Key screens | Key providers |
|---|---|---|
| `auth` | LoginScreen, SplashScreen | authProvider (JWT, role, profile) |
| `pilgrim` | PilgrimDashboardScreen, GroupInboxScreen, MeccaHotspotsScreen, PilgrimProfileScreen | pilgrimProvider, suggestedAreaProvider |
| `moderator` | ModeratorDashboardScreen, GroupManagementScreen, ManagePilgrimsScreen, SystemRemindersScreen | moderatorProvider, managePilgrimsProvider |
| `calling` | VoiceCallScreen, CallHistoryScreen | callProvider, missedCallsUnreadProvider |
| `notifications` | AlertsTab (embedded) | notificationProvider |
| `shared` | — | messageProvider, suggestedAreaProvider |
| `sos` | SosAlertCoordinator (moderator-side) | — |

### 3.4 State Management

**Riverpod 2** is used throughout with `ConsumerStatefulWidget` for screens that need lifecycle hooks.

```
authProvider          → StateNotifierProvider<AuthNotifier, AuthState>
pilgrimProvider       → StateNotifierProvider<PilgrimNotifier, PilgrimState>
callProvider          → StateNotifierProvider<CallNotifier, CallState>
messageProvider       → StateNotifierProvider<MessageNotifier, MessageState>
notificationProvider  → StateNotifierProvider<NotificationNotifier, NotificationState>
suggestedAreaProvider → StateNotifierProvider<SuggestedAreaNotifier, List<SuggestedArea>>
missedCallsUnreadProvider → StateProvider<int>
```

State classes are **immutable** — notifiers emit new instances via `copyWith`.

`AppDataCache` (SharedPreferences) provides **offline hydration**: every notifier calls `hydrateFromCache()` on startup so the UI renders instantly from cached data, then patches from the network.

Post-mutation sync uses `moderatorProvider.notifier.syncAfterMutation()` (always `force: true`). See [`docs/data-sync.md`](../docs/data-sync.md).

### 3.5 Real-time Communication

**`SocketService`** is a static singleton wrapping `socket_io_client`:

```dart
// Connect with identity
SocketService.connect(serverUrl, userId, role);

// Listen
SocketService.on('event_name', handler);
SocketService.onConnected(handler); // fires on every (re)connect

// Emit
SocketService.emit('event_name', payload);

// Teardown
SocketService.off('event_name');
SocketService.offConnected(handler);
```

Only top-level dashboard screens register listeners. Child widgets receive data via constructor params — they never call `SocketService` directly.

---

## 4. Pilgrim Dashboard — Deep Dive & Refactor Log

### 4.1 File

`lib/features/pilgrim/screens/pilgrim_dashboard_screen.dart`

### 4.2 Architecture

The dashboard is a `ConsumerStatefulWidget` that owns:
- All SOS lifecycle state (timers, phase enum, status keys)
- GPS position stream subscription
- Socket event registrations (15 events)
- Weather data fetch + refresh timer
- Map controller
- Battery reader
- Tab navigation state

It composes its UI from **fully decoupled child widgets** passed by constructor:

```
PilgrimDashboardScreen
└── _PilgrimDashboardScreenState (ConsumerState)
    ├── [Tab 0] PilgrimHomeTab           widgets/home_tab/home_tab.dart
    ├── [Tab 1] PilgrimMapTab            widgets/map_tab/pilgrim_map_tab.dart
    ├── [Tab 2] Empty placeholder (was Qibla — see docs/qibla-compass-restore.md)
    ├── [Tab 3] GroupInboxScreen         screens/group_inbox_screen.dart
    ├── [Tab 4] PilgrimProfileScreen     screens/pilgrim_profile_screen.dart
    └── PilgrimBottomNav                 widgets/bottom_nav.dart
```

### 4.3 SOS Lifecycle

```
Idle ──[hold 3 s]──► triggerSOS() ──► POST /api/sos/trigger
                                             │
                                     [sosActive = true]
                                             │
                                  SosHomePhase.helpSession
                                             │
                      ┌──────────────────────┴──────────────────────┐
                 [60 s auto-call timer]                   [sos-handling socket event]
                      │                                              │
             startGroupModeratorCall()                   _stopSosHelpTimers()
             VoiceCallScreen shown                       status → 'reviewing'
                      │
             [call ends OR sos-resolved socket]
                      │
             SosHomePhase.idle (panel dismissed)
```

**State variables driving SOS:**

| Variable | Type | Purpose |
|---|---|---|
| `_sosHomePhase` | `SosHomePhase` | idle vs helpSession |
| `_sosHelpStatusKey` | `String` | i18n key shown in help panel |
| `_sosModeratorName` | `String` | Name received from sos-handling |
| `_sosHelpPhaseTimer` | `Timer?` | Delays "notifying" → "waiting" status |
| `_sosAutoCallTimer` | `Timer?` | 60 s trigger for auto group-call |
| `_sosVoiceFollowup` | `bool` | True while SOS-spawned call is active |

### 4.4 Refactor — What Changed

#### Before

`pilgrim_dashboard_screen.dart` was a **single 3 902-line / 154 KB file** containing 13 private widget classes alongside the screen state.

#### After

The screen is **1 385 lines / 52 KB**. All sub-components are public, independently testable files:

```
features/pilgrim/widgets/
│
├── bottom_nav.dart
│   └── PilgrimBottomNav                 ← was _BottomNav
│
├── home_tab/
│   ├── home_tab.dart
│   │   ├── PilgrimHomeTab               ← was _HomeTab
│   │   └── _HomeBody                    (private, inside home_tab.dart)
│   └── home_cards.dart
│       ├── WeatherAlert (model)         ← was _WeatherAlert
│       ├── WeatherCard                  ← was _WeatherCardNew
│       ├── GroupCard                    ← was _GroupCardNew
│       └── ExploreCard                  ← was _ExploreCardNew
│
├── map_tab/
│   ├── pilgrim_map_tab.dart
│   │   └── PilgrimMapTab               ← was _PilgrimMapTab
│   ├── pilgrim_area_marker.dart
│   │   ├── PilgrimAreaMarker           ← was _PilgrimAreaMarker
│   │   └── showAreaInfo()              ← was _showAreaInfo()
│   └── suggestions_cycle_button.dart
│       └── SuggestionsCycleButton      ← was _SuggestionsCycleButton
│
└── sos/
    ├── sos_home_phase.dart
    │   └── enum SosHomePhase           ← was enum _SosHomePhase
    ├── sos_button.dart
    │   ├── SosButton                   ← was _SosButton
    │   ├── SosHoldingContent           ← was _SosHoldingContent
    │   └── SosIdleContent              ← was _SosIdleContent
    └── sos_help_session_panel.dart
        └── SosHelpSessionPanel         ← was _SosHelpSessionPanel (simplified)

features/pilgrim/screens/
    └── pilgrim_notifications_screen.dart ← was _PilgrimNotificationsScreen
```

#### SosHelpSessionPanel — Option B simplification

The refactored panel dropped `callCountdown` (no countdown ring). It displays:
- **Spinner** — when status is notifying / waiting / seen
- **Green checkmark** — when status is `responding` (moderator acknowledged)
- **Status text** — i18n key from `_sosHelpStatusKey`
- **Cancel button** — disabled when moderator is responding

#### Impact summary

| Metric | Before | After |
|---|---|---|
| Dashboard file size | 3 902 lines / 154 KB | 1 385 lines / 52 KB |
| Inline private widget classes | 13 | 0 |
| Public reusable widget files | 0 | 9 |
| `dart analyze` issues | 0 | 0 |

---

## 5. Moderator Dashboard — Overview

`lib/features/moderator/screens/moderator_dashboard_screen.dart` (~86 KB)

The moderator dashboard is a monolithic orchestration screen owning:
- **Group management** — create/join/delete, add pilgrims via QR or join code
- **Live pilgrim map** — all pilgrim GPS pins updated via socket beacons (`mod_nav_beacon`)
- **SOS coordination** — `SosAlertCoordinator` handles incoming SOS; moderator Accept emits `sos-handling` → pilgrim sees "reviewing" state
- **Messaging** — group + individual thread views
- **Navigation beacon** — moderator broadcasts live location to group
- **System reminders** — push scheduled alerts to all pilgrims

---

## 6. Calling System

```
features/calling/
├── call_signaling.dart           # WebRTC offer/answer/ICE helpers
├── calling_scope.dart            # InheritedWidget scope for active call
├── native_call_coordinator.dart  # Bridges FCM data message → callkit_service
│                                 #   Handles killed-state incoming calls
│                                 #   isNavigatingToCall flag prevents duplicate nav
├── providers/
│   ├── call_provider.dart        # StateNotifier: WebRTC peer + call state machine
│   └── missed_calls_unread_provider.dart
└── screens/
    ├── voice_call_screen.dart
    └── call_history_screen.dart
```

**Call flow (SOS auto-call):**

1. `_PilgrimDashboardScreenState._onSosAutoCallElapsed()` calls `callProvider.startGroupModeratorCall(modMaps)`
2. `callProvider` emits `start-group-call` socket → server broadcasts `incoming-call` to each moderator
3. Moderator FCM push → `native_call_coordinator` shows incoming call UI
4. On accept → WebRTC signaling (offer / answer / ICE via socket)
5. `VoiceCallScreen` renders for both parties
6. On hang-up → `call-ended` socket → both sides tear down peer

**Killed-state handling:** `notification_service.dart` + `callkit_service.dart` handle FCM data messages when the app is fully killed, showing a native call UI without launching Flutter, then routing to `VoiceCallScreen` on accept.

---

## 7. Node.js Backend

### Stack

- **Runtime:** Node.js + Express
- **Database:** MongoDB (Mongoose)
- **Real-time:** Socket.IO
- **Auth:** JWT (access token in Authorization header, refresh via `/auth/refresh`)
- **Push:** Firebase Admin SDK (FCM)
- **Deployment:** Google Cloud Run (containerized)

### REST Controllers

| Controller | Responsibility |
|---|---|
| `auth_controller.js` | Register, login, refresh token, profile fetch |
| `group_controller.js` | CRUD groups, pilgrim membership, suggested areas/meetpoints |
| `message_controller.js` | Group + individual messages, unread counts |
| `call_history_controller.js` | Store/retrieve call records; `/decline` endpoint has no auth (killed-state) |
| `notification_controller.js` | Notification records + badge count |
| `profile_controller.js` | Profile photo upload, field updates |
| `reminder_controller.js` | Moderator-scheduled push reminders |
| `invitation_controller.js` | Pilgrim join codes + QR |
| `communication_controller.js` | Communication session tracking |

### MongoDB Models

| Model | Key fields |
|---|---|
| `User` | role, group_id, sos_active, lat/lng, battery, fcm_token |
| `Group` | moderator_id, pilgrim_ids, hotel, name |
| `Message` | group_id / recipient_id, sender, content, is_urgent |
| `SuggestedArea` | group_id, lat/lng, is_meetpoint, meetpoint_time |
| `Notification` | recipient_id, type, body, read |
| `CallHistory` | caller_id, callee_ids, status, duration |
| `Reminder` | group_id, title, body, scheduled_at |
| `POI` | lat/lng, category, name (seeded Hajj POI cache) |

### Socket Manager (`socket_manager.js`)

All real-time events live in a single file. Key events:

| Client → Server | Purpose |
|---|---|
| `join_group` | Subscribe to group room |
| `sos_trigger` | Broadcast SOS to moderators |
| `sos-handling` | Moderator acknowledged → echo to pilgrim |
| `sos-resolved` | Moderator resolved → cancel pilgrim panel |
| `mod_nav_beacon` | Broadcast moderator live location |
| `start-group-call` | Initiate group WebRTC call |
| `new_message` | Broadcast chat message to group |
| `area_added / area_deleted` | Sync suggested areas in real-time |
| `notification_refresh` | Trigger badge refresh on group members |
| `force_logout` | Server-initiated logout (code refresh) |

---

## 8. Data Flow Diagrams

### SOS Trigger → Moderator Response

```
Pilgrim (Flutter)              Backend (Node.js)          Moderator (Flutter)
      │                               │                          │
      │── POST /api/sos/trigger ─────►│                          │
      │◄─ { sosId, ok } ─────────────│                          │
      │                               │── socket: sos_alert ────►│
      │                               │── FCM push ─────────────►│
      │                               │                          │
      │    [Moderator taps Handle]    │                          │
      │                               │◄─ socket: sos-handling ──│
      │◄── socket: sos-handling ──────│                          │
      │  panel → "reviewing" state    │                          │
      │                               │                          │
      │    [Moderator taps Resolve]   │                          │
      │                               │◄─ socket: sos-resolved ──│
      │◄── socket: sos-resolved ──────│                          │
      │  panel dismissed, idle        │                          │
```

### Moderator Navigation Beacon

```
Moderator enables beacon toggle
       │
       └──► socket: mod_nav_beacon { lat, lng, enabled: true }
                         │
                    Backend → broadcast to group room
                         │
            ┌────────────┴────────────┐
            ▼                         ▼
    Pilgrim A map marker        Pilgrim B map marker
    (PilgrimMapTab beacon layer)
```

---

## 9. Key Design Decisions

### One file per widget (post-dashboard refactor)
Any widget that can be named or reused goes in its own file under `widgets/`. Screens contain only state logic and orchestrate child widgets via constructor parameters.

### Riverpod for shared state, setState for ephemeral UI
Cross-screen state (auth, pilgrim data, call state, messages) lives in Riverpod providers. Ephemeral UI state (SOS timers, animation controllers, tab index) stays local in `State`.

### Socket singleton, listeners only at screen level
`SocketService` is a static singleton. Only top-level dashboard screens register/deregister listeners. Child widgets receive data as constructor parameters — they never call `SocketService` directly.

### AppDataCache for offline resilience
Every provider caches its last known state to `SharedPreferences`. On cold start, `hydrateFromCache()` runs before the API call, giving the UI instant data while fresh data loads in the background.

### No countdown ring in SosHelpSessionPanel (Option B)
The original design included a 30-second countdown ring. It was removed in favour of a spinner + status text approach to avoid adding a visible pressure timer during an already high-stress SOS moment.

### Backend POI cache (vs live Overpass API)
The Explore tab fetches from a MongoDB POI cache (`/api/poi/nearby`) seeded by `seed_pois.js`, avoiding Overpass API rate limits and reducing latency for Hajj-critical regions.
