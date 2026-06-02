# Live Translate — Backend Routing & API Integration Guide

This guide details how to integrate live machine translation and speech-to-text APIs into the "Live Translate" screen once you build the backend routes.

---

## Current Architecture

The "Live Translate" feature is implemented inside [live_translate_screen.dart](file:///c:/Users/drago/Desktop/projects/Durrah%20care%20mob%20app/Flutter_Munawwara/lib/features/pilgrim/screens/live_translate_screen.dart) as a standalone screen class. 

To deliver a fully functional, interactive mock prototype immediately, we built:
- **Language Swapping:** A functional swap button that exchanges the "FROM" and "TO" languages and their corresponding text fields.
- **Simulated Speech-to-Text (STT) Engine:** Pressing the microphone button triggers a realistic "Listening..." state with pulsing radar animations. After 3 seconds, it generates mock English audio transcriptions and their Arabic translations.
- **Interactive Keyboard Translation:** Typing a query into the "Type to translate..." input and pressing send triggers a mock translation request with a loading spinner, outputting the correct translation into the translation card.
- **TTS Sound & Copy Buttons:** Fully working clipboard copy button and voice-playback mock feedback.

---

## Placeholder / Callback Setup

We have exposed a clean integration hook inside the `LiveTranslateScreen` constructor:

```dart
class LiveTranslateScreen extends StatefulWidget {
  final Future<String> Function(String text, String from, String to)? onTranslateApi; // <-- API CALLBACK HOOK
  ...
}
```

If `onTranslateApi` is left null, the screen automatically runs our highly interactive local simulation, making it ready to demonstrate to clients or stakeholders.

---

## Future Integration Steps

Once your backend translation route is implemented, complete the integration by following these steps:

### Step 1: Implement the Translation Service Call
Create a network function inside your `ApiService` or a dedicated translation controller:

```dart
Future<String> translateText(String text, String fromLang, String toLang) async {
  final response = await ApiService.post('/translation/translate', {
    "text": text,
    "from": fromLang.toLowerCase(),
    "to": toLang.toLowerCase(),
  });
  
  if (response.statusCode == 200) {
    return response.data['translatedText'] as String;
  } else {
    throw Exception("Failed to translate text.");
  }
}
```

### Step 2: Inject the API Call into the Grid Button Tap
Update `lib/features/pilgrim/widgets/home_tab/home_tab.dart` where the grid card is tapped:

```dart
bottomLeft: ScoopedGridCard(
  position: CardPosition.bottomLeft,
  icon: _cardIcon(Icons.translate_rounded),
  title: 'Live Translate',
  subtext: 'Speak & translate',
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveTranslateScreen(
          onTranslateApi: (text, from, to) async {
            // Trigger actual API request
            return await ref.read(translationProvider.notifier).translateText(text, from, to);
          },
        ),
      ),
    );
  },
)
```

### Step 3: Inject the API Call into the Mini-bar Tap
Update `lib/features/pilgrim/widgets/sos/sos_help_session_panel.dart` where the mini service button is tapped:

```dart
_buildMiniServiceButton(
  icon: Icons.translate_rounded,
  label: 'Translate',
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LiveTranslateScreen(
          onTranslateApi: (text, from, to) async {
            return await ref.read(translationProvider.notifier).translateText(text, from, to);
          },
        ),
      ),
    );
  },
)
```

---

## Recommended Backend Translation API Options

For translation and Speech-to-Text on your server side, we recommend routing to one of these three services:

1. **Google Cloud Translation & Speech-to-Text APIs:**
   - Perfect for standard translations and text-to-speech. Highly accurate for Arabic, Turkish, Urdu, and Indonesian languages commonly used during Hajj & Umrah.
2. **OpenAI Whisper (STT) + GPT-4o (Translation):**
   - **Whisper API** is the gold standard for conversational speech-to-text.
   - **GPT-4o** is exceptional at natural, contextual translation and supports regional dialects.
3. **Microsoft Azure Cognitive Services:**
   - Offers highly reliable translation, STT, and extremely natural Text-to-Speech voices.
