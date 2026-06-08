# Privacy Policy for Munawwara Care

**Effective Date:** May 17, 2026  
**Last updated:** June 9, 2026

Munawwara Care (“we”, “our”, or “us”) operates the Munawwara Care mobile application (the “App”) and related services for organized Hajj and Umrah travel groups. This Privacy Policy explains what personal information we collect, how we use it, who we share it with, and your choices.

By downloading, accessing, or using the App, you agree to this Privacy Policy. If you do not agree, do not use the App.

**Data controller:** Munawwara Care.  
**Contact:** munawwaracare@gmail.com

---

## 1. Who this App is for

The App is intended for **adults** participating in organized Hajj or Umrah travel with an authorized travel operator and assigned group moderator. It is **not directed at children under 13**. Accounts for pilgrims are created by authorized moderators or administrators, not by self-registration in the App.

---

## 2. Information we collect

### A. Account and profile information

- Full name, phone number, and role (Pilgrim or Moderator)
- Email address (typically for moderators; pilgrims may not have an email on file)
- Gender, age, and optional travel/logistics details (such as nationality/ID, visa information, hotel, room, bus assignment, ethnicity, and optional medical notes) when provided by your travel operator during account setup
- Account login and device binding data (including a device identifier used to bind a pilgrim account to one phone)
- Emergency contact / travel companion information (such as full name, phone number, and email address) when provided during account setup or profile update, stored for your travel operator and group coordination records

### B. Location information

- **Precise location (GPS)**, including **background location** when permitted
- **Pilgrims:** Background location is used so authorized moderators can see your position for group safety, including during an SOS alert, when the App is in the background or not actively in use
- **Moderators:** Location may be used when you use map and navigation features (for example, navigation beacons shown to pilgrims)
- **Prayer Times:** When you access the Prayer Times feature, your device’s current latitude and longitude are used to retrieve local prayer schedules

### C. Safety and coordination data

- SOS alert status and location at the time of an alert
- Battery level (pilgrim devices), shared with moderators for operational awareness
- Group membership and online/presence indicators
- Meetpoint and area alerts (location-related notifications sent by moderators to the group)

### D. Communications

- **Voice calls (Internet / VoIP):** Microphone audio via our real-time communications provider; call-related metadata such as timestamps, duration, and connection status
- **Carrier calls:** If you use in-app options to call a phone number, your device’s phone/dialer may be used; we do not record the audio of cellular calls
- **Moderator messages:** Text messages, voice messages, text-to-speech (TTS) announcements, and meetpoint messages sent by moderators to the group or to individual pilgrims. Pilgrims **receive** these messages; the App is **not** designed for pilgrims to send group chat messages. We do **not** support sending or receiving photo or image messages in the App.
- **SOS alerts to moderators:** After the urgent notification sound, the App may play a short **pre-recorded** safety message in the moderator’s selected app language (not live text-to-speech of your personal data).
- **Push notifications:** Firebase Cloud Messaging device tokens and notification delivery data

### E. Technical and usage data

- App version, language preference, and authentication/session tokens (stored securely on your device where supported)
- Information needed to operate the service (for example, IP address and request logs on our servers)
- Locally cached data on your device so limited information may be shown when the network is unavailable
- **On-device preferences** for optional rating prompts (for example, whether you have already rated or when a prompt was last shown). These are stored locally on your device and are not used for advertising or profiling

### F. Voluntary feedback, ratings, and incident reports

When you choose to contact us or improve the App, we may collect:

- **App ratings and feedback:** Optional star rating (1–5), optional written comments, and whether the submission came from Settings or after certain in-app events (for example, after a completed voice call or a resolved SOS session). This is linked to your account on our servers.
- **General feedback:** Free-text comments you submit from **About** in the App.
- **Incident reports:** Category, subject, and description you submit through **Report issue** in the App (for example, medical, safety, transport, hotel, technical, or other). This is linked to your account on our servers.

We do **not** require you to leave a public store review. If you choose **Rate on Play Store**, you are taken to **Google Play**, which is governed by Google’s policies. We do not receive your Play Store review content automatically.

### G. Weather and on-device translation

- **Weather:** When you view weather on the home screen, the App may send your current **latitude and longitude** to **Open-Meteo** to retrieve a local forecast. We do not send your name or account ID with that request.
- **Offline Translator:** When you use this feature, **speech input** may be processed by your device’s speech-recognition service (for example, Google on Android). **Translation** is performed **on your device** using **Google ML Kit** language models you download; your typed or spoken text is not sent to our servers for translation. Microphone access is used only when you start voice input.

**We do not use Google Analytics or a dedicated crash-reporting SDK in the App.** We do not sell your personal information and we do not use your data for advertising.

---

## 3. How we use your information

We use personal information only to operate group safety and coordination features, including:

- Responding to **SOS alerts** and sharing your location with authorized moderators in your group
- Showing pilgrim locations to authorized moderators on a private group map
- Delivering moderator announcements, reminders, and meetpoint alerts (including spoken reminders where enabled)
- Enabling **voice** calls between pilgrims and moderators
- Authenticating users and assigning them to the correct travel group
- Sending push notifications for safety, calls, and operator messages
- Processing in-app support, feedback, ratings, incident reports, and account-deletion requests
- Improving the App based on voluntary feedback you submit
- Showing local weather information based on device coordinates
- Operating the on-device Offline Translator feature
- Maintaining service security and reliability
- Retrieving prayer times based on device coordinates

### Safety disclaimer

Munawwara Care **coordinates your travel group**. It is **not** medical advice, **not** a medical device, and **not** a substitute for local emergency services (for example **999** or **911**). **SOS alerts your group moderator**, not emergency dispatch. In a life-threatening emergency, contact local authorities and official Hajj/Umrah emergency services.

### Moderator content

Messages and announcements in the App are sent by **authorized moderators** (or administrators) on behalf of your travel operator. Report inappropriate content or account concerns via **Contact support** in the App or **munawwaracare@gmail.com**.

---

## 4. How we share your information

We **do not** sell, rent, or trade your personal information.

We share information only as follows:

- **Within your authorized group:** Pilgrim location, name, SOS status, and related safety information with moderators assigned to your group
- **Service providers** (processors acting on our behalf), including:
  - **Google Firebase** — push notifications (Firebase Cloud Messaging)
  - **Google Cloud Run** — application API hosting (deployment region: **europe-west3**, European Union)
  - **Google Cloud Storage** — stored voice message audio and generated TTS audio files
  - **Google Cloud Translation & Text-to-Speech** — translated reminders and spoken announcements (not used for pilgrim SOS voice clips sent to moderators, which use bundled audio in the App)
  - **Google Cloud Tasks** — scheduled reminder delivery
  - **MongoDB Atlas** — database hosting (region as configured for our deployment)
  - **Redis** — rate limiting and operational caching on our servers
  - **Agora** — voice (WebRTC) calls
  - **Gmail SMTP** — password-reset email, in-app support requests, and account-deletion requests delivered to our support inbox
  - **OpenStreetMap / Nominatim** — map tiles and place search (requests may include your general map area or search terms; see their policies)
  - **UmmahAPI** — prayer times and Hijri calendar lookup (requests include your latitude and longitude, but no personal identifiers such as name or account tokens)
  - **Open-Meteo** — weather forecast lookup (latitude and longitude only; no account identifiers)
  - **Google ML Kit** — on-device translation and language identification in the Offline Translator (processing occurs on your device after you download language models)
- **Legal requirements:** When required by law or valid legal process

When you open **Google Maps**, **Google Play** (for example to rate the App), or your phone’s dialer from the App, those services are governed by their own policies. Your device’s **speech-recognition** service (used for Offline Translator voice input) is governed by your platform provider’s policies.

---

## 5. Background location (Google Play)

In line with Google Play policies:

- The App may collect location **in the background** for pilgrim safety
- **Purpose:** So moderators can assist pilgrims during SOS or coordination when the App is not in the foreground
- **Consent:** Before the operating system requests background location, pilgrims are shown a clear in-app disclosure explaining why background location is needed

---

## 6. Data retention and deletion

We keep personal information only as long as needed to provide the service and meet legal obligations.

- When a **moderator or administrator deletes a pilgrim account**, we delete that user’s account record from our systems
- When a **travel group is deleted**, group-related content (such as messages, call history tied to the group, reminders, and notifications) is removed; **pilgrim account records may remain** in an unassigned state until deleted by an administrator or upon request
- When you **log out**, session tokens are cleared on the device; some profile or location fields may remain on our servers until account deletion
- **Feedback, ratings, and incident reports** you submit are retained on our servers for support and service improvement until your account is deleted or as required by law

### How to contact us or delete your account

**In the App (recommended):** Open **Profile** → **Privacy & support** → **About**:

- **Contact support** — describe your issue; your account details are included automatically and sent to our team (no email app required on your phone).
- **Request account deletion** — submit a deletion request; we process it according to this policy.
- **Send feedback**, **Rate app**, and **Report issue** — optional tools on the same **About** screen; submissions are stored as described in Section 2(F).

**By email:** You may also write to **munawwaracare@gmail.com**. For deletion, include your full name, phone number, and travel group name (if known).

**Moderators:** You may use the same in-app **Request account deletion** or **Contact support** options. Your travel operator’s administrator may also remove moderator accounts directly.

We will respond within a reasonable time subject to verification and applicable law.

---

## 7. Security

We use measures such as HTTPS for API traffic, secured WebSocket connections, encrypted real-time voice media (WebRTC) where supported, and secure on-device storage for session credentials where the platform allows. No method of transmission or storage is 100% secure.

---

## 8. International transfers and hosting

Our primary application API is hosted on **Google Cloud Run** in **europe-west3** (European Union). **MongoDB Atlas**, **Firebase**, and other providers may process data in regions configured in their respective services. By using the App, you understand that your information may be processed in those locations.

---

## 9. Changes to this policy

We may update this Privacy Policy. We will post the updated version at the same URL and change the “Effective Date” / “Last updated” date above. Continued use of the App after changes means you accept the updated policy.

---

## 10. Contact us

**Munawwara Care**  
**Email:** munawwaracare@gmail.com

Use **Contact support** or **Request account deletion** in the App under **Privacy & support**, or email us at the address above.
