# App version and About screen

## Version source

The displayed version comes from `pubspec.yaml` (`version: name+build`) via
`package_info_plus` and `appVersionProvider` in
`lib/core/providers/app_version_provider.dart`.

## Where it appears

| Location | Widget / screen |
|----------|-----------------|
| Splash | `AppVersionLabel` at the bottom of `SplashScreen` |
| Login | `AppVersionLabel` at the bottom of `LoginScreen` |
| Settings → About | `AboutScreen` under the app name |
| Settings list | **About** row in `LegalSupportSection` (pilgrim + moderator profiles) |

## About screen

Route: `/about` (`AboutScreen`).

Includes:

- App logo and name
- Dynamic version string
- Contact support → `/contact-support`
- Request account deletion → confirm dialog → `/request-account-deletion`

Privacy Policy remains on the profile **Privacy & support** card, not inside About.

## Rebuild

After changing `pubspec.yaml` version, rebuild the app; no code changes are
required for the label to update.
