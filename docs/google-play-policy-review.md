# Munawwara Care — Google Play Policy & Rejection Risk Review

**Document purpose:** Pre-submission review for Google Play Console policy compliance.  
**App:** Munawwara Care (Flutter Android) + Node.js backend (`mc_backend_app`) + moderator web (`mc_mod_front`).  
**Last updated:** May 17, 2026

---

## Executive summary — high-risk areas

| Area | Risk level | Summary |
|------|------------|---------|
| Background location | 🔴 Critical | Core pilgrim safety feature; must match disclosure, Data safety, and Play video |
| Data Safety form | 🔴 Critical | Not completed yet |
| Account deletion (pilgrims) | 🔴 High | No in-app deletion; email-only may fail User Data policy |
| Privacy Policy accuracy | 🔴 High | Live policy claims crash/diagnostics not in app; update before production |
| Trademark / brand (Munawwara) | 🔴 High | Developer does not own brand; freelancer build for client |
| `applicationId` typo | 🟡 Medium | Change `andriod` → `android` before production |
| `usesCleartextTraffic="true"` | 🟡 Medium | Release should be HTTPS-only |
| `SYSTEM_ALERT_WINDOW` | 🟡 Medium | Declared; no app code usage found — candidate for removal |
| `BATTERY_STATS` | 🟡 Medium | Declared; app uses `battery_plus` instead — candidate for removal |
| Group delete vs pilgrim PII | 🟡 Medium | Group deletion does not delete pilgrim user records |
| Children / minors | 🟡 Medium | Not primary audience; minors possible with parents — declare 13+ on Play |
| Store listing assets | 🟡 Medium | Screenshots / feature graphic not ready yet |
| UGC / communication policy | 🟡 Low–Medium | Moderator-only messaging; still need Terms + support contact |
| Payments / ads | 🟢 Low | Free app, no IAP, no ads, B2B revenue |

---

## 1. App identity & metadata

### Your answers

| Field | Value |
|-------|--------|
| **Play Store title** | Munawwara Care |
| **Package name (current)** | `com.munawwaracare.andriod` (typo: **andriod**) |
| **Package name (confirmed)** | `com.munawwaracare.android` — change **before first production upload** |
| **Version** | `1.0.0` (versionName) / `1` (versionCode) |
| **Developer account** | Individual, Egypt |
| **Category** | Travel + Health (primary/secondary TBD in Console) |
| **Target audience** | Adults on organized Hajj/Umrah with travel guides; **not designed for children under 13** |
| **Distribution** | Internal testing first |
| **Countries** | Saudi Arabia and Egypt (initially) |
| **Brand** | Built for Munawwara Care; developer is freelancer — **does not own** “Munawwara” trademark |
| **Similar apps** | No impersonation concern reported |
| **Support email** | munawwaracare@gmail.com |

### Draft — Short description (≤80 chars)

> Safety app for Hajj & Umrah groups: live location, SOS, chat & calls with your guide.

### Draft — Full description (key points)

- Group safety for Hajj/Umrah: live location, SOS, moderator calls, pilgrim coordination
- Pilgrims share location (including background); moderators monitor on a map
- Accounts provided by travel operator (login code / QR)
- **Not** a replacement for emergency services
- Background location may affect battery life
- Intended for adults in organized travel — not for children under 13

### ⚠️ Potential rejection risks

| Risk | Severity | Notes |
|------|----------|--------|
| Trademark authorization | High | Obtain written permission from Munawwara Care for name, icon, listing |
| Medical/health positioning | Medium | Use “coordination / group safety,” not medical device claims |
| Background location | Critical | Must match in-app disclosure, Data safety, store listing |
| Package typo | Medium | Fix `applicationId` before production; new ID = new listing if changed later |
| Publisher vs client | Low–Medium | Ideally publish under client’s account or document brand relationship |

---

## 2. Permissions

### Declared in `AndroidManifest.xml`

| Permission | Feature | Runtime prompt? |
|------------|---------|-------------------|
| `ACCESS_FINE_LOCATION` | Pilgrim tracking, SOS, maps | Yes |
| `ACCESS_COARSE_LOCATION` | Same | Yes |
| `ACCESS_BACKGROUND_LOCATION` | Pilgrim safety when backgrounded | Yes + prominent disclosure |
| `CAMERA` | QR login / scanner only | Yes (on scanner open) |
| `RECORD_AUDIO` | VoIP calls, voice messages | Yes |
| `POST_NOTIFICATIONS` | FCM, reminders, SOS, calls | Yes (Android 13+) |
| `CALL_PHONE` | Cellular fallback via dialer (`tel:`) | Verify if needed vs dialer only |
| `READ_PHONE_STATE` / `READ_PHONE_NUMBERS` | CallKit / telecom (plugins) | System / plugin |
| `MANAGE_OWN_CALLS` / `FOREGROUND_SERVICE_PHONE_CALL` | Incoming call UI, `IncomingCallService` | Foreground during calls |
| `USE_FULL_SCREEN_INTENT` | Lock-screen incoming calls | System |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Reliable FCM/calls (device care) | Settings + explained in UI |
| `SYSTEM_ALERT_WINDOW` | **Unclear** — no Dart/Kotlin usage found | Consider removing |
| `BATTERY_STATS` | **Likely unused** — app uses `battery_plus` | Consider removing |
| `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` | Reminders, meetpoint alerts | Android 12+ |
| `RECEIVE_BOOT_COMPLETED` | Reschedule local notifications | Install-time |
| `FOREGROUND_SERVICE` | Incoming call service | While call active |
| `INTERNET` | API, Agora, FCM | Normal |
| `BLUETOOTH` / `BLUETOOTH_CONNECT` | Audio routing (calls) | If needed by OS |

**AccessibilityService:** **Not declared. Not used.**

### Your answers

| # | Topic | Answer |
|---|--------|--------|
| 1 | Background location purpose | Pilgrim **safety** |
| 2 | Disclosure before OS prompt | **Yes** — users told why |
| 3 | Moderators without location | **Yes**, with **limitations** |
| 4 | Location when logged out | Unlikely — location stream from pilgrim dashboard; logout clears token (verify no leak) |
| 5 | Cellular vs VoIP | **Both** — cellular if VoIP fails |
| 6 | Phone permissions | From **CallKit / incoming call** plugins, not direct app code |
| 7 | Reviewer documentation | Provide App access notes: test logins, permissions, SOS, calls |
| 8 | `SYSTEM_ALERT_WINDOW` | Unsure — **no usage found in app code** |
| 9 | Battery optimization | **Yes** — explained for calls + FCM when app off |
| 10 | Battery stats | Uses **battery %** via `battery_plus`; `BATTERY_STATS` permission likely unnecessary |
| 11 | Exact alarms | **Reminders** and **meetpoint alerts** |
| 12 | Other runtime prompts | Notifications; camera when **QR scanner** opens |
| 13 | Unused permissions | None intentionally requested |
| 14 | Accessibility service | **Not used** |

### ⚠️ Potential rejection risks

| Risk | Severity |
|------|----------|
| Background location without matching Play declaration + video | **Critical** |
| `SYSTEM_ALERT_WINDOW` without core need | **High** |
| `BATTERY_STATS` declared but unused | **Medium** |
| `CALL_PHONE` if only `tel:` dialer used | **Medium** |
| Phone permissions without Play justification | **Medium** |

---

## 3. Authentication & user accounts

### Your answers

| Topic | Detail |
|-------|--------|
| Login required | **Yes** — mandatory |
| Account creation | **Admins** create moderators (web); **moderators** provision pilgrims |
| Login methods | Pilgrim: **QR / one-time code**; Moderator: **email + password** |
| Guest mode | **No** |
| Pilgrim self-delete | **No** in app; deleted when group removed or moderator deletes; request via **munawwaracare@gmail.com** |
| Moderator self-delete | **Admins only** (web dashboard) |
| Password reset | Moderators: in-app forgot password; pilgrims: new code from moderator |
| Target users | **Older pilgrims** primary; others can use too |
| Play test accounts | **Will provide** mod emails + pilgrim codes |
| Reviewer access | Credentials in App access section |

### From code — device binding

- One pilgrim account = **one bound device** (`bound_device_id`).
- Second device: *“Account is bound to another device.”*
- Moderator **reissue** clears binding + `force_logout`.
- One-time login code is **single-use** for activation.

### ⚠️ Potential rejection risks

| Risk | Severity |
|------|----------|
| No in-app account deletion for pilgrims | **High** — add “Request deletion” → munawwaracare@gmail.com |
| No pilgrim logout in UI | **Low–Medium** |
| Test credentials device-bound / one-time | **Medium** — document reissue for reviewers |
| B2B-provisioned accounts still need Data safety | **Low** |

---

## 4. Data collection & privacy

### Your answers

| Topic | Detail |
|-------|--------|
| Privacy Policy URL | https://saifisvibinn.github.io/munawwara-privacy/ |
| Purpose | Group safety only; **no ads; no selling data** |
| Data sold | **No** |
| Data Safety form | **Not filled yet** |
| Children | Not for under-13; minors possible if parents want tracking — primary users older |
| Data controller | **Munawwara Care** (client) |
| Export/correct | **No** self-service; via moderator/admin |
| Support / deletion email | **munawwaracare@gmail.com** |
| MongoDB / Firebase region | **Unknown** — API hosted **europe-west3** (GCP) |

### Data collected (from code)

Name, phone, email (mods), national ID, age, gender, medical history, visa, hotel/room/bus, ethnicity, precise + background location, battery %, FCM token, device ID, moderator-sent text/voice/TTS, VoIP audio (Agora), call history metadata, SOS, optional profile picture. Camera: **QR only**.

### Third parties (from code)

| Provider | Purpose |
|----------|---------|
| Google Cloud Run | API + Socket.IO (`europe-west3`) |
| MongoDB Atlas | Database |
| Redis | Socket.IO scaling |
| Google Cloud Storage | TTS audio, chat media |
| Google Cloud Translation + TTS | Reminders / announcements |
| Google Cloud Tasks | Scheduled jobs |
| Firebase (FCM) | Push notifications |
| Agora | Voice/video calls |
| Gmail SMTP (nodemailer) | Password reset email |
| OpenStreetMap / Nominatim | Map tiles / geocoding |
| Google Maps (external) | Turn-by-turn via `url_launcher` |

**Not in app:** Firebase Analytics, Crashlytics, ads, Play Billing.

### Retention (from code)

| Action | Behavior |
|--------|----------|
| Delete pilgrim (moderator) | `User.deleteOne` — hard delete |
| Delete group | Pilgrims **remain** (`limbo_reason: group_deleted`); group messages/calls/reminders **purged** |
| Logout | FCM cleared; profile/location may remain |

### Privacy policy gaps (live site vs app)

The published policy at https://saifisvibinn.github.io/munawwara-privacy/ should be updated:

| Issue | Fix |
|-------|-----|
| Claims “crash reports, diagnostic data” | **Remove** — no Analytics/Crashlytics in app |
| “Chat messages” (implies pilgrim chat) | Clarify **moderator-sent** messages |
| Service providers too narrow | Add Agora, GCP, MongoDB, etc. |
| Deletion email only in §8 | Put **munawwaracare@gmail.com** in deletion section |
| Missing medical/visa/hotel/battery/device binding | Add for Data safety alignment |
| Group delete vs account delete | Describe accurately |
| No “not emergency services” disclaimer | Add |

### ⚠️ Potential rejection risks

| Risk | Severity |
|------|----------|
| Data Safety form incomplete | **Critical** |
| Privacy Policy inaccurate vs app | **High** |
| Background location vs declarations | **Critical** |
| Group delete leaves pilgrim PII | **Medium** |
| Medical history in Data safety | **Medium** |
| `usesCleartextTraffic="true"` | **Medium** |
| Minors provisioned | **Medium** — declare 13+ on Play |

---

## 5. Payments & monetization

### Your answers

| Topic | Answer |
|-------|--------|
| Free download | **Yes** |
| In-app purchases | **No** |
| Digital goods | **No** |
| Physical goods in app | **No** |
| Business model | **B2B** — companies pay Munawwara Care |
| Currency/tokens | **No** |
| Ads | **No** |
| Financial features (Play Console) | App does **not** offer banking/crypto/loans — select **No** |

### ⚠️ Potential rejection risks

**🟢 Looks good** — no Play Billing required.

---

## 6. Content inside the app

### Your answers

| Topic | Answer |
|-------|--------|
| UGC types | **Text and voice** (moderator-sent only) |
| Pilgrim actions | **SOS**, **return calls** when called |
| Reach | **Group / moderators only** |
| Report/block | **No** (one-way mod → pilgrim) |
| Moderation | Humans delete messages, remove pilgrims, delete accounts |
| Automated content review | **No** |
| Medical info | **Moderators only** |
| SOS audience | **Moderators only** |
| Misleading claims | **No** |
| Prohibited content | **None** |
| Ads | **No** |
| User-posted URLs | **No** |

### ⚠️ Potential rejection risks

| Risk | Severity |
|------|----------|
| UGC policy — moderator messages still apply | **Low–Medium** — Terms + munawwaracare@gmail.com |
| SOS vs emergency services wording | **Medium** |
| Backend supports `image` messages — ensure disabled if unused | **Low** |

---

## 7. Backend & APIs

*From codebase.*

| Topic | Finding |
|-------|---------|
| **Stack** | Node.js Express + Socket.IO on **Google Cloud Run** (`europe-west3`) |
| **Web admin** | `mc_mod_front` (React/Vite) — same API |
| **Secrets in Flutter** | `AGORA_APP_ID` in `.env` (gitignored); JWT/Agora cert **server only** |
| **Production API** | `https://mc-backend-44890250266.europe-west3.run.app/api` (HTTPS) |
| **Cleartext** | `usesCleartextTraffic="true"` in manifest — disable for release |
| **Scraping** | No; OSM/Nominatim API only |
| **`.env` in git** | Gitignored in backend, Flutter, mod front |

### ⚠️ Potential rejection risks

| Risk | Severity |
|------|----------|
| Cleartext in release | **Medium** |
| Client API keys in APK | **Medium** — restrict in cloud consoles |
| Data residency (Atlas/Firebase) unconfirmed | **Medium** |

---

## 8. App behavior & technical details

*From codebase.*

| Topic | Finding |
|-------|---------|
| **Offline** | **Internet required** for core features; limited cached read (`AppDataCache`) when API fails |
| **Background** | FCM handler, `IncomingCallService` (foreground phoneCall), location stream, boot receiver for notifications |
| **AccessibilityService** | **Not used** |
| **Install APKs** | **No**; opens system settings (OEM onboarding) |
| **minSdkVersion** | **24** (Flutter 3.41) |
| **targetSdkVersion** | **36** (Flutter 3.41) |
| **64-bit** | Standard Flutter arm64 build |
| **Firebase (client)** | `firebase_core` + `firebase_messaging` only |

### ⚠️ Potential rejection risks

| Risk | Severity |
|------|----------|
| targetSdk 36 — pre-launch report | **Low–Medium** |
| Background location + FCM + call service — document for reviewers | **Medium** |

---

## 9. Store listing assets

| Asset | Status |
|-------|--------|
| Launcher icon | In repo (`ic_launcher`) |
| 512×512 Play icon | **Not ready yet** |
| Feature graphic 1024×500 | **Not ready yet** |
| Screenshots | **Not ready yet** |

### ⚠️ Potential rejection risks

| Risk | Severity |
|------|----------|
| Missing / inaccurate screenshots | **Medium** |
| Screenshots should show location disclosure if claiming location | **Medium** |

---

## 10. Testing & release

| Topic | Status |
|-------|--------|
| Real device testing | **Yes** — multiple devices |
| Release track | **Internal testing** first |
| Test accounts | **Will provide** moderator emails + pilgrim codes |
| Gated access | Login required; pilgrim codes device-bound |

### Recommended App access notes for reviewers

1. Moderator: email + password (test account).
2. Pilgrim: **fresh** one-time code or QR (not bound to another device).
3. Grant **location (Always)**, **notifications**; complete **device care onboarding** if shown.
4. Test incoming **VoIP call** (Agora) and optional **cellular** via phone button.
5. Pilgrim inbox is **read-only** for moderator messages; test **SOS** from pilgrim.
6. Backend: `https://mc-backend-44890250266.europe-west3.run.app/api`

### ⚠️ Potential rejection risks

| Risk | Severity |
|------|----------|
| Reviewers cannot log in without credentials | **High** |
| Stale/bound pilgrim codes | **Medium** |

---

## Final summary

### 🔴 Critical issues (fix before production)

1. Complete **Play Data safety** form (location, audio, personal info, health, device IDs — **not** crash analytics unless added).
2. **Update Privacy Policy** at https://saifisvibinn.github.io/munawwara-privacy/ (remove false crash/diagnostics claim; align with app).
3. Add **in-app account deletion request** → munawwaracare@gmail.com + link Privacy Policy.
4. Align **background location** disclosure, in-app UX, Data safety, and store listing.
5. Resolve **brand/trademark** authorization with Munawwara Care.
6. Change **`applicationId`** to `com.munawwaracare.android` **before** production upload.
7. Prepare **store screenshots** and feature graphic.

### 🟡 Warnings

1. Remove or justify **`SYSTEM_ALERT_WINDOW`** and **`BATTERY_STATS`**.
2. Set **`usesCleartextTraffic="false"`** for release builds.
3. Document **group delete** vs pilgrim delete in privacy policy.
4. Add **munawwaracare@gmail.com** in-app and on store listing.
5. Play Console: **not for children** (13+); operator policy for any minors.
6. Restrict **Agora / Google API keys** in client.
7. Confirm **MongoDB Atlas** region for privacy policy.

### 🟢 Looks good

1. No ads, no IAP, no gambling, no crypto.
2. No AccessibilityService abuse.
3. No in-app APK sideloading.
4. HTTPS production API.
5. B2B model — no Play Billing.
6. Moderator-only broadcast messaging (reduced UGC scope).
7. Firebase limited to **FCM** (no Analytics in repo).
8. Real-device testing on multiple devices completed.

---

## Open items checklist

| # | Item | Status |
|---|------|--------|
| 1 | Privacy Policy content updated on GitHub Pages | **Pending** |
| 2 | Privacy Policy + support email linked **in-app** | **Pending** |
| 3 | Store assets (512 icon, feature graphic, screenshots) | **Not ready** |
| 4 | Data Safety form | **Not done** |
| 5 | `applicationId` → `com.munawwaracare.android` | **Confirmed** — implement in code |
| 6 | MongoDB Atlas + Firebase regions | **Unknown** |
| 7 | Play test credentials in App access | **Pending** |
| 8 | Written brand authorization from Munawwara Care | **Pending** |

---

*This document is a compliance aid, not legal advice.*
