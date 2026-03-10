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

  /// ISO timestamp of the oldest loaded message; used as the cursor for loading older pages.
  final String? oldestCursor;

  /// True when more messages exist on the server beyond the current page.
  final bool hasMore;

  const MessageState({
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.error,
    this.unreadCount = 0,
    this.oldestCursor,
    this.hasMore = false,
  });

  MessageState copyWith({
    List<GroupMessage>? messages,
    bool? isLoading,
    bool? isSending,
    String? error,
    int? unreadCount,
    String? oldestCursor,
    bool? hasMore,
  }) => MessageState(
    messages: messages ?? this.messages,
    isLoading: isLoading ?? this.isLoading,
    isSending: isSending ?? this.isSending,
    error: error,
    unreadCount: unreadCount ?? this.unreadCount,
    oldestCursor: oldestCursor ?? this.oldestCursor,
    hasMore: hasMore ?? this.hasMore,
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

  /// Full URL to stream a voice/image upload from the server.
  /// Appends the JWT as ?token= so audio players (which cannot set
  /// Authorization headers) can still fetch protected files.
  String buildUploadUrl(String filename) {
    final rawToken =
        ApiService.dio.options.headers['Authorization']
            ?.toString()
            .replaceFirst('Bearer ', '') ??
        '';
    final encoded = Uri.encodeComponent(rawToken);
    return '$_uploadBase/uploads/$filename?token=$encoded';
  }

  // ── Fetch ──────────────────────────────────────────────────────────────────

  Future<void> loadMessages(String groupId) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await ApiService.dio.get(
        '/messages/group/$groupId',
        queryParameters: {'limit': 50},
      );
      final raw = (res.data['data'] as List<dynamic>)
          .map((j) => GroupMessage.fromJson(j as Map<String, dynamic>))
          .toList();
      // oldest first (chronological / chat order)
      raw.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      // Backend returns up to `limit` newest messages; if exactly 50 came back
      // there may be more older ones available.
      final hasMore = raw.length >= 50;
      final oldest = raw.isNotEmpty
          ? raw.first.createdAt.toIso8601String()
          : null;
      state = state.copyWith(
        messages: raw,
        isLoading: false,
        hasMore: hasMore,
        oldestCursor: oldest,
      );
    } on DioException catch (e) {
      state = state.copyWith(isLoading: false, error: ApiService.parseError(e));
    }
  }

  /// Load messages older than the current oldest, prepending them to the list.
  Future<void> loadOlderMessages(String groupId) async {
    if (!state.hasMore || state.isLoading || state.oldestCursor == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final res = await ApiService.dio.get(
        '/messages/group/$groupId',
        queryParameters: {'limit': 50, 'before': state.oldestCursor},
      );
      final older = (res.data['data'] as List<dynamic>)
          .map((j) => GroupMessage.fromJson(j as Map<String, dynamic>))
          .toList();
      older.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      final combined = [...older, ...state.messages];
      final hasMore = older.length >= 50;
      final oldest = older.isNotEmpty
          ? older.first.createdAt.toIso8601String()
          : state.oldestCursor;
      state = state.copyWith(
        messages: combined,
        isLoading: false,
        hasMore: hasMore,
        oldestCursor: oldest,
      );
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

  // ── Send Text / TTS ────────────────────────────────────────────

  /// Sends a text (or TTS) message. Pass [recipientId] for an individual
  /// thread; omit for a group broadcast. Routes to the correct endpoint.
  Future<bool> sendTextMessage({
    required String groupId,
    String? recipientId,
    required String content,
    required bool isUrgent,
    bool isTts = false,
  }) async {
    state = state.copyWith(isSending: true);
    try {
      final response = await ApiService.dio.post(
        recipientId != null ? '/messages/individual' : '/messages',
        data: {
          'group_id': groupId,
          'recipient_id': ?recipientId,
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

  // ── Send Voice ───────────────────────────────────────────────────────────────

  /// Sends a voice message. Pass [recipientId] for an individual thread;
  /// omit for a group broadcast. Routes to the correct endpoint.
  Future<bool> sendVoiceMessage({
    required String groupId,
    String? recipientId,
    required String filePath,
    required bool isUrgent,
    int durationSeconds = 0,
  }) async {
    state = state.copyWith(isSending: true);
    try {
      final formData = FormData.fromMap({
        'group_id': groupId,
        'recipient_id': ?recipientId,
        'type': 'voice',
        'is_urgent': isUrgent.toString(),
        'duration': durationSeconds.toString(),
        'file': await MultipartFile.fromFile(
          filePath,
          filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        ),
      });
      final response = await ApiService.dio.post(
        recipientId != null ? '/messages/individual' : '/messages',
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
