# Muslim Corner — Implementation Handoff

**Date:** 2026-06-01  
**Status:** Feature largely complete; **Qibla live compass has a known open bug** (see [Qibla section](#qibla-compass--open-issue)).

---

## Summary

The pilgrim app’s third bottom-nav tab (index **2**) was replaced from an empty Qibla placeholder with a full **Islamic Corner / “Muslim”** hub. Content is powered by **[UmmahAPI](https://ummahapi.com/api)**. UI was aligned with Stitch mockups from `C:\Users\drago\Desktop\muslim\`.

The Qibla compass lives on the **Prayer Times** screen (not the hub tab itself). It was migrated from a standalone full-screen compass (`docs/archive/qibla_compass_screen.dart`) into a compact embedded widget, with several iterations on sensor behavior and animation.

---

## Dashboard integration

| Item | Location | Detail |
|------|----------|--------|
| Tab index | `lib/features/pilgrim/screens/pilgrim_dashboard_screen.dart` | Index **2** → `IslamicCornerHubScreen()` |
| Bottom nav label | `lib/features/pilgrim/widgets/bottom_nav.dart` | `tab_muslim`.tr() |
| Bottom nav style | `lib/core/widgets/app_liquid_glass_bottom_bar.dart` | iOS Liquid Glass via `cupertino_liquid_glass` — requires `Scaffold.extendBody: true` |
| Bottom nav icon | same | `Symbols.pan_tool` (praying hand) |
| Previous Qibla tab | `docs/qibla-compass-restore.md` | Full-screen compass removed 2026-06-01; archived for restore |

---

## Module layout

```
lib/features/muslim/
├── constants/
│   ├── muslim_colors.dart          # Stitch-aligned palette
│   └── dua_category_icons.dart     # Icon map for du'aa categories
├── models/
│   └── muslim_models.dart          # API DTOs (prayer, qibla, duas, hadith, asma)
├── providers/
│   └── muslim_providers.dart       # Riverpod: location, prayer bundle, azkar, hadith, etc.
├── services/
│   └── ummah_api_service.dart      # Dio client → https://ummahapi.com/api
├── screens/
│   ├── islamic_corner_hub_screen.dart
│   ├── prayer_times_screen.dart    # Includes QiblaCompassWidget
│   ├── azkar_screen.dart
│   ├── duaa_screen.dart
│   ├── duaa_category_screen.dart
│   ├── hadith_screen.dart
│   └── asma_ul_husna_screen.dart
└── widgets/
    ├── muslim_widgets.dart         # MuslimScreenScaffold, ArabicText, etc.
    ├── dua_card.dart
    └── qibla_compass_widget.dart   # Live compass (see Qibla section)
```

---

## API & data flow

**Base URL:** `https://ummahapi.com/api`  
**Client:** `UmmahApiService` (Dio, 15s connect / 20s receive timeouts)

| Endpoint | Used for |
|----------|----------|
| `/prayer-times?lat=&lng=` | Prayer times + current/next prayer status |
| `/today-hijri` | Hijri date on hub + prayer screen |
| `/qibla?lat=&lng=` | Qibla bearing, distance, compass label |
| `/duas/category/{id}` | Azkar + du'aa lists |
| `/duas/categories` | Du'aa category grid |
| `/hadith/random` | Hub “Hadith of the Day” |
| `/hadith/collections` | Browse collections sheet |
| `/hadith/{collection}/{number}` | Specific / random-from-collection hadith |
| `/asma-ul-husna` | 99 Names list + search |

**Location:** `muslimLocationProvider` uses Geolocator (8s timeout, low accuracy). Falls back to Mecca `(21.4225, 39.8262)` if GPS/permission unavailable.

**Hub load:** `prayerBundleProvider` fetches prayer times + hijri + qibla in parallel after GPS resolves. Hub also loads `randomHadithProvider` separately. **No caching** — pull-to-refresh invalidates and refetches.

---

## Screens & UX decisions

### Hub (`IslamicCornerHubScreen`)
- Featured prayer card (next prayer, countdown, tap → Prayer Times)
- 2×2 grid: Azkar, Du'aa, Hadith, 99 Names
- Pull-to-refresh invalidates prayer bundle + random hadith

### Prayer Times
- Full prayer table (imsak → isha), current/next highlighting
- Hijri + Gregorian dates
- **Qibla compass card** at bottom

### Hadith
- Removed confusing “enter hadith number” flow
- **Next Hadith** button → new random hadith
- **Browse Collections** → bottom sheet; **one tap on a book** loads a random hadith from that collection into the main card via `displayedHadithProvider` (no number dialog)
- Removed `TextButton` underline styling on collection names

### Du'aa
- **“For Hajj & Umrah”** featured section with icon tiles (`dua_category_icons.dart`)
- Category grid with icons for priority categories

### 99 Names (`AsmaUlHusnaScreen`)
- Search via `asmaSearchQueryProvider` + API search
- Detail bottom sheet wrapped in `SingleChildScrollView` (overflow fix)

### Shared scaffold
- `MuslimScreenScaffold` wraps body in **`Material`** (not just `ColoredBox`) so `TextField` / `InkWell` work on 99 Names and elsewhere
- Arabic text uses bundled **Amiri** font (`assets/fonts/`)

---

## Fixes applied during implementation

| Issue | Fix |
|-------|-----|
| Analyzer errors from archived Qibla in `docs/` | `analysis_options.yaml` excludes `docs/**` |
| 99 Names crash: “No Material widget found” | `MuslimScreenScaffold` uses `Material` |
| 99 Names bottom sheet overflow | `SingleChildScrollView` in detail sheet |
| `Symbols.place_of_worship` undefined | Use `Symbols.mosque` |
| Hadith browse UX confusing | Single-tap collection → random hadith in card |
| Lint / callback warnings | Minor cleanups in Muslim screens |

---

## Dependencies added

```yaml
# pubspec.yaml
flutter_compass_v2:
  path: ./plugins/flutter_compass_v2
```

**Not added (but relevant for Qibla fix):**

```yaml
flutter_qiblah: ^3.2.0   # Used by the old full-screen compass; merges compass + GPS qibla offset
```

**Fonts bundled:** Lexend (existing) + Amiri for Arabic (`pubspec.yaml` → `assets/fonts/`).

---

## i18n

New keys in `assets/translations/en.json`, `ar.json`, and other locales for `tab_muslim` + Muslim screen strings.

Existing Qibla strings reused from the old compass:
- `qibla_facing`, `qibla_rotate`, `qibla_error_sensor`
- Full set documented in `docs/qibla-compass-restore.md`

---

## Qibla compass — history & current state

### Original (working reference)

Full implementation archived at:

```
docs/archive/qibla_compass_screen.dart   (~1,065 lines)
```

Restore guide: `docs/qibla-compass-restore.md`

**Old stack:**
- `flutter_qiblah` → `FlutterQiblah.qiblahStream` (merges `FlutterCompass.events` + one GPS fix)
- `QiblahDirection`: `direction` = device heading, `offset` = absolute Qibla bearing from North (computed locally from GPS via great-circle math)
- `flutter_compass_v2` (local plugin) for calibration accuracy + heading fallback

**Old UI model (important):**
1. **Compass dial** rotates by **`-heading`** so N/E/S/W track the real world
2. **Kaaba marker** (mosque icon on ring) rotates by **`(offset - heading)`** in screen space
3. **Center navigation arrow stays fixed** (points where the phone faces)
4. User rotates until the **fixed arrow sits under the Kaaba marker**
5. Alignment ±5°, green glow + haptic when matched

Also included: calibration figure-8 screen, distance to Kaaba, accuracy chip, navy full-screen theme.

### Current embedded widget

**File:** `lib/features/muslim/widgets/qibla_compass_widget.dart`  
**Used in:** `lib/features/muslim/screens/prayer_times_screen.dart`

**Data:** Qibla bearing from **UmmahAPI** (`QiblaData.qiblaDirection`), not locally computed `offset`.

**Sensors:** `FlutterCompass.events` directly (`event.heading` only).

**UI:** Compact card on Prayer Times screen; same 3-layer model as old compass (dial / Kaaba marker / fixed center arrow), styled with `MuslimColors` and `_CompassDialPainter` tick marks.

### Iterations (conversation timeline)

| Iteration | Problem | Change |
|-----------|---------|--------|
| v1 | Compass was static (API angle only, no sensor) | Added `flutter_compass_v2`, live heading |
| v2 | User: “animations don’t make sense” | Replaced rotating needle with old model: fixed center arrow + rotating dial + orbiting Kaaba marker |
| v3 | User: “correct when still; when I move toward Qibla, direction changes” | **Investigated, not fully fixed** |

### Qibla — open issue

**Reported behavior:** When the phone is held still, the Qibla marker appears in the right place. When the user physically rotates the phone toward Qibla, the marker **does not converge** under the center arrow — it appears to “move” or drift incorrectly.

**Likely causes (investigated, not yet implemented):**

1. **Mixed bearing sources**  
   - Current widget: API `qibla_direction` (UmmahAPI) + raw `FlutterCompass` heading  
   - Old widget: **locally computed** `offset` (same GPS math as `flutter_qiblah`) + compass heading from the **same** `qiblahStream`  
   - Mismatch between API true bearing and Android **magnetic** azimuth (plugin reports magnetic on Android, no declination applied in `FlutterCompassPlugin.kt`).

2. **Heading axis / phone orientation**  
   - `CompassEvent.heading` = top of device (`flutter_compass_v2` docs)  
   - `headingForCameraMode` = back of device (iOS only; Android sends `0`)  
   - Tilting the phone while turning can skew heading; Qibla apps usually assume **phone held flat** (screen up) or use `flutter_qiblah`’s merged stream like the old screen.

3. **Transform model**  
   - Marker and dial are sibling `Transform.rotate` widgets (math equivalent to nesting marker on dial at fixed `offset`, but nesting is clearer and matches archived code structure).

4. **No `flutter_qiblah`**  
   - Old app’s proven path; package merges compass events with GPS and exposes consistent `direction` + `offset`.

### Recommended fix (next engineer)

**Option A — Match old behavior (preferred):**

1. Add `flutter_qiblah: ^3.2.0` to `pubspec.yaml` (keep `flutter_compass_v2` path override).
2. In `QiblaCompassWidget`, subscribe to `FlutterQiblah.qiblahStream`:
   - `heading` ← `QiblahDirection.direction`
   - `qiblaBearing` ← `QiblahDirection.offset` (local GPS math, not API)
3. Keep UmmahAPI qibla for **distance** / display label only, or drop API qibla for compass math entirely.
4. Nest Kaaba marker **inside** the dial transform at fixed `offset` angle (see archived `qibla_compass_screen.dart` lines ~367–389).
5. Optional: low-pass filter on heading; iOS `headingForCameraMode` when phone is flat.

**Option B — Stay API-only:**

1. Apply **magnetic declination** correction to Android heading using user lat/lng (`GeomagneticField` — helper exists in plugin’s `MathUtils.kt`).
2. Verify UmmahAPI `qibla_direction` is **true north** absolute bearing (compare with `flutter_qiblah` `Utils.getOffsetFromNorth` for same coordinates).

**Alignment formula (same as archived screen):**

```dart
// Aligned when phone heading ≈ absolute Qibla bearing
final delta = (heading - qiblaBearing + 180) % 360 - 180;
final aligned = delta.abs() <= 5.0;

// Kaaba marker screen angle
final qiblaScreenAngle = (qiblaBearing - heading + 360) % 360;

// Dial rotation
final dialAngle = -heading;
```

**Testing:**
- **Real device only** (emulators usually lack magnetometer → `qibla_error_sensor`)
- **Full restart** after adding native plugins (`flutter run`, not hot reload)
- Hold phone **flat**, rotate slowly in horizontal plane
- Compare bearing with old archived full-screen compass or a known Qibla app

---

## Performance notes (not implemented)

Discussed but not built:
- Cache API responses (prayer bundle, azkar)
- Use last-known GPS immediately, refine in background
- Prefetch on app start
- Stagger hub API calls

Slow first load is **expected**: GPS wait (up to 8s) + 3 parallel UmmahAPI calls + separate random hadith call.

---

## Related docs & assets

| Path | Purpose |
|------|---------|
| `docs/archive/qibla_compass_screen.dart` | Full old Qibla UI + calibration + painters |
| `docs/qibla-compass-restore.md` | Step-by-step restore to dedicated tab |
| `C:\Users\drago\Desktop\muslim\` | Stitch mockups (reference) |
| `plugins/flutter_compass_v2/` | Local compass plugin (vendored) |

---

## Quick test checklist

- [ ] Bottom nav tab 2 opens Muslim hub
- [ ] Prayer card shows next prayer + countdown; tap opens Prayer Times
- [ ] Prayer Times lists all prayers + Qibla card
- [ ] Qibla: dial N/E/S/W track world when rotating phone flat on **real device**
- [ ] Qibla: Kaaba marker converges under center arrow when facing Qibla
- [ ] Azkar morning/evening toggle + tap counters
- [ ] Du'aa Hajj/Umrah section + category icons
- [ ] Hadith: Next + Browse Collections (one tap → random from book)
- [ ] 99 Names: search, detail sheet scrolls, no Material/TextField crash
- [ ] Pull-to-refresh on hub
- [ ] Arabic renders with Amiri font

---

## Agent transcript

Full conversation history (Muslim implementation + Qibla iterations):

```
C:\Users\drago\.cursor\projects\c-Users-drago-Desktop-projects-Durrah-care-mob-app\agent-transcripts\4dbccb80-9ded-463b-b052-0e284ce900c8\4dbccb80-9ded-463b-b052-0e284ce900c8.jsonl
```
