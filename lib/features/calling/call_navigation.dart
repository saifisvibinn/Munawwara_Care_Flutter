import 'package:flutter/material.dart';

import '../../core/router/app_router.dart';
import 'native_call_coordinator.dart' show isNavigatingToCall;
import 'screens/voice_call_screen.dart';

/// Opens [VoiceCallScreen] when no call UI is already on screen.
///
/// Returns the push [Future] when navigation starts, or `null` if skipped or
/// no [Navigator] is available.
Future<void>? openVoiceCallScreen({BuildContext? context, bool bypassNavigatingGuard = false}) {
  if (VoiceCallScreen.isActive || (isNavigatingToCall && !bypassNavigatingGuard)) {
    return null;
  }
  final NavigatorState? nav = context != null
      ? Navigator.maybeOf(context)
      : AppRouter.navigatorKey.currentState;
  if (nav == null) {
    return null;
  }
  return nav.push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const VoiceCallScreen(),
    ),
  );
}
