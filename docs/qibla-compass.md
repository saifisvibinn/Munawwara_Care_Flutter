# Qibla compass (pilgrim tab)

## Behavior

The Qibla compass uses device magnetometer, location, and `flutter_qiblah` streams.
Alignment haptics (`HapticFeedback.lightImpact`) fire when the phone points within
±5° of the Qibla bearing **and** the pilgrim is on the Qibla bottom-nav tab.

## Haptics vs compass accuracy

The compass keeps updating in the background while other tabs are shown
(`IndexedStack` keeps the widget mounted). Only **haptics** are gated via
`QiblaCompassScreen.enableAlignmentHaptics`, set from
`pilgrim_dashboard_screen.dart` when `_currentTab == _qiblaTabIndex` (2).

This preserves heading accuracy when returning to the Qibla tab without
re-initializing sensors.

## Related files

| File | Role |
|------|------|
| `lib/features/pilgrim/screens/qibla_compass_screen.dart` | Compass UI, streams, gated haptics |
| `lib/features/pilgrim/screens/pilgrim_dashboard_screen.dart` | Passes `enableAlignmentHaptics` |
