import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global Riverpod container for subsystems that must run before `runApp`
/// (CallKit stream, FCM foreground) or without widget context.
///
/// Set once from [main] after [ProviderContainer] construction.
class CallingScope {
  static ProviderContainer? riverpod;
}
