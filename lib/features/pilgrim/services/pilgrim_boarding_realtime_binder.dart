import 'dart:async';

import '../../../core/services/socket_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../auth/providers/auth_provider.dart';
import '../../calling/calling_scope.dart';
import '../providers/pilgrim_provider.dart';

/// Global socket binding for trip attendance on the pilgrim home tab.
///
/// Lives outside [PilgrimDashboardScreen] so `dispose()` cannot unregister
/// handlers pilgrims still need while logged in.
class PilgrimBoardingRealtimeBinder {
  PilgrimBoardingRealtimeBinder._();

  static bool _bound = false;

  /// Registers `bus_boarding_started` / `bus_boarding_ended` once at bootstrap.
  static void bindListeners() {
    if (_bound) return;
    _bound = true;

    SocketService.on('bus_boarding_started', _onBoardingStarted);
    SocketService.on('bus_boarding_ended', _onBoardingEnded);
    AppLogger.i('[PilgrimBoardingRealtimeBinder] boarding listeners bound');
  }

  static void _onBoardingStarted(dynamic data) {
    final container = CallingScope.riverpod;
    if (container == null) return;
    final auth = container.read(authProvider);
    if (auth.role != 'pilgrim') return;

    try {
      if (data is Map) {
        final map = Map<String, dynamic>.from(data);
        container
            .read(pilgrimProvider.notifier)
            .applyBoardingSessionStarted(map);
      }
    } catch (e) {
      AppLogger.e('[PilgrimBoardingRealtimeBinder] started handler error: $e');
    }

    unawaited(
      container.read(pilgrimProvider.notifier).loadDashboard(
            force: true,
            silently: true,
          ),
    );
  }

  static void _onBoardingEnded(dynamic _) {
    final container = CallingScope.riverpod;
    if (container == null) return;
    final auth = container.read(authProvider);
    if (auth.role != 'pilgrim') return;

    container.read(pilgrimProvider.notifier).clearActiveBoardingSession();
    unawaited(
      container.read(pilgrimProvider.notifier).loadDashboard(
            force: true,
            silently: true,
          ),
    );
  }
}
