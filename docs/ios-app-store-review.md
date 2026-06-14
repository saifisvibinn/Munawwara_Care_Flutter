# Munawwara Care — iOS App Store: rejection risks

**Purpose:** Issues that may cause App Store rejection or a failed review, based on an audit against [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) and [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/).  
**App:** Munawwara Care (Flutter iOS) — bundle ID `com.munawwaracare.ios`, branch `IOS`  
**Last updated:** June 13, 2026

Nothing here is fixed unless marked **Done**. Code paths and plist values were re-checked against the repo at audit time.

---

## Critical — fix before submission

| # | Issue | Why Apple may reject | Current state | What to do |
|---|--------|----------------------|---------------|------------|
| 1 | **Push / VoIP entitlements empty** | App advertises calls, SOS, and chat alerts but killed-state push/CallKit will not work in production. Reviewers may treat this as incomplete or broken. **Guideline 2.1 — App Completeness** | `ios/Runner/Runner.entitlements` is an empty `<dict>` (push was removed for free Personal Team testing) | On a **paid Apple Developer** account: Xcode → Runner → Signing & Capabilities → add **Push Notifications** + **Background Modes** (Voice over IP, Remote notifications). Restore `aps-environment` in entitlements. Test incoming calls with app killed. |
| 2 | **Missing `voip` and `remote-notification` background modes** | CallKit / PushKit / FCM need these in addition to `audio`. Without them, VoIP and remote notifications are unreliable. | `ios/Runner/Info.plist` → `UIBackgroundModes` only lists `location` and `audio` | Add `voip` and `remote-notification` to `UIBackgroundModes` when push is enabled. Include reviewer notes: VoIP is for group safety voice calls (Agora), not promotional push. |
| 3 | **Account deletion is request-only** | Apps that create accounts must offer **in-app account deletion** that actually removes the account. Email/support requests alone are not enough. **Guideline 5.1.1(v)** | Pilgrims: Profile → About → **Request account deletion** → `POST /support/request` with `type: account_deletion` (`lib/features/legal/data/support_api.dart`). No `DELETE /auth/account` (or equivalent) in client or docs. | Backend: add authenticated account-deletion endpoint. App: confirmation flow → API call → sign out → “Account deleted.” Keep support email as fallback only. |
| 4 | **Release build can crash without `API_BASE_URL`** | Reviewer cold-launches a broken white screen = instant rejection. **Guideline 2.1** | `lib/core/env/env_check.dart` throws if `API_BASE_URL` is missing. `.env` is bundled in `pubspec.yaml` assets — risky for store builds. | Always archive with production URL, e.g. `flutter build ipa --release --dart-define=API_BASE_URL=https://<prod-api>/api`. Cold-launch test before upload. Prefer dart-define over bundled `.env` for release. |

---

## High — strong rejection risk or broken on iOS

| # | Issue | Why it matters | Current state | What to do |
|---|--------|----------------|---------------|------------|
| 5 | **Photo library usage strings inaccurate** | Strings must match real behavior. Mismatch → rejection under permission guidelines. **Guideline 5.1.1(i)** | `Info.plist`: both `NSPhotoLibraryUsageDescription` and `NSPhotoLibraryAddUsageDescription` say “save QR codes” only. App also **picks** photos for profile (`pilgrim_profile_screen.dart`) and provisioning (`create_pilgrim_card.dart`). | Update both keys to mention selecting/uploading profile photos **and** saving QR codes to the library. |
| 6 | **“Rate app” opens Google Play on iOS** | Broken or irrelevant store link on iPhone looks unfinished. | `lib/core/widgets/support_dialogs.dart` uses `market://` and `play.google.com` URLs after rating. | On iOS: `SKStoreReviewController.requestReview()` (via `in_app_review` or platform channel) and/or App Store review URL. Keep Play Store flow on Android only. |
| 7 | **Microphone permission macro missing in Podfile** | `permission_handler` on iOS only shows system dialogs for permissions enabled at compile time. Without the macro, mic requests can return denied with **no prompt**. | `ios/Podfile` post_install only sets `PERMISSION_LOCATION=1` and `PERMISSION_NOTIFICATIONS=1`. Voice calls and translation call `Permission.microphone.request()`. | Add `PERMISSION_MICROPHONE=1` (and `PERMISSION_CAMERA=1` if camera QR flow is tested on iOS). Run `pod install` and verify mic prompt on device. |
| 8 | **Background location — extra scrutiny** | Continuous background location is heavily reviewed. Incomplete disclosure or unclear purpose → rejection or follow-up questions. | Always location + `UIBackgroundModes: location` + in-app disclosure dialogs and toggle — good direction, but still sensitive. | App Store Connect: declare precise + background location accurately. Reviewer notes + demo pilgrim/moderator accounts. Optional short demo video for safety use case. |
| 9 | **Privacy policy URL must be live and accurate** | In-app link and App Privacy labels must match published policy. | In-app WebView loads `https://saifisvibinn.github.io/munawwara-privacy/` (`lib/core/config/legal_config.dart`). Repo draft: `docs/privacy-policy.md` (may be out of sync with live site). | Publish synced policy before submit. Open privacy screen on a **release** build and verify it loads. Align App Privacy questionnaire in Connect. |
| 10 | **No Runner privacy manifest** | Apple requires privacy manifests for apps/SDKs using certain “required reason” APIs. | No `ios/Runner/PrivacyInfo.xcprivacy`. Native code (e.g. `LocationChannelHandler.swift`) uses UserDefaults. | Add `PrivacyInfo.xcprivacy` for APIs used directly in Runner. Run Xcode **Privacy Report** before upload. |

---

## Medium — HIG polish / quality (may not reject alone)

| # | Issue | Detail | Location |
|---|--------|--------|----------|
| 11 | **Launch screen placeholders** | `LaunchImage.png` / `@2x` / `@3x` are ~68 bytes each (blank placeholders). HIG expects branded launch, not white flash. | `ios/Runner/Assets.xcassets/LaunchImage.imageset/` |
| 12 | **SOS copy typo** | User-visible English error: *"you're request was resolved... munawwara care care"* | `assets/translations/en.json` → `sos_status_resolved_friendly` |
| 13 | **Report categories hardcoded in English** | Incident report dropdown ignores app language. | `lib/core/widgets/support_dialogs.dart` → `_categories` in `ReportIssueDialog` |
| 14 | **Moderator deletion UX** | `legal_moderator_deletion_note` exists in translations but moderators may still see pilgrim self-delete flow. | About / legal screens |
| 15 | **Export compliance key missing** | Connect asks about encryption; missing plist key adds manual steps each upload. | Add `ITSAppUsesNonExemptEncryption` = `false` to `Info.plist` if you only use standard HTTPS (no custom crypto). |
| 16 | **Reminders tab / API** | If reviewers open System Reminders and backend returns 404, tab may look broken. | `lib/features/moderator/providers/reminder_provider.dart` logs 404 for `GET /reminders` |
| 17 | **`.env` in release assets** | Dev/staging URLs could ship in store builds if someone forgets dart-define. | `pubspec.yaml` → `assets: - .env` |

---

## Already in good shape

| Area | Status |
|------|--------|
| **App Settings UI** | Grouped card, appearance toggles, language disclosure + endonym picker — aligns with iOS Settings patterns |
| **Privacy policy in-app** | Profile → Privacy Policy WebView |
| **Deletion discoverability** | Entry point exists for pilgrims (needs real deletion API — see #3) |
| **Location permission flow** | When-in-use → disclosure → Always; iOS setup wizard |
| **Core permission strings** | Location, camera, mic, speech — generally clear and purpose-specific (photo library needs fix — see #5) |
| **No IAP / subscriptions** | No StoreKit compliance needed |
| **No third-party sign-in** | No “Sign in with Apple” requirement for current QR/device-bound auth |
| **SOS disclaimer** | Not positioned as 911 / medical device |
| **App icons** | Full `AppIcon.appiconset` including 1024×1024 |
| **Portrait / full screen** | Consistent travel-app pattern |
| **Debug banner** | Disabled in `main.dart` |
| **In-app support** | Forms via API, not mailto-only |

---

## Pre-submission checklist

- [ ] Paid Apple Developer Program enrolled; Push + VoIP capabilities enabled in Xcode
- [ ] `Runner.entitlements` includes `aps-environment`; `Info.plist` includes `voip` + `remote-notification`
- [ ] APNs key configured in Firebase Console for `com.munawwaracare.ios`
- [ ] Release IPA built with production `API_BASE_URL`; cold-launch tested on device
- [ ] Real in-app account deletion implemented and tested
- [ ] Photo library strings updated; Podfile mic (and camera) macros added; `pod install`
- [ ] iOS rate-app uses App Store / `SKStoreReviewController`, not Play Store URLs
- [ ] Privacy policy published and matches in-app URL + App Privacy labels
- [ ] `PrivacyInfo.xcprivacy` added; Xcode privacy report clean
- [ ] Branded launch screen replaces placeholder PNGs
- [ ] Reviewer notes prepared: demo accounts, background location rationale, VoIP for safety calls
- [ ] English typos fixed; support report categories localized

---

## Reviewer notes template (App Store Connect)

Use or adapt when submitting:

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
> Profile → About → Request account deletion. [Update this line after #3 is implemented: “Profile → Delete account” performs immediate deletion after confirmation.”]

---

## Related docs

- `docs/google-play-policy-review.md` — Android / Play Console counterpart
- `docs/privacy-policy.md` — policy draft to publish at live URL
- `docs/support-requests.md` — current support / deletion request API
