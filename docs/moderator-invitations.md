# Moderator group invitations (mobile)

## Overview

Group creators invite co-moderators by email. The backend creates a pending
`Invitation` and notifies the invitee. The mobile app lets invitees **accept**
or **decline** in-app; the inviter sees outcomes under **Alerts → Updates**.

## Roles

| Role | Experience |
|------|------------|
| **Invitee** | Pending cards on moderator dashboard (Groups tab); Accept / Decline |
| **Inviter** | `invitation_accepted` / `invitation_declined` in Alerts → Updates tab |

## API (existing backend)

| Method | Path | Notes |
|--------|------|--------|
| `POST` | `/api/groups/:group_id/invite` | Creator sends invite (already used from group management) |
| `GET` | `/api/invitations` | Pending invites for current user |
| `POST` | `/api/invitations/:id/accept` | Join group; notify inviter |
| `POST` | `/api/invitations/:id/decline` | Decline; confirm in UI first |

## Flutter modules

- `lib/features/invitations/models/group_invitation.dart`
- `lib/features/invitations/providers/invitation_provider.dart` — `pendingInvitationsProvider`
- `lib/features/invitations/widgets/pending_invitations_section.dart` — dashboard embed
- `lib/features/notifications/widgets/moderator_updates_tab.dart` — Alerts tab

## Real-time

- `notification_refresh` socket → refetch notifications + pending invitations +
  moderator dashboard (`moderator_dashboard_screen._refreshRealtimeState`).
- FCM tap: `group_invitation` → moderator dashboard; accept/decline outcome →
  Alerts with Updates tab selected.

## Related

- Web reference: `mc_mod_front` invitations page
- Data sync after accept: `moderatorProvider.loadDashboard(force: true)` and
  `SocketService.emit('join_group', groupId)`
