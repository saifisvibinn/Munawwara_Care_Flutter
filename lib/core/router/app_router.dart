import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/device_care_onboarding_screen.dart';

import '../../features/pilgrim/screens/pilgrim_dashboard_screen.dart';
import '../../features/moderator/screens/moderator_dashboard_screen.dart';

class AppRouter {
  /// Global navigator key — used by CallKit accept handler to push
  /// VoiceCallScreen immediately without waiting for a dashboard rebuild.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static final RouteObserver<ModalRoute<void>> moderatorRouteObserver =
      RouteObserver<ModalRoute<void>>();

  static final GoRouter router = GoRouter(
    navigatorKey: navigatorKey,
    observers: [moderatorRouteObserver],
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
        path: '/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/device-care-onboarding',
        name: 'device-care-onboarding',
        builder: (context, state) => const DeviceCareOnboardingScreen(),
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
