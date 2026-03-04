import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'callkit_service.dart';
import '../../core/utils/app_logger.dart';
import '../../core/router/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/pilgrim/screens/group_inbox_screen.dart';
import '../../features/moderator/screens/group_messages_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Background Message Handler
// MUST be a top-level function (not in a class)
// ─────────────────────────────────────────────────────────────────────────────

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  AppLogger.i('📩 Background message received: ${message.messageId}');
  AppLogger.i('   Title: ${message.notification?.title}');
  AppLogger.i('   Body: ${message.notification?.body}');
  AppLogger.i('   Data: ${message.data}');

  // ── Incoming call → show native call screen (like WhatsApp) ─────────────
  final handled = await CallKitService.handleFcmMessage(message);
  if (handled) return; // CallKit took over, don't show regular notification

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
      dataType == 'incoming_call' || (dataType == 'urgent' && msgType == 'tts');
  if (!isDataOnly) {
    AppLogger.i(
      '📩 Standard FCM (type=$dataType) — Android likely showed it, skipping local notif',
    );
    return;
  }

  // ── Data-only messages → show local notification ────────────────────────
  await NotificationService.instance.initialize();

  // ── Urgent TTS: urgent.wav → "Urgent message." → speak text ─────────────
  if (dataType == 'urgent' && msgType == 'tts') {
    final text =
        message.data['body']?.toString() ??
        message.data['content']?.toString() ??
        '';
    AppLogger.i('🔊 Urgent TTS: background handler, text: "$text"');

    // 1. Show notification first — the urgent channel plays urgent.wav as its sound
    await NotificationService.instance.showNotificationFromMessage(message);

    if (text.isNotEmpty) {
      try {
        // 2. Wait for urgent.wav to finish before TTS begins
        await Future.delayed(const Duration(milliseconds: 2200));

        // 3. Speak "Urgent message." prefix then the actual message text
        final tts = FlutterTts();
        await tts.awaitSpeakCompletion(true);
        await tts.setVolume(1.0);
        await tts.setSpeechRate(0.4);
        await tts.setPitch(1.0);
        await tts.speak('Urgent message. $text');
      } catch (e) {
        AppLogger.e('🔊 Background TTS error: $e');
      }
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

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

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

    // Handle incoming call → route to native CallKit screen
    if (type == 'incoming_call') {
      AppLogger.i('📞 INCOMING CALL DETECTED → routing to native call screen');
      await CallKitService.handleFcmMessage(message);
      return;
    }

    // Handle urgent notifications
    if (type == 'urgent') {
      AppLogger.w('🚨 Urgent notification detected');
      await _showUrgentNotification(title: title, body: body, data: data);
      return;
    }

    // Default notification
    AppLogger.i('📬 Default notification');
    await _showDefaultNotification(title: title, body: body, data: data);
  }

  // (Incoming call notifications are now handled by CallKitService)

  // ── Show Urgent Notification ──────────────────────────────────────────────

  Future<void> _showUrgentNotification({
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
    final groupId = data['group_id']?.toString() ?? '';
    final groupName = data['group_name']?.toString() ?? '';

    AppLogger.i(
      '📱 Navigating from notification: type=$notificationType, '
      'groupId=$groupId, groupName=$groupName',
    );

    if (notificationType == 'new_message' && groupId.isNotEmpty) {
      _navigateToChat(groupId: groupId, groupName: groupName);
    } else if (notificationType == 'meetpoint' && groupId.isNotEmpty) {
      _navigateToChat(groupId: groupId, groupName: groupName);
    } else if (notificationType == 'meetpoint' && groupId.isNotEmpty) {
      _navigateToChat(groupId: groupId, groupName: groupName);
    }
  }

  /// Pending notification data when navigator isn't ready yet (cold start).
  static Map<String, dynamic>? _pendingNotificationData;

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

    // Import lazily to avoid circular deps — these are pushed imperatively
    // exactly like the rest of the app already does.
    nav.push(
      MaterialPageRoute(
        builder: (_) =>
            _ChatRouteResolver(groupId: groupId, groupName: groupName),
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
          map[pair.substring(0, idx)] = pair.substring(idx + 1);
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

class _ChatRouteResolver extends StatelessWidget {
  final String groupId;
  final String groupName;

  const _ChatRouteResolver({required this.groupId, required this.groupName});

  @override
  Widget build(BuildContext context) {
    // We need to check the role from SharedPreferences synchronously.
    // Use a FutureBuilder to load it.
    return FutureBuilder<String?>(
      future: _getRole(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final role = snap.data;
        if (role == 'pilgrim') {
          // Lazy import — pilgrim inbox
          return _buildPilgrimInbox();
        } else {
          // Moderator / admin chat
          return _buildModeratorChat();
        }
      },
    );
  }

  Future<String?> _getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_role');
  }

  Widget _buildPilgrimInbox() {
    // Import at call-site to keep notification_service lean
    return GroupInboxScreen(
      groupId: groupId,
      groupName: groupName.isNotEmpty ? groupName : 'Messages',
    );
  }

  Widget _buildModeratorChat() {
    return FutureBuilder<String?>(
      future: _getUserId(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return GroupMessagesScreen(
          groupId: groupId,
          groupName: groupName.isNotEmpty ? groupName : 'Messages',
          currentUserId: snap.data ?? '',
        );
      },
    );
  }

  Future<String?> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }
}
