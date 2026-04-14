import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_service.dart';
import '../../../core/utils/app_logger.dart';
import '../models/reminder_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class ReminderState {
  final List<ReminderModel> reminders;
  final bool isLoading;
  final String? error;

  const ReminderState({
    this.reminders = const [],
    this.isLoading = false,
    this.error,
  });

  ReminderState copyWith({
    List<ReminderModel>? reminders,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return ReminderState(
      reminders: reminders ?? this.reminders,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class ReminderNotifier extends Notifier<ReminderState> {
  @override
  ReminderState build() => const ReminderState();

  // ── Load reminders for a group ───────────────────────────────────────────
  Future<void> load(String groupId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await ApiService.dio.get(
        '/reminders',
        queryParameters: {'group_id': groupId},
      );
      final list = (response.data['reminders'] as List? ?? [])
          .map((j) => ReminderModel.fromJson(j as Map<String, dynamic>))
          .toList();
      state = state.copyWith(reminders: list, isLoading: false);
    } catch (e) {
      AppLogger.e('[ReminderProvider] load error: $e');
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load reminders',
      );
    }
  }

  // ── Create reminder ───────────────────────────────────────────────────────
  Future<bool> create({
    required String groupId,
    required String targetType,
    String? pilgrimId,
    required String text,
    required DateTime scheduledAt,
    required int repeatCount,
    required int repeatIntervalMin,
  }) async {
    try {
      final response = await ApiService.dio.post(
        '/reminders',
        data: {
          'group_id': groupId,
          'target_type': targetType,
          'pilgrim_id': pilgrimId,
          'text': text,
          'scheduled_at': scheduledAt.toUtc().toIso8601String(),
          'repeat_count': repeatCount,
          'repeat_interval_min': repeatIntervalMin,
        },
      );
      final created = ReminderModel.fromJson(
        response.data['reminder'] as Map<String, dynamic>,
      );
      state = state.copyWith(reminders: [created, ...state.reminders]);
      AppLogger.i('[ReminderProvider] Created reminder ${created.id}');
      return true;
    } catch (e) {
      AppLogger.e('[ReminderProvider] create error: $e');
      state = state.copyWith(error: 'Failed to create reminder');
      return false;
    }
  }

  // ── Cancel reminder (soft – status → cancelled, kept in DB) ───────────────
  Future<void> cancel(String reminderId) async {
    try {
      await ApiService.dio.patch('/reminders/$reminderId/cancel');
      state = state.copyWith(
        reminders: state.reminders
            .map(
              (r) => r.id == reminderId
                  ? ReminderModel(
                      id: r.id,
                      groupId: r.groupId,
                      targetType: r.targetType,
                      pilgrimId: r.pilgrimId,
                      pilgrimName: r.pilgrimName,
                      text: r.text,
                      scheduledAt: r.scheduledAt,
                      repeatCount: r.repeatCount,
                      repeatIntervalMin: r.repeatIntervalMin,
                      status: 'cancelled',
                      firesSent: r.firesSent,
                      createdAt: r.createdAt,
                    )
                  : r,
            )
            .toList(),
      );
    } catch (e) {
      AppLogger.e('[ReminderProvider] cancel error: $e');
    }
  }

  // ── Hard-delete reminder (removed from DB entirely) ──────────────────────
  Future<void> delete(String reminderId) async {
    // Optimistically remove from state immediately
    state = state.copyWith(
      reminders: state.reminders.where((r) => r.id != reminderId).toList(),
    );
    try {
      await ApiService.dio.delete('/reminders/$reminderId');
      AppLogger.i('[ReminderProvider] Deleted reminder $reminderId');
    } catch (e) {
      AppLogger.e('[ReminderProvider] delete error: $e');
      // Reload to restore accurate state on failure
      if (state.reminders.isNotEmpty) {
        await load(state.reminders.first.groupId);
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final reminderProvider = NotifierProvider<ReminderNotifier, ReminderState>(
  ReminderNotifier.new,
);
