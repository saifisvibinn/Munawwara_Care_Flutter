# Munawwara Care — PushKit & CallKit Checklist

> **Purpose:** End-to-end setup and App Store compliance for iOS VoIP incoming calls.  
> **Master flow doc:** [voice-calls-complete-flow.md](./voice-calls-complete-flow.md)  
> **Plugin reference:** [plugins/flutter_callkit_incoming/PUSHKIT.md](../plugins/flutter_callkit_incoming/PUSHKIT.md) (Apple portal steps; we use `.p8` token auth, not legacy `.p12`)

---

## Apple policy (must follow)

1. **VoIP push (`pushType: voip`) is only for incoming voice calls** — never chat, SOS, reminders, or `call_ended`.
2. **Every VoIP push must present CallKit UI** before calling PushKit `completion()`.
3. **Do not pre-activate AVAudioSession** before the user answers (`configureAudioSession: false`).
4. **CallKit End must tear down the server session** — native `postEnd` on hangup (lock screen included).

Non-call notifications use **FCM / standard APNs** only.

---

## Xcode capabilities

| Capability | Where | Notes |
|------------|-------|-------|
| Push Notifications | Signing & Capabilities | Required |
| Background Modes | `Info.plist` `UIBackgroundModes` | `voip`, `audio`, `remote-notification` (+ `location`, `fetch` for pilgrim safety) |
| CallKit | Via `flutter_callkit_incoming` | Incoming call UI |

**Entitlements:** `ios/Runner/Runner-Release.entitlements` — `aps-environment: production` for Archive/TestFlight.

---

## Native wiring (iOS)

| File | Role |
|------|------|
| `ios/Runner/AppDelegate.swift` | `PKPushRegistry`, VoIP push → `showCallkitIncoming(fromPushKit:completion:)` |
| `ios/Runner/CallSignalingBridge.swift` | Killed/background HTTP: `postAnswer`, `postDecline`, **`postEnd`** |
| `ios/Runner/CallKitAudioChannelHandler.swift` | Method channel `com.munawwaracare/callkit_audio` |
| `lib/core/services/callkit_audio_bridge.dart` | Wait for CallKit audio before Agora join |

### CallKit delegate → server

| User action | Native HTTP | Dart notify |
|-------------|-------------|-------------|
| Accept | `POST /call-history/answer` | `callAccepted` |
| Decline | `POST /call-history/decline` | `callDeclined` (450ms defer) |
| Timeout | `POST /call-history/decline` (noAnswer) | `callDeclined` |
| **End (lock screen)** | **`POST /call-history/end`** | **`callEnded`** |

---

## Dart wiring

| Step | File |
|------|------|
| Early CallKit listeners | `main.dart` → `NativeCallCoordinator.registerEarlyListeners()` |
| VoIP token lifecycle | `mobile_messaging_bootstrap.dart` → `bindIosVoipTokenLifecycle()` |
| Upload token | `auth_provider.dart` → `PUT /auth/voip-token` |
| Accept/decline/end bridges | `CallKitAudioBridge.onNativeCallAccepted/Declined/Ended` |

---

## Backend (APNs VoIP)

| Item | Detail |
|------|--------|
| Service | `mc_backend_app/services/apns_voip_service.js` |
| Auth | `.p8` key (not `.p12`) |
| Topic | `{bundleId}.voip` (e.g. `com.munawwaracare.ios.voip`) |
| Payload type | `incoming_call` only |
| User field | `apns_voip_token` on User model |

### Required env vars (production)

```
APNS_KEY_ID=
APNS_TEAM_ID=
APNS_BUNDLE_ID=com.munawwaracare.ios
APNS_PRIVATE_KEY=   # .p8 contents
APNS_PRODUCTION=true
```

---

## Test matrix (physical iPhone, TestFlight)

| # | State | Action | Pass criteria |
|---|-------|--------|---------------|
| 1 | Foreground | Incoming call → accept | Two-way Agora audio |
| 2 | Background | Same | CallKit ring → accept → connected |
| 3 | **Killed** | Same | VoIP wake → CallKit → `POST /answer` before Flutter boot → audio |
| 4 | Killed | Decline | Caller stops ringing; `POST /decline` in logs |
| 5 | Foreground, **screen off** | Accept → talk → **End on lock screen** | `POST /end`; caller idle; unlock → not in-call |
| 6 | After 5 | Second call immediately | Connects; no ghost / instant drop |

**Log grep:** `VoIP push delivered`, `POST /call-history/answer`, `[CallSignaling] Native END ->`

---

## App Store reviewer notes (template)

- Voice calls use **Agora RTC + CallKit**.
- **PushKit VoIP** is used **only** for incoming voice calls when the app is terminated.
- **FCM / standard push** handles chat, SOS alerts, missed calls — **not** VoIP.
- Background location is for pilgrim safety (separate from VoIP); see in-app disclosure.
- Provide moderator + pilgrim demo accounts and a fresh QR code.

See also: [ios-app-store-review.md](./ios-app-store-review.md)

---

## Common failures

| Symptom | Likely cause |
|---------|----------------|
| No ring when killed | Missing/wrong APNs `.p8` env; VoIP token not uploaded |
| Ring but no audio | CallKit audio not activated before Agora join |
| Ghost call after lock-screen end | Fixed: ensure `postEnd` + Dart `endCall` on `actionCallEnded` when `connected` |
| Double ring | Socket + FCM + VoIP dedup — see voice-calls §9 |
