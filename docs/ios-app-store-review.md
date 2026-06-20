# Munawwara Care — iOS App Store: rejection risks

**Purpose:** Issues that may cause App Store rejection or a failed review.  
**App:** Munawwara Care (Flutter iOS) — bundle ID `com.munawwaracare.ios`, branch `IOS`  
**Last updated:** June 2026

Items marked **Done** were implemented on branch `IOS`. Re-verify before submission.

---

## Critical — fix before submission

| # | Issue | Status | Notes |
|---|--------|--------|-------|
| 1 | **Push / VoIP entitlements** | **Done** | `Runner-Release.entitlements` has `aps-environment: production`. Verify Push capability on paid team before Archive. Test killed-state CallKit + lock-screen hangup (`POST /end`). See [pushkit_doc.md](./pushkit_doc.md). |
| 2 | **Background modes `voip` + `remote-notification`** | **Done** | Added to `Info.plist` `UIBackgroundModes`. |
| 3 | **In-app account deletion** | **Done** | `DELETE /api/auth/account` + About → confirm → delete → sign out. Moderators see admin note only. |
| 4 | **Release `API_BASE_URL`** | **Done** | `.env` removed from assets; use `--dart-define=API_BASE_URL=...`. See `docs/env-and-release-builds.md`. |

---

## High — strong rejection risk

| # | Issue | Status | Notes |
|---|--------|--------|-------|
| 5 | Photo library usage strings | **Done** | Pick + save QR codes in `Info.plist`. |
| 6 | Rate app opens Play Store on iOS | **Done** | `in_app_review` on iOS; Play Store on Android. |
| 7 | Mic/camera Podfile macros | **Done** | `PERMISSION_MICROPHONE=1`, `PERMISSION_CAMERA=1`. |
| 8 | Background location scrutiny | **Connect + review** | In-app disclosure exists. **Paid account:** App Store Connect privacy labels + reviewer notes + demo accounts. |
| 9 | Privacy policy live | **Open** | Sync `docs/privacy-policy.md` with live URL before submit. |
| 10 | Runner privacy manifest | **Done** | `ios/Runner/PrivacyInfo.xcprivacy`. |

---

## Medium — polish

| # | Issue | Status |
|---|--------|--------|
| 11 | Launch screen placeholders | **Done** — branded from `app_icon.png` |
| 12 | SOS English typo | **Done** |
| 13 | Report categories hardcoded | **Done** — localized `report_cat_*` keys |
| 14 | Moderator deletion UX | **Done** |
| 15 | Export compliance plist key | **Done** — `ITSAppUsesNonExemptEncryption=false` |
| 16 | Reminders tab 404 | **Open** — backend `GET /reminders` if reviewers use tab |
| 17 | `.env` in release assets | **Done** |

---

## Requires paid Apple Developer Program ($99/yr)

Do these **after** enrollment at [developer.apple.com/programs](https://developer.apple.com/programs/):

| Step | Action |
|------|--------|
| 1 | Create/confirm App ID `com.munawwaracare.ios` with **Push Notifications** + **Background Modes** (VoIP, Remote notifications, Location, Audio) |
| 2 | Xcode → Runner → Signing & Capabilities → paid **Team** |
| 3 | Restore `aps-environment` in `ios/Runner/Runner.entitlements` |
| 4 | Apple Developer → Keys → APNs Auth Key (`.p8`) → Firebase Console (`munawwaracare-5353a`) → Cloud Messaging → upload for iOS app |
| 5 | Rebuild; verify `PUT /api/auth/fcm-token` and **`PUT /api/auth/voip-token`** after login |
| 6 | Test push: SOS, chat; CallKit: foreground → background → **killed** → **lock-screen end** |
| 7 | **Optional:** backend `voip_token` field for reliable killed-state VoIP |
| 8 | Xcode → Archive → **TestFlight** internal test |
| 9 | **App Store Connect:** app record, screenshots, age rating, **App Privacy** labels, support URL |
| 10 | Submit with reviewer notes (template below) |

**Still works on free Personal Team (USB):** login, map, chat, foreground Agora calls, location, session restore. App expires ~7 days; no push/killed CallKit/TestFlight.

---

## Pre-submission checklist

### Done (no paid account)

- [x] Info.plist: voip, remote-notification, photo strings, encryption export key
- [x] Podfile mic/camera macros; `PrivacyInfo.xcprivacy`; branded launch screen
- [x] In-app account deletion; iOS rate app; env via dart-define (`docs/env-and-release-builds.md`)
- [x] SOS typo, localized report categories, moderator deletion note

### Requires paid Apple Developer

- [ ] Enroll; Push + VoIP capabilities in Xcode
- [ ] `Runner.entitlements` includes `aps-environment`
- [ ] APNs `.p8` in Firebase for `com.munawwaracare.ios`
- [ ] Push + killed-state CallKit tested on physical device
- [ ] TestFlight upload + smoke test
- [ ] App Store Connect: metadata, screenshots, privacy labels, reviewer notes
- [ ] Privacy policy published and matches in-app URL

### Before submit (any account)

- [ ] Release IPA with production `API_BASE_URL`, `AGORA_APP_ID`, `UMMAH_API_KEY` dart-defines
- [ ] Cold-launch test on device
- [ ] Demo moderator + fresh pilgrim QR for reviewers

---

## Reviewer notes template (App Store Connect)

> **Test accounts**  
> Moderator: [email] / [password]  
> Pilgrim: one-time QR/code — contact [email] for a fresh code if expired  
>
> **Background location**  
> Pilgrims share location with their assigned group moderator for safety, meetpoints, and SOS. Always permission is optional and explained in-app before the system prompt.  
>
> **VoIP / Push**  
> Voice calls use Agora with CallKit for group safety. Push is used for SOS, chat, and incoming call alerts — not marketing.  
>
> **Account deletion**  
> Profile → About → Delete account → confirm → account removed immediately.

---

## Related docs

- `docs/env-and-release-builds.md` — API URL, Agora, Ummah keys (Android + iOS)
- `docs/google-play-policy-review.md` — Android counterpart
- `docs/privacy-policy.md` — policy draft for live site
- `docs/support-requests.md` — support API (fallback contact)
