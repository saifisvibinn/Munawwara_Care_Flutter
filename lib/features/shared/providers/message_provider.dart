import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/app_data_cache.dart';
import '../../../core/utils/app_logger.dart';
import '../helpers/chat_popup_dedup.dart';
import '../models/message_model.dart';

/// Server may run translation + Cloud TTS before responding; avoid false
/// "send failed" when the default Dio receive timeout fires too early.
const Duration _kMessageSendReceiveTimeout = Duration(seconds: 90);

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class MessageState {
  final List<GroupMessage> messages;
  final bool isLoading;
  final bool isSending;
  final String? error;
  final int unreadCount;
  final String? activeGroupId;

  const MessageState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
    this.unreadCount = 0,
    this.activeGroupId,
  });

  MessageState copyWith({
    List<GroupMessage>? messages,
    bool? isLoading,
    bool? isSending,
    String? error,
    int? unreadCount,
    bool updateActiveGroup = false,
    String? activeGroupId,
  }) =>
      MessageState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        isSending: isSending ?? this.isSending,
        error: error,
        unreadCount: unreadCount ?? this.unreadCount,
        activeGroupId:
            updateActiveGroup ? activeGroupId : this.activeGroupId,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class MessageNotifier extends Notifier<MessageState> {
  static const _maxCachedMessages = 100;

  @override
  MessageState build() => const MessageState();

  String get _uploadBase => ApiService.apiOrigin;

  /// Full URL to stream a voice/image upload from the server
  String buildUploadUrl(String filename) => '$_uploadBase/uploads/$filename';

  Map<String, dynamic> _trimMessagesBody(Map<String, dynamic> body) {
    final copy = Map<String, dynamic>.from(body);
    final list = copy['data'];
    if (list is List && list.length > _maxCachedMessages) {
      copy['data'] = list.sublist(list.length - _maxCachedMessages);
    }
    return copy;
  }

  Future<void> _hydrateMessagesFromCache(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_id');
    if (uid == null) return;
    final blob = AppDataCache.jsonMap(
      await AppDataCache.readData(
        uid,
        AppDataCache.messagesFile(groupId),
      ),
    );
    if (blob == null) return;
    final listRaw = blob['data'];
    if (listRaw is! List<dynamic>) return;
    try {
      final parsed = <GroupMessage>[];
      for (final item in listRaw) {
        final jm = AppDataCache.jsonMap(item);
        if (jm == null) continue;
        try {
          parsed.add(GroupMessage.fromJson(jm));
        } catch (_) {}
      }
      parsed.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      if (parsed.isEmpty) return;
      state = state.copyWith(messages: parsed);
      await ChatPopupDedup.mergeKnownMessageIds(
        parsed.map((m) => m.id),
      );
    } catch (_) {}
  }

  Future<void> _writeMessagesCache(
    String groupId,
    Map<String, dynamic> body,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_id');
    if (uid == null) return;
    await AppDataCache.write(
      uid,
      AppDataCache.messagesFile(groupId),
      _trimMessagesBody(body),
    );
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> loadMessages(String groupId) async {
    // Enter loading before cache hydrate so listeners never see 0→N growth
    // while isLoading is false (avoids phantom receive SFX / tab pulses).
    state = state.copyWith(isLoading: true, error: null);
    await _hydrateMessagesFromCache(groupId);
    try {
      final res = await ApiService.dio.get('/messages/group/$groupId');
      final body = Map<String, dynamic>.from(res.data as Map);
      await _writeMessagesCache(groupId, body);
      final raw = (body['data'] as List<dynamic>)
          .map((j) => GroupMessage.fromJson(j as Map<String, dynamic>))
          .toList();
      // oldest first (chronological / chat order)
      raw.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      state = state.copyWith(messages: raw, isLoading: false);
      await ChatPopupDedup.mergeKnownMessageIds(raw.map((m) => m.id));
    } on DioException catch (e) {
      if (state.messages.isEmpty) {
        await _hydrateMessagesFromCache(groupId);
      }
      if (state.messages.isNotEmpty) {
        state = state.copyWith(isLoading: false, error: null);
        await ChatPopupDedup.mergeKnownMessageIds(
          state.messages.map((m) => m.id),
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          error: ApiService.parseError(e),
        );
      }
    }
  }

  // ── Unread ─────────────────────────────────────────────────────────────────

  Future<int> fetchUnreadCount(String groupId) async {
    try {
      final res = await ApiService.dio.get('/messages/group/$groupId/unread');
      final count = (res.data['unread_count'] as num?)?.toInt() ?? 0;
      state = state.copyWith(unreadCount: count);
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markAllRead(String groupId) async {
    try {
      await ApiService.dio.post('/messages/group/$groupId/mark-read');
      state = state.copyWith(unreadCount: 0);
    } catch (_) {}
  }

  void setActiveGroup(String? groupId) {
    state = state.copyWith(updateActiveGroup: true, activeGroupId: groupId);
  }

  /// Silently appends a single message received from a socket event.
  /// No loading state is touched, so the list never flickers.
  /// Returns false when the message was already present or could not be parsed.
  bool appendMessage(Map<String, dynamic> json) {
    try {
      final msg = GroupMessage.fromJson(json);
      if (state.messages.any((m) => m.id == msg.id)) {
        return false;
      }

      final isReadingNow = state.activeGroupId == msg.groupId;

      state = state.copyWith(
        messages: [...state.messages, msg],
        unreadCount: isReadingNow ? state.unreadCount : state.unreadCount + 1,
      );

      if (isReadingNow) {
        markAllRead(msg.groupId);
      }
      return true;
    } catch (e) {
      AppLogger.w('[MessageNotifier] Error appending message: $e');
      return false;
    }
  }

  /// Silently removes a message received via socket (no loading state).
  void removeMessage(String messageId) {
    state = state.copyWith(
      messages: state.messages.where((m) => m.id != messageId).toList(),
    );
  }

  // ── Send Text / TTS ────────────────────────────────────────────────────────

  Future<bool> sendTextMessage({
    required String groupId,
    required String content,
    required bool isUrgent,
    bool isTts = false,
    String? replyToMessageId,
  }) async {
    state = state.copyWith(isSending: true);
    try {
      final response = await ApiService.dio.post(
        '/messages',
        data: {
          'group_id': groupId,
          'type': isTts ? 'tts' : 'text',
          'content': content,
          if (isTts) 'original_text': content,
          'is_urgent': isUrgent,
          if (replyToMessageId != null && replyToMessageId.isNotEmpty)
            'reply_to': replyToMessageId,
        },
        options: Options(receiveTimeout: _kMessageSendReceiveTimeout),
      );
      final msg = GroupMessage.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
      if (state.messages.any((m) => m.id == msg.id)) {
        state = state.copyWith(isSending: false);
      } else {
        state = state.copyWith(
          messages: [...state.messages, msg],
          isSending: false,
        );
      }
      return true;
    } catch (_) {
      state = state.copyWith(isSending: false);
      return false;
    }
  }

  Future<bool> sendIndividualTextMessage({
    required String groupId,
    required String recipientId,
    required String content,
    required bool isUrgent,
    bool isTts = false,
    String? replyToMessageId,
  }) async {
    state = state.copyWith(isSending: true);
    try {
      final response = await ApiService.dio.post(
        '/messages/individual',
        data: {
          'group_id': groupId,
          'recipient_id': recipientId,
          'type': isTts ? 'tts' : 'text',
          'content': content,
          if (isTts) 'original_text': content,
          'is_urgent': isUrgent,
          if (replyToMessageId != null && replyToMessageId.isNotEmpty)
            'reply_to': replyToMessageId,
        },
        options: Options(receiveTimeout: _kMessageSendReceiveTimeout),
      );
      final msg = GroupMessage.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
      if (state.messages.any((m) => m.id == msg.id)) {
        state = state.copyWith(isSending: false);
      } else {
        state = state.copyWith(
          messages: [...state.messages, msg],
          isSending: false,
        );
      }
      return true;
    } catch (_) {
      state = state.copyWith(isSending: false);
      return false;
    }
  }

  // ── Send Voice ─────────────────────────────────────────────────────────────

  Future<bool> sendVoiceMessage({
    required String groupId,
    required String filePath,
    required bool isUrgent,
    int durationSeconds = 0,
    String? replyToMessageId,
  }) async {
    state = state.copyWith(isSending: true);
    try {
      final formData = FormData.fromMap({
        'group_id': groupId,
        'type': 'voice',
        'is_urgent': isUrgent.toString(),
        'duration': durationSeconds.toString(),
        if (replyToMessageId != null && replyToMessageId.isNotEmpty)
          'reply_to': replyToMessageId,
        'file': await MultipartFile.fromFile(
          filePath,
          filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        ),
      });
      final response = await ApiService.dio.post(
        '/messages',
        data: formData,
        options: Options(receiveTimeout: _kMessageSendReceiveTimeout),
      );
      final msg = GroupMessage.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
      if (state.messages.any((m) => m.id == msg.id)) {
        state = state.copyWith(isSending: false);
      } else {
        state = state.copyWith(
          messages: [...state.messages, msg],
          isSending: false,
        );
      }
      return true;
    } catch (_) {
      state = state.copyWith(isSending: false);
      return false;
    }
  }

  Future<bool> sendIndividualVoiceMessage({
    required String groupId,
    required String recipientId,
    required String filePath,
    required bool isUrgent,
    int durationSeconds = 0,
    String? replyToMessageId,
  }) async {
    state = state.copyWith(isSending: true);
    try {
      final formData = FormData.fromMap({
        'group_id': groupId,
        'recipient_id': recipientId,
        'type': 'voice',
        'is_urgent': isUrgent.toString(),
        'duration': durationSeconds.toString(),
        if (replyToMessageId != null && replyToMessageId.isNotEmpty)
          'reply_to': replyToMessageId,
        'file': await MultipartFile.fromFile(
          filePath,
          filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        ),
      });
      final response = await ApiService.dio.post(
        '/messages/individual',
        data: formData,
        options: Options(receiveTimeout: _kMessageSendReceiveTimeout),
      );
      final msg = GroupMessage.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
      if (state.messages.any((m) => m.id == msg.id)) {
        state = state.copyWith(isSending: false);
      } else {
        state = state.copyWith(
          messages: [...state.messages, msg],
          isSending: false,
        );
      }
      return true;
    } catch (_) {
      state = state.copyWith(isSending: false);
      return false;
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  Future<bool> deleteMessage(String messageId) async {
    try {
      await ApiService.dio.delete('/messages/$messageId');
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != messageId).toList(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final messageProvider = NotifierProvider<MessageNotifier, MessageState>(
  MessageNotifier.new,
);
