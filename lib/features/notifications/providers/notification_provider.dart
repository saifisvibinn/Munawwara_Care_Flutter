import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/app_data_cache.dart';
import '../../../core/services/secure_session_store.dart';
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

  Future<void> _hydrateFromCache() async {
    final uid = await SecureSessionStore.getUserId();
    if (uid == null) return;
    final data = AppDataCache.jsonMap(
      await AppDataCache.readData(uid, AppDataCache.notificationsFile),
    );
    if (data == null || data['success'] != true) return;
    try {
      final rawList = data['notifications'];
      if (rawList is! List<dynamic>) return;
      final list = <AppNotification>[];
      for (final e in rawList) {
        final em = AppDataCache.jsonMap(e);
        if (em == null) continue;
        try {
          list.add(AppNotification.fromJson(em));
        } catch (_) {}
      }
      final unread = data['unread_count'] as int? ?? 0;
      state = state.copyWith(notifications: list, unreadCount: unread);
    } catch (_) {}
  }

  Future<void> _persistNotifications(Map<String, dynamic> data) async {
    final uid = await SecureSessionStore.getUserId();
    if (uid == null) return;
    await AppDataCache.write(uid, AppDataCache.notificationsFile, data);
  }

  // ── Fetch all notifications ───────────────────────────────────────────────
  Future<void> fetch({bool markAllAsRead = false}) async {
    await _hydrateFromCache();
    state = state.copyWith(isLoading: true, error: null);
    try {
      final res = await ApiService.dio.get('/notifications');
      final data = res.data as Map<String, dynamic>;
      if (data['success'] == true) {
        await _persistNotifications(data);
        final list = (data['notifications'] as List)
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
        final unread = data['unread_count'] as int? ?? 0;
        state = state.copyWith(
          notifications: list,
          unreadCount: unread,
          isLoading: false,
        );
        // Only mark read when the user is explicitly viewing Alerts.
        if (markAllAsRead && unread > 0) {
          await _markAllReadRemote();
          state = state.copyWith(
            unreadCount: 0,
            notifications: state.notifications
                .map((n) => n.copyWith(read: true))
                .toList(),
          );
        }
      } else {
        state = state.copyWith(isLoading: false, error: 'Failed to load');
      }
    } on DioException catch (e) {
      if (state.notifications.isEmpty) {
        await _hydrateFromCache();
      }
      if (state.notifications.isNotEmpty) {
        state = state.copyWith(isLoading: false, error: null);
      } else {
        state = state.copyWith(
          isLoading: false,
          error: ApiService.parseError(e),
        );
      }
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
        await _persistNotifications(data);
        final list = (data['notifications'] as List)
            .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
            .toList();
        final unread = data['unread_count'] as int? ?? 0;
        state = state.copyWith(notifications: list, unreadCount: unread);
      }
    } catch (_) {}
  }

  /// Removes SOS rows for [pilgrimId] (and optional [sosId]) from bell/badge state.
  static String? _normalizeId(dynamic value) {
    if (value == null) return null;
    if (value is Map) {
      final nested = value['_id'] ?? value['id'];
      return nested?.toString().trim();
    }
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  void removeSosAlertsForPilgrim(String pilgrimId, {String? sosId}) {
    if (pilgrimId.isEmpty && (sosId == null || sosId.isEmpty)) return;
    final targetPid = pilgrimId.trim();
    final targetSid = sosId?.trim() ?? '';
    var removedUnread = 0;
    final kept = state.notifications.where((n) {
      if (n.type != 'sos_alert') return true;
      final pid = _normalizeId(n.data?['pilgrim_id'] ?? n.data?['pilgrimId']);
      final sid = _normalizeId(n.data?['sos_id'] ?? n.data?['sosId']);
      final matchPilgrim =
          targetPid.isNotEmpty && pid != null && pid == targetPid;
      final matchSos =
          targetSid.isNotEmpty && sid != null && sid == targetSid;
      final match = matchPilgrim || matchSos;
      if (match && !n.read) removedUnread++;
      return !match;
    }).toList();
    if (kept.length == state.notifications.length) return;
    final unread = (state.unreadCount - removedUnread).clamp(0, 999999);
    state = state.copyWith(notifications: kept, unreadCount: unread);
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
