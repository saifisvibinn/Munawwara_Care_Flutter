# Dashboard tab navigation

Moderator and pilgrim home screens use a **horizontal `PageView`** with a shared
**`PageController`** instead of an `IndexedStack` for instant tab switches.

## Goals

- Tap bottom navigation: **350ms** slide with `Curves.easeInOut`
- Swipe between primary tabs (indices 0–3)
- Preserve tab state (search, lists, map, chat scroll) via **`KeepAliveTab`**
- Hidden screens (pilgrim Profile) open only from in-screen actions, not swipe

## Shared widgets

| File | Role |
|------|------|
| `lib/core/widgets/keep_alive_tab.dart` | `KeepAliveTab`, `DashboardTabPageView` |

### `KeepAliveTab`

Wraps each page child with `AutomaticKeepAliveClientMixin` so `PageView` does not
drop off-screen tab state.

Pilgrim **Profile** is not in the `PageView` (opened via `_openProfileScreen` from home settings).

## Flow

1. Bottom nav `onTap` → `_goToTab(index)` → `pageController.animateToPage`
2. Swipe → `onPageChanged` → `_handlePageChanged` → `setState(_currentTab)` + side effects
3. Back button on non-home tab → `_goToTab(0)`

## Screens

| Screen | File | Tabs (index) |
|--------|------|----------------|
| Moderator | `lib/features/moderator/screens/moderator_dashboard_screen.dart` | Groups 0, Provisioning 1, Reminders 2, Profile 3 |
| Pilgrim | `lib/features/pilgrim/screens/pilgrim_dashboard_screen.dart` | Home 0, Map 1, Qibla 2, Chat 3 (Profile: pushed route) |

### Moderator alerts (not a PageView tab)

Opened from the Groups tab bell via a **circular reveal** route:

- `lib/features/moderator/routes/moderator_alerts_reveal_route.dart`
- `openModeratorAlertsWithReveal(context)` — 500ms open / 400ms reverse, `Curves.easeInOut`
- Tray/deep links still use `NotificationService` `MaterialPageRoute` pushes

Pilgrim tab side effects (active chat group, weather refresh, map recenter) run in
`_applyTabSideEffects` from `_handlePageChanged` so swipe and tap share one path.

## Related

- [qibla-compass.md](qibla-compass.md) — Qibla haptics gated by `_currentTab`
