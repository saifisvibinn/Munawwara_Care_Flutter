import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';

import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/env/env_check.dart';
import 'core/services/notification_service.dart';
import 'core/services/api_service.dart';
import 'core/router/app_router.dart' show AppRouter;
import 'features/auth/providers/auth_provider.dart';
import 'features/calling/providers/call_provider.dart';
import 'features/calling/screens/voice_call_screen.dart';
import 'core/utils/app_logger.dart';

// Global FCM token
String? _globalFcmToken;

// Global Riverpod container (set in main, used by CallKit listeners)
ProviderContainer? _globalContainer;

// Guard: prevent pushing VoiceCallScreen more than once
bool _navigatingToCall = false;

/// Whether a VoiceCallScreen navigation is in progress.
/// Dashboards check this to avoid double-pushing.
bool get isNavigatingToCall => _navigatingToCall;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.d('main: after ensureInitialized');

  await Firebase.initializeApp();
  AppLogger.i('Firebase initialized');

  // ── Initialize Notification Service ───────────────────────────────────────
  await NotificationService.instance.initialize();
  AppLogger.i('Notification service initialized');

  // ── Set up Firebase Background Message Handler ────────────────────────────
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  AppLogger.i('Background message handler registered');

  // ── Listen for CallKit events (accept/decline/timeout) ────────────────────
  _setupCallKitListeners();

  // ── Request Notification Permissions ──────────────────────────────────────
  AppLogger.d('main: requesting fcm permission');
  if (Platform.isAndroid || Platform.isIOS) {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      // Request local notification permissions
      await NotificationService.instance.requestPermissions();
    } catch (e) {
      AppLogger.e('FCM permission request failed: $e');
    }

    try {
      // ── Get and Store FCM Token ───────────────────────────────────────────────
      _globalFcmToken = await FirebaseMessaging.instance.getToken();
      AppLogger.i('FCM token: $_globalFcmToken');

      // ── Handle Token Refresh ──────────────────────────────────────────────────
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _globalFcmToken = newToken;
        AppLogger.i('FCM token refreshed: $newToken');
      });

      // ── Handle Foreground Messages ──────────────────────────────────────────
      FirebaseMessaging.onMessage.listen((msg) async {
        AppLogger.i('FCM onMessage: ${msg.notification?.title} ${msg.data}');
        final notifType = msg.data['notification_type']?.toString() ?? '';
        // Skip system tray notification for message/meetpoint types when
        // the app is in foreground — the in-app popup overlay handles these.
        if (notifType == 'new_message' || notifType == 'meetpoint') {
          AppLogger.i('FCM onMessage: suppressed system notif (in-app popup)');
          return;
        }
        await NotificationService.instance.showNotificationFromMessage(msg);
      });

      // ── Handle Message Opened App ───────────────────────────────────────────
      FirebaseMessaging.onMessageOpenedApp.listen((msg) {
        AppLogger.i(
          'FCM onMessageOpenedApp: ${msg.notification?.title} ${msg.data}',
        );
        NotificationService.navigateFromNotificationData(msg.data);
      });

      // ── Handle Initial Message (App opened from terminated state) ──────────
      FirebaseMessaging.instance.getInitialMessage().then((msg) {
        if (msg != null) {
          AppLogger.i(
            'FCM getInitialMessage: ${msg.notification?.title} ${msg.data}',
          );
          NotificationService.navigateFromNotificationData(msg.data);
        }
      });
    } catch (e) {
      AppLogger.e(
        'FCM messaging initialization failed (likely missing Google Play Services): $e',
      );
    }
  }

  // Prevent GoogleFonts from making network requests at runtime.
  // Fonts are served from the local cache only — avoids ANR on emulators.
  GoogleFonts.config.allowRuntimeFetching = false;
  AppLogger.d('main: initializing EasyLocalization');
  await EasyLocalization.ensureInitialized();
  AppLogger.d('main: loading dotenv');
  await dotenv.load(fileName: '.env');
  AppLogger.d('main: verifying env');
  await verifyEnv();
  AppLogger.d('main: screenutil ensureScreenSize');
  await ScreenUtil.ensureScreenSize();

  final container = ProviderContainer();
  _globalContainer = container;

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en'),
        Locale('ar'),
        Locale('ur'),
        Locale('fr'),
        Locale('id'), // Bahasa
        Locale('tr'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: UncontrolledProviderScope(
        container: container,
        child: const MyApp(),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CallKit Event Listeners — handles accept/decline from native call screen
// ─────────────────────────────────────────────────────────────────────────────

void _setupCallKitListeners() {
  FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
    if (event == null) return;
    AppLogger.i('📞 CallKit event: ${event.event}');

    switch (event.event) {
      case Event.actionCallAccept:
        AppLogger.i('✅ Call ACCEPTED from native call screen');
        final extra = event.body?['extra'] as Map<dynamic, dynamic>? ?? {};
        final channelName = extra['channelName']?.toString() ?? '';
        final callerId = extra['callerId']?.toString() ?? '';
        final callerName = extra['callerName']?.toString() ?? 'Unknown';

        // Always store pending data first
        _pendingAcceptedCall = {
          'callerId': callerId,
          'callerName': callerName,
          'channelName': channelName,
          'callerRole': extra['callerRole']?.toString() ?? '',
        };

        // If provider is ready, accept the call right away and navigate
        // directly to VoiceCallScreen so the user never sees the dashboard.
        if (_globalContainer != null && channelName.isNotEmpty) {
          final notifier = _globalContainer!.read(callProvider.notifier);
          final currentState = _globalContainer!.read(callProvider);

          if (currentState.status == CallStatus.ringing) {
            // Set navigation guard BEFORE acceptCall() so that the
            // synchronous state change (ringing→connected) doesn't
            // trigger the dashboard's ref.listen to push a second screen.
            _navigatingToCall = true;
            notifier.acceptCall();
            _pendingAcceptedCall = null;
            _navigateToVoiceCallScreen();
          } else if (!currentState.isInCall) {
            _navigatingToCall = true;
            notifier.acceptCallFromFcm(
              callerId: callerId,
              callerName: callerName,
              channelName: channelName,
            );
            _pendingAcceptedCall = null;
            _navigateToVoiceCallScreen();
          }
          // Otherwise leave _pendingAcceptedCall for dashboard pickup
        }
        break;

      case Event.actionCallDecline:
        AppLogger.w('❌ Call DECLINED from native call screen');
        _pendingAcceptedCall = null;
        if (_globalContainer != null) {
          final currentState = _globalContainer!.read(callProvider);
          if (currentState.status == CallStatus.ringing) {
            _globalContainer!.read(callProvider.notifier).declineCall();
          } else {
            // Killed/background cold-start: provider state is idle (not ringing)
            // because socket never delivered the call-offer. Use HTTP fallback
            // to notify the caller directly.
            final extra = event.body?['extra'] as Map<dynamic, dynamic>? ?? {};
            final callerId = extra['callerId']?.toString() ?? '';
            if (callerId.isNotEmpty) {
              AppLogger.w('❌ Decline via HTTP fallback (cold-start, state=${currentState.status})');
              Dio()
                  .post(
                    '${ApiService.baseUrl}/call-history/decline',
                    data: {'callerId': callerId, 'declinerId': ''},
                  )
                  .then((_) => AppLogger.i('[Main] HTTP call-declined sent to $callerId'))
                  .catchError((e) => AppLogger.e('[Main] HTTP call-declined failed: $e'));
            }
          }
        }
        break;

      case Event.actionCallTimeout:
        AppLogger.w('⏰ Call TIMEOUT from native call screen');
        _pendingAcceptedCall = null;
        if (_globalContainer != null) {
          final currentState = _globalContainer!.read(callProvider);
          if (currentState.status == CallStatus.ringing) {
            _globalContainer!.read(callProvider.notifier).declineCall();
          } else {
            // Killed/background cold-start: same HTTP fallback as decline
            final extra = event.body?['extra'] as Map<dynamic, dynamic>? ?? {};
            final callerId = extra['callerId']?.toString() ?? '';
            if (callerId.isNotEmpty) {
              AppLogger.w('⏰ Timeout via HTTP fallback (cold-start, state=${currentState.status})');
              Dio()
                  .post(
                    '${ApiService.baseUrl}/call-history/decline',
                    data: {'callerId': callerId, 'declinerId': ''},
                  )
                  .then((_) => AppLogger.i('[Main] HTTP call-declined (timeout) sent to $callerId'))
                  .catchError((e) => AppLogger.e('[Main] HTTP call-declined (timeout) failed: $e'));
            }
          }
        }
        break;

      case Event.actionCallEnded:
        AppLogger.i('📵 Call ENDED from native call screen');
        _pendingAcceptedCall = null;
        break;

      default:
        break;
    }
  });
}

/// Push VoiceCallScreen via the global navigator key.
/// Retries until navigator is ready (handles cold-start + background resume).
/// Caller must set _navigatingToCall = true before calling this.
void _navigateToVoiceCallScreen() {
  // _navigatingToCall is already true (set by caller before acceptCall)
  _tryPushVoiceCall(attemptsLeft: 15);
}

void _tryPushVoiceCall({required int attemptsLeft}) {
  if (attemptsLeft <= 0) {
    _navigatingToCall = false;
    AppLogger.w(
      '📞 All navigation retries exhausted — relying on dashboard fallback',
    );
    return;
  }
  final nav = AppRouter.navigatorKey.currentState;
  if (nav != null) {
    if (VoiceCallScreen.isActive) {
      _navigatingToCall = false;
      AppLogger.d('📞 VoiceCallScreen already active — skipping push');
      return;
    }
    nav
        .push(MaterialPageRoute(builder: (_) => const VoiceCallScreen()))
        .then((_) => _navigatingToCall = false);
    AppLogger.i(
      '📞 Navigated to VoiceCallScreen (attempt ${16 - attemptsLeft})',
    );
  } else {
    // Navigator not ready yet — retry after 400ms
    Future.delayed(const Duration(milliseconds: 400), () {
      _tryPushVoiceCall(attemptsLeft: attemptsLeft - 1);
    });
  }
}

/// Pending call data set when user accepts from native call screen.
/// The call provider reads this to know which call to join.
Map<String, String>? _pendingAcceptedCall;

/// Get and clear the pending accepted call data.
Map<String, String>? consumePendingAcceptedCall() {
  final data = _pendingAcceptedCall;
  _pendingAcceptedCall = null;
  return data;
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    // ── Register FCM Token when user logs in ──────────────────────────────────
    ref.listen<AuthState>(authProvider, (previous, next) {
      // When user becomes authenticated and we have an FCM token, register it
      if (next.isAuthenticated && _globalFcmToken != null) {
        ref.read(authProvider.notifier).updateFcmToken(_globalFcmToken!);
      }
    });

    return ScreenUtilInit(
      designSize: const Size(393, 852),
      minTextAdapt: true,
      ensureScreenSize: true,
      builder: (context, child) {
        return MaterialApp.router(
          title: 'Munawwara Care',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          routerConfig: AppRouter.router,
        );
      },
    );
  }
}
