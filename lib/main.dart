import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'dart:ui';
import 'dart:isolate';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'core/env/env_check.dart';
import 'core/services/api_service.dart';
import 'core/services/notification_service.dart';
import 'features/moderator/services/sos_alert_coordinator.dart';
import 'core/router/app_router.dart' show AppRouter;
import 'features/auth/providers/auth_provider.dart';
import 'features/calling/calling_scope.dart';
import 'features/calling/native_call_coordinator.dart';
import 'core/utils/app_logger.dart';
import 'core/widgets/reminder_popup.dart';

// Global FCM token
String? _globalFcmToken;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  AppLogger.d('main: after ensureInitialized');

  // Attach CallKit listener as early as possible. On cold start from native
  // accept action, event can fire very early and be missed if we subscribe
  // after other async initialization tasks.
  NativeCallCoordinator.registerEarlyListeners();

  await Firebase.initializeApp();
  AppLogger.i('Firebase initialized');

  // ── Initialize Notification Service ───────────────────────────────────────
  await NotificationService.instance.initialize();
  AppLogger.i('Notification service initialized');

  // ── Set up Firebase Background Message Handler ────────────────────────────
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  AppLogger.i('Background message handler registered');

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

      // ── Give AuthNotifier a way to read the current token ──────────────────
      // This avoids a circular import (main ↔ auth_provider) while still
      // letting _restoreSession() and login() call updateFcmToken directly.
      AuthNotifier.setFcmTokenGetter(() => _globalFcmToken);

      // ── Handle Token Refresh ──────────────────────────────────────────────────
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _globalFcmToken = newToken;
        AppLogger.i('FCM token refreshed: $newToken');
        // Re-register immediately if user is already authenticated
        final c = CallingScope.riverpod;
        if (c != null) {
          final auth = c.read(authProvider);
          if (auth.isAuthenticated) {
            c.read(authProvider.notifier).updateFcmToken(newToken);
          }
        }
      });

      // ── Background Isolate Communication Port ───────────────────────────────
      // Used to receive triggers from the background isolate (e.g. for reminders)
      // when Android routes FCM messages to the background even if app is open.
      final ReceivePort port = ReceivePort();
      IsolateNameServer.removePortNameMapping('popup_port');
      IsolateNameServer.registerPortWithName(port.sendPort, 'popup_port');
      port.listen((dynamic data) {
        if (data is Map && data['type'] == 'reminder_popup') {
          AppLogger.i('🔔 Received popup trigger from background isolate');
          final ctx = AppRouter.navigatorKey.currentContext;
          if (ctx != null) {
            String schedTime = '';
            final rawTime = data['rawTime']?.toString() ?? '';
            if (rawTime.isNotEmpty) {
              try {
                final parsed = DateTime.parse(rawTime).toLocal();
                schedTime = 'reminder_popup_scheduled_for'.tr(
                  namedArgs: {'time': DateFormat('HH:mm').format(parsed)},
                );
              } catch (_) {}
            }
            if (schedTime.isEmpty) {
              schedTime = 'reminder_popup_scheduled_for'.tr(
                namedArgs: {'time': DateFormat('HH:mm').format(DateTime.now())},
              );
            }
            ReminderPopup.show(
              ctx,
              body: data['body']?.toString() ?? '',
              scheduledTime: schedTime,
            );
          } else {
            AppLogger.w('⚠️ No navigator context — cannot show reminder popup');
          }
        }
      });

      // ── Handle Foreground Messages ──────────────────────────────────────────
      FirebaseMessaging.onMessage.listen((msg) async {
        AppLogger.i('FCM onMessage: ${msg.notification?.title} ${msg.data}');
        final notifType = msg.data['notification_type']?.toString() ?? '';
        final dataType = msg.data['type']?.toString() ?? '';
        final msgType = msg.data['messageType']?.toString() ?? '';
        final isReminderTts = msgType == 'reminder_tts';
        final isUrgentTts =
            dataType == 'urgent' &&
            (msgType == 'tts' || msgType == 'reminder_tts');
        final messageKey =
            msg.data['message_id']?.toString() ??
            msg.messageId ??
            '';
        // ── call_declined / call_cancel arriving via FCM ────────────────────
        // When the pilgrim's app is killed and declines, the backend's 30-second
        // ring timeout fires and sends a silent FCM with type=call_declined
        // directly to the moderator. Handle it here to immediately stop ringing.
        if (dataType == 'call_declined' || dataType == 'call_cancel') {
          NativeCallCoordinator.handleForegroundCallControl(msg.data);
          return;
        }
        // Skip system tray notification for message/meetpoint types when
        // the app is in foreground — the in-app popup overlay handles these.
        if ((notifType == 'new_message' || notifType == 'meetpoint') &&
            !isUrgentTts) {
          AppLogger.i('FCM onMessage: suppressed system notif (in-app popup)');
          return;
        }
        // SOS: one tray notification from FCM when backgrounded; in foreground
        // show the in-app dialog only — do not stack a second local notification.
        if (notifType == 'sos_alert') {
          AppLogger.i(
            'FCM onMessage: SOS — in-app dialog (no duplicate local notif)',
          );
          await SosAlertCoordinator.showOnceFromMap(
            Map<String, dynamic>.from(msg.data),
          );
          return;
        }
        // Reminder (moderator default = data type "normal"): still show popup + optional TTS
        if (isReminderTts) {
          final text =
              msg.data['body']?.toString() ??
              msg.data['content']?.toString() ??
              msg.notification?.body ??
              '';
          if (text.isNotEmpty) {
            AppLogger.i('🔔 Foreground reminder TTS payload: "$text"');
            final ctx = AppRouter.navigatorKey.currentContext;
            if (ctx != null && ctx.mounted) {
              String schedTime = '';
              final rawTime =
                  msg.data['scheduledAt']?.toString() ??
                  msg.data['scheduled_time']?.toString() ??
                  '';
              if (rawTime.isNotEmpty) {
                try {
                  final parsed = DateTime.parse(rawTime).toLocal();
                  schedTime = 'reminder_popup_scheduled_for'.tr(
                    namedArgs: {'time': DateFormat('HH:mm').format(parsed)},
                  );
                } catch (_) {}
              }
              if (schedTime.isEmpty) {
                schedTime = 'reminder_popup_scheduled_for'.tr(
                  namedArgs: {
                    'time': DateFormat('HH:mm').format(DateTime.now()),
                  },
                );
              }
              ReminderPopup.show(ctx, body: text, scheduledTime: schedTime);
            } else {
              AppLogger.w(
                '⚠️ No navigator context — cannot show reminder popup',
              );
            }
            if (isUrgentTts) {
              // Keep ordering consistent with background: sound -> delay -> TTS.
              await NotificationService.instance.showNotificationFromMessage(msg);
              await Future.delayed(const Duration(milliseconds: 2200));
              await NotificationService.speakTts(
                'Incoming reminder. $text',
                audioUrl: msg.data['audio_url']?.toString(),
                lang: msg.data['lang']?.toString() ?? 'en',
                messageKey: messageKey.isEmpty ? null : messageKey,
              );
            }
          }
          return;
        }
        // Other urgent TTS (not reminder)
        if (isUrgentTts) {
          final text =
              msg.data['body']?.toString() ??
              msg.data['content']?.toString() ??
              '';
          if (text.isNotEmpty) {
            AppLogger.i('🔊 Foreground urgent TTS: "$text"');
            await NotificationService.instance.showNotificationFromMessage(msg);
            await Future.delayed(const Duration(milliseconds: 2200));
            await NotificationService.speakTts(
              'Urgent message. $text',
              audioUrl: msg.data['audio_url']?.toString(),
              lang: msg.data['lang']?.toString() ?? 'en',
              messageKey: messageKey.isEmpty ? null : messageKey,
            );
          }
          return; // we already showed a local notification above
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
  CallingScope.riverpod = container;

  // ── Register global unauthorized (401) handler ─────────────────────────────
  ApiService.setUnauthorizedCallback(() async {
    AppLogger.w('🛑 Unauthorized (401) detected — forcing logout');
    await container.read(authProvider.notifier).logout();
    AppRouter.router.go('/login');
  });

  // Cold-start safeguard: if accept event fired before listener handling,
  // restore pending call context from persisted CallKit payload.
  await NativeCallCoordinator.recoverAcceptedCallOnStartup();

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

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    // ── Register FCM Token when user logs in ──────────────────────────────────
    ref.listen<AuthState>(authProvider, (previous, next) {
      // Register FCM token whenever the user becomes authenticated:
      // 1. Fresh login (unauthenticated → authenticated)
      // 2. Session restore (isRestoringSession: true → authenticated)
      final wasRestoringOrUnauthenticated =
          previous == null ||
          previous.isRestoringSession ||
          !previous.isAuthenticated;
      if (next.isAuthenticated &&
          wasRestoringOrUnauthenticated &&
          _globalFcmToken != null) {
        ref.read(authProvider.notifier).updateFcmToken(_globalFcmToken!);
      }
    });

    return ScreenUtilInit(
      designSize: const Size(393, 852),
      minTextAdapt: true,
      ensureScreenSize: true,
      builder: (context, child) {
        final bool isDarkUi = switch (themeMode) {
          ThemeMode.dark => true,
          ThemeMode.light => false,
          ThemeMode.system =>
            View.of(context).platformDispatcher.platformBrightness ==
                Brightness.dark,
        };

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
          builder: (context, child) {
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: isDarkUi
                    ? Brightness.light
                    : Brightness.dark,
                statusBarBrightness: isDarkUi
                    ? Brightness.dark
                    : Brightness.light,
                systemNavigationBarColor: Colors.transparent,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarIconBrightness: isDarkUi
                    ? Brightness.light
                    : Brightness.dark,
                systemNavigationBarContrastEnforced: false,
              ),
              child: GestureDetector(
                onTap: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                },
                child: _HotReloadSosAlertSuppressor(child: child!),
              ),
            );
          },
        );
      },
    );
  }
}

/// Briefly suppresses moderator SOS in-app dialogs after hot reload so
/// duplicate socket/FCM deliveries or cleared dedupe state do not flash a false alert.
class _HotReloadSosAlertSuppressor extends StatefulWidget {
  const _HotReloadSosAlertSuppressor({required this.child});

  final Widget child;

  @override
  State<_HotReloadSosAlertSuppressor> createState() =>
      _HotReloadSosAlertSuppressorState();
}

class _HotReloadSosAlertSuppressorState
    extends State<_HotReloadSosAlertSuppressor> {
  @override
  void reassemble() {
    super.reassemble();
    if (!kReleaseMode) {
      SosAlertCoordinator.suppressInAppSosAlertsFor(const Duration(seconds: 3));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
