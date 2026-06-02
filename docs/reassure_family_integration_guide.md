# Reassure Family — Emergency Contacts Integration Guide

This guide details how to integrate family emergency contacts and complete the mock/placeholder "Reassure Family" feature once the user creation and contact management system is implemented.

---

## Current Architecture

The "Reassure Family" screen is implemented inside [reassure_family_sheet.dart](file:///c:/Users/drago/Desktop/projects/Durrah%20care%20mob%20app/Flutter_Munawwara/lib/features/pilgrim/widgets/home_tab/reassure_family_sheet.dart) as a reusable premium bottom sheet. 

To make it fully interactive immediately, we have integrated a **mock simulation**:
- Tapping **"Send Status to All"** simulates a `1.2-second` secure network call.
- Renders a loading spinner.
- Displays a success toast: **"Reassurance sent! Primary contacts notified."**
- Closes the bottom sheet automatically.

---

## Placeholder / Callback Setup

We have exposed a clean hook at the entry point of the bottom sheet:

```dart
void showReassureFamilyBottomSheet({
  required BuildContext context,
  Future<void> Function()? onSendReassurance, // <-- API CALLBACK PLACEHOLDER
})
```

If `onSendReassurance` is not provided, the sheet falls back to the interactive simulation. This allows you to integrate the actual contact synchronization and messaging pipeline globally when ready.

---

## Future Integration Steps

Once you implement emergency contacts during user creation (e.g. stored in `user.emergencyContacts` or managed via a `ProfileProvider`), complete the integration by following these 3 simple steps:

### Step 1: Implement the API Trigger in a Controller or Provider
Create a method inside `PilgrimProvider` or `ProfileNotifier` that dispatches the safety message to the backend messaging pipeline.

```dart
Future<void> sendFamilyReassurance() async {
  final contacts = state.profile?.emergencyContacts;
  if (contacts == null || contacts.isEmpty) {
    throw Exception("No emergency contacts set up yet.");
  }
  
  // Call your API service
  await ApiService.post('/pilgrim/reassure', {
    "message": "Assalamu Alaykum, I am doing well and safe in Makkah. Alhamdulillah.",
    "contacts": contacts.map((c) => c.toJson()).toList(),
  });
}
```

### Step 2: Inject the API Call into the Grid Button Tap
Update `lib/features/pilgrim/widgets/home_tab/home_tab.dart` where the scooped card is tapped:

```dart
bottomRight: ScoopedGridCard(
  position: CardPosition.bottomRight,
  icon: _cardIcon(Icons.people_alt_rounded),
  title: 'Reassure Family',
  subtext: 'Share your safety',
  onTap: () {
    showReassureFamilyBottomSheet(
      context: context,
      onSendReassurance: () async {
        // Trigger actual provider call
        await ref.read(pilgrimProvider.notifier).sendFamilyReassurance();
      },
    );
  },
)
```

### Step 3: Inject the API Call into the Mini-bar Tap
Update `lib/features/pilgrim/widgets/sos/sos_help_session_panel.dart` where the mini service button is tapped:

```dart
_buildMiniServiceButton(
  icon: Icons.people_alt_rounded,
  label: 'Reassure',
  onTap: () {
    showReassureFamilyBottomSheet(
      context: context,
      onSendReassurance: () async {
        await ref.read(pilgrimProvider.notifier).sendFamilyReassurance();
      },
    );
  },
)
```

---

## SMS and Email Simultaneously
On the backend, your `/pilgrim/reassure` route should:
1. Fetch the user's primary emergency contacts.
2. Route an outgoing SMS via **Twilio** (or your selected SMS provider) to each phone number.
3. Dispatch an email template via **SendGrid** or **SMTP** to each email address.
4. Log the transaction to ensure auditability of reassurance broadcasts.
