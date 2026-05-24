# Data synchronization (moderator)

## Overview

Moderator-facing group and pilgrim data must stay consistent across tabs and screens without manual pull-to-refresh. The app uses **Riverpod notifiers** plus **Socket.IO `group_updated`** events from the backend.

## Single source of truth

| Data | Provider | API |
|------|----------|-----|
| Groups + pilgrims in groups | `moderatorProvider` | `GET /groups/dashboard` |
| Manage Pilgrims list | `managePilgrimsProvider` | `GET /groups/my-pilgrims` |
| Provisioning tracker items | Local state in `ProvisioningTab` | `GET /auth/groups/:id/provisioning-status` |

The **Provisioning** tab reads its group dropdown from `ref.watch(moderatorProvider).groups`, not a duplicate dashboard fetch.

## After any mutation

Call `moderatorProvider.notifier.syncAfterMutation({String? groupId})`:

- With `groupId`: refreshes one group via `GET /groups/:id`, falls back to full dashboard.
- Without `groupId`: `loadDashboard(force: true, silently: true)` (bypasses the 10s throttle).

All CRUD methods on `ModeratorNotifier` (create group, add/remove pilgrim, invite moderators, etc.) call this internally.

Manage Pilgrims assign/remove/bulk flows use `addPilgrimToGroup` / `removePilgrimFromGroup`, then `managePilgrimsProvider.refresh()`.

## Real-time (Socket.IO)

The moderator dashboard listens for `group_updated` and calls `loadDashboard(force: true)`.

Backend emits `group_updated` (see `mc_backend_app/utils/group_socket_events.js`) after:

- Group create / update
- Pilgrim add / remove / provision (single and bulk)
- Moderator invite sent

## Screens with separate state (by design)

- **Provisioning items** (`pending` / `activated`) — only refreshed via `_loadProvisioningStatus()`; group membership still syncs via `moderatorProvider`.
- **Reminders** — polled on tab interval, not socket-driven.
- **Call history / explore** — fetch on open.

## Manual test checklist

1. Create group → open Provisioning tab → new group appears in dropdown without pull-to-refresh.
2. Provision pilgrim → Groups tab shows new member immediately.
3. Manage Pilgrims: assign, remove, bulk move → Groups tab and group map update without refresh.
4. Invite moderator → co-moderator list updates after success.
5. Second device: same actions propagate within a few seconds via `group_updated`.
