# Bus attendance — pilgrim realtime updates

## Overview

When a moderator **starts** a trip boarding session, pilgrims should see the
`ActiveAttendanceCard` on the home tab immediately — without pull-to-refresh.

## Data source

| Layer | Detail |
|-------|--------|
| API | `GET /pilgrim/my-group` → `active_boarding_session` (only `status: active`) |
| Socket | `bus_boarding_started` / `bus_boarding_ended` emitted to `group_{id}` room |

## Pilgrim client flow

1. `PilgrimBoardingRealtimeBinder.bindListeners()` runs at app bootstrap (same
   pattern as `MessageRealtimeBinder`) so handlers are never removed when the
   dashboard widget disposes.
2. On `bus_boarding_started`, `PilgrimNotifier.applyBoardingSessionStarted()`
   updates local state for instant UI, then `loadDashboard(force: true)` confirms
   from the API.
3. On `bus_boarding_ended`, `clearActiveBoardingSession()` removes the card.
4. Backend also emits `group_updated` with `reason: bus_boarding_started` as a
   fallback; the dashboard already refreshes on `group_updated`.

## Startup ordering

Realtime must connect **before** GPS initialization. `_initLocation()` can take
several seconds (permission + first fix); delaying the socket caused pilgrims to
miss `bus_boarding_started` while the dashboard was already visible.

## Group room join

`_joinPilgrimGroupRoom` emits `join_group` immediately and again after 500 ms so
the pilgrim is in the group room even when `join_group` races ahead of async
`register-user` on the server.

## Manual test

1. Open pilgrim app on home tab (do not refresh).
2. Moderator starts trip attendance for the pilgrim's group.
3. Attendance card appears within ~1 s without pilgrim refresh.
4. Moderator ends session → card disappears without refresh.
