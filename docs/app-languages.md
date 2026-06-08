# App languages (i18n)

## Supported UI locales

| Code | Language | Direction | Config |
|------|----------|-----------|--------|
| `en` | English | LTR | [`app_locales.dart`](../lib/core/config/app_locales.dart) |
| `ar` | Arabic | RTL | |
| `ur` | Urdu | RTL | |
| `fr` | French | LTR | |
| `id` | Bahasa Indonesia | LTR | |
| `tr` | Turkish | LTR | |
| `fa` | Persian (Farsi) | RTL | |
| `ms` | Bahasa Malaysia | LTR | |

Translation files: `assets/translations/{code}.json`.

## Pilgrim account language

Stored on the user record as `language` (short code). Must match an entry in platform `pilgrim_languages` (see backend `DEFAULT_LANGUAGES`).

Used for:

- Cloud TTS for moderator messages (`tts_service.js`)
- SOS moderator alert bundled clip (`assets/audio/sos/{code}.mp3`)
- Push notification translation targets

## SOS bundled audio

One MP3 per supported code under `assets/audio/sos/`. Replace placeholder copies with recorded clips in the target language when available.

## Adding a new language

1. Add locale to `AppLocales` and `main.dart` / profile pickers.
2. Add `{code}.json` with full key parity vs `en.json`.
3. Update backend `DEFAULT_LANGUAGES`, Joi allowlists, and `tts_service.js` voice map.
4. Add SOS MP3 and `pubspec.yaml` asset entry.
5. Extend live translate mappings if ML Kit supports the language.
6. Update moderator web `SUPPORTED_LANGUAGES` and UI catalogs.
