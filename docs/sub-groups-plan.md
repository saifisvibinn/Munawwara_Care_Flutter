# Sub-groups (group hierarchy) — implementation plan

## Overview

Support **organizational parent groups** (containers) that contain **operational
child groups** (leaves). Example:

```
Malaysian group          ← container (folder)
├── Group A              ← leaf (pilgrims, SOS, chat, map)
├── Group B
└── Group C
```

**Goal:** Moderators tap a parent on the dashboard to see and manage child
groups. Pilgrims continue to belong to **one leaf group** only.

**Status:** Planning only — not implemented.

---

## Current architecture (baseline)

Groups are **flat**. Each `Group` document holds moderators, pilgrims, hotel/bus
assignments, and a unique join code.

| Assumption | Location |
|------------|----------|
| Pilgrim in exactly one group | `Group.findOne({ pilgrim_ids: user_id })` — profile, SOS, auth |
| Moderator dashboard is a flat list | `GET /groups/dashboard` → `{ moderator_ids: user_id }` |
| Adding pilgrim moves them | `add_pilgrim_to_group` pulls from old group, adds to new |
| Real-time scoped per group | Socket room `group_${groupId}` |
| Pilgrim home shows one group | `GroupInfo` + `/pilgrim/my-group` |

**Key files**

- Backend model: `mc_backend_app/models/group_model.js`
- Backend controller: `mc_backend_app/controllers/group_controller.js`
- Pilgrim group API: `mc_backend_app/controllers/profile_controller.js` (`get_my_group`)
- Sockets: `mc_backend_app/sockets/socket_manager.js`
- Flutter moderator model: `lib/features/moderator/providers/moderator_provider.dart` (`ModeratorGroup`)
- Flutter pilgrim model: `lib/features/pilgrim/providers/pilgrim_provider.dart` (`GroupInfo`)
- Moderator UI: `lib/features/moderator/screens/moderator_dashboard_screen.dart`, `group_management_screen.dart`

---

## Proposed data model

Add to `group_schema`:

```javascript
parent_group_id: {
  type: mongoose.Schema.Types.ObjectId,
  ref: 'Group',
  default: null,
},
group_kind: {
  type: String,
  enum: ['container', 'leaf'],
  default: 'leaf',
},
```

### Rules

| Rule | Rationale |
|------|-----------|
| `container` groups **must not** have `pilgrim_ids` | Pilgrims live only in leaves |
| `leaf` groups **may** have `parent_group_id` | Child of a container |
| Top-level leaves have `parent_group_id: null` | Backward compatible with today |
| Each group keeps its own `group_code` | Join flow stays per leaf |
| Prevent cycles in `parent_group_id` | Validation on create/update |

### Migration

- Existing groups → `group_kind: 'leaf'`, `parent_group_id: null`
- Optional later: wrap existing groups under new containers manually or via admin tool

---

## Product decisions (lock before build)

| # | Question | Recommended default |
|---|----------|-------------------|
| 1 | Can pilgrims join a container? | **No** — join code only on leaves |
| 2 | Does container have its own join code? | **No** (or disabled in UI) |
| 3 | Do parent moderators auto-manage all children? | **Yes (read + manage)** for v1 |
| 4 | Can leaf co-mods differ from parent co-mods? | **Yes** — leaf `moderator_ids` can extend parent set |
| 5 | SOS / chat / map scope | **Leaf only** for v1 |
| 6 | Broadcast “whole Malaysian group” | **Phase 2** — fan-out to all descendant leaves |

---

## User workflows (target)

### Moderator — create hierarchy

1. Create **Malaysian group** → kind `container` (no pilgrims).
2. Open Malaysian group → **Create sub-group** → Group A (`leaf`, `parent_group_id` set).
3. Repeat for B, C.
4. Manage pilgrims inside A/B/C as today (add, transfer, provision).

### Moderator — dashboard navigation

1. Dashboard shows **top-level** groups (containers + orphan leaves).
2. Tap **Malaysian group** → **child list** (A, B, C) with roll-up stats.
3. Tap **Group A** → existing `GroupManagementScreen` (unchanged behavior).

### Pilgrim — unchanged

1. Scan / enter **Group A** code → join leaf.
2. Home card, SOS, chat, navigate-to-mod → same single `group_id`.
3. No UI change unless we later show parent name (“Malaysian group · Group A”).

### Add / transfer pilgrim

- Allowed only on **leaf** groups.
- Transfer A → B: same as today (pull from old leaf, add to new leaf).
- Reject add to container with `400` + clear message.

---

## Implementation phases

### Phase 1 — Foundation (MVP)

**Backend**

- [ ] Extend `group_model.js` + Joi schemas
- [ ] Migration script for existing documents
- [ ] `POST /groups/create` — accept optional `parent_group_id`, set `group_kind`
- [ ] Validate: parent is `container`, caller is mod on parent
- [ ] `GET /groups/dashboard` — return tree metadata:
  - `parent_group_id`, `group_kind`, `child_count`, optional `children[]` summary
- [ ] Block `pilgrim_ids` mutations on containers
- [ ] `GET /groups/:id/children` — list direct child groups (optional if embedded in dashboard)
- [ ] Shared helper: `isModeratorOfGroupOrAncestor(userId, groupId)`
- [ ] Shared helper: `resolveLeafDescendants(containerId)` (for Phase 2)

**Flutter (moderator)**

- [ ] Extend `ModeratorGroup` with `parentGroupId`, `groupKind`, `childCount`
- [ ] Dashboard: container row → navigates to **SubGroupsScreen**
- [ ] **SubGroupsScreen**: list children + “Create sub-group”
- [ ] Create-group flow: pass `parentGroupId` when creating under container
- [ ] Breadcrumb in `GroupManagementScreen`: `Malaysian group › Group A`

**Flutter (pilgrim)**

- [ ] No required changes if pilgrims stay on leaves only

**Estimate:** Medium — ~1–2 weeks focused work.

---

### Phase 2 — Parent operations

**Backend**

- [ ] `POST /groups/:container_id/broadcast` — message to all leaf pilgrims under tree
- [ ] Reminders: allow `target_type: container` → resolve leaf IDs
- [ ] Roll-up stats endpoint or enrich dashboard payload:
  - total pilgrims, online, SOS count across children
- [ ] Authorization uses ancestor check everywhere group mod is verified

**Flutter (moderator)**

- [ ] Container detail header with aggregated stats
- [ ] Broadcast UI from container (reuse group message composer with fan-out API)
- [ ] Manage pilgrims: filter scope “this group” vs “whole Malaysian group”

**Estimate:** Medium.

---

### Phase 3 — Live parent visibility (optional)

**Backend / sockets**

- [ ] Option A: parent mod joins all child `group_${id}` rooms when viewing container
- [ ] Option B: new `container_${id}` room with aggregated location/SOS events
- [ ] Parent map: aggregate pilgrim markers from all leaves

**Flutter**

- [ ] Container map screen (read-only roll-up or multi-layer map)

**Estimate:** Hard — socket and map complexity.

---

## API changes (summary)

| Method | Path | Change |
|--------|------|--------|
| `POST` | `/groups/create` | Optional `parent_group_id`; set `group_kind` |
| `GET` | `/groups/dashboard` | Tree fields + optional nested children |
| `GET` | `/groups/:id` | Include parent name, kind, child summary |
| `GET` | `/groups/:id/children` | **New** — direct children (moderator auth) |
| `POST` | `/groups/:id/pilgrims` | Reject if target is container |
| `POST` | `/groups/join` | Reject join to container (pilgrims) |
| `GET` | `/pilgrim/my-group` | Optional `parent_group_name` for display |
| `POST` | `/groups/:id/broadcast` | **New (Phase 2)** — fan-out to descendant leaves |

---

## Authorization model (v1)

```
canManage(groupId, userId):
  if user in group.moderator_ids → true
  if group.parent_group_id:
    if user in ancestor(container).moderator_ids → true
  return false
```

Apply to: add/remove pilgrim, invite mod, messages, areas, meetpoints, settings.

---

## Areas that need audit (grep / refactor)

Every place that assumes a flat group list or single-level mod check:

| Area | File(s) | Change |
|------|---------|--------|
| Group list query | `group_controller.js` | Filter top-level vs children |
| Pilgrim my-group | `profile_controller.js` | Optional parent label |
| SOS | `profile_controller.js`, sockets | Stay leaf-scoped |
| Messages | `message_controller.js` | Container broadcast in Phase 2 |
| Invitations | `invitation_controller.js` | Invite to leaf; container invite TBD |
| Manage all pilgrims | `group_controller.js` (`my-pilgrims`) | Scope by parent tree |
| Reminders | `reminder_controller.js` | Resolve container → leaves |
| Offline cache | `moderator_provider.dart`, `app_data_cache.dart` | Store tree shape |
| Socket join | `moderator_dashboard_screen.dart` | Join leaf rooms; container TBD |
| Notifications / FCM | `notification_service.dart` | `group_id` remains leaf |

---

## Risk assessment

| Area | Difficulty | Notes |
|------|------------|-------|
| Schema + create child API | Easy | Isolated change |
| Pilgrim app | Easy | No change if leaves-only |
| Moderator dashboard tree UI | Medium–Hard | New navigation layer |
| Permission inheritance | Hard | Touch many auth checks |
| Sockets / parent map | Hard | Defer to Phase 3 |
| Migration | Easy | Default all existing → leaf |

**Overall:** Moderately messy — cross-cutting domain change, not a one-field add.
Pilgrim experience can remain stable; **moderator dashboard and backend auth**
carry most of the cost.

---

## Testing checklist

### Phase 1

- [ ] Create container → create 3 children → dashboard drill-down works
- [ ] Cannot add pilgrim to container
- [ ] Pilgrim joins leaf code → `my-group` returns leaf only
- [ ] Transfer pilgrim between sibling leaves (A → B)
- [ ] Parent mod can open and manage child without being in child `moderator_ids` (if inheritance on)
- [ ] Leaf-only mod cannot open sibling group
- [ ] Existing flat groups behave unchanged after migration
- [ ] SOS, chat, beacon still scoped to leaf `group_id`

### Phase 2

- [ ] Broadcast from container reaches all leaf pilgrims
- [ ] Roll-up counts match sum of children

---

## Out of scope (v1)

- More than **two levels** of nesting (parent → child only)
- Pilgrim belonging to multiple groups
- Pilgrim picking sub-group after joining parent
- Admin web (`mc_mod_front`) — separate follow-up unless required at launch

---

## Related docs

- `docs/data-sync.md` — moderator provider + `group_updated` socket
- `docs/moderator-invitations.md` — co-mod invites (per group, needs ancestor rules)
- `mc_backend_app/docs/API_DOCUMENTATION.md` — update after implementation
