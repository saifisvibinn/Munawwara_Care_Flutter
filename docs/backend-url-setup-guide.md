# Backend URL — setup steps

Quick checklist for running and releasing the Munawwara Care Flutter app
after the API URL security changes.

---

## One-time setup (new machine or fresh clone)

1. Open a terminal in the Flutter project folder:
   ```bash
   cd Flutter_Munawwara
   ```

2. Create your local environment file from the template:
   ```bash
   cp .env.example .env
   ```

3. Edit `.env` and set at least:
   ```env
   API_BASE_URL=https://your-backend-host.example.com/api
   AGORA_APP_ID=your-agora-app-id
   UMMAH_API_KEY=your-ummah-api-key
   GOOGLE_MAPS_API_KEY=your-google-maps-key
   ```
   - Use your **real** production or staging URL (include `/api` at the end if
     your backend expects it).
   - `.env` is gitignored — it never gets committed.
   - `.env` is **not** bundled in release builds (see `docs/env-and-release-builds.md`).

4. Run the app:
   ```bash
   flutter pub get
   flutter run --dart-define-from-file=.env
   ```

5. If the app crashes on startup with a message about missing `API_BASE_URL`,
   pass `--dart-define-from-file=.env` or `--dart-define=API_BASE_URL=...`.

---

## Daily development (`flutter run`)

You **do not** need `--dart-define` for normal dev.

| Step | Action |
|------|--------|
| 1 | Make sure `.env` exists and `API_BASE_URL` points to the backend you want |
| 2 | Start your backend (local or use deployed Cloud Run) |
| 3 | Run `flutter run` |
| 4 | After changing `.env`, stop the app and run `flutter run` again |

The app loads `.env` automatically. No extra flags required.

---

## Which `API_BASE_URL` to use

### Production / staging (Cloud Run or hosted server)

```env
API_BASE_URL=https://mc-backend-44890250266.europe-west3.run.app/api
```
*(Replace with your actual deployed URL if it changes.)*

### Local backend on your PC (physical phone, same Wi‑Fi)

1. Find your PC’s LAN IP (e.g. `192.168.1.7`).
2. Start the backend on that machine.
3. In `.env`:
   ```env
   API_BASE_URL=http://192.168.1.7:5000/api
   ```

### Local backend (Android emulator)

Either use the emulator host IP:

```env
API_BASE_URL=http://10.0.2.2:5000/api
```

Or keep your LAN URL and add:

```env
API_BASE_URL=http://192.168.1.7:5000/api
API_ANDROID_HOST=10.0.2.2
```

---

## Deploying the backend

Deploying the backend **does not** configure the app automatically.

| Step | Action |
|------|--------|
| 1 | Deploy your backend (e.g. Cloud Run) |
| 2 | Copy the new public API URL (with `/api` if applicable) |
| 3 | Update `API_BASE_URL` in your local `.env` |
| 4 | Restart the app with `flutter run` |

For **release builds** (below), also update the URL in your CI/build command
if you use `--dart-define`.

---

## Release builds (APK / App Bundle / Play Store)

Choose **one** of these approaches.

### Option A — `.env` on the build machine (simplest)

1. Ensure `.env` exists on the machine that runs `flutter build`.
2. Set production `API_BASE_URL` in that `.env`.
3. Build:
   ```bash
   flutter build appbundle --release
   ```
   The `.env` file is bundled into the app as an asset.

### Option B — `dart-define` (recommended for CI / no secrets in files)

Pass the URL at build time (no production URL needs to live in `.env` on CI):

```bash
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://mc-backend-44890250266.europe-west3.run.app/api
```

Use the same flag for:

```bash
flutter build apk --release --dart-define=API_BASE_URL=...
flutter build ios --release --dart-define=API_BASE_URL=...
```

This sets both Dart (`String.fromEnvironment`) and Android native
(`BuildConfig.API_BASE_URL`) fallbacks.

---

## Native calls (decline/answer when app is killed)

| Situation | What happens |
|-----------|----------------|
| User opened the app at least once | URL is cached in device prefs — native decline/answer works |
| Fresh install, never opened app | Needs `dart-define` on **release** build, or user must open app once |
| Dev with `.env` | Works after first launch; prefs are written automatically |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| App won’t start — missing `API_BASE_URL` | Create/fix `.env`; set `API_BASE_URL` |
| Network errors / can’t reach API | Check backend is running; URL matches deploy; phone on same Wi‑Fi for local |
| Emulator can’t reach local backend | Use `10.0.2.2` or `API_ANDROID_HOST=10.0.2.2` |
| Calls work in app but decline fails when killed | Open app once, or use `--dart-define` on release build |
| Changed `.env` but app still uses old URL | Full restart (`flutter run` again), not just hot reload |
| Calls only on same Wi‑Fi, not on 4G | LAN `API_BASE_URL` in build or cached prefs — see [voice-calls-networking.md](./voice-calls-networking.md) |

---

## Quick reference

| Task | Command / file |
|------|----------------|
| First-time env | `cp .env.example .env` then edit |
| Daily dev | `flutter run --dart-define-from-file=.env` |
| Release with define | `flutter build appbundle --release --dart-define=API_BASE_URL=...` (see env doc) |
| Env template | `.env.example` |
| Technical details | `docs/env-and-release-builds.md` |

---

## Checklist before sharing a build with QA

- [ ] `--dart-define-from-file=.env` or `--dart-define` has correct `API_BASE_URL`
- [ ] Backend is deployed and reachable from a test device
- [ ] `AGORA_APP_ID` set if testing voice calls
- [ ] `UMMAH_API_KEY` set if testing Islamic Corner / UmmahAPI
- [ ] `GOOGLE_MAPS_API_KEY` set if testing maps
- [ ] Test login and one API call after install
- [ ] If testing killed-state call decline: open app once, or build with `dart-define`
