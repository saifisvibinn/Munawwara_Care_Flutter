import 'package:shared_preferences/shared_preferences.dart';

/// Pilgrim-side SOS resolve/cancel helpers (FCM fallback + UI hook).
abstract final class PilgrimSosCoordinator {
  static const _pendingModeratorResolvedKey =
      'pending_sos_moderator_resolved';

  /// Dashboard registers this to show the resolved card when FCM arrives.
  static void Function()? onModeratorResolvedUi;

  static Future<void> persistPendingModeratorResolved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pendingModeratorResolvedKey, true);
    } catch (_) {}
  }

  static Future<bool> consumePendingModeratorResolved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getBool(_pendingModeratorResolvedKey) ?? false;
      if (pending) {
        await prefs.remove(_pendingModeratorResolvedKey);
      }
      return pending;
    } catch (_) {
      return false;
    }
  }
}
