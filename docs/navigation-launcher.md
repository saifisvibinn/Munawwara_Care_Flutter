# Navigation Launcher — manual test steps

**Last updated:** June 13, 2026

## iOS

1. **First tap (default)** — Profile → App Settings should show **Preferred Navigation App: System Selection**. Tap any Navigate button (e.g. hotel, meetpoint). Bottom sheet appears with Apple Maps + Google Maps (if installed).
2. **Remember choice** — Select Google Maps, check **Remember my choice**, confirm launch. Second tap opens Google Maps directly (no sheet).
3. **Settings override** — App Settings → Preferred Navigation App → **System Selection**. Every tap shows the sheet again.
4. **Apple Maps** — Set preference to Apple Maps in settings. Tap Navigate → Apple Maps opens directly.
5. **Uninstalled fallback** — Set Google Maps as preference, uninstall Google Maps, tap Navigate → sheet reappears.

## Android

1. **Google Maps installed** — First tap shows bottom sheet with Google Maps only.
2. **Remember choice** — Check remember, select Google Maps → subsequent taps launch directly.
3. **No Google Maps** — Uninstall Google Maps, tap Navigate → launches system maps via `geo:` intent (no sheet).
4. **Settings** — Preferred Navigation App row shows current choice; System Selection restores chooser behavior.

## Error handling

- Airplane mode / maps unavailable: sheet stays open, error dialog after failed launch attempt.

## Hot reload

Dart-only changes — hot reload is sufficient. Preference persists across app restarts via SharedPreferences.
