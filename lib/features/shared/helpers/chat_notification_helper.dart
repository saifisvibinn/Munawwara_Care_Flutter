import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/app_logger.dart';
import '../../../core/services/incoming_chat_sfx.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/tts_cloud_api.dart';
import '../../../core/widgets/in_app_popup.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/message_model.dart';
import '../providers/message_provider.dart';
import 'chat_popup_dedup.dart';
import 'message_visibility.dart';

class ChatNotificationHelper {
  /// Same heuristic as pilgrim inbox — skip translate when script matches UI.
  static String _detectLikelyLanguage(String text) {
    if (text.trim().isEmpty) return 'unknown';
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(text)) return 'ar';
    if (RegExp(r'[A-Za-z]').hasMatch(text)) return 'en';
    return 'unknown';
  }

  static String _voicePopupLabel() => '\ud83c\udfa4 ${'voice_message'.tr()}';

  static Future<String> _translateIfNeeded(
    String targetLang,
    String text,
  ) async {
    final t = text.trim();
    if (t.isEmpty) return text;
    final detected = _detectLikelyLanguage(t);
    if (detected != 'unknown' && detected == targetLang) return text;
    try {
      final response = await ApiService.dio.post(
        '/auth/translate',
        data: {'text': t, 'targetLang': targetLang},
      );
      final translated = response.data?['translatedText'] as String?;
      if (translated != null && translated.trim().isNotEmpty) {
        return translated.trim();
      }
    } catch (e) {
      AppLogger.w('[ChatNotificationHelper] translate: $e');
    }
    return text;
  }

  /// Moderator text/TTS → [targetLang] for popup body; others unchanged.
  static Future<String> _bodyTextForPopup(
    String targetLang,
    GroupMessage msg,
  ) async {
    if (msg.type == 'voice') return _voicePopupLabel();
    if (!msg.isFromModerator) return msg.content ?? '';
    if (msg.type != 'text' && msg.type != 'tts') return msg.content ?? '';

    final original = msg.type == 'tts'
        ? (msg.originalText ?? msg.content ?? '')
        : (msg.content ?? '');
    if (original.trim().isEmpty) return msg.content ?? '';
    return _translateIfNeeded(targetLang, original);
  }

  static String _messageIdFromMap(Map<String, dynamic> map) {
    final raw = map['_id'] ?? map['id'];
    if (raw == null) return '';
    if (raw is String) return raw.trim();
    if (raw is Map) {
      final oid = raw[r'$oid'] ?? raw['oid'];
      if (oid != null) return oid.toString().trim();
    }
    return raw.toString().trim();
  }

  static Future<void> _recordDedup(
    SharedPreferences prefs,
    int msgMs,
    String messageId,
  ) async {
    await prefs.setInt(ChatPopupDedup.lastPopupMsKey, msgMs);
    if (messageId.isEmpty) return;
    final existing = prefs.getStringList(ChatPopupDedup.notifiedIdsKey) ?? [];
    if (existing.contains(messageId)) return;
    final next = [...existing, messageId];
    final trimmed = next.length > ChatPopupDedup.maxNotifiedIds
        ? next.sublist(next.length - ChatPopupDedup.maxNotifiedIds)
        : next;
    await prefs.setStringList(ChatPopupDedup.notifiedIdsKey, trimmed);
  }

  static Future<void> showIncomingMessage({
    required BuildContext context,
    required WidgetRef ref,
    required Map<String, dynamic> map,
    required VoidCallback onViewChat,
  }) async {
    if (!context.mounted) return;

    try {
      final myId = ref.read(authProvider).userId ?? '';
      final isModerator =
          ref.read(authProvider).role?.toLowerCase() != 'pilgrim';
      if (!isRawMessageVisibleToUser(
        map,
        myId,
        isModerator: isModerator,
      )) {
        AppLogger.d(
          '[ChatNotificationHelper] Skipping popup (private, not for user)',
        );
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      if (!context.mounted) return;
      final targetLang = context.locale.languageCode;

      final messageId = _messageIdFromMap(map);
      final notifiedIds =
          prefs.getStringList(ChatPopupDedup.notifiedIdsKey) ?? [];
      if (messageId.isNotEmpty && notifiedIds.contains(messageId)) {
        AppLogger.d(
          '[ChatNotificationHelper] Skipping popup (id dedup) id=$messageId',
        );
        return;
      }

      final createdAtRaw = map['created_at']?.toString() ??
          map['createdAt']?.toString() ??
          map['timestamp']?.toString();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      var msgMs = nowMs;
      if (createdAtRaw != null && createdAtRaw.isNotEmpty) {
        try {
          msgMs = DateTime.parse(createdAtRaw).toLocal().millisecondsSinceEpoch;
        } catch (_) {}
      }

      // Prevent replaying old socket messages on reconnect/hot restart.
      final lastMs = prefs.getInt(ChatPopupDedup.lastPopupMsKey) ?? 0;
      if (msgMs <= lastMs) {
        AppLogger.d(
          '[ChatNotificationHelper] Skipping popup (dedup) '
          'msgMs=$msgMs lastMs=$lastMs',
        );
        return;
      }

      final msg = GroupMessage.fromJson(map);

      // Don't show popup for our own messages
      if (myId.isNotEmpty && msg.sender?.id == myId) return;

      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        AppLogger.d(
          '[ChatNotificationHelper] Skipping popup/SFX (app not resumed)',
        );
        return;
      }

      // ── Play SFX and Haptics ───────────────────────────────────────────────
      // Urgent TTS: tray + InAppPopup already play speech — skip asset SFX so
      // audioplayers does not steal focus from just_audio (cloud MP3 cutoff +
      // flutter_tts fallback).
      if (msg.isUrgent && msg.type == 'tts') {
        HapticFeedback.heavyImpact();
        HapticFeedback.vibrate();
      } else if (msg.isUrgent) {
        IncomingChatSfx.playUrgentAlarm();
        HapticFeedback.heavyImpact();
        HapticFeedback.vibrate();
      } else {
        IncomingChatSfx.playNormalPop();
        HapticFeedback.lightImpact();
      }

      final senderName = msg.isFromModerator
          ? 'call_support_display_name'.tr()
          : (msg.sender?.fullName ?? 'notification_title'.tr());

      if (msg.type == 'meetpoint') {
        // Meetpoint message → special popup with Navigate button
        var mpName =
            msg.meetpointData?['name']?.toString() ?? 'meetpoint'.tr();
        if (msg.isFromModerator) {
          mpName = await _translateIfNeeded(targetLang, mpName);
        }
        var meetBody = msg.content ?? '';
        if (msg.isFromModerator && meetBody.trim().isNotEmpty) {
          meetBody = await _translateIfNeeded(targetLang, meetBody);
        }
        if (!context.mounted) return;
        final lat = msg.meetpointData?['latitude'];
        final lng = msg.meetpointData?['longitude'];
        final mTimeRaw = msg.meetpointData?['meetpoint_time'];
        String? displayTime;
        if (mTimeRaw != null) {
          try {
            final dt = DateTime.parse(mTimeRaw.toString()).toLocal();
            displayTime = DateFormat('hh:mm a').format(dt);
          } catch (_) {}
        }
        InAppPopup.showMeetpoint(
          context,
          name: mpName,
          body: meetBody.isEmpty ? null : meetBody,
          time: displayTime,
          onNavigate: (lat != null && lng != null)
              ? () {
                  final url = Uri.parse(
                    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
                  );
                  launchUrl(url, mode: LaunchMode.externalApplication);
                }
              : null,
        );
      } else {
        // Only show popup for urgent messages or brief for non-urgent
        if (!msg.isUrgent) {
          // Non-urgent: brief auto-dismissing popup (no lock, no TTS)
          final body = await _bodyTextForPopup(targetLang, msg);
          if (!context.mounted) return;
          InAppPopup.show(
            context,
            title: senderName,
            body: body,
            isUrgent: false,
            lockUntilDismiss: false,
            duration: const Duration(seconds: 4),
            onViewChat: onViewChat,
          );
          await _recordDedup(prefs, msgMs, msg.id);
          return;
        }

        final body = await _bodyTextForPopup(targetLang, msg);
        if (!context.mounted) return;

        String? playType;
        String? playValue;
        String? playTtsAudioUrl;
        if (msg.isUrgent && msg.type == 'voice' && msg.mediaUrl != null) {
          playType = 'voice';
          playValue = ref
              .read(messageProvider.notifier)
              .buildUploadUrl(msg.mediaUrl!);
        } else if (msg.isUrgent && msg.type == 'tts') {
          playType = 'tts';
          // Same wording as the popup (translated for moderator copy).
          playValue = body;
          final original =
              (msg.originalText ?? msg.content ?? '').trim();
          final bodyTrim = body.trim();
          if (msg.isFromModerator &&
              bodyTrim.isNotEmpty &&
              bodyTrim != original) {
            playTtsAudioUrl = await TtsCloudApi.fetchAudioUrl(
              text: body,
              lang: targetLang,
            );
          }
          if ((playTtsAudioUrl ?? '').trim().isEmpty) {
            final rawTts = msg.audioUrl?.trim();
            if (rawTts != null && rawTts.isNotEmpty) {
              playTtsAudioUrl = ref
                  .read(messageProvider.notifier)
                  .buildUploadUrl(rawTts);
            }
          }
        }

        if (!context.mounted) return;
        InAppPopup.show(
          context,
          title: senderName,
          body: body,
          isUrgent: msg.isUrgent,
          lockUntilDismiss: true,
          playType: playType,
          playValue: playValue,
          playTtsAudioUrl: playTtsAudioUrl,
          playLocale: targetLang,
          onViewChat: onViewChat,
        );
      }

      await _recordDedup(prefs, msgMs, msg.id);
    } catch (e) {
      AppLogger.e('[ChatNotificationHelper] Error showing popup: $e');
    }
  }

  static void dispose() {
    unawaited(IncomingChatSfx.dispose());
  }
}
