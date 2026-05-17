import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../config/backend_config.dart';
import 'api_service.dart';
import 'callkit_service.dart';
import 'speech_service.dart';
import '../../core/utils/app_logger.dart';
import '../../core/router/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import '../../features/pilgrim/screens/group_inbox_screen.dart';
import '../../features/moderator/screens/group_messages_screen.dart';
import '../../features/moderator/services/sos_alert_coordinator.dart';
import '../../features/notifications/screens/alerts_tab_v2.dart';
import '../../features/calling/calling_scope.dart';
import '../../features/shared/providers/message_provider.dart';
import '../theme/app_colors.dart';
import '../utils/route_id_utils.dart';

/// Wait after the urgent notification sound before starting TTS (extra 2 s).
const Duration kUrgentAlertToTtsDelay = Duration(milliseconds: 4200);

// ─────────────────────────────────────────────────────────────────────────────
// Background Message Handler
// MUST be a top-level function (not in a class)
// ─────────────────────────────────────────────────────────────────────────────

// ── TTS Helper (top-level so it's available in background isolate) ────────────
//
// Logs engine + language availability so you can see in the console whether
// the device actually supports TTS.  No extra Android permission is needed —
// TTS uses the system engine (Google TTS / Samsung TTS etc.) which is
// pre-installed on virtually every device.  If a device has no engine or
// hasn't downloaded the English language pack, we log a clear warning.
//
@pragma('vm:entry-point')
Future<void> _speakWithTts(String text) async {
  final tts = FlutterTts();
  try {
    // ── 1. Check that at least one TTS engine is installed ───────────────────
    final rawEngines = await tts.getEngines;
    final engines = rawEngines is List
        ? List<String>.from(rawEngines)
        : <String>[];
    if (engines.isEmpty) {
      AppLogger.w(
        '🔇 TTS: NO engines found on this device — speech impossible.\n'
        '   Ask the user to install Google Text-to-Speech from the Play Store.',
      );
      return;
    }
    AppLogger.i('🔊 TTS engines installed: $engines');

    // ── 2. Check language availability ────────────────────────────────────────
    final langResult = await tts.isLanguageAvailable('en-US');
    final langOk = langResult == 1 || langResult == true;
    AppLogger.i('🔊 TTS en-US available: $langResult (ok=$langOk)');

    if (langOk) {
      await tts.setLanguage('en-US');
    } else {
      final enResult = await tts.isLanguageAvailable('en');
      final enOk = enResult == 1 || enResult == true;
      AppLogger.w('🔊 TTS en available: $enResult (ok=$enOk)');
      if (!enOk) {
        AppLogger.w(
          '🔇 TTS: English language data NOT downloaded on this device.\n'
          '   User should go to Settings → General → Text-to-Speech and download English.',
        );
        return;
      }
      await tts.setLanguage('en');
    }

    // ── 3. Configure and speak ─────────────────────────────────────────────────
    await tts.awaitSpeakCompletion(true);
    await tts.setVolume(1.0);
    await tts.setSpeechRate(0.4);
    await tts.setPitch(1.0);

    AppLogger.i('🔊 TTS speaking: "$text"');
    final result = await tts.speak(text);
    AppLogger.i('🔊 TTS speak result: $result');
  } catch (e, st) {
    AppLogger.e('🔇 TTS error: $e\n$st');
  }
}

/// Sends a decline HTTP request directly from the background isolate.
/// No Riverpod, no dotenv — uses SharedPreferences for URL, falls back
/// to the hardcoded production URL.
@pragma('vm:entry-point')
Future<void> _sendDeclineHttp(
  String callerId, {
  bool noAnswer = false,
}) async {
  try {
    String baseUrl = kDefaultProductionApiBaseUrl;
    String declinerId = '';
    String callRecordId = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('api_base_url');
      if (cached != null && cached.isNotEmpty) baseUrl = cached;
      if (callerId.isEmpty) {
        callerId = prefs.getString('pending_call_caller_id') ?? '';
      }
      declinerId = prefs.getString('user_id') ?? '';
      callRecordId = prefs.getString('pending_call_record_id') ?? '';
    } catch (_) {}
    if (callerId.isEmpty && callRecordId.isEmpty) return;
    final uri = Uri.parse('$baseUrl/call-history/decline');
    final client = HttpClient();
    final body = <String, dynamic>{
      'callerId': callerId,
      if (declinerId.isNotEmpty) 'declinerId': declinerId,
      if (callRecordId.isNotEmpty) 'callRecordId': callRecordId,
      if (noAnswer) 'noAnswer': true,
    };
    final req = await client.postUrl(uri)
      ..headers.set('Content-Type', 'application/json')
      ..write(jsonEncode(body));
    final resp = await req.close();
    await resp.drain<void>();
    AppLogger.i('❌ [BG] HTTP decline sent for $callerId → ${resp.statusCode}');
    client.close();
  } catch (e) {
    AppLogger.e('❌ [BG] Failed to send HTTP decline: $e');
  }
}

/// Full translated TTS string from FCM, with English prefix only when needed.
String urgentTtsSpokenBackupText(
  RemoteMessage message, {
  required bool isReminder,
}) {
  final lang = message.data['lang']?.toString().toLowerCase() ?? 'en';
  final content = message.data['content']?.toString() ?? '';
  final body = message.data['body']?.toString() ?? '';
  final text = content.isNotEmpty ? content : body;
  if (text.isEmpty) return '';
  final prefix = isReminder ? 'Incoming reminder.' : 'Urgent message.';
  final useEnglishPrefix = lang == 'en' && content.isEmpty;
  return useEnglishPrefix ? '$prefix $text' : text;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  AppLogger.i('📩 Background message received: ${message.messageId}');
  AppLogger.i('   Title: ${message.notification?.title}');
  AppLogger.i('   Body: ${message.notification?.body}');
  AppLogger.i('   Data: ${message.data}');

  // ── Incoming call → show native call screen (like WhatsApp) ─────────────
  final callControlType = CallKitService.fcmCallControlType(message.data);
  final handled = await CallKitService.handleFcmMessage(message);
  if (handled) {
    if (callControlType == 'call_cancel' ||
        callControlType == 'call_declined') {
      return;
    }
    // ── CRITICAL: Keep this isolate alive while the call is ringing ─────────
    // The background isolate lives only as long as this function is awaited.
    // If we return immediately, the isolate is killed and no CallKit event
    // can ever be received. We use a Completer to block until the user acts
    // or 32 s elapse (matching the 30 s CallKit ring + a small buffer).
    final completer = Completer<void>();
    late StreamSubscription<CallEvent?> sub;
    sub = FlutterCallkitIncoming.onEvent.listen((CallEvent? event) async {
      if (event == null) return;
      AppLogger.i('📞 [BG isolate] CallKit event: ${event.event}');
      final eventName = event.event.toString().toLowerCase();
      final isDecline =
          eventName.contains('decline') ||
          eventName.contains('timeout') ||
          (eventName.contains('end') && !eventName.contains('ended_call'));
      final isAccept =
          eventName.contains('accept') ||
          (eventName.contains('start') && eventName.contains('call'));
      if (isDecline) {
        String callerId = '';
        var noAnswer = eventName.contains('timeout');
        try {
          final body = event.body;
          if (body is Map) {
            callerId = (body['extra']?['callerId'] ?? body['callerId'] ?? '')
                .toString();
          }
        } catch (_) {}
        if (callerId.isEmpty) {
          try {
            final prefs = await SharedPreferences.getInstance();
            callerId = prefs.getString('pending_call_caller_id') ?? '';
          } catch (_) {}
        }
        AppLogger.w('❌ [BG isolate] Decline — callerId=$callerId');
        await _sendDeclineHttp(callerId, noAnswer: noAnswer);
        try {
          await CallKitService.instance.endCurrentCall();
        } catch (e) {
          AppLogger.w('📞 [BG isolate] endCurrentCall after decline: $e');
        }
        await sub.cancel();
        if (!completer.isCompleted) completer.complete();
      } else if (isAccept) {
        // Accept handled by main isolate on cold-start; just unblock.
        AppLogger.i('✅ [BG isolate] Accept — releasing isolate');
        try {
          await CallKitService.hideIncomingTrayFromPersistedUuidOnly();
        } catch (_) {}
        await sub.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    // Safety: unblock after 32 s regardless, let server ring-timeout handle it.
    Future.delayed(const Duration(seconds: 32), () {
      sub.cancel();
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future; // keeps background isolate alive
    return;
  }

  // ── If the FCM payload contains a 'notification' block, Android already
  //    showed a system notification automatically — skip showing another one
  //    to avoid duplicates. We only create a local notification for
  //    data-only messages (urgent TTS, etc.) that Android won't display.
  if (message.notification != null) {
    // Standard FCM still delivers to this handler on some devices. If the main
    // isolate is alive, show the in-app reminder card (tray may be enough,
    // but pilgrims expect the same popup as foreground onMessage).
    final msgTypeEarly = message.data['messageType']?.toString() ?? '';
    if (msgTypeEarly == 'reminder_tts') {
      final sendPort = IsolateNameServer.lookupPortByName('popup_port');
      if (sendPort != null) {
        final text =
            message.data['body']?.toString() ??
            message.data['content']?.toString() ??
            message.notification?.body ??
            '';
        if (text.isNotEmpty) {
          sendPort.send({
            'type': 'reminder_popup',
            'body': text,
            'rawTime':
                message.data['scheduledAt']?.toString() ??
                message.data['scheduled_time']?.toString() ??
                '',
          });
        }
      }
    }
    AppLogger.i('📩 Notification block present — Android already displayed it');
    return;
  }

  // ── SECONDARY GUARD: On some Samsung / Android 12 devices the background
  //    isolate receives message.notification as null even though the backend
  //    sent a notification block. The backend only omits the notification
  //    block for 'incoming_call' and urgent-TTS (data['messageType']=='tts').
  //    So if type is 'normal' or 'urgent' (and NOT urgent-TTS), Android
  //    already showed the notification — skip to avoid duplicates.
  final dataType = message.data['type']?.toString() ?? '';
  final msgType = message.data['messageType']?.toString() ?? '';
  final isDataOnly =
      dataType == 'incoming_call' ||
      (dataType == 'urgent' && (msgType == 'tts' || msgType == 'reminder_tts'));
  if (!isDataOnly) {
    AppLogger.i(
      '📩 Standard FCM (type=$dataType) — Android likely showed it, skipping local notif',
    );
    return;
  }

  // ── Data-only messages → show local notification ────────────────────────
  await NotificationService.instance.initialize();

  // ── Urgent TTS / Reminder TTS → show notification then speak ──────────────
  if (dataType == 'urgent' && (msgType == 'tts' || msgType == 'reminder_tts')) {
    final isReminder = msgType == 'reminder_tts';
    var text = urgentTtsSpokenBackupText(message, isReminder: isReminder);
    final audioUrl = message.data['audio_url']?.toString();
    final lang = message.data['lang']?.toString() ?? 'en';
    final messageKey =
        message.data['message_id']?.toString() ??
        message.messageId ??
        '';
    if (text.isEmpty &&
        isReminder &&
        (message.notification?.body ?? '').isNotEmpty) {
      text = message.notification!.body!;
    }
    AppLogger.i(
      '🔊 ${isReminder ? 'Reminder' : 'Urgent'} TTS [background]: "$text" '
      '(audioUrl=${audioUrl != null ? 'present' : 'null'}, lang=$lang)',
    );

    // 1. Show notification — the urgent channel plays urgent_tts.wav as sound
    await NotificationService.instance.showNotificationFromMessage(message);

    // Reminder TTS only: main isolate may show ReminderPopup. Urgent broadcast
    // TTS must not use that UI (wrong "reminder" title); tray + TTS suffice.
    final sendPort = IsolateNameServer.lookupPortByName('popup_port');
    if (sendPort != null && isReminder) {
      AppLogger.i('🔔 Main isolate is alive — sending reminder popup trigger');
      sendPort.send({
        'type': 'reminder_popup',
        'body': text,
        'rawTime':
            message.data['scheduledAt']?.toString() ??
            message.data['scheduled_time']?.toString() ??
            '',
      });
    }

    if (text.isNotEmpty) {
      // 2. Wait for the alert sound to finish before TTS begins.
      await Future.delayed(kUrgentAlertToTtsDelay);

      // 3. Play cloud audio (with local TTS fallback) once.
      await SpeechService.playRobust(
        audioUrl: audioUrl,
        backupText: text,
        lang: lang,
        isUrgent: true,
        messageKey: messageKey.isEmpty ? null : messageKey,
      );
    }
    return; // notification already shown above, skip the call below
  }

  await NotificationService.instance.showNotificationFromMessage(message);
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification Service
// Handles local notifications, channels, sounds, and incoming call alerts
// ─────────────────────────────────────────────────────────────────────────────

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  static bool _fcmRefreshBound = false;

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Future<void>? _initializationFuture;

  /// Registers FCM token refresh listener and uploads the current token.
  /// Returns the initial token when available (Android/iOS only).
  static Future<String?> registerFcmTokenLifecycle() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }
    if (!_fcmRefreshBound) {
      _fcmRefreshBound = true;
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        unawaited(_uploadFcmToken(newToken));
      });
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) {
      await _uploadFcmToken(token);
    }
    return token;
  }

  static Future<void> _uploadFcmToken(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastRegistered = prefs.getString('last_registered_fcm_token');
      if (lastRegistered == token) {
        return;
      }
      await ApiService.dio.put(
        '/auth/fcm-token',
        data: {'fcm_token': token},
      );
      await prefs.setString('last_registered_fcm_token', token);
      AppLogger.i('[NotificationService] FCM token refreshed and uploaded');
    } catch (e) {
      AppLogger.e('[NotificationService] FCM token upload failed: $e');
    }
  }

  Future<void> ensureInitialized() {
    return _initializationFuture ??= initialize();
  }

  // ── Initialize ─────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }

    _initialized = true;
    AppLogger.i('✅ NotificationService initialized');
  }

  // ── Create Android Notification Channels ──────────────────────────────────

  Future<void> _createNotificationChannels() async {
    final androidPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin == null) return;

    // ── Delete legacy channels so Android creates fresh ones with correct sounds
    // Android caches channel sound on first creation and never updates it.
    for (final oldId in [
      'default',
      'urgent',
      'calls',
      'mc_default',
      'mc_urgent',
      'mc_calls',
    ]) {
      await androidPlugin.deleteNotificationChannel(oldId);
    }

    // Default channel for regular messages — uses custom notification sound
    final defaultChannel = AndroidNotificationChannel(
      'mc_default_v2',
      'Default Notifications',
      description: 'General notifications for messages and updates',
      importance: Importance.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('background_app'),
      enableVibration: true,
    );
    // Urgent channel with custom sound
    final urgentChannel = AndroidNotificationChannel(
      'mc_urgent_v2',
      'Urgent Notifications',
      description: 'High-priority urgent messages and alerts',
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('urgent_tts'),
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xFFF97316), // AppColors.primary
    );

    // Call channel with full-screen intent
    final callChannel = AndroidNotificationChannel(
      'mc_calls_v2',
      'Incoming Calls',
      description: 'Incoming voice calls',
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('urgent_tts'),
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xFF10B981),
    );

    await androidPlugin.createNotificationChannel(defaultChannel);
    await androidPlugin.createNotificationChannel(urgentChannel);
    await androidPlugin.createNotificationChannel(callChannel);

    AppLogger.i('✅ Notification channels created (v2)');
  }

  // ── Show Notification from FCM Message ────────────────────────────────────

  Future<void> showNotificationFromMessage(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    final type = data['type'] ?? 'normal';
    final notificationType =
        data['notification_type']?.toString() ?? data['type']?.toString() ?? '';

    // Determine title and body
    String title = notification?.title ?? data['title'] ?? 'Munawwara Care';
    String body = notification?.body ?? data['body'] ?? '';

    AppLogger.d('🔔 Processing FCM message:');
    AppLogger.d('   Type: $type');
    AppLogger.d('   Title: $title');
    AppLogger.d('   Body: $body');
    AppLogger.d('   Has notification block: ${notification != null}');
    AppLogger.d('   Data keys: ${data.keys.toList()}');

    // Skip notifications with no meaningful content
    if (body.isEmpty && (title == 'Munawwara Care' || title.isEmpty)) {
      AppLogger.w('🔔 Skipping empty notification (no title/body)');
      return;
    }

    // Handle call-control notifications (incoming/cancel) via CallKit service
    if (type == 'incoming_call' || type == 'call_cancel') {
      AppLogger.i('📞 CALL CONTROL message detected (type=$type)');
      await CallKitService.handleFcmMessage(message);
      return;
    }

    // SOS claimed by another moderator:
    // - Update in-app UI state (in case socket event was missed)
    // - Do not show a foreground local notification (prevents spam)
    if (notificationType == 'sos_claimed') {
      unawaited(
        SosAlertCoordinator.applyClaimedStatusFromMap(
          Map<String, dynamic>.from(data),
        ),
      );
      return;
    }

    // Missed-call notifications are sent as standard FCM (with a notification
    // block). In background/killed state Android auto-displays them — the
    // background handler already returned early above, so we never reach here.
    // In foreground, onMessage delivers it here and we show it once via the
    // default path below. No extra guard needed — fall through is correct.
    // We only skip if the FCM already had a notification block AND we are
    // NOT in foreground (which is guaranteed: onMessage only fires in foreground).
    if (type == 'missed_call') {
      final callerId = data['callerId']?.toString() ?? '';
      if (callerId.isNotEmpty) {
        final pending = await CallKitService.readRecentPendingIncomingCall(
          maxAgeSeconds: 120,
        );
        if (pending != null && pending['callerId'] == callerId) {
          AppLogger.i(
            '📞 missed_call while incoming ring — treating as remote cancel',
          );
          await CallKitService.handleFcmMessage(
            RemoteMessage(
              data: {'type': 'call_cancel', 'callerId': callerId},
            ),
          );
          return;
        }
      }
      if (notification != null) {
        AppLogger.i(
          '📬 missed_call in foreground — showing single local notification',
        );
        await _showDefaultNotification(title: title, body: body, data: data);
      }
      return;
    }

    // Handle urgent notifications
    if (type == 'urgent') {
      AppLogger.w('🚨 Urgent notification detected');
      await showUrgentNotification(title: title, body: body, data: data);
      return;
    }

    // Default notification
    AppLogger.i('📬 Default notification');
    await _showDefaultNotification(title: title, body: body, data: data);
  }

  // (Incoming call notifications are now handled by CallKitService)

  // ── Show Urgent Notification ──────────────────────────────────────────────

  Future<void> showUrgentNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    AppLogger.w('🚨 Showing urgent notification');

    final androidDetails = AndroidNotificationDetails(
      'mc_urgent_v2',
      'Urgent Notifications',
      channelDescription: 'High-priority urgent messages and alerts',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('urgent_tts'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 250, 500]),
      enableLights: true,
      color: const Color(0xFFF97316),
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(body),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'urgent_tts.wav',
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: _encodePayload(data),
    );
  }

  // ── Show Default Notification ─────────────────────────────────────────────

  Future<void> _showDefaultNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    AppLogger.i('📬 Showing default notification');

    final androidDetails = AndroidNotificationDetails(
      'mc_default_v2',
      'Default Notifications',
      channelDescription: 'General notifications for messages and updates',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('background_app'),
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(body),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: _encodePayload(data),
    );
  }

  // (Ringtone is now handled by flutter_callkit_incoming native call screen)

  // ── Cancel Notification ────────────────────────────────────────────────────

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
  }

  // ── TTS (public, usable from foreground context) ───────────────────────────

  /// Play [text] aloud using the hybrid SpeechService.
  /// Optionally supply [audioUrl] (GCS MP3) to attempt cloud playback first;
  /// falls back to local flutter_tts on timeout or failure.
  static Future<void> speakTts(
    String text, {
    String? audioUrl,
    String lang = 'en',
    String? messageKey,
  }) =>
      SpeechService.playRobust(
        audioUrl: audioUrl,
        backupText: text,
        lang: lang,
        messageKey: messageKey,
      );

  // ── Notification Tap Handler ──────────────────────────────────────────────

  void _onNotificationTap(NotificationResponse response) {
    AppLogger.i('📱 Notification tapped: ${response.payload}');

    if (response.actionId == 'accept_call') {
      AppLogger.i('✅ Accept call action');
      return;
    } else if (response.actionId == 'decline_call') {
      AppLogger.i('❌ Decline call action');
      return;
    }

    // Parse the payload and navigate accordingly
    final data = _decodePayload(response.payload);
    navigateFromNotificationData(data);
  }

  // ── Navigate from notification data ───────────────────────────────────────

  /// Called when a notification is tapped (local or FCM).
  /// Routes to the appropriate screen based on notification data.
  static void navigateFromNotificationData(Map<String, dynamic> data) {
    final notificationType =
        data['notification_type']?.toString() ?? data['type']?.toString() ?? '';
    final groupId = normalizeRouteId(data['group_id']?.toString() ?? '');
    final groupName = data['group_name']?.toString() ?? '';

    final messageType = data['messageType']?.toString() ?? '';

    AppLogger.i(
      '📱 Navigating from notification: type=$notificationType, '
      'messageType=$messageType, groupId=$groupId, groupName=$groupName',
    );

    final isReminderTap =
        notificationType == 'reminder' ||
        messageType == 'reminder_tts' ||
        (notificationType == 'urgent' && messageType == 'reminder_tts');
    if (isReminderTap) {
      _navigateToAlertsInbox();
      return;
    }

    if (notificationType == 'sos_alert') {
      queuePendingSosAlert(data);
      return;
    }

    // SOS claimed by another moderator — no navigation (tray notification update).
    if (notificationType == 'sos_claimed') {
      return;
    }

    if (notificationType == 'new_message' && groupId.isNotEmpty) {
      _navigateToChat(groupId: groupId, groupName: groupName);
    } else if (notificationType == 'meetpoint' && groupId.isNotEmpty) {
      _navigateToChat(groupId: groupId, groupName: groupName);
    }
  }

  /// Pending notification data when navigator isn't ready yet (cold start).
  static Map<String, dynamic>? _pendingNotificationData;

  /// SOS from notification tap — shown only after moderator dashboard load.
  static Map<String, dynamic>? _pendingSosAlertData;
  static bool _moderatorDashboardReady = false;

  static bool get hasPendingSosAlert => _pendingSosAlertData != null;

  /// Queue SOS until [markModeratorDashboardReady] / dashboard bootstrap completes.
  static void queuePendingSosAlert(Map<String, dynamic> data) {
    _pendingSosAlertData = Map<String, dynamic>.from(data);
    _pendingSosAlertData!['notification_type'] = 'sos_alert';
    AppLogger.w(
      '[NotificationService] SOS alert queued '
      '(dashboardReady=$_moderatorDashboardReady)',
    );
    _tryShowPendingSos();
  }

  static void markModeratorDashboardReady() {
    _moderatorDashboardReady = true;
    AppLogger.w('[NotificationService] Moderator dashboard ready');
    _tryShowPendingSos();
  }

  static void markModeratorDashboardNotReady() {
    _moderatorDashboardReady = false;
  }

  /// Try to display a queued SOS dialog (no-op until dashboard is ready).
  static void showPendingSosAlertIfAny() {
    _tryShowPendingSos();
  }

  static void _tryShowPendingSos() {
    if (!_moderatorDashboardReady || _pendingSosAlertData == null) {
      return;
    }
    final data = _pendingSosAlertData!;
    _pendingSosAlertData = null;
    AppLogger.w('[NotificationService] Showing queued SOS alert dialog');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(SosAlertCoordinator.showOnceFromMap(data));
    });
  }

  /// Consume and clear any pending notification data.
  static Map<String, dynamic>? consumePendingNotificationData() {
    final data = _pendingNotificationData;
    _pendingNotificationData = null;
    return data;
  }

  static void _navigateToChat({
    required String groupId,
    required String groupName,
  }) {
    final nav = AppRouter.navigatorKey.currentState;
    if (nav == null) {
      // Navigator not ready — store for later (cold-start scenario)
      AppLogger.w('📱 Navigator not ready — storing pending message nav');
      _pendingNotificationData = {
        'notification_type': 'new_message',
        'group_id': groupId,
        'group_name': groupName,
      };
      return;
    }

    final container = CallingScope.riverpod;
    if (container != null) {
      final notifier = container.read(messageProvider.notifier);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifier.setActiveGroup(groupId);
        unawaited(notifier.loadMessages(groupId));
      });
    }

    nav.push(
      MaterialPageRoute(
        builder: (_) =>
            _ChatRouteResolver(groupId: groupId, groupName: groupName),
      ),
    );
  }

  /// Full-screen alerts list (reminder / in-app notification taps).
  static void _navigateToAlertsInbox() {
    final nav = AppRouter.navigatorKey.currentState;
    if (nav == null) {
      AppLogger.w('📱 Navigator not ready — storing pending reminder nav');
      _pendingNotificationData = {
        'notification_type': 'reminder',
        'messageType': 'reminder_tts',
      };
      return;
    }

    nav.push(
      MaterialPageRoute<void>(
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Scaffold(
            backgroundColor: isDark
                ? AppColors.backgroundDark
                : const Color(0xfff1f5f3),
            body: SafeArea(
              child: AlertsTab(onBack: () => Navigator.of(ctx).pop()),
            ),
          );
        },
      ),
    );
  }

  // ── Helper: Encode Payload ────────────────────────────────────────────────

  String _encodePayload(Map<String, dynamic> data) {
    try {
      return data.entries.map((e) => '${e.key}=${e.value}').join('&');
    } catch (e) {
      return '';
    }
  }

  // ── Request Permissions ────────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidPlugin != null) {
        // Request notification permission
        final notifGranted = await androidPlugin
            .requestNotificationsPermission();
        AppLogger.i('📱 Notification permission: $notifGranted');

        // Request exact alarms permission (for scheduling)
        await androidPlugin.requestExactAlarmsPermission();

        // ── CRITICAL: Request Full-Screen Intent Permission ──────────────────
        // This is REQUIRED on Android 10+ (API 29+) to show full-screen call UI
        // Without this, incoming calls will only show as regular notifications
        final fullScreenGranted = await androidPlugin
            .requestFullScreenIntentPermission();
        AppLogger.i('📱 Full-screen intent permission: $fullScreenGranted');

        if (fullScreenGranted == false) {
          AppLogger.w('⚠️ WARNING: Full-screen intent permission denied!');
          AppLogger.w('   Incoming calls will NOT show full-screen call UI');
          AppLogger.w(
            '   User must enable in Settings > Apps > Munawwara Care > Notifications',
          );
        }
      }
      return true;
    } else if (Platform.isIOS) {
      final iosPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();

      return await iosPlugin?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    return false;
  }

  // ── Helper: Decode Payload ────────────────────────────────────────────────

  Map<String, dynamic> _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return {};
    try {
      final map = <String, dynamic>{};
      for (final pair in payload.split('&')) {
        final idx = pair.indexOf('=');
        if (idx > 0) {
          final key = pair.substring(0, idx);
          var value = pair.substring(idx + 1);
          if (key == 'group_id') {
            value = normalizeRouteId(value);
          }
          map[key] = value;
        }
      }
      return map;
    } catch (e) {
      return {};
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat Route Resolver — picks the right chat screen based on the user's role.
// Pilgrims see GroupInboxScreen; moderators see GroupMessagesScreen.
// ─────────────────────────────────────────────────────────────────────────────

class _ChatRouteResolver extends StatefulWidget {
  final String groupId;
  final String groupName;

  const _ChatRouteResolver({required this.groupId, required this.groupName});

  @override
  State<_ChatRouteResolver> createState() => _ChatRouteResolverState();
}

class _ChatRouteResolverState extends State<_ChatRouteResolver> {
  late final Future<String?> _roleFuture = _getRole();
  Future<String?>? _userIdFuture;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _roleFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final role = snap.data;
        if (role == 'pilgrim') {
          return GroupInboxScreen(
            groupId: widget.groupId,
            groupName:
                widget.groupName.isNotEmpty ? widget.groupName : 'Messages',
          );
        }
        _userIdFuture ??= _getUserId();
        return FutureBuilder<String?>(
          future: _userIdFuture,
          builder: (context, userSnap) {
            if (!userSnap.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return GroupMessagesScreen(
              groupId: widget.groupId,
              groupName:
                  widget.groupName.isNotEmpty ? widget.groupName : 'Messages',
              currentUserId: userSnap.data ?? '',
            );
          },
        );
      },
    );
  }

  Future<String?> _getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_role');
  }

  Future<String?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }
}
