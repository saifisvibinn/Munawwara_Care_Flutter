# Munawwara Care — Google Play: remaining work

**Purpose:** What is still required before / during Play submission.  
**App:** Munawwara Care (Flutter Android) + `mc_backend_app` + `mc_mod_front`.  
**Last updated:** May 18, 2026

Completed in-app / manifest work (package rename, cleartext, permission cleanup, in-app privacy/support/deletion forms, SOS disclaimers, Firebase project `munawwaracare-5353a`) is **not** listed here unless you still need to verify it in Console.

---

## Critical — block production / Play approval

| # | Item | What to do |
|---|------|------------|
| 1 | **Play Data safety form** | Complete in Play Console: precise + **background** location, audio (calls), personal/health fields (medical history, visa, etc.), device IDs, FCM. **Do not** declare crash/analytics — app has none. |
| 2 | **Background location** | In-app disclosure exists; still need **Data safety** + store listing text + **background location video** (Play requirement) aligned with pilgrim safety use case. |
| 3 | **Privacy Policy (live site)** | **Draft updated** in `docs/privacy policy.md` (May 20, 2026). **Publish** the same content to https://saifisvibinn.github.io/munawwara-privacy/ — must match app + Data safety. |
| 4 | **Brand / trademark** | Written authorization from Munawwara Care for store name, icon, and listing (freelancer ≠ brand owner). |
| 5 | **Store listing assets** | 512×512 icon, feature graphic 1024×500, phone screenshots (show location disclosure / SOS / calls if you claim those features). |
| 6 | **Firebase FCM (backend)** | Service account on **`munawwaracare-5353a`** needs **Firebase Cloud Messaging API Admin** (or equivalent). Logs must show `FCM Notification sent: 1/1 succeeded`, not `cloudmessaging.messages.create denied`. |
| 7 | **Deploy backend** | Ship `POST /api/support/request` and latest env (Firebase `munawwaracare-5353a`) to **Cloud Run** if not already deployed. |

---

## High priority

| # | Item | What to do |
|---|------|------------|
| 8 | **App access (reviewers)** | Play Console → App access: moderator test account + **fresh** pilgrim one-time code/QR (device-bound). Note reissue if code fails. |
| 9 | **Support email on store listing** | List **munawwaracare@gmail.com** on Play store listing (in-app forms already email this address). |
| 10 | **Privacy policy — deletion/support copy** | Covered in `docs/privacy policy.md` §6 — **publish to live site**. In-app: **تواصل مع الدعم** / **Request account deletion**. |
| 11 | **Target audience** | Play Console: **not designed for children under 13**; operator policy if minors are provisioned. |
| 12 | **Pre-launch report** | Run internal testing track; fix crashes/permission issues on **targetSdk 36**. |

---

## Medium priority

| # | Item | What to do |
|---|------|------------|
| 13 | **Data residency** | API `europe-west3` is in `docs/privacy policy.md` §8 — confirm **MongoDB Atlas** and **Firebase** regions in Console and align policy if different. |
| 14 | **Group delete vs account delete** | Documented in `docs/privacy policy.md` §6 — publish to live site. |
| 15 | **API keys in APK** | Restrict **Agora** and **Google Maps** keys in cloud consoles (package `com.munawwaracare.android`). |
| 16 | **Category & positioning** | Store category (e.g. Travel); avoid medical-device claims — use “group safety / coordination.” |
| 17 | **UGC / communication** | Moderator-only messaging — ensure Terms/privacy mention moderation and **munawwaracare@gmail.com**. |

---

## Play Console checklist (manual)

- [ ] Data safety form submitted  
- [ ] Background location declaration + **video** uploaded  
- [ ] Privacy policy URL set and content updated  
- [ ] Store listing: short/full description, screenshots, feature graphic  
- [ ] App access credentials for reviewers  
- [ ] Target audience / not for children (13+)  
- [ ] Financial features: **No** (no IAP, no ads)  
- [ ] Internal testing → closed/open when ready  

---

## Privacy policy site checklist

**Repo draft:** `docs/privacy policy.md` (updated May 20, 2026). **Still required:** copy/publish to https://saifisvibinn.github.io/munawwara-privacy/

Draft covers:

1. **No** crash/diagnostics (no Analytics/Crashlytics).  
2. Providers: Firebase FCM, Cloud Run, GCS, Translation/TTS, Tasks, MongoDB Atlas, Redis, Agora, Gmail SMTP, OSM.  
3. **Moderator-sent** messages only; **no image/photo messages** in the App.  
4. Data listed: medical, visa, hotel/room/bus, battery %, device binding, background location, call metadata, meetpoints.  
5. In-app **Contact support** / **Request account deletion** + email.  
6. **Group delete** vs pilgrim account deletion.  
7. Safety disclaimer (999/911; SOS → moderator).  
8. Contact email + in-app forms.

---

## Suggested store copy (drafts)

**Short description (≤80 chars)**  
> Safety app for Hajj & Umrah groups: live location, SOS, chat & calls with your guide.

**Reviewer notes (App access)**  
1. Moderator: email + password (test account you provide).  
2. Pilgrim: fresh one-time code or QR (not bound to another device).  
3. Grant **location (Always)** and **notifications**; complete device-care onboarding if shown.  
4. Test VoIP call and SOS from pilgrim.  
5. API: production `API_BASE_URL` (see `docs/backend-config.md`)

---

## Verify before upload (quick smoke)

| Check | Expected |
|-------|----------|
| Release APK package | `com.munawwaracare.android` |
| `PUT /api/auth/fcm-token` after login | **200** in Cloud Run logs |
| Test call → FCM log | `1/1 succeeded` |
| Profile → Contact support / Deletion | Form submits; email received at support inbox |
| Privacy policy | Opens in-app WebView |

---

## Completed (in repo — May 2026)

Record of work already done in the codebase. Re-verify in Play Console / production where noted.

### Android manifest & build

| Item | Done |
|------|------|
| `applicationId` / namespace | `com.munawwaracare.android` (was `…andriod`) |
| Kotlin package + method channels + CallKit receivers | Renamed to `com.munawwaracare.android` |
| `google-services.json` | Firebase project `munawwaracare-5353a`, package `com.munawwaracare.android` |
| `usesCleartextTraffic` | `false` in release; `true` in debug only |
| Removed permissions | `BATTERY_STATS`, `SYSTEM_ALERT_WINDOW`, `CALL_PHONE`; duplicate `FOREGROUND_SERVICE` deduped; `USE_EXACT_ALARM`, `SCHEDULE_EXACT_ALARM` (meetpoints/reminders use server + FCM) |
| `<queries>` | https, http, mailto, common browsers (for optional external links) |

### In-app legal & UX (pilgrim + moderator Settings)

| Item | Done |
|------|------|
| Privacy Policy | In-app WebView → GitHub Pages URL |
| Contact support | In-app form → `POST /api/support/request` → emails support |
| Request account deletion | Confirm dialog → in-app form (same API, type `account_deletion`) |
| SOS / safety copy | Home tab banner + updated strings (6 locales) |
| Agora disclosure | Shown in legal section |
| Arabic label | Contact support = **تواصل مع الدعم** |

### Backend (local / partial prod)

| Item | Done |
|------|------|
| Firebase Admin env | `FIREBASE_*` for `munawwaracare-5353a` in `.env` |
| Support API | `POST /api/support/request` + `sendSupportInquiryEmail` |
| FCM token upload guard | Auth required; no logout on `fcm-token` 401 |

### Still verify on production

- Cloud Run env matches `munawwaracare-5353a` + support route deployed  
- FCM IAM → `FCM Notification sent: 1/1 succeeded`  
- Release APK smoke (calls, support forms, fcm-token **200**)

### Payments / content (unchanged — still compliant)

- No ads, no IAP, no Play Billing  
- No AccessibilityService  
- Firebase client: FCM only (no Analytics/Crashlytics in repo)  
- HTTPS production API: configured via `API_BASE_URL` / `dart-define`

---

*Compliance aid only — not legal advice.*
