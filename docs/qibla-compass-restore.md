# Qibla compass — removed (restore guide)

**Status:** Removed from the pilgrim app on 2026-06-01. Tab index **2** is now an empty
placeholder. Bottom nav still shows the Qibla label/icon until replaced.

## Why it was removed

The third bottom-nav slot is reserved for a future feature. The full Qibla implementation
is preserved so it can be dropped back in with the same UI and behavior.

## Archived source (exact UI)

Full implementation (1,065 lines):

```
docs/archive/qibla_compass_screen.dart
```

Restore by copying back to:

```
lib/features/pilgrim/screens/qibla_compass_screen.dart
```

---

## Dependencies (`pubspec.yaml`)

Re-add when restoring:

```yaml
dependencies:
  flutter_qiblah: ^3.2.0
  flutter_compass_v2: any

dependency_overrides:
  flutter_compass_v2:
    path: ./plugins/flutter_compass_v2
```

Then run `flutter pub get`.

---

## Dashboard wiring (`pilgrim_dashboard_screen.dart`)

### Tab order (unchanged)

| Index | Tab |
|-------|-----|
| 0 | Home |
| 1 | Map |
| 2 | **Placeholder** (was Qibla) |
| 3 | Announcements |

### Restore steps

1. Copy `docs/archive/qibla_compass_screen.dart` → `lib/features/pilgrim/screens/`.
2. Import:

   ```dart
   import 'qibla_compass_screen.dart';
   ```

3. Add constant:

   ```dart
   static const int _qiblaTabIndex = 2;
   ```

4. Replace the empty tab in `_buildTabPages()` with:

   ```dart
   QiblaCompassScreen(
     enableAlignmentHaptics: _currentTab == _qiblaTabIndex,
   ),
   ```

5. Remove `_EmptyDashboardTab` if no longer needed.

### Haptics gating

The compass stays mounted in the dashboard `PageView` (keep-alive). Alignment haptics
(`HapticFeedback.lightImpact` within ±5°) only fire when the user is on tab index 2,
via `enableAlignmentHaptics`. This avoids buzzing while on Home/Map/Announcements.

---

## Bottom nav (`bottom_nav.dart`)

Slot 2 currently uses:

- Label: `tab_qibla`.tr()
- Icon: `Symbols.explore`

When restoring Qibla, keep this slot as-is (already correct).

---

## UI structure (reference)

### Screens / states

1. **Calibration** — figure-8 animation, accuracy pills, “Calibrating Compass” copy
   (shown when magnetometer accuracy &lt; 2).
2. **Loading** — navy `#09162D` background, orange spinner.
3. **Error** — location off, permission denied, or generic init failure.
4. **Compass** — main experience:
   - Navy background `#09162D`
   - Title: `qibla_title`
   - Subtitle: `qibla_facing` (green) or `qibla_rotate` (orange)
   - 340×340 compass dial (`_CompassDialPainter`) rotating with heading
   - Kaaba marker (`_QiblaMarker`) at Qibla bearing in screen space
   - Center navigation arrow (green when aligned, orange otherwise)
   - Bottom sheet: heading ° + cardinal, Qibla bearing, distance to Kaaba (km),
     accuracy chip with snackbar hint

### Colors

| Use | Color |
|-----|-------|
| Background | `#09162D` |
| Accent / rotate | `#E67E22` |
| Aligned | `#2ECC71` |
| Dial ticks | `#E67E22` / `#2A4A6B` |

### Sensors & logic

- `FlutterQiblah.qiblahStream` — heading + Qibla offset
- `Geolocator.getPositionStream` — distance to Kaaba (21.422487, 39.826206)
- `FlutterCompass.events` — calibration accuracy + fallback heading
- Alignment tolerance: **±5°**
- 4s loading fallback for silent emulators

### Private widgets (in archived file)

- `_Figure8Painter` — calibration lemniscate path
- `_QiblaMarker` — mosque icon + triangle pointer
- `_InfoChip` — bottom stat chips
- `_CompassDialPainter` — tick marks, N/E/S/W, degree labels
- `_TrianglePainter` — marker pointer

---

## i18n keys (all locales)

Keep in `assets/translations/*.json`:

- `tab_qibla`
- `qibla_title`, `qibla_facing`, `qibla_rotate`
- `qibla_label`, `qibla_distance`, `qibla_offset`
- `qibla_error_location`, `qibla_error_permission`, `qibla_error_sensor`, `qibla_error_generic`
- `qibla_calibration_needed`
- `qibla_accuracy`, `qibla_accuracy_unreliable`, `qibla_accuracy_low`, `qibla_accuracy_medium`, `qibla_accuracy_high`, `qibla_accuracy_hint`

Calibration screen uses hardcoded English strings (“Calibrating Compass”, figure-8
instructions) — restore as-is if matching previous behavior.

---

## Permissions

Same as live map: location services + magnetometer. No extra manifest entries beyond
existing location permissions.

---

## Related docs

- Previous short note: `docs/qibla-compass.md` (superseded by this file)
- App tab map: `lib/app_architecture.md` (update tab 2 when restoring)
