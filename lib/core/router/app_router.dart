import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/one_time_login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/pilgrim/screens/pilgrim_dashboard_screen.dart';
import '../../features/moderator/screens/moderator_dashboard_screen.dart';

class AppRouter {
  /// Global navigator key — used by CallKit accept handler to push
  /// VoiceCallScreen immediately without waiting for a dashboard rebuild.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/login/one-time',
        name: 'one-time-login',
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'];
          return OneTimeLoginScreen(startWithQr: mode == 'qr');
        },
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/pilgrim-dashboard',
        name: 'pilgrim-dashboard',
        builder: (context, state) => const PilgrimDashboardScreen(),
      ),
      GoRoute(
        path: '/moderator-dashboard',
        name: 'moderator-dashboard',
        builder: (context, state) => const ModeratorDashboardScreen(),
      ),
    ],
  );
}
