import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../moderator/providers/moderator_provider.dart';
import '../models/group_invitation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class PendingInvitationsState {
  final List<GroupInvitation> invitations;
  final bool isLoading;
  final String? error;
  final String? actionInvitationId;

  const PendingInvitationsState({
    this.invitations = const [],
    this.isLoading = false,
    this.error,
    this.actionInvitationId,
  });

  PendingInvitationsState copyWith({
    List<GroupInvitation>? invitations,
    bool? isLoading,
    String? error,
    String? actionInvitationId,
    bool clearError = false,
    bool clearAction = false,
  }) {
    return PendingInvitationsState(
      invitations: invitations ?? this.invitations,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      actionInvitationId: clearAction
          ? null
          : (actionInvitationId ?? this.actionInvitationId),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class PendingInvitationsNotifier extends Notifier<PendingInvitationsState> {
  @override
  PendingInvitationsState build() => const PendingInvitationsState();

  /// Loads pending invitations for the signed-in user (invitee).
  Future<void> fetchPending() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await ApiService.dio.get('/invitations');
      final data = res.data;
      final List<dynamic> raw;
      if (data is List) {
        raw = data;
      } else if (data is Map<String, dynamic>) {
        raw = data['invitations'] as List<dynamic>? ?? [];
      } else {
        raw = [];
      }
      final list = raw
          .map((e) => GroupInvitation.fromJson(e as Map<String, dynamic>))
          .where((i) => i.id.isNotEmpty && i.status == 'pending')
          .toList();
      state = state.copyWith(invitations: list, isLoading: false);
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: ApiService.parseError(e),
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<bool> accept(String invitationId) async {
    state = state.copyWith(actionInvitationId: invitationId, clearError: true);
    try {
      final res = await ApiService.dio.post(
        '/invitations/$invitationId/accept',
      );
      final body = res.data as Map<String, dynamic>? ?? {};
      final groupId = body['group_id']?.toString();
      if (groupId != null && groupId.isNotEmpty) {
        SocketService.emit('join_group', groupId);
      }
      await ref.read(moderatorProvider.notifier).loadDashboard(force: true);
      await fetchPending();
      state = state.copyWith(clearAction: true);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(
        error: ApiService.parseError(e),
        clearAction: true,
      );
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString(), clearAction: true);
      return false;
    }
  }

  Future<bool> decline(String invitationId) async {
    state = state.copyWith(actionInvitationId: invitationId, clearError: true);
    try {
      await ApiService.dio.post('/invitations/$invitationId/decline');
      await fetchPending();
      state = state.copyWith(clearAction: true);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(
        error: ApiService.parseError(e),
        clearAction: true,
      );
      return false;
    } catch (e) {
      state = state.copyWith(error: e.toString(), clearAction: true);
      return false;
    }
  }
}

final pendingInvitationsProvider =
    NotifierProvider<PendingInvitationsNotifier, PendingInvitationsState>(
      PendingInvitationsNotifier.new,
    );
