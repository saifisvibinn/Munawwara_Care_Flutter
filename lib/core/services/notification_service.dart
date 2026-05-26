import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../config/backend_config.dart';
import 'api_service.dart';
import 'callkit_service.dart';
import 'secure_session_store.dart';
import 'speech_service.dart';
import 'locale_prefs.dart';
import 'sos_alert_audio.dart';
import '../../features/moderator/models/sos_moderator_payload.dart';
import 'tts_cloud_api.dart';
import '../../core/utils/app_logger.dart';
import '../../core/router/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../features/pilgrim/screens/group_inbox_screen.dart';
import '../../features/moderator/screens/group_messages_screen.dart';
import '../../features/moderator/services/sos_alert_coordinator.dart';
import '../../features/pilgrim/services/pilgrim_sos_coordinator.dart';
import '../../features/notifications/screens/alerts_tab_v2.dart';
import '../../features/calling/calling_scope.dart';
import '../../features/calling/data/call_history_api.dart';
import '../../features/calling/providers/missed_calls_unread_provider.dart';
import '../../features/shared/providers/message_provider.dart';
import '../theme/app_colors.dart';
import '../utils/route_id_utils.dart';

/// Wait after the urgent notification sound before starting TTS (extra 2 s).
const Duration kUrgentAlertToTtsDelay = Duration(milliseconds: 4200);

const _notificationTrayChannel = MethodChannel(
  'com.munawwaracare.android/notification_tray',
);

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
      declinerId =
          (await SecureSessionStore.getUserId()) ??
          prefs.getString('user_id') ??
          '';
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

bool _isSosAlertFcm(RemoteMessage message) {
  final data = message.data;
  final t = data['notification_type']?.toString() ??
      data['type']?.toString() ??
      '';
  return t == 'sos_alert';
}

bool _isReminderTtsFcm(RemoteMessage message) {
  final dataType = message.data['type']?.toString() ?? '';
  final msgType = message.data['messageType']?.toString() ?? '';
  return dataType == 'urgent' && msgType == 'reminder_tts';
}

Future<String> _resolveTtsLang(RemoteMessage message) async {
  final fromFcm = message.data['lang']?.toString().trim() ?? '';
  if (fromFcm.isNotEmpty) {
    return TtsCloudApi.normalizeLang(fromFcm);
  }
  return TtsCloudApi.normalizeLang(await LocalePrefs.readLanguageCode());
}

void _sendReminderPopupToMainIsolate(RemoteMessage message) {
  final sendPort = IsolateNameServer.lookupPortByName('popup_port');
  if (sendPort == null) return;
  final text =
      message.data['content']?.toString() ??
      message.data['body']?.toString() ??
      message.notification?.body ??
      '';
  if (text.isEmpty) return;
  sendPort.send({
    'type': 'reminder_popup',
    'body': text,
    'rawTime':
        message.data['scheduledAt']?.toString() ??
        message.data['scheduled_time']?.toString() ??
        '',
  });
}

/// Bundled SOS MP3 when the app is killed, backgrounded, or the screen is off.
@pragma('vm:entry-point')
Future<void> _playSosAlertAudioInBackground(RemoteMessage message) async {
  try {
    final role = await SecureSessionStore.getRole();
    if (role != 'moderator') {
      AppLogger.i('🔊 SOS audio [background]: skipped (role=$role)');
      return;
    }

    final payload = SosModeratorPayload.fromMap(
      Map<String, dynamic>.from(message.data),
    );
    final storageKey = payload.storageKey;

    var wakelockOn = false;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await WakelockPlus.enable();
        wakelockOn = true;
      } catch (e) {
        AppLogger.w('[SOS audio] WakeLock failed (non-fatal): $e');
      }
    }

    try {
      if (await SosAlertAudio.wasHandledByMainIsolate(storageKey)) {
        AppLogger.i(
          '🔊 SOS audio [background]: skipped (main isolate handled)',
        );
        return;
      }
      await SosAlertAudio.playBackgroundSequence(storageKey: storageKey);
    } finally {
      if (wakelockOn) {
        try {
          await WakelockPlus.disable();
        } catch (_) {}
      }
    }
  } catch (e, st) {
    AppLogger.e('🔊 SOS audio [background] failed: $e\n$st');
  }
}

/// Cloud TTS for scheduled reminders (killed / locked / background).
@pragma('vm:entry-point')
Future<void> _playReminderTtsInBackground(RemoteMessage message) async {
  try {
    var text = urgentTtsSpokenBackupText(message, isReminder: true);
    if (text.isEmpty &&
        (message.notification?.body ?? '').trim().isNotEmpty) {
      text = message.notification!.body!.trim();
    }
    if (text.isEmpty) return;

    final lang = await _resolveTtsLang(message);
    final reminderId = message.data['reminderId']?.toString() ?? '';
    final messageKey = reminderId.isNotEmpty
        ? 'reminder_$reminderId'
        : (message.data['message_id']?.toString() ??
            message.messageId ??
            '');

    AppLogger.i(
      '🔊 Reminder TTS [background]: "$text" (lang=$lang, '
      'audioUrl=pending)',
    );

    await ApiService.restoreForBackgroundIsolate();
    var audioUrl = message.data['audio_url']?.toString().trim();
    if (audioUrl == null || audioUrl.isEmpty) {
      audioUrl = await TtsCloudApi.fetchAudioUrl(text: text, lang: lang);
    }

    var wakelockOn = false;
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        await WakelockPlus.enable();
        wakelockOn = true;
      } catch (e) {
        AppLogger.w('[Reminder TTS] WakeLock failed (non-fatal): $e');
      }
    }

    try {
      await Future.delayed(kUrgentAlertToTtsDelay);
      await SpeechService.playRobust(
        audioUrl: audioUrl,
        backupText: text,
        lang: lang,
        isUrgent: true,
        messageKey: messageKey.isEmpty ? null : messageKey,
      );
    } finally {
      if (wakelockOn) {
        try {
          await WakelockPlus.disable();
        } catch (_) {}
      }
    }
  } catch (e, st) {
    AppLogger.e('🔊 Reminder TTS [background] failed: $e\n$st');
  }
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
        callControlType == 'call_declined' ||
        callControlType == 'call_ended') {
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

  final fcmType = message.data['type']?.toString() ?? '';
  if (fcmType == 'sos_alert_cancelled') {
    await SosAlertCoordinator.handleCancelledFromMap(
      Map<String, dynamic>.from(message.data),
    );
    return;
  }
  if (fcmType == 'sos_resolved') {
    await PilgrimSosCoordinator.persistPendingModeratorResolved();
    return;
  }

  // SOS: silent visual tray (data-only) + asset urgent + language in handler.
  if (_isSosAlertFcm(message)) {
    await NotificationService.instance.initialize();
    if (message.notification == null) {
      final data = message.data;
      final title =
          data['title']?.toString() ?? 'Munawwara Care';
      final body = data['body']?.toString() ?? '';
      await NotificationService.instance.showSosAlertTraySilent(
        title: title,
        body: body,
        data: Map<String, dynamic>.from(data),
      );
    }
    await _playSosAlertAudioInBackground(message);
    return;
  }

  // Reminders: always cloud TTS (data-only FCM; legacy notif payloads too).
  if (_isReminderTtsFcm(message)) {
    await NotificationService.instance.initialize();
    _sendReminderPopupToMainIsolate(message);
    if (message.notification == null) {
      await NotificationService.instance.showNotificationFromMessage(message);
    }
    await _playReminderTtsInBackground(message);
    return;
  }

  // ── If the FCM payload contains a 'notification' block, Android already
  //    showed a system notification automatically — skip showing another one
  //    to avoid duplicates. We only create a local notification for
  //    data-only messages (urgent TTS, etc.) that Android won't display.
  if (message.notification != null) {
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

  // ── Urgent broadcast TTS (not reminders — handled above) ─────────────────
  if (dataType == 'urgent' && msgType == 'tts') {
    var text = urgentTtsSpokenBackupText(message, isReminder: false);
    if (text.isEmpty) return;

    final lang = await _resolveTtsLang(message);
    final messageKey =
        message.data['message_id']?.toString() ??
        message.messageId ??
        '';

    AppLogger.i(
      '🔊 Urgent TTS [background]: "$text" (lang=$lang)',
    );

    await NotificationService.instance.showNotificationFromMessage(message);
    await Future.delayed(kUrgentAlertToTtsDelay);

    var audioUrl = message.data['audio_url']?.toString().trim();
    if (audioUrl == null || audioUrl.isEmpty) {
      await ApiService.restoreForBackgroundIsolate();
      audioUrl = await TtsCloudApi.fetchAudioUrl(text: text, lang: lang);
    }

    await SpeechService.playRobust(
      audioUrl: audioUrl,
      backupText: text,
      lang: lang,
      isUrgent: true,
      messageKey: messageKey.isEmpty ? null : messageKey,
    );
    return;
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

  static String chatTrayTag(String groupId) => 'chat_$groupId';

  static const String missedCallTrayTag = 'missed_call';

  /// Dismisses a tray notification by Android tag (FCM + local plugin).
  static Future<void> dismissTrayByTag(String tag) async {
    final t = tag.trim();
    if (t.isEmpty) return;
    if (Platform.isAndroid) {
      try {
        await _notificationTrayChannel.invokeMethod<bool>(
          'dismissNotificationByTag',
          <String, String>{'tag': t},
        );
        AppLogger.i('[NotificationService] Dismissed tray tag=$t');
      } catch (e) {
        AppLogger.w('[NotificationService] dismissTrayByTag native: $e');
      }
    }
    if (Platform.isAndroid) {
      final android = NotificationService.instance._notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.cancel(0, tag: t);
    }
  }

  static Future<void> dismissTrayByTags(Iterable<String> tags) async {
    for (final tag in tags) {
      await dismissTrayByTag(tag);
    }
  }

  static Future<void> dismissChatTrayForGroup(String groupId) async {
    final gid = normalizeRouteId(groupId);
    if (gid.isEmpty) return;
    await dismissTrayByTag(chatTrayTag(gid));
  }

  static Future<void> dismissMissedCallTray() async {
    await dismissTrayByTag(missedCallTrayTag);
  }

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
        unawaited(_uploadFcmTokenWhenAuthenticated(newToken));
      });
    }
    return FirebaseMessaging.instance.getToken();
  }

  /// Uploads FCM token only when the user has a logged-in session.
  static Future<void> _uploadFcmTokenWhenAuthenticated(String token) async {
    if (!await ApiService.hasStoredAuthToken()) {
      AppLogger.d(
        '[NotificationService] Skip FCM upload — no auth session',
      );
      return;
    }
    await ApiService.ensureAuthHeaderFromPrefs();
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
      AppLogger.i('[NotificationService] FCM token uploaded to backend');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      AppLogger.e(
        '[NotificationService] FCM token upload failed (HTTP $code): '
        '${e.response?.data}',
      );
      if (code == 401) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('last_registered_fcm_token');
      }
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

    // SOS tray: visual only — audio from background handler assets.
    final sosChannel = AndroidNotificationChannel(
      'mc_sos_v2',
      'SOS Alerts',
      description: 'Pilgrim SOS alerts (sound played in-app)',
      importance: Importance.max,
      playSound: false,
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xFFF97316),
    );

    await androidPlugin.createNotificationChannel(defaultChannel);
    await androidPlugin.createNotificationChannel(urgentChannel);
    await androidPlugin.createNotificationChannel(callChannel);
    await androidPlugin.createNotificationChannel(sosChannel);

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

    // Foreground SOS: in-app chime + dialog only (no tray).
    if (notificationType == 'sos_alert') {
      if (WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed) {
        AppLogger.i(
          '[NotificationService] Skip SOS tray (foreground in-app handling)',
        );
        return;
      }
      await showSosAlertTraySilent(
        title: title,
        body: body,
        data: data,
      );
      return;
    }

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

  // ── SOS tray (silent — handler plays urgent + language assets) ───────────

  Future<void> showSosAlertTraySilent({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    AppLogger.i('[NotificationService] SOS tray (silent, visual only)');

    final androidDetails = AndroidNotificationDetails(
      'mc_sos_v2',
      'SOS Alerts',
      channelDescription: 'Pilgrim SOS alerts (sound played in-app)',
      importance: Importance.max,
      priority: Priority.max,
      playSound: false,
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
      presentSound: false,
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

    final notifType =
        data['notification_type']?.toString() ?? data['type']?.toString() ?? '';
    final groupId = normalizeRouteId(data['group_id']?.toString() ?? '');
    String? androidTag;
    if (notifType == 'missed_call') {
      androidTag = missedCallTrayTag;
    } else if ((notifType == 'new_message' || notifType == 'meetpoint') &&
        groupId.isNotEmpty) {
      androidTag = chatTrayTag(groupId);
    }

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
      tag: androidTag,
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

  /// Dismisses Android tray SOS notifications (FCM tag matches backend).
  static Future<void> dismissSosTrayFor({
    required String pilgrimId,
    String? groupId,
    String? sosId,
  }) async {
    final tags = <String>{};
    final sid = sosId?.trim() ?? '';
    final gid = groupId?.trim() ?? '';
    final pid = pilgrimId.trim();
    if (sid.isNotEmpty) tags.add('sos_$sid');
    if (pid.isNotEmpty && gid.isNotEmpty) tags.add('sos_c_${pid}_$gid');
    if (tags.isEmpty) return;
    await dismissTrayByTags(tags);
  }

  /// Drops queued in-app SOS dialog when the pilgrim cancels.
  static void clearPendingSosForPilgrim(String pilgrimId) {
    final pending = _pendingSosAlertData;
    if (pending == null) return;
    if (pilgrimId.isEmpty) {
      _pendingSosAlertData = null;
      return;
    }
    final pid = (pending['pilgrim_id'] ?? pending['pilgrimId'])?.toString();
    if (pid == pilgrimId) {
      _pendingSosAlertData = null;
      AppLogger.i('[NotificationService] Cleared pending SOS for $pilgrimId');
    }
  }

  // ── TTS (public, usable from foreground context) ───────────────────────────

  /// Cloud TTS first ([audioUrl] or `/auth/tts-audio-url`), then device TTS.
  static Future<void> speakTtsCloud(
    String text, {
    String? audioUrl,
    String? lang,
    String? messageKey,
  }) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final normalizedLang = TtsCloudApi.normalizeLang(
      lang ?? await LocalePrefs.readLanguageCode(),
    );
    var url = audioUrl?.trim();
    if (url == null || url.isEmpty) {
      url = await TtsCloudApi.fetchAudioUrl(text: t, lang: normalizedLang);
    }
    await SpeechService.playRobust(
      audioUrl: url,
      backupText: t,
      lang: normalizedLang,
      isUrgent: true,
      messageKey: messageKey,
    );
  }

  /// Play [text] aloud using cloud TTS when possible.
  static Future<void> speakTts(
    String text, {
    String? audioUrl,
    String lang = 'en',
    String? messageKey,
  }) =>
      speakTtsCloud(
        text,
        audioUrl: audioUrl,
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
      unawaited(SosAlertCoordinator.queueSosAlertIfStillActive(data));
      return;
    }

    // SOS claimed by another moderator — no navigation (tray notification update).
    if (notificationType == 'sos_claimed') {
      return;
    }

    if (notificationType == 'group_invitation') {
      _navigateToModeratorDashboard();
      return;
    }

    if (notificationType == 'invitation_accepted' ||
        notificationType == 'invitation_declined') {
      _navigateToModeratorUpdates();
      return;
    }

    if (notificationType == 'new_message' && groupId.isNotEmpty) {
      unawaited(dismissChatTrayForGroup(groupId));
      _navigateToChat(groupId: groupId, groupName: groupName);
    } else if (notificationType == 'meetpoint' && groupId.isNotEmpty) {
      unawaited(dismissChatTrayForGroup(groupId));
      _navigateToChat(groupId: groupId, groupName: groupName);
    }
  }

  static void _navigateToModeratorDashboard() {
    final ctx = AppRouter.navigatorKey.currentContext;
    if (ctx == null) {
      _pendingNotificationData = {'notification_type': 'group_invitation'};
      return;
    }
    ctx.go('/moderator-dashboard');
  }

  static void _navigateToModeratorUpdates() {
    final nav = AppRouter.navigatorKey.currentState;
    if (nav == null) {
      _pendingNotificationData = {
        'notification_type': 'invitation_accepted',
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
              child: AlertsTab(
                onBack: () => Navigator.of(ctx).pop(),
                initialModeratorTabIndex: 3,
              ),
            ),
          );
        },
      ),
    );
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

  /// Clears missed-call tray + server read state when opening Alerts.
  static Future<void> onAlertsTabOpened() async {
    await dismissMissedCallTray();
    final c = CallingScope.riverpod;
    if (c == null) return;
    try {
      await CallHistoryApi.markMissedCallsRead();
      await c.read(missedCallsUnreadProvider.notifier).refresh();
    } catch (e) {
      AppLogger.w('[NotificationService] onAlertsTabOpened: $e');
    }
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

  Future<String?> _getRole() => SecureSessionStore.getRole();

  Future<String?> _getUserId() => SecureSessionStore.getUserId();
}
