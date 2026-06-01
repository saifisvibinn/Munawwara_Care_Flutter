import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/device_care_onboarding_screen.dart';

import '../../features/pilgrim/screens/pilgrim_dashboard_screen.dart';
import '../../features/moderator/screens/moderator_dashboard_screen.dart';
import '../../features/legal/screens/privacy_policy_screen.dart';
import '../../features/legal/data/support_api.dart';
import '../../features/legal/screens/about_screen.dart';
import '../../features/legal/screens/contact_support_screen.dart';
import '../../features/legal/screens/faq_screen.dart';

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
      GoRoute(
        path: '/privacy-policy',
        name: 'privacy-policy',
        builder: (context, state) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: '/about',
        name: 'about',
        builder: (context, state) {
          final showDeletion = state.extra as bool? ?? true;
          return AboutScreen(showAccountDeletion: showDeletion);
        },
      ),
      GoRoute(
        path: '/faq',
        name: 'faq',
        builder: (context, state) => const FaqScreen(),
      ),
      GoRoute(
        path: '/contact-support',
        name: 'contact-support',
        builder: (context, state) => const ContactSupportScreen(),
      ),
      GoRoute(
        path: '/request-account-deletion',
        name: 'request-account-deletion',
        builder: (context, state) => const ContactSupportScreen(
          requestType: SupportRequestType.accountDeletion,
        ),
      ),
    ],
  );
}
