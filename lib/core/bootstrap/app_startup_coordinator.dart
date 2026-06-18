import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/moderator/providers/moderator_provider.dart';
import '../../features/moderator/providers/moderator_sos_engagement_provider.dart';
import '../../features/pilgrim/providers/pilgrim_provider.dart';
import '../services/app_language_service.dart';
import '../services/callkit_service.dart';
import '../services/notification_service.dart';
import '../utils/app_logger.dart';
import 'app_startup.dart';
import 'mobile_messaging_bootstrap.dart';

/// Orchestrates cold-start work so [SplashScreen] stays visible until ready.
class AppStartupCoordinator {
  AppStartupCoordinator._();

  static Future<void>? _prepareInFlight;
  static bool _dashboardPrimed = false;

  /// True when splash already loaded dashboard data (dashboard skips spinner).
  static bool consumeDashboardPrimed() {
    final v = _dashboardPrimed;
    _dashboardPrimed = false;
    return v;
  }

  /// Runs auth, env, messaging, and (when logged in) remote dashboard load.
  static Future<void> prepareForNavigation(WidgetRef ref) {
    return _prepareInFlight ??= _prepareForNavigationImpl(ref);
  }

  static Future<void> _prepareForNavigationImpl(WidgetRef ref) async {
    final sw = Stopwatch()..start();
    AppLogger.i('[Startup] coordinator begin');

    await _waitForAuthRestore(ref);

    await Future.wait<void>([
      runDeferredStartupTasks(),
      CallKitService.cacheSupportDisplayNameFromBundle(),
    ]);

    var auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      await Future.wait<void>([
        ref.read(authProvider.notifier).waitForRemoteSessionValidation(),
        ref.read(authProvider.notifier).hydrateFromCache(),
        if (auth.role == 'moderator')
          ref.read(moderatorProvider.notifier).hydrateFromCache()
        else
          ref.read(pilgrimProvider.notifier).hydrateFromCache(),
      ]);

      auth = ref.read(authProvider);
      if (!auth.isAuthenticated) {
        AppLogger.i(
          '[Startup] coordinator done in ${sw.elapsedMilliseconds}ms '
          '(session cleared during validate)',
        );
        return;
      }

      if (auth.role == 'moderator') {
        await ref.read(moderatorProvider.notifier).loadDashboard();
        await ref.read(moderatorSosEngagementProvider.notifier).refresh();
        NotificationService.markModeratorDashboardReady();
      } else {
        final hasCached =
            ref.read(pilgrimProvider).profile != null ||
            ref.read(pilgrimProvider).groupInfo != null;
        await ref.read(pilgrimProvider.notifier).loadDashboard(
          silently: hasCached,
        );
      }

      _dashboardPrimed = true;
    }

    await bindMobileMessagingServices();

    auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      await AppLanguageService.syncToBackendIfNeeded(
        profileLanguage: auth.language,
      );
    }

    AppLogger.i('[Startup] coordinator done in ${sw.elapsedMilliseconds}ms');
  }

  static Future<void> _waitForAuthRestore(WidgetRef ref) async {
    const step = Duration(milliseconds: 50);
    const timeout = Duration(seconds: 8);
    final deadline = DateTime.now().add(timeout);

    while (ref.read(authProvider).isRestoringSession) {
      if (DateTime.now().isAfter(deadline)) {
        AppLogger.w('[Startup] auth restore timed out');
        break;
      }
      await Future.delayed(step);
    }
  }
}
