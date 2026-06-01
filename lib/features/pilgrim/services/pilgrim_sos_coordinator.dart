import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/providers/auth_provider.dart';
import '../../calling/calling_scope.dart';

/// Pilgrim-side SOS resolve/cancel helpers (FCM fallback + UI hook).
abstract final class PilgrimSosCoordinator {
  static const _pendingModeratorResolvedKey =
      'pending_sos_moderator_resolved';

  /// Dashboard registers this to show the resolved card when FCM arrives.
  static void Function()? onModeratorResolvedUi;

  static bool isModeratorResolvedPayload(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? '';
    final notificationType = data['notification_type']?.toString() ?? '';
    return type == 'sos_resolved' || notificationType == 'sos_resolved';
  }

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

  /// FCM / notification tap while app is alive — show resolved card or defer.
  static Future<void> handleModeratorResolvedPush() async {
    final role =
        CallingScope.riverpod?.read(authProvider).role?.toLowerCase() ?? '';
    if (role != 'pilgrim') return;

    final applyUi = onModeratorResolvedUi;
    if (applyUi != null) {
      applyUi();
      // Dashboard handled it — drop any stale flag so resume won't re-apply.
      await consumePendingModeratorResolved();
      return;
    }
    await persistPendingModeratorResolved();
  }

  /// After background FCM or cold start — apply if dashboard is mounted.
  static Future<void> applyPendingModeratorResolvedIfAny() async {
    if (!await consumePendingModeratorResolved()) return;
    onModeratorResolvedUi?.call();
  }
}
