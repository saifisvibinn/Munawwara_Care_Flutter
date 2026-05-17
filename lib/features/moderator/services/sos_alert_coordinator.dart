import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/speech_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/tts_cloud_api.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../calling/calling_scope.dart';
import '../../notifications/providers/notification_provider.dart';
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
  static String? _openDialogStorageKey;
  static bool _cancelListenersBound = false;

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

  /// Notifies the pilgrim that the moderator **saw** the SOS (dialog appeared).
  /// This updates the pilgrim's status label but does NOT stop the auto-call timer.
  static void emitModeratorHandling({
    required String pilgrimId,
    required String groupId,
    String? sosId,
    String moderatorName = '',
  }) {
    if (pilgrimId.isEmpty || groupId.isEmpty) return;
    final payload = <String, dynamic>{
      'groupId': groupId,
      'pilgrimId': pilgrimId,
      'moderator_name': moderatorName,
    };
    if (sosId != null && sosId.isNotEmpty) payload['sos_id'] = sosId;
    SocketService.emit('sos_handling', payload);
  }

  /// Notifies the pilgrim that the moderator is **actively handling** the SOS
  /// (clicked Review or Navigate — a deliberate action). This stops the
  /// pilgrim's auto-call timer. Only the first moderator to respond counts.
  static void emitModeratorResponding({
    required String pilgrimId,
    required String groupId,
    String? sosId,
    String moderatorName = '',
  }) {
    if (pilgrimId.isEmpty || groupId.isEmpty) return;
    final payload = <String, dynamic>{
      'groupId': groupId,
      'pilgrimId': pilgrimId,
      'moderator_name': moderatorName,
    };
    if (sosId != null && sosId.isNotEmpty) payload['sos_id'] = sosId;
    SocketService.emit('sos_responding', payload);
  }

  static String _getModeratorName() {
    final c = CallingScope.riverpod;
    if (c == null) return '';
    return c.read(authProvider).fullName ?? '';
  }

  /// Cloud TTS (GCS MP3) with local fallback — same pipeline as urgent messages.
  static Future<void> speakAlertForPayload(SosModeratorPayload payload) async {
    final ctx = AppRouter.navigatorKey.currentContext;
    final lang = ctx != null
        ? TtsCloudApi.normalizeLang(ctx.locale.languageCode)
        : 'en';
    final group = payload.groupName.isEmpty ? '—' : payload.groupName;
    final text = 'sos_mod_spoken_alert'.tr(
      namedArgs: {'name': payload.pilgrimName, 'group': group},
    );
    if (text.trim().isEmpty) return;

    AppLogger.i('[SosAlertCoordinator] Speaking SOS alert (lang=$lang)');
    final audioUrl = await TtsCloudApi.fetchAudioUrl(text: text, lang: lang);

    await Future.delayed(kUrgentAlertToTtsDelay);
    await SpeechService.playRobust(
      audioUrl: audioUrl,
      backupText: text,
      lang: lang,
      isUrgent: true,
      messageKey: 'sos_speak_${payload.storageKey}',
      dedupeWindow: _dedupeWindow,
    );
  }

  /// Stops in-progress SOS speech (e.g. pilgrim cancelled).
  static Future<void> stopAlertSpeech() async {
    await SpeechService.stop();
  }

  /// Global socket listener so cancel is handled even off the dashboard route.
  static void bindCancelListeners() {
    if (_cancelListenersBound) return;
    _cancelListenersBound = true;
    SocketService.on('sos-alert-cancelled', _onCancelledSocket);
    SocketService.on('sos_cancel', _onCancelledSocket);
    AppLogger.i('[SosAlertCoordinator] SOS cancel listeners bound');
  }

  static void _onCancelledSocket(dynamic data) {
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    unawaited(handleCancelledFromMap(map));
  }

  /// Pilgrim cancelled SOS: clear UI, tray notification, and local state.
  static Future<void> handleCancelledFromMap(Map<String, dynamic> raw) async {
    await stopAlertSpeech();

    final payload = SosModeratorPayload.fromMap(raw);
    final pid = payload.pilgrimId?.trim() ?? '';
    final gid = payload.groupId?.trim() ?? '';

    dismissOpenSosDialogIfAny();
    NotificationService.clearPendingSosForPilgrim(pid);

    if (pid.isNotEmpty) {
      await NotificationService.dismissSosTrayFor(
        pilgrimId: pid,
        groupId: gid.isEmpty ? null : gid,
        sosId: payload.sosId,
      );

      final c = CallingScope.riverpod;
      final notif = c?.read(notificationProvider.notifier);
      final mod = c?.read(moderatorProvider.notifier);
      mod?.markPilgrimSOS(pid, active: false);
      await ModeratorSosEngagementStore.removeAllEntriesForPilgrim(pid);
      await _refreshEngagementUi();
      notif?.removeSosAlertsForPilgrim(
        pid,
        sosId: payload.sosId,
      );
      // Sync badge + Active SOS tab from server; do not refetch() immediately
      // or stale SOS rows can reappear before DB delete completes.
      unawaited(mod?.loadDashboard(silently: true) ?? Future.value());
      unawaited(notif?.fetchUnreadCount() ?? Future.value());
    }

    _lastShownSosId = null;
    _lastShownAt = null;

    AppLogger.i(
      '[SosAlertCoordinator] SOS cancelled'
      '${pid.isEmpty ? '' : ' pilgrim=$pid'}',
    );
  }

  /// Whether [pilgrimId] still has an active SOS on the moderator dashboard.
  static Future<bool> isPilgrimSosStillActive(String pilgrimId) async {
    if (pilgrimId.isEmpty) return true;
    final c = CallingScope.riverpod;
    if (c == null) return true;
    var groups = c.read(moderatorProvider).groups;
    if (groups.isEmpty) {
      await c.read(moderatorProvider.notifier).loadDashboard(silently: true);
      groups = c.read(moderatorProvider).groups;
    }
    for (final g in groups) {
      for (final p in g.pilgrims) {
        if (p.id == pilgrimId && p.hasSOS) return true;
      }
    }
    return false;
  }

  /// Queues SOS dialog only if the pilgrim still has an active request.
  static Future<void> queueSosAlertIfStillActive(
    Map<String, dynamic> data,
  ) async {
    final payload = SosModeratorPayload.fromMap(data);
    final pid = payload.pilgrimId?.trim() ?? '';
    if (pid.isNotEmpty) {
      final stillActive = await isPilgrimSosStillActive(pid);
      if (!stillActive) {
        AppLogger.i(
          '[SosAlertCoordinator] Stale SOS tap — pilgrim $pid no longer active',
        );
        NotificationService.clearPendingSosForPilgrim(pid);
        await NotificationService.dismissSosTrayFor(
          pilgrimId: pid,
          groupId: payload.groupId,
          sosId: payload.sosId,
        );
        return;
      }
    }
    NotificationService.queuePendingSosAlert(data);
  }

  /// Closes the blocking SOS dialog if it is open.
  static void dismissOpenSosDialogIfAny() {
    if (_openDialogStorageKey == null || _openDialogStorageKey!.isEmpty) {
      return;
    }
    final ctx = AppRouter.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) {
      _openDialogStorageKey = null;
      return;
    }
    final nav = Navigator.of(ctx, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
    }
    _openDialogStorageKey = null;
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
    final pid = payload.pilgrimId?.trim() ?? '';
    if (pid.isNotEmpty) {
      final stillActive = await isPilgrimSosStillActive(pid);
      if (!stillActive) {
        AppLogger.i(
          '[SosAlertCoordinator] SOS no longer active — skip dialog for $pid',
        );
        NotificationService.clearPendingSosForPilgrim(pid);
        await NotificationService.dismissSosTrayFor(
          pilgrimId: pid,
          groupId: payload.groupId,
          sosId: payload.sosId,
        );
        return;
      }
    }
    await ModeratorSosEngagementStore.upsertActiveFromPayload(payload);
    await _refreshEngagementUi();

    final storageKey = payload.storageKey;

    // If another moderator already claimed this SOS on this device, do not show
    // the blocking popup again.
    final myId = CallingScope.riverpod?.read(authProvider).userId ?? '';
    if (myId.isNotEmpty) {
      final all = await ModeratorSosEngagementStore.loadAll();
      final r = all
          .where((e) => e.storageKey == storageKey)
          .cast<ModeratorSosEngagementRecord?>()
          .firstOrNull;
      final claimedBy = r?.handledByModeratorId?.trim() ?? '';
      final status = r?.handledStatus.trim() ?? '';
      if (claimedBy.isNotEmpty && claimedBy != myId && status.isNotEmpty) {
        AppLogger.i(
          '[SosAlertCoordinator] Skipped SOS dialog (claimed by another moderator)',
        );
        return;
      }
    }
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

    unawaited(speakAlertForPayload(payload));

    final groupLabel = payload.groupName.isEmpty ? '—' : payload.groupName;

    final gid = payload.groupId?.trim() ?? '';
    final modName = _getModeratorName();

    _openDialogStorageKey = storageKey;
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
            // Any button click — stop the pilgrim countdown, show "being reviewed"
            if (pid.isNotEmpty && gid.isNotEmpty) {
              emitModeratorHandling(
                pilgrimId: pid,
                groupId: gid,
                sosId: payload.sosId,
                moderatorName: modName,
              );
            }
          },
          onReview: () async {
            Navigator.of(dialogCtx).pop();
            final c = CallingScope.riverpod;
            final mid = c?.read(authProvider).userId ?? '';
            await ModeratorSosEngagementStore.markReviewSuppressed(
              storageKey,
              moderatorId: mid,
              moderatorName: modName,
            );
            await _refreshEngagementUi();
            // Button click — stop pilgrim countdown, show "being reviewed"
            if (pid.isNotEmpty && gid.isNotEmpty) {
              emitModeratorResponding(
                pilgrimId: pid,
                groupId: gid,
                sosId: payload.sosId,
                moderatorName: modName,
              );
            }
            unawaited(_openReviewFlow(payload));
          },
          onNavigateSuccess: () async {
            final next = await ModeratorSosEngagementStore.markNavigatedSuccess(
              storageKey,
            );
            await _refreshEngagementUi();
            // Button click — stop pilgrim countdown, show "being reviewed"
            if (pid.isNotEmpty && gid.isNotEmpty) {
              emitModeratorHandling(
                pilgrimId: pid,
                groupId: gid,
                sosId: payload.sosId,
                moderatorName: modName,
              );
            }
            if (next?.fullyHandled == true) {
              AppRouter.navigatorKey.currentState?.pop();
            }
          },
        );
      },
    );
    if (_openDialogStorageKey == storageKey) _openDialogStorageKey = null;
  }

  static void dismissIfOpenForStorageKey(
    String storageKey, {
    String? reasonMessage,
  }) {
    if (storageKey.isEmpty) return;
    if (_openDialogStorageKey != storageKey) return;
    final ctx = AppRouter.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final nav = Navigator.of(ctx, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
      _openDialogStorageKey = null;
      if (reasonMessage != null && reasonMessage.trim().isNotEmpty) {
        StandardSnackBar.showInfo(ctx, reasonMessage);
      }
    }
  }

  static Future<void> applyClaimedStatusFromMap(
    Map<String, dynamic> raw,
  ) async {
    final c = CallingScope.riverpod;
    if (c == null) return;
    final role = c.read(authProvider).role?.toLowerCase();
    if (role != 'moderator') return;

    final status = raw['status']?.toString() ?? '';
    if (status != 'reviewing' && status != 'in_call') return;

    final pid = raw['pilgrim_id']?.toString() ?? '';
    final gid = raw['group_id']?.toString() ?? '';
    final sid = raw['sos_id']?.toString();
    final modId = raw['moderator_id']?.toString() ?? '';
    final modName = raw['moderator_name']?.toString() ?? '';
    if (pid.isEmpty || gid.isEmpty || modId.isEmpty) return;

    final sk = (sid != null && sid.isNotEmpty) ? sid : 'c_${pid}_$gid';
    await ModeratorSosEngagementStore.upsertModeratorStatus(
      storageKey: sk,
      pilgrimId: pid,
      groupId: gid,
      pilgrimName: raw['pilgrim_name']?.toString() ?? '',
      groupName: raw['group_name']?.toString() ?? '',
      moderatorId: modId,
      moderatorName: modName,
      status: status == 'in_call' ? 'in_call' : 'reviewing',
    );
    await c.read(moderatorSosEngagementProvider.notifier).refresh();

    dismissIfOpenForStorageKey(
      sk,
      reasonMessage: status == 'in_call'
          ? (modName.trim().isEmpty
              ? 'sos_claimed_in_call_other_mod'.tr()
              : 'sos_claimed_in_call_with'.tr(namedArgs: {'name': modName}))
          : (modName.trim().isEmpty
              ? 'sos_claimed_handled_by_other_mod'.tr()
              : 'sos_claimed_being_reviewed_by'.tr(namedArgs: {'name': modName})),
    );
  }

  /// After moderator starts an internet call, refresh banner engagement.
  /// (Do not [Navigator.pop] here — [VoiceCallScreen] may be on top.)
  static Future<void> afterModeratorPlacedCall(String pilgrimId) async {
    final c = CallingScope.riverpod;
    final mid = c?.read(authProvider).userId ?? '';
    final mName = _getModeratorName();
    final entry = await ModeratorSosEngagementStore.markCalledForPilgrim(
      pilgrimId,
    );
    if (mid.isNotEmpty) {
      await ModeratorSosEngagementStore.markInCallForPilgrim(
        pilgrimId,
        moderatorId: mid,
        moderatorName: mName,
      );
    }
    // Broadcast for other moderators immediately.
    if (entry != null && entry.groupId.isNotEmpty) {
      SocketService.emit('sos_in_call', <String, dynamic>{
        'groupId': entry.groupId,
        'pilgrimId': pilgrimId,
        if (entry.sosId != null && entry.sosId!.isNotEmpty) 'sos_id': entry.sosId,
        'moderator_name': mName,
      });
    }
    await _refreshEngagementUi();
  }

  /// After moderator ends a call with a pilgrim — send "responding" signal
  /// so the pilgrim's card switches to "being handled right now" with a
  /// greyed-out cancel button. Re-uses the engagement store to look up the
  /// active SOS context for [pilgrimId].
  static Future<void> afterModeratorEndedCall(String pilgrimId) async {
    final c = CallingScope.riverpod;
    final mid = c?.read(authProvider).userId ?? '';
    // markCalledForPilgrim finds the best active SOS entry for this pilgrim.
    // We just need it for group_id / sos_id — the "called" mark is a bonus.
    final entry = await ModeratorSosEngagementStore.markCalledForPilgrim(
      pilgrimId,
    );
    if (entry == null) return; // no active SOS for this pilgrim
    final gid = entry.groupId;
    final sid = entry.sosId;
    final modName = _getModeratorName();
    if (mid.isNotEmpty) {
      await ModeratorSosEngagementStore.markReviewingForPilgrim(
        pilgrimId,
        moderatorId: mid,
        moderatorName: modName,
      );
      await _refreshEngagementUi();
    }
    if (gid.isNotEmpty) {
      emitModeratorResponding(
        pilgrimId: pilgrimId,
        groupId: gid,
        sosId: sid,
        moderatorName: modName,
      );
    }
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
