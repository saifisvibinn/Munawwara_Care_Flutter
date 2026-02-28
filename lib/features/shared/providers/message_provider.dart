import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_service.dart';
import '../models/message_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class MessageState {
  final List<GroupMessage> messages;
  final bool isLoading;
  final bool isSending;
  final String? error;
  final int unreadCount;

  const MessageState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
    this.unreadCount = 0,
  });

  MessageState copyWith({
    List<GroupMessage>? messages,
    bool? isLoading,
    bool? isSending,
    String? error,
    int? unreadCount,
  }) => MessageState(
    messages: messages ?? this.messages,
    isLoading: isLoading ?? this.isLoading,
    isSending: isSending ?? this.isSending,
    error: error,
    unreadCount: unreadCount ?? this.unreadCount,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class MessageNotifier extends Notifier<MessageState> {
  @override
  MessageState build() => const MessageState();

  // Strips "/api" suffix to build the upload base URL
  String get _uploadBase =>
      ApiService.baseUrl.replaceFirst(RegExp(r'/api$'), '');

  /// Full URL to stream a voice/image upload from the server
  String buildUploadUrl(String filename) => '$_uploadBase/uploads/$filename';

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> loadMessages(String groupId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await ApiService.dio.get('/messages/group/$groupId');
      final raw = (res.data['data'] as List<dynamic>)
          .map((j) => GroupMessage.fromJson(j as Map<String, dynamic>))
          .toList();
      // oldest first (chronological / chat order)
      raw.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      state = state.copyWith(messages: raw, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
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

  /// Silently appends a single message received from a socket event.
  /// No loading state is touched, so the list never flickers.
  void appendMessage(Map<String, dynamic> json) {
    try {
      final msg = GroupMessage.fromJson(json);
      if (state.messages.any((m) => m.id == msg.id)) return; // dedup
      state = state.copyWith(
        messages: [...state.messages, msg],
        unreadCount: state.unreadCount + 1,
      );
    } catch (_) {}
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
        },
      );
      final msg = GroupMessage.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
      state = state.copyWith(
        messages: [...state.messages, msg],
        isSending: false,
      );
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
        },
      );
      final msg = GroupMessage.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
      state = state.copyWith(
        messages: [...state.messages, msg],
        isSending: false,
      );
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
  }) async {
    state = state.copyWith(isSending: true);
    try {
      final formData = FormData.fromMap({
        'group_id': groupId,
        'type': 'voice',
        'is_urgent': isUrgent.toString(),
        'duration': durationSeconds.toString(),
        'file': await MultipartFile.fromFile(
          filePath,
          filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        ),
      });
      final response = await ApiService.dio.post('/messages', data: formData);
      final msg = GroupMessage.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
      state = state.copyWith(
        messages: [...state.messages, msg],
        isSending: false,
      );
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
  }) async {
    state = state.copyWith(isSending: true);
    try {
      final formData = FormData.fromMap({
        'group_id': groupId,
        'recipient_id': recipientId,
        'type': 'voice',
        'is_urgent': isUrgent.toString(),
        'duration': durationSeconds.toString(),
        'file': await MultipartFile.fromFile(
          filePath,
          filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        ),
      });
      final response = await ApiService.dio.post(
        '/messages/individual',
        data: formData,
      );
      final msg = GroupMessage.fromJson(
        response.data['data'] as Map<String, dynamic>,
      );
      state = state.copyWith(
        messages: [...state.messages, msg],
        isSending: false,
      );
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
