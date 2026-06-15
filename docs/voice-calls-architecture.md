# Munawwara Care — Voice Calls Architecture & Handoff Guide

> [!CAUTION]
> # CRITICAL DEVELOPER & AI AGENT WARNING
> **THE VOICE-CALLING WORKFLOW IN THIS APPLICATION IS HIGHLY DELICATE AND COALESCES NATIVE DEVICE SYSTEMS, OS BACKGROUND ISOLATES, FIREBASE CLOUD MESSAGING (FCM), SOCKET.IO, CALLKIT, AND AGORA RTC MEDIA LAYERS.**
>
> **Calls are working on Android and iOS (June 2026). DO NOT refactor, rewrite, or “simplify” calling files without reading this entire document.**
>
> A single careless change in states, navigation guards, iOS audio session handling, or socket ACK logic can:
> 1. Cause silent **routing deadlocks** (call screen never opens).
> 2. Leave **stale records** in MongoDB, blocking subsequent calls.
> 3. Leave **Agora active** in the background (mic open, battery drain).
> 4. Cause devices to **ring indefinitely** or **auto-decline** incoming calls.
> 5. Break **Android ↔ iOS** cross-platform calls while Android-only tests still pass.

---

## 1. High-Level Blueprint

Voice calling uses a **dual-layer model** shared by Android and iOS:

1. **Signaling (Socket.IO + REST + FCM)**: Offers, rings, accepts, declines, cancellations, state sync. REST fallbacks recover when sockets are dead or “ghost” (client thinks connected, server evicted).
2. **Media (Agora RTC)**: Low-latency voice. Both parties fetch a temporary token from `/call-history/agora-token` and join the same channel **after** signaling says the call is accepted.

**Native ring UI**: Both platforms use `flutter_callkit_incoming` (CallKit on iOS, Telecom/ConnectionService on Android). Agora does **not** replace CallKit — it only carries audio once the call is accepted.

```mermaid
sequenceDiagram
    autonumber
    actor Caller as Caller
    participant Server as Node.js Backend
    actor Callee as Callee (CallKit)

    Caller->>Server: POST /call-history/offer (preferred) or socket call-offer
    Note over Server: CallHistory status = ringing
    Server-->>Callee: socket call-offer + FCM incoming_call (parallel)
    Note over Callee: CallKit incoming UI
    Callee->>Server: socket call-answer + POST /call-history/answer
    Note over Server: status = in-progress; FCM call_answered to caller
    Note over Caller: Join Agora
    Note over Callee: Wait CallKit audio session → Join Agora
```

### Platform summary

| Concern | Android | iOS |
|--------|---------|-----|
| Incoming ring | FCM + socket → CallKit plugin | Same (+ PushKit VoIP when entitled) |
| Accept / decline events | Usually reliable on event channel | **Often dropped** — needs polls + native bridge |
| Audio before Agora | Agora owns session directly | **CallKit activates AVAudioSession first** (Apple requirement) |
| Killed-state ring | FCM data | FCM when app running; **VoIP push** for production killed-state (paid Apple account) |

---

## 2. Resolved Bugs (Do Not Reintroduce)

### Bug 1: Pilgrim accepts but no VoiceCallScreen (double deadlock)

* **Cause**: Dashboard listeners missed `ringing → connecting`; `openVoiceCallScreen()` blocked itself because `isNavigatingToCall` was already true.
* **Fix**: Dashboards listen for `ringing → connecting` and `connecting → connected`. `NativeCallCoordinator._tryPushVoiceCall()` passes `bypassNavigatingGuard: true`.

### Bug 2: Third call fails (stale MongoDB records)

* **Cause**: Stuck `ringing` / `in-progress` rows made `check-active` return `active: true` forever.
* **Fix**: Server auto-expires records older than 5 minutes in `check_call_active`. Client ring-poll filters by exact `callRecordId` from `/offer`.

### Bug 3: Pilgrim calls back → moderator accepts → pilgrim keeps ringing

* **Cause**: Background pilgrim missed socket `call-answer`.
* **Fix**: Server sends FCM `call_answered`; client handles it in `mobile_messaging_bootstrap.dart` / `NativeCallCoordinator`.

### Bug 4: iOS accept does nothing / moderator keeps ringing (event channel gap)

* **Cause**: `Event.actionCallAccept` often never reaches Dart on iOS (Flutter implicit engine / CallKit event-channel race). Callee never emitted `call-answer`.
* **Fix (DO NOT REMOVE)**:
  * `_startIosCallKitRingPoll()` in `call_provider.dart` — polls `FlutterCallkitIncoming.activeCalls()` for `accepted == true`, then runs `acceptCall()`.
  * `actionCallToggleAudioSession` with `isActivate: true` in `native_call_coordinator.dart` — fallback accept when ringing.
  * `NativeCallCoordinator.registerEarlyListeners()` + `CallingScope.riverpod` set in `main.dart` **before** async Firebase init.

### Bug 5: iOS decline → Android keeps ringing

* **Cause**: Same event-channel gap for `actionCallDecline` / `actionCallEnded`.
* **Fix (DO NOT REMOVE)**:
  * `AppDelegate.onDecline` / `onTimeOut` → `CallKitAudioChannelHandler.notifyCallDeclined` → `CallKitAudioBridge` → `NativeCallCoordinator.handleNativeCallDeclined`.
  * Ring poll: after `activeCalls()` **first shows** an entry, **3 consecutive empty polls** (~1.2s) → `declineCall()`. **Never** set “saw CallKit ring” at `showIncomingCall` time — that caused instant false declines.
  * Decline emits socket + **awaits** HTTP `POST /call-history/decline` (with `callRecordId`) **before** `forceIdleCallSession`.

### Bug 6: Socket ACK on `call-offer` evicted iOS sockets / blocked second call

* **Cause**: Server waited for socket ACK; iOS rarely ACKed; server evicted pilgrim socket; next call had no live socket.
* **Fix (backend — deployed)**: `call_offer_service.js` emits plain `io.to(user_${to}).emit('call-offer', offerPayload)` with **no ACK**. Client uses `SocketService.on('call-offer', …)` not `onWithAck`.

### Bug 7: iOS `Session activation failed` / no audio on connect

* **Cause**: Plugin + Agora both fought for `AVAudioSession` before CallKit elevated the session.
* **Fix (DO NOT REMOVE)**:
  * `IOSParams`: `configureAudioSession: false`, `audioSessionActive: false` in `callkit_service.dart` (and PushKit mapper in `AppDelegate.swift`).
  * `CallKitAudioBridge` + `CallKitAudioChannelHandler.swift`: `didActivateAudioSession` → Dart → `AgoraRtcService.onCallKitAudioSessionActivated()`.
  * `acceptCall()` on iOS: `await CallKitAudioBridge.ensureReadyBeforeMediaJoin()` before Agora join.
  * Agora init on iOS: `setAudioSessionOperationRestrictionAll` until CallKit activates.

---

## 3. Component Directory

```
Munawwara_Care_Flutter/
├── lib/
│   ├── features/calling/
│   │   ├── providers/call_provider.dart      # State machine, Agora, ring poll, iOS CallKit poll
│   │   ├── native_call_coordinator.dart      # CallKit events, FCM control, native decline bridge
│   │   ├── call_signaling.dart               # Socket + HTTP /offer /answer /decline /cancel
│   │   ├── call_navigation.dart              # openVoiceCallScreen(bypassNavigatingGuard)
│   │   └── screens/voice_call_screen.dart    # In-call UI + PopScope
│   ├── core/
│   │   ├── services/
│   │   │   ├── callkit_service.dart          # showIncomingCall, IOSParams, dismiss
│   │   │   ├── callkit_audio_bridge.dart     # iOS didActivate + native decline MethodChannel
│   │   │   ├── agora_rtc_service.dart        # Join/leave, CallKit audio handoff
│   │   │   └── socket_service.dart           # Socket.IO; plain on() for call-offer
│   │   └── bootstrap/mobile_messaging_bootstrap.dart
│   └── main.dart                             # CallingScope + early CallKit/audio listeners
├── ios/Runner/
│   ├── AppDelegate.swift                     # PushKit (if entitled), onDecline → bridge
│   └── CallKitAudioChannelHandler.swift      # Native → Dart audio + decline
├── scripts/
│   ├── pod                                   # CocoaPods wrapper (Ruby 2.6 Logger fix)
│   └── flutter_ios.sh                        # flutter run with scripts/ on PATH
└── docs/voice-calls-architecture.md          # This file

mc_backend_app/
├── services/call_offer_service.js            # Parallel socket emit + FCM; NO socket ACK
├── services/call_decline_service.js          # FCM call_declined / call_answered to caller
├── controllers/call_history_controller.js    # REST + stale expiry
└── sockets/socket_manager.js                 # call-answer, call-declined, etc.
```

---

## 4. Structural Safeguards (Guards)

### Guard 1: Coordinator navigation lock (`bypassNavigatingGuard`)

`NativeCallCoordinator._tryPushVoiceCall()` **must** call:

```dart
openVoiceCallScreen(bypassNavigatingGuard: true);
```

### Guard 2: Stale call record expiry (server)

`check_call_active` expires `ringing` / `in-progress` older than 5 minutes before checking activity.

### Guard 3: Ring-poll `callRecordId` filtering

Outgoing ring poll must pass the `callRecordId` returned from `/offer` so it does not match a previous dead session.

### Guard 4: PopScope on VoiceCallScreen

`canPop` only when `ended` or `idle` — prevents swipe-back leaving Agora running.

### Guard 5: Android IncomingCallService tray (Android only)

Do not cancel FGS notification id `9999` during incoming ring; only on end/cancel/decline paths.

### Guard 6: iOS CallKit ring poll — accept path

While `CallStatus.ringing`, poll `activeCalls()` for accepted call → `acceptCall()` → `openVoiceCallScreen(bypassNavigatingGuard: true)`.

**Do not remove** because iOS often skips `actionCallAccept`.

### Guard 7: iOS CallKit ring poll — decline path

Decline via poll **only when**:

1. Poll has **seen** `activeCalls()` non-empty at least once (`_iosSawCallKitRing`), **and**
2. `activeCalls()` is empty for **3 consecutive** polls (~1.2s).

**Never** set `_iosSawCallKitRing = true` at `showIncomingCall` time — causes immediate false decline.

Prefer native `AppDelegate.onDecline` → `handleNativeCallDeclined` for user-initiated decline.

### Guard 8: iOS audio session before Agora

Order on callee accept:

1. User accepts (CallKit).
2. System fires `didActivateAudioSession` → `CallKitAudioBridge`.
3. `call-answer` signaling (socket + HTTP).
4. `ensureReadyBeforeMediaJoin()` if CallKit session active.
5. `AgoraRtcService.joinVoiceChannel()`.

**Do not** set `audioSessionActive: true` or `configureAudioSession: true` on incoming `IOSParams` — causes `Session activation failed`.

### Guard 9: Decline signaling before local teardown

`_declineCallInternal` must **await** `_emitDeclineSignaling` (socket + HTTP with `callRecordId`) **before** `forceIdleCallSession`. Use `_declineSignalingInFlight` to dedupe native bridge + poll.

### Guard 10: Ignore spurious `actionCallEnded` after iOS accept

`native_call_coordinator.dart` ignores `actionCallEnded` when `connecting`, `connected`, `isNavigatingToCall`, or `_pendingAcceptedCall` — iOS fires ended right after accept.

### Guard 11: No socket ACK on `call-offer` (server + client)

Server: plain emit in `call_offer_service.js`. Client: `SocketService.on('call-offer', …)` — not `onWithAck`.

---

## 5. Golden Rules

1. **Outgoing offers**: Prefer `POST /call-history/offer` (especially pilgrim / background).
2. **FCM call control** (`call_declined`, `call_cancel`, `call_ended`, `call_answered`): Silent data only — never show as chat notifications.
3. **Dashboard listeners**: Watch `ringing → connecting` and `connecting → connected`.
4. **Post-call cooldown**: Keep 10s `hasRecentCallCooldown` in `call_provider.dart`.
5. **PopScope**: Never remove from `voice_call_screen.dart`.
6. **Deploy backend** before testing signaling changes (`mc_backend_app/redeploy_cloudrun.sh`).
7. **Do not “unify” iOS into Android-only paths** — iOS needs CallKit poll, audio bridge, and native decline. Same architecture, extra adapters.
8. **Do not re-add socket ACK** on `call-offer` without fixing iOS ACK delivery and removing server socket eviction.
9. **iOS dev**: Run via `./scripts/flutter_ios.sh run --dart-define-from-file=.env` (CocoaPods needs `scripts/pod` on PATH).
10. **Run `flutter analyze`** before committing calling changes.

---

## 6. Dev & Test Commands

```bash
# iOS device (CocoaPods wrapper on PATH)
cd Munawwara_Care_Flutter
./scripts/flutter_ios.sh run --dart-define-from-file=.env

# Or add once to ~/.zshrc:
# export PATH="/path/to/Munawwara_Care_Flutter/scripts:$PATH"

# Backend redeploy (after mc_backend_app signaling changes)
cd mc_backend_app && bash redeploy_cloudrun.sh
```

### Smoke test checklist (Android ↔ iOS)

- [ ] Moderator → Pilgrim: rings on iOS CallKit
- [ ] Accept: `call-answer` logged, Agora join both sides, audio heard
- [ ] Decline: `call-declined` + HTTP decline, Android stops ringing within ~2s
- [ ] Second call in same session without hot restart
- [ ] Cancel outgoing while ringing

---

## 7. Production iOS (paid Apple Developer — not required for foreground dev)

* Enable Push Notifications + VoIP entitlement.
* Server sends **APNs VoIP push** (not only FCM) for killed-state incoming calls.
* `AppDelegate` PushKit handler already maps payload → `showCallkitIncoming(fromPushKit: true)`.

Until then, iOS incoming calls work when the app is running or recently backgrounded (socket + FCM data).

---

*Last verified working: June 2026 — Android ↔ iOS voice calls with Agora on Cloud Run backend `mc-backend-prod1`.*
