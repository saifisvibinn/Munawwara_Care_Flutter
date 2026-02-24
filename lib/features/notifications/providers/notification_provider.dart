import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_service.dart';
import '../models/notification_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class NotificationState {
  final List<AppNotification> notifications;
  final bool isLoading;
  final String? error;
  final int unreadCount;

  const NotificationState({
    this.notifications = const [],
    this.isLoading = false,
    this.error,
    this.unreadCount = 0,
  });

  NotificationState copyWith({
    List<AppNotification>? notifications,
    bool? isLoading,
    String? error,
    int? unreadCount,
  }) {
    return NotificationState(
      notifications: notifications ?? this.notifications,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class NotificationNotifier extends Notifier<NotificationState> {
  @override
  NotificationState build() => const NotificationState();

  // ── Fetch all notifications ───────────────────────────────────────────────
  Future<void> fetch() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await ApiService.dio.get('/notifications');
      final data = res.data as Map<String, dynamic>;
      if (data['success'] == true) {
        final list = (data['notifications'] as List)
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
        final unread = data['unread_count'] as int? ?? 0;
        state = state.copyWith(
          notifications: list,
          unreadCount: unread,
          isLoading: false,
        );
        // Auto-mark all as read once fetched
        if (unread > 0) {
          await _markAllReadRemote();
          state = state.copyWith(
            unreadCount: 0,
            notifications:
                state.notifications.map((n) => n.copyWith(read: true)).toList(),
          );
        }
      } else {
        state = state.copyWith(isLoading: false, error: 'Failed to load');
      }
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: ApiService.parseError(e),
      );
    }
  }

  // ── Fetch unread count only (for badge) ──────────────────────────────────
  Future<void> fetchUnreadCount() async {
    try {
      final res = await ApiService.dio.get('/notifications/unread-count');
      final data = res.data as Map<String, dynamic>;
      if (data['success'] == true) {
        state = state.copyWith(unreadCount: data['unread_count'] as int? ?? 0);
      }
    } catch (_) {}
  }

  // ── Silent refresh (socket push) — updates list + badge without marking read ──
  Future<void> refetch() async {
    try {
      final res = await ApiService.dio.get('/notifications');
      final data = res.data as Map<String, dynamic>;
      if (data['success'] == true) {
        final list = (data['notifications'] as List)
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
        final unread = data['unread_count'] as int? ?? 0;
        state = state.copyWith(
          notifications: list,
          unreadCount: unread,
        );
      }
    } catch (_) {}
  }

  // ── Delete single notification ────────────────────────────────────────────
  Future<void> delete(String id) async {
    final prev = state.notifications;
    state = state.copyWith(
      notifications: state.notifications.where((n) => n.id != id).toList(),
    );
    try {
      await ApiService.dio.delete('/notifications/$id');
    } catch (_) {
      // Rollback on failure
      state = state.copyWith(notifications: prev);
    }
  }

  // ── Clear all read notifications ─────────────────────────────────────────
  Future<void> clearRead() async {
    final prev = state.notifications;
    state = state.copyWith(
      notifications: state.notifications.where((n) => !n.read).toList(),
    );
    try {
      await ApiService.dio.delete('/notifications/read');
    } catch (_) {
      state = state.copyWith(notifications: prev);
    }
  }

  Future<void> _markAllReadRemote() async {
    try {
      await ApiService.dio.put('/notifications/read-all');
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final notificationProvider =
    NotifierProvider<NotificationNotifier, NotificationState>(
  NotificationNotifier.new,
);
