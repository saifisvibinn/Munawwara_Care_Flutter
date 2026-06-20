import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/calling/calling_scope.dart';
import '../../features/calling/native_call_coordinator.dart';
import '../../features/moderator/models/sos_moderator_payload.dart';
import '../../features/moderator/services/sos_alert_coordinator.dart';
import '../../features/pilgrim/services/pilgrim_boarding_realtime_binder.dart';
import '../../features/pilgrim/services/pilgrim_sos_coordinator.dart';
import '../../features/shared/helpers/message_visibility.dart';
import '../../features/shared/providers/message_provider.dart';
import '../../features/shared/services/message_realtime_binder.dart';
import '../router/app_router.dart';
import '../widgets/standard_snackbar.dart';
import '../utils/route_id_utils.dart';
import '../services/callkit_service.dart';
import '../services/incoming_chat_sfx.dart';
import '../services/notification_service.dart';
import '../services/tts_cloud_api.dart';
import '../utils/app_logger.dart';
import '../widgets/reminder_popup.dart';

String? globalFcmToken;
bool _mobileMessagingBound = false;
bool _iosVoipTokenBound = false;

const String kIosVoipPushTokenPrefsKey = 'ios_voip_push_token';

/// When chat FCM is suppressed in the foreground, still refresh chat if the
/// socket missed [new_message] (common after ghost-socket eviction).
Future<void> refreshChatFromFcmData(Map<String, dynamic> data) async {
  final notifType =
      data['notification_type']?.toString() ?? data['type']?.toString() ?? '';
  if (notifType != 'new_message' && notifType != 'meetpoint') return;

  final groupId = normalizeRouteId(data['group_id']?.toString() ?? '');
  if (groupId.isEmpty) return;

  final c = CallingScope.riverpod;
  if (c == null) return;

  final myId = c.read(authProvider).userId ?? '';
  final isModerator = c.read(authProvider).role?.toLowerCase() != 'pilgrim';
  if (!isRawMessageVisibleToUser(
    data,
    myId,
    isModerator: isModerator,
  )) {
    return;
  }

  AppLogger.i(
    '[FCM] Foreground chat refresh for group=$groupId (socket fallback)',
  );
  await c.read(messageProvider.notifier).loadMessages(groupId, force: true);
}

Future<void> bindMobileMessagingServices() async {
  if (_mobileMessagingBound) return;

  await NotificationService.instance.ensureInitialized();
  AppLogger.i('Notification service initialized');

  // Socket cancel must bind even when FCM setup fails (e.g. no Play Services).
  SosAlertCoordinator.bindCancelListeners();
  MessageRealtimeBinder.bindDeleteListener();
  PilgrimBoardingRealtimeBinder.bindListeners();

  final riverpod = CallingScope.riverpod;
  if (riverpod != null) {
    await riverpod
        .read(authProvider.notifier)
        .requestNotificationPermissionsForStartup();
  }

  if (!Platform.isAndroid && !Platform.isIOS) {
    _mobileMessagingBound = true;
    return;
  }

  try {
    globalFcmToken = await NotificationService.registerFcmTokenLifecycle();
    AppLogger.i('FCM token obtained');
    AppLogger.d('FCM token: $globalFcmToken');

    AuthNotifier.setFcmTokenGetter(() => globalFcmToken);

    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: false,
    );

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      globalFcmToken = newToken;
      AppLogger.d('FCM token (refresh): $newToken');
      final container = CallingScope.riverpod;
      if (container != null) {
        final auth = container.read(authProvider);
        if (auth.isAuthenticated) {
          unawaited(
            container.read(authProvider.notifier).updateFcmToken(newToken),
          );
        }
      }
    });

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
          IncomingChatSfx.playNormalPop();
        } else {
          AppLogger.w('⚠️ No navigator context — cannot show reminder popup');
        }
      }
    });

    FirebaseMessaging.onMessage.listen((msg) async {
      AppLogger.i('FCM onMessage: ${msg.notification?.title ?? '(no title)'}');
      AppLogger.d('FCM onMessage data: ${msg.data}');
      final notifType = msg.data['notification_type']?.toString() ?? '';
      final dataType = msg.data['type']?.toString() ?? '';
      final callControlType = CallKitService.fcmCallControlType(msg.data);
      if (callControlType == 'call_declined' ||
          callControlType == 'call_cancel' ||
          callControlType == 'call_ended' ||
          callControlType == 'call_answered') {
        NativeCallCoordinator.handleForegroundCallControl(msg.data);
        return;
      }
      if (CallKitService.isIncomingCallFcm(msg.data)) {
        await CallKitService.handleFcmMessage(msg);
        return;
      }
      final msgType = msg.data['messageType']?.toString().toLowerCase() ?? '';
      final isReminderTts = msgType == 'reminder_tts';
      final isUrgentTts =
          dataType == 'urgent' &&
          (msgType == 'tts' || msgType == 'reminder_tts');
      final messageKey =
          msg.data['message_id']?.toString() ?? msg.messageId ?? '';
      const chatMsgTypes = {'text', 'voice', 'image', 'tts', 'meetpoint'};
      final isChatNotif =
          notifType == 'new_message' || notifType == 'meetpoint';
      // Foreground: socket + ChatNotificationHelper already surface urgent chat
      // (voice, text, …). Suppress FCM-driven local notifications when the
      // server tags the payload as generic "urgent" or omits notification_type,
      // otherwise we duplicate (tray + in-app popup / alarm).
      // Urgent TTS / reminder_tts are excluded — they are handled below.
      final urgentChatNoNotifType =
          dataType == 'urgent' &&
          chatMsgTypes.contains(msgType) &&
          msgType != 'tts' &&
          msgType != 'reminder_tts' &&
          (notifType.isEmpty || notifType == 'urgent');
      if (isChatNotif || urgentChatNoNotifType) {
        AppLogger.i(
          'FCM onMessage: suppressed tray (socket primary; refresh fallback)',
        );
        unawaited(refreshChatFromFcmData(msg.data));
        return;
      }
      final fcmType = msg.data['type']?.toString() ?? '';
      if (fcmType == 'sos_alert_cancelled') {
        await SosAlertCoordinator.handleCancelledFromMap(
          Map<String, dynamic>.from(msg.data),
        );
        return;
      }
      if (PilgrimSosCoordinator.isModeratorResolvedPayload(msg.data)) {
        AppLogger.i('[FCM] sos_resolved — pilgrim help request closed');
        // Trigger UI while sosActive is still true; cancelSOS() runs inside
        // _applyModeratorResolvedUi on the dashboard.
        await PilgrimSosCoordinator.handleModeratorResolvedPush();
        return;
      }
      if (SosAlertCoordinator.isSosAlertPayload(msg.data)) {
        final sosData = Map<String, dynamic>.from(msg.data);
        AppLogger.i(
          'FCM onMessage: SOS — in-app dialog (no local tray in foreground)',
        );
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed) {
          final payload = SosModeratorPayload.fromMap(sosData);
          unawaited(
            NotificationService.dismissSosTrayFor(
              pilgrimId: payload.pilgrimId?.trim() ?? '',
              groupId: payload.groupId,
              sosId: payload.sosId,
            ),
          );
          await SosAlertCoordinator.presentForegroundFromPush(sosData);
        } else {
          await SosAlertCoordinator.queueSosAlertIfStillActive(sosData);
        }
        return;
      }
      if (notifType == 'missed_call') {
        unawaited(NotificationService.refreshAlertsFromFcm());
        await NotificationService.instance.showNotificationFromMessage(msg);
        return;
      }
      if (isReminderTts) {
        final text =
            msg.data['content']?.toString() ??
            msg.data['body']?.toString() ??
            msg.notification?.body ??
            '';
        if (text.isNotEmpty) {
          AppLogger.d('🔔 Foreground reminder TTS payload: "$text"');
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
            IncomingChatSfx.playNormalPop();
          } else {
            AppLogger.w(
              '⚠️ No navigator context — cannot show reminder popup',
            );
          }
          if (isUrgentTts) {
            await Future.delayed(kUrgentAlertToTtsDelay);
            final spoken = urgentTtsSpokenBackupText(msg, isReminder: true);
            final ctx = AppRouter.navigatorKey.currentContext;
            final lang = msg.data['lang']?.toString() ??
                (ctx != null && ctx.mounted
                    ? ctx.locale.languageCode
                    : null);
            final rid = msg.data['reminderId']?.toString() ?? '';
            await NotificationService.speakTtsCloud(
              spoken,
              audioUrl: msg.data['audio_url']?.toString(),
              lang: lang != null
                  ? TtsCloudApi.normalizeLang(lang)
                  : null,
              messageKey: rid.isNotEmpty
                  ? 'reminder_$rid'
                  : (messageKey.isEmpty ? null : messageKey),
            );
          }
        }
        return;
      }
      if (isUrgentTts) {
        final text =
            msg.data['content']?.toString() ??
            msg.data['body']?.toString() ??
            '';
        if (text.isNotEmpty) {
          AppLogger.d('🔊 Foreground urgent TTS: "$text"');
          await Future.delayed(kUrgentAlertToTtsDelay);
          final spoken = urgentTtsSpokenBackupText(msg, isReminder: false);
          final ctx = AppRouter.navigatorKey.currentContext;
          final lang = msg.data['lang']?.toString() ??
              (ctx != null && ctx.mounted ? ctx.locale.languageCode : null);
          await NotificationService.speakTtsCloud(
            spoken,
            audioUrl: msg.data['audio_url']?.toString(),
            lang: lang != null ? TtsCloudApi.normalizeLang(lang) : null,
            messageKey: messageKey.isEmpty ? null : messageKey,
          );
        }
        return;
      }

      if (notifType == 'meetpoint_deleted') {
        final body =
            msg.data['content']?.toString() ??
            msg.data['body']?.toString() ??
            '';
        if (body.isNotEmpty) {
          final ctx = AppRouter.navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            StandardSnackBar.showInfo(
              ctx,
              body,
              duration: const Duration(seconds: 6),
            );
          }
        }
        return;
      }

      await NotificationService.instance.showNotificationFromMessage(msg);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((msg) {
      AppLogger.i(
        'FCM onMessageOpenedApp: ${msg.notification?.title ?? '(no title)'}',
      );
      AppLogger.d('FCM onMessageOpenedApp data: ${msg.data}');
      NotificationService.navigateFromNotificationData(msg.data);
    });

    FirebaseMessaging.instance.getInitialMessage().then((msg) {
      if (msg != null) {
        AppLogger.i(
          'FCM getInitialMessage: ${msg.notification?.title ?? '(no title)'}',
        );
        AppLogger.d('FCM getInitialMessage data: ${msg.data}');
        NotificationService.navigateFromNotificationData(msg.data);
      }
    });
  } catch (e) {
    AppLogger.e(
      'FCM messaging initialization failed (likely missing Google Play Services): $e',
    );
  }

  await NativeCallCoordinator.recoverAcceptedCallOnStartup();

  final container = CallingScope.riverpod;
  if (container != null) {
    final auth = container.read(authProvider);
    if (auth.isAuthenticated) {
      await container.read(authProvider.notifier).ensureFcmTokenRegistered();
      await container.read(authProvider.notifier).ensureVoipTokenRegistered();
      await NotificationService.consumePendingAlertsRefetch();
    }
  }

  if (Platform.isIOS) {
    await bindIosVoipTokenLifecycle();
  }

  _mobileMessagingBound = true;
}

/// Caches the PushKit VoIP device token and uploads it to the backend via
/// `PUT /auth/voip-token` (kept separate from the FCM registration token).
/// The backend uses it to send APNs VoIP pushes for reliable backgrounded
/// incoming calls.
Future<void> bindIosVoipTokenLifecycle() async {
  if (_iosVoipTokenBound) return;
  _iosVoipTokenBound = true;

  Future<void> cacheVoipToken(String token) async {
    if (token.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kIosVoipPushTokenPrefsKey, token);
    AppLogger.i('iOS VoIP token cached locally');

    // Upload immediately when logged in; updateVoipToken de-dupes by token.
    final container = CallingScope.riverpod;
    if (container != null && container.read(authProvider).isAuthenticated) {
      await container.read(authProvider.notifier).updateVoipToken(token);
    }
  }

  FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
    if (event?.event != Event.actionDidUpdateDevicePushTokenVoip) return;
    final body = event?.body;
    if (body is! Map) return;
    final token = body['deviceTokenVoIP']?.toString() ?? '';
    await cacheVoipToken(token);
  });

  try {
    final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
    if (token is String) {
      await cacheVoipToken(token);
    }
  } catch (e) {
    AppLogger.w('iOS VoIP getDevicePushTokenVoIP failed: $e');
  }

  // PushKit registration can lag behind Dart startup on cold launch.
  unawaited(_pollIosVoipToken(cacheVoipToken));
}

Future<void> _pollIosVoipToken(Future<void> Function(String) cacheVoipToken) async {
  final deadline = DateTime.now().add(const Duration(seconds: 45));
  while (DateTime.now().isBefore(deadline)) {
    await Future.delayed(const Duration(seconds: 2));
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      if (token is String && token.isNotEmpty) {
        await cacheVoipToken(token);
        return;
      }
    } catch (_) {}
  }
  AppLogger.w('iOS VoIP token poll ended without a token');
}

