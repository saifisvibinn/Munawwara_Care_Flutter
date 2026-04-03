import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/providers/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:dio/dio.dart';
import 'core/env/env_check.dart';
import 'core/services/notification_service.dart';
import 'core/services/callkit_service.dart';
import 'core/router/app_router.dart' show AppRouter;
import 'features/auth/providers/auth_provider.dart';
import 'features/calling/providers/call_provider.dart';
import 'features/calling/screens/voice_call_screen.dart';
import 'core/utils/app_logger.dart';

// Global FCM token
String? _globalFcmToken;

// Global Riverpod container (set in main, used by CallKit listeners)
ProviderContainer? _globalContainer;

// Pending decline caller id set when native decline happens before provider
// is ready (cold-start race). Dashboard/provider consumes this later.
String? _pendingDeclinedCallerId;

// Guard: prevent pushing VoiceCallScreen more than once
bool _navigatingToCall = false;

/// Whether a VoiceCallScreen navigation is in progress.
/// Dashboards check this to avoid double-pushing.
bool get isNavigatingToCall => _navigatingToCall;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.d('main: after ensureInitialized');

  // Attach CallKit listener as early as possible. On cold start from native
  // accept action, event can fire very early and be missed if we subscribe
  // after other async initialization tasks.
  _setupCallKitListeners();

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

      // ── Handle Token Refresh ──────────────────────────────────────────────────
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _globalFcmToken = newToken;
        AppLogger.i('FCM token refreshed: $newToken');
      });

      // ── Handle Foreground Messages ──────────────────────────────────────────
      FirebaseMessaging.onMessage.listen((msg) async {
        AppLogger.i('FCM onMessage: ${msg.notification?.title} ${msg.data}');
        final notifType = msg.data['notification_type']?.toString() ?? '';
        final dataType = msg.data['type']?.toString() ?? '';
        final msgType = msg.data['messageType']?.toString() ?? '';
        final isUrgentTts =
            dataType == 'urgent' &&
            (msgType == 'tts' || msgType == 'reminder_tts');
        // ── call_declined / call_cancel arriving via FCM ────────────────────
        // When the pilgrim's app is killed and declines, the backend's 30-second
        // ring timeout fires and sends a silent FCM with type=call_declined
        // directly to the moderator. Handle it here to immediately stop ringing.
        if (dataType == 'call_declined' || dataType == 'call_cancel') {
          AppLogger.w(
            '📵 FCM call_declined/call_cancel received — stopping call',
          );
          if (_globalContainer != null) {
            final cs = _globalContainer!.read(callProvider);
            if (cs.status == CallStatus.calling ||
                cs.status == CallStatus.ringing) {
              _globalContainer!.read(callProvider.notifier).endCall();
            }
          }
          return;
        }
        // Skip system tray notification for message/meetpoint types when
        // the app is in foreground — the in-app popup overlay handles these.
        if ((notifType == 'new_message' || notifType == 'meetpoint') &&
            !isUrgentTts) {
          AppLogger.i('FCM onMessage: suppressed system notif (in-app popup)');
          return;
        }
        await NotificationService.instance.showNotificationFromMessage(msg);
        // ── Foreground TTS for urgent / reminder messages ─────────────────
        // showNotificationFromMessage plays the alert sound; after it finishes
        // we also speak the text so the pilgrim hears it even with screen on.
        if (isUrgentTts) {
          final text =
              msg.data['body']?.toString() ??
              msg.data['content']?.toString() ??
              '';
          if (text.isNotEmpty) {
            final isReminder = msgType == 'reminder_tts';
            final prefix = isReminder
                ? 'Incoming reminder.'
                : 'Urgent message.';
            AppLogger.i(
              '🔊 Foreground TTS (${isReminder ? "reminder" : "urgent"}): "$text"',
            );
            await Future.delayed(const Duration(milliseconds: 2200));
            await NotificationService.speakTts('$prefix $text');
          }
        }
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

  // Cold-start safeguard: if accept event fired before listener handling,
  // restore pending call context from persisted CallKit payload.
  await _recoverAcceptedCallOnStartup();

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

Future<void> _recoverAcceptedCallOnStartup() async {
  try {
    final activeCalls = await FlutterCallkitIncoming.activeCalls();
    if (activeCalls is List && activeCalls.isNotEmpty) {
      final pending = await CallKitService.readRecentPendingIncomingCall(
        maxAgeSeconds: 90,
      );
      if (pending != null && (pending['channelName'] ?? '').isNotEmpty) {
        _pendingAcceptedCall = {
          'callerId': pending['callerId'] ?? '',
          'callerName': (pending['callerName'] ?? '').isNotEmpty
              ? (pending['callerName'] ?? 'Unknown')
              : 'Unknown',
          'channelName': pending['channelName'] ?? '',
          'callerRole': pending['callerRole'] ?? '',
        };
        AppLogger.i(
          '📞 Startup recovery: restored pending accepted call from persisted CallKit payload',
        );
      }
    } else {
      // No active native call UI; this clears stale payloads when expired.
      await CallKitService.readRecentPendingIncomingCall(maxAgeSeconds: 90);
    }
  } catch (e) {
    AppLogger.e('📞 Startup recovery failed: $e');
  }
}

void _setupCallKitListeners() {
  FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
    if (event == null) return;
    AppLogger.i('📞 CallKit event: ${event.event}');

    final eventName = event.event.toString().toLowerCase();
    if (eventName.contains('start') && eventName.contains('call')) {
      AppLogger.i('✅ Call START event treated as ACCEPT');
      await _handleAcceptedCallEvent(event);
      return;
    }

    switch (event.event) {
      case Event.actionCallAccept:
        await _handleAcceptedCallEvent(event);
        break;

      case Event.actionCallDecline:
        AppLogger.w('❌ Call DECLINED from native call screen');
        final declineCallerId = await _resolveCallerIdFromEvent(event);
        _pendingAcceptedCall = null;
        await CallKitService.instance.clearLocalCallTracking();
        if (_globalContainer != null) {
          final currentState = _globalContainer!.read(callProvider);
          if (currentState.status == CallStatus.ringing) {
            _globalContainer!.read(callProvider.notifier).declineCall();
          } else {
            // Killed/background cold-start: provider state is idle (not ringing)
            // because socket never delivered the call-offer.
            if (declineCallerId.isNotEmpty) {
              AppLogger.w(
                '❌ Decline via HTTP fallback (cold-start, state=${currentState.status})',
              );
              _globalContainer!
                  .read(callProvider.notifier)
                  .declineCallFromCallerId(declineCallerId);
            }
          }
        } else if (declineCallerId.isNotEmpty) {
          _pendingDeclinedCallerId = declineCallerId;
          AppLogger.w(
            '❌ Decline queued (container not ready) for callerId=$declineCallerId',
          );
          _sendBackgroundDecline(declineCallerId);
        }
        break;

      case Event.actionCallTimeout:
        AppLogger.w('⏰ Call TIMEOUT from native call screen');
        final timeoutCallerId = await _resolveCallerIdFromEvent(event);
        _pendingAcceptedCall = null;
        await CallKitService.instance.clearLocalCallTracking();
        if (_globalContainer != null) {
          final currentState = _globalContainer!.read(callProvider);
          if (currentState.status == CallStatus.ringing) {
            _globalContainer!.read(callProvider.notifier).declineCall();
          } else {
            // Killed/background cold-start: same fallback as decline
            if (timeoutCallerId.isNotEmpty) {
              AppLogger.w(
                '⏰ Timeout via HTTP fallback (cold-start, state=${currentState.status})',
              );
              _globalContainer!
                  .read(callProvider.notifier)
                  .declineCallFromCallerId(timeoutCallerId);
            }
          }
        } else if (timeoutCallerId.isNotEmpty) {
          _pendingDeclinedCallerId = timeoutCallerId;
          AppLogger.w(
            '⏰ Timeout decline queued (container not ready) for callerId=$timeoutCallerId',
          );
          _sendBackgroundDecline(timeoutCallerId);
        }
        break;

      case Event.actionCallEnded:
        AppLogger.i('📵 Call ENDED from native call screen');
        final endedCallerId = await _resolveCallerIdFromEvent(event);
        if (endedCallerId.isNotEmpty && _globalContainer != null) {
          final currentState = _globalContainer!.read(callProvider);
          if (!currentState.isInCall) {
            // Some Android CallKit flows emit ENDED instead of DECLINE.
            _globalContainer!
                .read(callProvider.notifier)
                .declineCallFromCallerId(endedCallerId);
          }
        } else if (endedCallerId.isNotEmpty && _globalContainer == null) {
          _pendingDeclinedCallerId = endedCallerId;
          AppLogger.w(
            '📵 Ended mapped to queued decline (container not ready) for callerId=$endedCallerId',
          );
          _sendBackgroundDecline(endedCallerId);
        }
        _pendingAcceptedCall = null;
        await CallKitService.instance.clearLocalCallTracking();
        break;

      default:
        break;
    }
  });
}

/// Helper: sends HTTP decline request directly from the background isolate.
/// Avoids dotenv (unreliable outside the main isolate). Falls back to the
/// production Cloud Run URL so this always works even when app is killed.
Future<void> _sendBackgroundDecline(String callerId) async {
  if (callerId.isEmpty) return;
  const fallbackUrl =
      'https://mcbackendapp-199324116788.europe-west8.run.app/api';
  try {
    // Try to read a cached URL from SharedPreferences (written by ApiService),
    // otherwise use the hardcoded production URL.
    String baseUrl = fallbackUrl;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('api_base_url');
      if (cached != null && cached.isNotEmpty) baseUrl = cached;
    } catch (_) {}

    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    await dio.post('/call-history/decline', data: {'callerId': callerId});
    AppLogger.i('❌ Background HTTP decline sent to $callerId (url=$baseUrl)');
  } catch (e) {
    AppLogger.e('Failed to send background decline: $e');
  }
}

Future<String> _resolveCallerIdFromEvent(CallEvent event) async {
  final fromEvent = _extractCallEventValue(event, 'callerId');
  if (fromEvent.isNotEmpty) return fromEvent;

  final pending = await CallKitService.readRecentPendingIncomingCall(
    maxAgeSeconds: 120,
  );
  return pending?['callerId'] ?? '';
}

Future<void> _handleAcceptedCallEvent(CallEvent event) async {
  AppLogger.i('✅ Call ACCEPTED from native call screen');

  String channelName = _extractCallEventValue(event, 'channelName');
  String callerId = _extractCallEventValue(event, 'callerId');
  String callerName = _extractCallEventValue(event, 'callerName');
  String callerRole = _extractCallEventValue(event, 'callerRole');

  if (channelName.isEmpty || callerId.isEmpty) {
    final pending = await CallKitService.readRecentPendingIncomingCall(
      maxAgeSeconds: 90,
    );
    if (pending != null) {
      channelName = channelName.isNotEmpty
          ? channelName
          : (pending['channelName'] ?? '');
      callerId = callerId.isNotEmpty ? callerId : (pending['callerId'] ?? '');
      callerName = callerName.isNotEmpty
          ? callerName
          : (pending['callerName'] ?? '');
      callerRole = callerRole.isNotEmpty
          ? callerRole
          : (pending['callerRole'] ?? '');
      AppLogger.i('📞 Accept payload recovered from persisted pending call');
    }
  }

  _pendingAcceptedCall = {
    'callerId': callerId,
    'callerName': callerName.isNotEmpty ? callerName : 'Unknown',
    'channelName': channelName,
    'callerRole': callerRole,
  };

  AppLogger.i(
    '📞 Accept payload parsed: callerId=$callerId, channelName=$channelName, callerName=${callerName.isNotEmpty ? callerName : 'Unknown'}',
  );

  if (_globalContainer != null && channelName.isNotEmpty) {
    final notifier = _globalContainer!.read(callProvider.notifier);
    final currentState = _globalContainer!.read(callProvider);

    if (currentState.status == CallStatus.ringing) {
      _navigatingToCall = true;
      notifier.acceptCall();
      _navigateToVoiceCallScreen();
    } else if (!currentState.isInCall) {
      _navigatingToCall = true;
      notifier.acceptCallFromFcm(
        callerId: callerId,
        callerName: callerName.isNotEmpty ? callerName : 'Unknown',
        channelName: channelName,
      );
      _navigateToVoiceCallScreen();
    }
  }
}

String _extractCallEventValue(CallEvent event, String key) {
  final body = event.body;
  if (body is! Map) return '';

  dynamic value = body[key];

  if (value == null) {
    final extra = body['extra'];
    if (extra is Map) value = extra[key];
  }

  if (value == null) {
    final nestedBody = body['body'];
    if (nestedBody is Map) {
      value = nestedBody[key];
      if (value == null) {
        final nestedExtra = nestedBody['extra'];
        if (nestedExtra is Map) value = nestedExtra[key];
      }
    }
  }

  if (value == null) {
    final data = body['data'];
    if (data is Map) {
      value = data[key];
      if (value == null) {
        final dataExtra = data['extra'];
        if (dataExtra is Map) value = dataExtra[key];
      }
    }
  }

  return value?.toString() ?? '';
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

String? consumePendingDeclinedCallerId() {
  final callerId = _pendingDeclinedCallerId;
  _pendingDeclinedCallerId = null;
  return callerId;
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
