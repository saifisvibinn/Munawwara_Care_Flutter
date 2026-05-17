import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/calling/calling_scope.dart';
import '../../features/calling/native_call_coordinator.dart';
import '../../features/moderator/services/sos_alert_coordinator.dart';
import '../router/app_router.dart';
import '../services/callkit_service.dart';
import '../services/incoming_chat_sfx.dart';
import '../services/notification_service.dart';
import '../services/tts_cloud_api.dart';
import '../theme/app_colors.dart';
import '../utils/app_logger.dart';
import '../widgets/reminder_popup.dart';

String? globalFcmToken;
bool _mobileMessagingBound = false;

Future<void> bindMobileMessagingServices() async {
  if (_mobileMessagingBound) return;

  await NotificationService.instance.ensureInitialized();
  AppLogger.i('Notification service initialized');

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
    SosAlertCoordinator.bindCancelListeners();

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      globalFcmToken = newToken;
      AppLogger.d('FCM token (refresh): $newToken');
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
          callControlType == 'call_cancel') {
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
          'FCM onMessage: suppressed (socket + in-app chat for urgent)',
        );
        return;
      }
      final fcmType = msg.data['type']?.toString() ?? '';
      if (fcmType == 'sos_alert_cancelled') {
        await SosAlertCoordinator.handleCancelledFromMap(
          Map<String, dynamic>.from(msg.data),
        );
        return;
      }
      if (notifType == 'sos_alert') {
        AppLogger.i(
          'FCM onMessage: SOS — in-app dialog (no duplicate local notif)',
        );
        await SosAlertCoordinator.showOnceFromMap(
          Map<String, dynamic>.from(msg.data),
        );
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
            ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: Text(body),
                backgroundColor: AppColors.primary,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 6),
              ),
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
  if (container != null && globalFcmToken != null) {
    final auth = container.read(authProvider);
    if (auth.isAuthenticated) {
      await container.read(authProvider.notifier).updateFcmToken(
            globalFcmToken!,
          );
    }
  }

  _mobileMessagingBound = true;
}
