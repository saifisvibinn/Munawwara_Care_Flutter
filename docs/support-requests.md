# In-app support and account deletion requests

## Purpose

Pilgrims and moderators can contact support or request account deletion **without leaving the app** or using `mailto:` links. The mobile app posts to the backend; the backend emails `munawwaracare@gmail.com` via Gmail SMTP.

Both flows are opened from **Settings → About** (`AboutScreen`, route `/about`). See `docs/app-version-and-about.md`.

## API

- `POST /api/support/request` (authenticated)
- Body: `{ "type": "support" | "account_deletion", "message"?: string, "contact_hint"?: string }`
- User profile fields (id, name, phone, role) are loaded server-side from the JWT.

## Flutter routes

- `/contact-support` — general support form
- `/request-account-deletion` — deletion form (after confirm dialog on pilgrim profile)

## Backend

- `mc_backend_app/routes/support_routes.js`
- `mc_backend_app/controllers/support_controller.js`
- `mc_backend_app/config/email_service.js` → `sendSupportInquiryEmail`

Optional env: `SUPPORT_EMAIL` (defaults to `EMAIL_USER`).
