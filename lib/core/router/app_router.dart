import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/api_service.dart';
import '../../features/splash/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
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
    redirect: (context, state) {
      const protected = {'/pilgrim-dashboard', '/moderator-dashboard'};
      if (!protected.contains(state.matchedLocation)) return null;
      // If no auth token is in Dio headers, the user is not logged in.
      final hasToken = ApiService.dio.options.headers.containsKey(
        'Authorization',
      );
      return hasToken ? null : '/login';
    },
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
