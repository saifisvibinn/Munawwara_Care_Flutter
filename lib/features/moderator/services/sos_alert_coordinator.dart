import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../calling/calling_scope.dart';
import '../models/sos_moderator_payload.dart';
import '../providers/moderator_provider.dart';
import '../providers/moderator_sos_engagement_provider.dart';
import '../widgets/pilgrim_profile_sheet.dart';
import '../widgets/sos_alert_dialog.dart';
import 'moderator_sos_engagement_store.dart';

/// Dedupes and shows one in-app SOS dialog per [sosId] (or per burst if id
/// missing).
class SosAlertCoordinator {
  SosAlertCoordinator._();

  static String? _lastShownSosId;
  static DateTime? _lastShownAt;
  static const _dedupeWindow = Duration(seconds: 4);

  /// Set after IDE hot reload so a replayed socket/FCM SOS or reset dedupe
  /// state does not immediately show the full-screen moderator dialog again.
  static DateTime? _suppressDialogsUntil;

  /// Called from app `reassemble()` (debug/profile hot reload only).
  static void suppressInAppSosAlertsFor(Duration duration) {
    if (kReleaseMode) return;
    _suppressDialogsUntil = DateTime.now().add(duration);
    AppLogger.i(
      '[SosAlertCoordinator] In-app SOS dialogs suppressed for '
      '${duration.inSeconds}s (post hot-reload window)',
    );
  }

  static Future<void> _refreshEngagementUi() async {
    final c = CallingScope.riverpod;
    await c?.read(moderatorSosEngagementProvider.notifier).refresh();
  }

  /// Notifies the pilgrim app so the SOS **auto-call** timer is cancelled
  /// (moderator is viewing / engaging, not ignoring the request).
  static void emitModeratorHandling({
    required String pilgrimId,
    required String groupId,
    String? sosId,
  }) {
    if (pilgrimId.isEmpty || groupId.isEmpty) return;
    final handling = <String, dynamic>{
      'groupId': groupId,
      'pilgrimId': pilgrimId,
    };
    if (sosId != null && sosId.isNotEmpty) handling['sos_id'] = sosId;
    SocketService.emit('sos_handling', handling);
  }

  /// Unified entry for socket payload, FCM `data`, or pending deep-link map.
  static Future<void> showOnceFromMap(Map<String, dynamic> raw) async {
    final until = _suppressDialogsUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      AppLogger.i(
        '[SosAlertCoordinator] Skipped SOS dialog (post hot-reload quiet '
        'window)',
      );
      return;
    }

    final payload = SosModeratorPayload.fromMap(raw);
    await ModeratorSosEngagementStore.upsertActiveFromPayload(payload);
    await _refreshEngagementUi();

    final storageKey = payload.storageKey;
    final showModal =
        await ModeratorSosEngagementStore.shouldShowBlockingModal(storageKey);
    if (!showModal) {
      AppLogger.i(
        '[SosAlertCoordinator] Blocking modal suppressed for $storageKey',
      );
      return;
    }

    final sid = payload.sosId;
    if (sid != null && sid.isNotEmpty) {
      if (_lastShownSosId == sid &&
          _lastShownAt != null &&
          DateTime.now().difference(_lastShownAt!) < _dedupeWindow) {
        AppLogger.i('[SosAlertCoordinator] Deduped duplicate sos_id=$sid');
        return;
      }
      _lastShownSosId = sid;
      _lastShownAt = DateTime.now();
    } else {
      final composite =
          '${payload.pilgrimId ?? ""}|${payload.groupId ?? ""}|'
          '${payload.pilgrimName}';
      if (_lastShownSosId == composite &&
          _lastShownAt != null &&
          DateTime.now().difference(_lastShownAt!) < _dedupeWindow) {
        return;
      }
      _lastShownSosId = composite;
      _lastShownAt = DateTime.now();
    }

    final nav = AppRouter.navigatorKey.currentState;
    final ctx = AppRouter.navigatorKey.currentContext;
    if (nav == null || ctx == null || !ctx.mounted) {
      AppLogger.w(
        '[SosAlertCoordinator] No navigator — caller should use pending SOS',
      );
      return;
    }

    final groupLabel = payload.groupName.isEmpty ? '—' : payload.groupName;

    final pid = payload.pilgrimId;
    final gid = payload.groupId;
    if (pid != null && pid.isNotEmpty && gid != null && gid.isNotEmpty) {
      emitModeratorHandling(
        pilgrimId: pid,
        groupId: gid,
        sosId: payload.sosId,
      );
    }

    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return SosAlertDialog(
          pilgrimName: payload.pilgrimName,
          groupName: groupLabel,
          pilgrimGender: payload.pilgrimGender,
          navigateLat: payload.lat,
          navigateLng: payload.lng,
          onDismiss: () async {
            Navigator.of(dialogCtx).pop();
            await ModeratorSosEngagementStore.markUserDismissed(storageKey);
            await _refreshEngagementUi();
          },
          onReview: () async {
            Navigator.of(dialogCtx).pop();
            await ModeratorSosEngagementStore.markReviewSuppressed(storageKey);
            await _refreshEngagementUi();
            unawaited(_openReviewFlow(payload));
          },
          onNavigateSuccess: () async {
            final next = await ModeratorSosEngagementStore.markNavigatedSuccess(
              storageKey,
            );
            await _refreshEngagementUi();
            if (next?.fullyHandled == true) {
              AppRouter.navigatorKey.currentState?.pop();
            }
          },
        );
      },
    );
  }

  /// After moderator starts an internet call, refresh banner engagement.
  /// (Do not [Navigator.pop] here — [VoiceCallScreen] may be on top.)
  static Future<void> afterModeratorPlacedCall(String pilgrimId) async {
    await ModeratorSosEngagementStore.markCalledForPilgrim(pilgrimId);
    await _refreshEngagementUi();
  }

  static Future<void> _openReviewFlow(SosModeratorPayload payload) async {
    final c = CallingScope.riverpod;
    if (c == null) {
      AppLogger.e('[SosAlertCoordinator] CallingScope.riverpod is null');
      return;
    }

    final gid = payload.groupId;
    final pid = payload.pilgrimId;
    if (gid != null && gid.isNotEmpty && pid != null && pid.isNotEmpty) {
      emitModeratorHandling(
        pilgrimId: pid,
        groupId: gid,
        sosId: payload.sosId,
      );
    }

    await c.read(moderatorProvider.notifier).loadDashboard(silently: true);

    PilgrimInGroup? target;
    final groups = c.read(moderatorProvider).groups;
    if (gid != null && pid != null) {
      for (final g in groups) {
        if (g.id == gid) {
          try {
            target = g.pilgrims.firstWhere((p) => p.id == pid);
          } catch (_) {}
          break;
        }
      }
    }

    final sheetCtx = AppRouter.navigatorKey.currentContext;
    final currentUserId = c.read(authProvider).userId ?? '';

    if (sheetCtx != null &&
        sheetCtx.mounted &&
        target != null &&
        gid != null &&
        gid.isNotEmpty) {
      showPilgrimProfileSheet(
        sheetCtx,
        target,
        gid,
        currentUserId,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final snackCtx = AppRouter.navigatorKey.currentContext;
        if (snackCtx != null && snackCtx.mounted) {
          StandardSnackBar.showInfo(
            snackCtx,
            'sos_mod_sheet_call_hint'.tr(),
          );
        }
      });
    } else {
      final snackCtx = AppRouter.navigatorKey.currentContext;
      if (snackCtx != null && snackCtx.mounted) {
        StandardSnackBar.showInfo(
          snackCtx,
          'sos_mod_pilgrim_not_loaded'.tr(),
        );
      }
    }
  }
}
