import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/open_maps_navigation.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/services/api_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../auth/providers/auth_provider.dart';
import 'package:dio/dio.dart';
import '../../notifications/providers/notification_provider.dart';
import '../providers/moderator_provider.dart';
import '../providers/moderator_resolved_sos_provider.dart';
import '../providers/moderator_sos_engagement_provider.dart';
import '../services/moderator_resolved_sos_store.dart';
import '../services/moderator_sos_engagement_store.dart';
import '../services/sos_alert_coordinator.dart';
import '../../shared/widgets/pilgrim_gender_avatar.dart';
import 'pilgrim_profile_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Active SOS — moderator alerts tab (single incident per pilgrim + group)
// ─────────────────────────────────────────────────────────────────────────────

ModeratorSosEngagementRecord? latestModeratorSosEngagementFor(
  List<ModeratorSosEngagementRecord> list,
  String pilgrimId,
  String groupId,
) {
  ModeratorSosEngagementRecord? best;
  for (final r in list) {
    if (!r.active) continue;
    if (r.pilgrimId != pilgrimId) continue;
    if (r.groupId != groupId) continue;
    if (best == null || r.updatedAtMs > best.updatedAtMs) best = r;
  }
  return best;
}

/// True when the moderator should see the Active SOS panel somewhere.
bool moderatorHasActiveSosAlerts(
  List<ModeratorGroup> groups,
  List<ModeratorSosEngagementRecord> engagements,
) {
  for (final g in groups) {
    for (final p in g.pilgrims) {
      if (!p.hasSOS) continue;
      final rec = latestModeratorSosEngagementFor(engagements, p.id, g.id);
      if (rec != null && rec.fullyHandled) continue;
      return true;
    }
  }
  for (final r in engagements) {
    if (r.active && !r.fullyHandled && r.blockingSuppressed) {
      return true;
    }
  }
  return false;
}

class ModeratorSosBannerRow {
  ModeratorSosBannerRow({
    required this.group,
    required this.pilgrim,
    this.record,
  });

  final ModeratorGroup? group;
  final PilgrimInGroup? pilgrim;
  final ModeratorSosEngagementRecord? record;

  String get displayName => pilgrim?.fullName ?? record?.pilgrimName ?? '';

  String get groupLabel => group?.groupName ?? record?.groupName ?? '';

  bool get isClaimedByOtherModerator {
    final r = record;
    if (r == null) return false;
    final hid = r.handledByModeratorId?.trim() ?? '';
    if (hid.isEmpty) return false;
    final myId = SocketService.connectedUserId ?? '';
    if (myId.isEmpty) return false;
    return hid != myId;
  }

  String get claimedStatusLabel {
    final r = record;
    if (r == null) return '';
    final name = r.handledByModeratorName.trim();
    if (name.isEmpty) return '';
    switch (r.handledStatus) {
      case 'in_call':
        return 'sos_claimed_in_call_with'.tr(namedArgs: {'name': name});
      case 'reviewing':
        return 'sos_claimed_being_reviewed_by'.tr(namedArgs: {'name': name});
      default:
        return '';
    }
  }

  double? get lat => record?.lat ?? pilgrim?.lat;

  double? get lng => record?.lng ?? pilgrim?.lng;

  String? get storageKey => record?.storageKey;

  int get sortMs =>
      record?.updatedAtMs ?? pilgrim?.lastUpdated?.millisecondsSinceEpoch ?? 0;
}

List<ModeratorSosBannerRow> buildModeratorSosBannerRows(
  List<ModeratorGroup> groups,
  List<ModeratorSosEngagementRecord> engagements,
) {
  final rows = <ModeratorSosBannerRow>[];
  final seen = <String>{};

  for (final g in groups) {
    for (final p in g.pilgrims) {
      if (!p.hasSOS) continue;
      final rec = latestModeratorSosEngagementFor(engagements, p.id, g.id);
      if (rec != null && rec.fullyHandled) continue;
      final key = rec?.storageKey ?? 'g_${p.id}_${g.id}';
      if (seen.contains(key)) continue;
      seen.add(key);
      rows.add(
        ModeratorSosBannerRow(group: g, pilgrim: p, record: rec),
      );
    }
  }

  for (final r in engagements) {
    if (!r.active || r.fullyHandled || !r.blockingSuppressed) continue;
    if (seen.contains(r.storageKey)) continue;
    seen.add(r.storageKey);
    ModeratorGroup? g;
    PilgrimInGroup? p;
    for (final gg in groups) {
      if (gg.id != r.groupId) continue;
      g = gg;
      try {
        p = gg.pilgrims.firstWhere((x) => x.id == r.pilgrimId);
      } catch (_) {}
      break;
    }
    rows.add(ModeratorSosBannerRow(group: g, pilgrim: p, record: r));
  }

  rows.sort((a, b) => b.sortMs.compareTo(a.sortMs));
  return _dedupeModeratorSosRows(rows);
}

/// One row per pilgrim + group so duplicate store keys cannot multiply cards.
List<ModeratorSosBannerRow> _dedupeModeratorSosRows(
  List<ModeratorSosBannerRow> rows,
) {
  final bestByPg = <String, ModeratorSosBannerRow>{};
  final byOrphanSk = <String, ModeratorSosBannerRow>{};
  final noKey = <ModeratorSosBannerRow>[];

  for (final r in rows) {
    final pid = r.pilgrim?.id ?? r.record?.pilgrimId ?? '';
    final gid = r.group?.id ?? r.record?.groupId ?? '';
    if (pid.isNotEmpty && gid.isNotEmpty) {
      final k = '$pid|$gid';
      final prev = bestByPg[k];
      if (prev == null || r.sortMs > prev.sortMs) bestByPg[k] = r;
    } else {
      final sk = r.record?.storageKey ?? '';
      if (sk.isEmpty) {
        noKey.add(r);
      } else {
        final prev = byOrphanSk[sk];
        if (prev == null || r.sortMs > prev.sortMs) byOrphanSk[sk] = r;
      }
    }
  }

  final out = <ModeratorSosBannerRow>[
    ...noKey,
    ...bestByPg.values,
    ...byOrphanSk.values,
  ];
  out.sort((a, b) => b.sortMs.compareTo(a.sortMs));
  return out;
}

/// Stacked SOS cards for the moderator Alerts tab.
class ModeratorActiveSosPanel extends ConsumerWidget {
  final List<ModeratorGroup> groups;
  /// After marking resolved: refresh lists and optionally switch to All alerts.
  final VoidCallback? onSosResolved;

  const ModeratorActiveSosPanel({
    super.key,
    required this.groups,
    this.onSosResolved,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engagements = ref.watch(moderatorSosEngagementProvider).value ?? [];
    final rows = buildModeratorSosBannerRows(groups, engagements);
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: 14.h),
          ModeratorSosBannerCard(
            row: rows[i],
            onSosResolved: onSosResolved,
          ),
        ],
      ],
    );
  }
}

String _formatSosAlertTimestamp(BuildContext context, int updatedAtMs) {
  if (updatedAtMs <= 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
  final locale = context.locale.toString();
  final time = DateFormat.jm(locale).format(dt);
  final date = DateFormat.MMMd(locale).format(dt);
  return '$time • $date';
}

class ModeratorSosBannerCard extends ConsumerWidget {
  final ModeratorSosBannerRow row;
  final VoidCallback? onSosResolved;

  const ModeratorSosBannerCard({
    super.key,
    required this.row,
    this.onSosResolved,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasNav = row.lat != null && row.lng != null;
    final canShowClaimed = row.isClaimedByOtherModerator &&
        row.claimedStatusLabel.isNotEmpty;

    Future<void> resolveSos() async {
      final gId = row.group?.id ?? row.record?.groupId;
      final pId = row.pilgrim?.id ?? row.record?.pilgrimId;
      final sosId = row.record?.sosId;
      if (gId == null || gId.isEmpty || pId == null || pId.isEmpty) {
        StandardSnackBar.showWarning(
          context,
          'sos_mod_pilgrim_not_loaded'.tr(),
        );
        return;
      }

      if (row.isClaimedByOtherModerator) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            return AlertDialog(
              title: Text('sos_claimed_resolve_title'.tr()),
              content: Text('sos_claimed_resolve_body'.tr()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text('dialog_cancel'.tr()),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text('sos_claimed_resolve_anyway'.tr()),
                ),
              ],
            );
          },
        );
        if (confirmed != true || !context.mounted) return;
      }

      final payload = <String, dynamic>{
        'groupId': gId,
        'pilgrimId': pId,
      };
      if (sosId != null && sosId.isNotEmpty) {
        payload['sos_id'] = sosId;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final resolved = ModeratorResolvedSosRecord(
        resolveKey: '${pId}_${gId}_$now',
        pilgrimId: pId,
        groupId: gId,
        pilgrimName: row.displayName,
        groupName: row.groupLabel.isEmpty ? '—' : row.groupLabel,
        sosId: sosId,
        lat: row.lat,
        lng: row.lng,
        resolvedAtMs: now,
      );
      final modProv = ref.read(moderatorProvider.notifier);
      final resProv = ref.read(moderatorResolvedSosProvider.notifier);
      final engProv = ref.read(moderatorSosEngagementProvider.notifier);
      final notifProv = ref.read(notificationProvider.notifier);

      // 1. Emit via socket (for real-time responsiveness when online)
      try {
        SocketService.emit('sos_resolve', payload);
      } catch (e) {
        AppLogger.e('[ModeratorActiveSosPanel] Socket emit failed: $e');
      }

      // 2. Call HTTP fallback (guarantees delivery across network drops)
      try {
        await ApiService.dio.post(
          '/auth/groups/$gId/pilgrims/$pId/resolve-sos',
          data: {
            if (sosId != null && sosId.isNotEmpty) 'sos_id': sosId,
          },
        );
      } on DioException catch (e) {
        AppLogger.e('[ModeratorActiveSosPanel] HTTP resolve fallback failed: $e');
        // If it's a real API failure (e.g. 403 Forbidden / 404), show error snackbar
        // and abort local optimistic updates.
        if (e.response != null && e.response!.statusCode != null) {
          final code = e.response!.statusCode!;
          if (code >= 400 && code < 500) {
            if (context.mounted) {
              StandardSnackBar.showError(
                context,
                ApiService.parseError(e),
              );
            }
            return;
          }
        }
        // For other network/timeout errors, we allow it to proceed locally so that the moderator
        // can at least clear their local UI during offline/poor network conditions.
      } catch (e) {
        AppLogger.e('[ModeratorActiveSosPanel] General resolve error: $e');
      }

      modProv.markPilgrimSOS(pId, active: false);
      await ModeratorSosEngagementStore.removeAllEntriesForPilgrim(pId);
      await resProv.addResolved(resolved);
      await engProv.refresh();
      await modProv.loadDashboard(silently: true);
      notifProv.removeSosAlertsForPilgrim(pId, sosId: sosId);
      await notifProv.fetchUnreadCount();
      
      if (!context.mounted) return;
      onSosResolved?.call();
      StandardSnackBar.showSuccess(
        context,
        'sos_moderator_resolve_sent'.tr(),
      );
    }

    Future<void> navigateToSos() async {
      if (!hasNav) return;
      final p = row.pilgrim;
      final g = row.group;
      if (p != null && g != null) {
        SosAlertCoordinator.emitModeratorHandling(
          pilgrimId: p.id,
          groupId: g.id,
          sosId: row.record?.sosId,
        );
      }
      final engProv = ref.read(moderatorSosEngagementProvider.notifier);
      final ok = await OpenMapsNavigation.confirmAndLaunch(
        context,
        row.lat!,
        row.lng!,
      );
      if (!ok || !context.mounted) return;
      final sk = row.storageKey;
      if (sk != null) {
        final next = await ModeratorSosEngagementStore.markNavigatedSuccess(sk);
        await engProv.refresh();
        if (next?.fullyHandled == true && context.mounted) {
          StandardSnackBar.showInfo(
            context,
            'sos_mod_handling_complete_hint'.tr(),
          );
        }
      }
    }

    void viewDetails() {
      final g = row.group;
      final p = row.pilgrim;
      if (g == null || p == null) {
        StandardSnackBar.showWarning(
          context,
          'sos_mod_pilgrim_not_loaded'.tr(),
        );
        return;
      }
      SosAlertCoordinator.emitModeratorHandling(
        pilgrimId: p.id,
        groupId: g.id,
        sosId: row.record?.sosId,
      );
      final uid = ref.read(authProvider).userId ?? '';
      showPilgrimProfileSheet(context, p, g.id, uid);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final timestamp = _formatSosAlertTimestamp(context, row.sortMs);
    final pilgrim = row.pilgrim;

    return Container(
      padding: EdgeInsets.fromLTRB(18.w, 18.h, 18.w, 16.h),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : const Color(0xFFF1F5F9),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SosCardAvatar(
                gender: pilgrim?.gender ?? row.record?.pilgrimGender,
                imageUrl: pilgrim?.profilePicture,
                size: 52.w,
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'sos_active_alert_title'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w800,
                        fontSize: 17.sp,
                        color: textPrimary,
                      ),
                    ),
                    if (timestamp.isNotEmpty) ...[
                      SizedBox(height: 4.h),
                      Text(
                        timestamp,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          Text(
            'dashboard_sos_banner_subtitle'.tr(
              namedArgs: {
                'name': row.displayName,
                'group': row.groupLabel.isEmpty ? '—' : row.groupLabel,
              },
            ),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: textMuted,
              height: 1.45,
            ),
          ),
          if (canShowClaimed) ...[
            SizedBox(height: 12.h),
            Row(
              children: [
                Icon(
                  row.record?.handledStatus == 'in_call'
                      ? Symbols.call
                      : Symbols.person,
                  size: 18.sp,
                  color: textMuted,
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    row.claimedStatusLabel,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 16.h),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: resolveSos,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF2563EB)),
                    foregroundColor: const Color(0xFF2563EB),
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                  icon: Icon(Symbols.check_circle, size: 18.sp, fill: 1),
                  label: Text(
                    'sos_moderator_resolve'.tr(),
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasNav ? navigateToSos : null,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.accentGold),
                    foregroundColor: AppColors.accentGold,
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                  icon: Icon(Symbols.navigation, size: 18.sp, fill: 1),
                  label: Text(
                    'explore_navigate'.tr(),
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: viewDetails,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 14.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28.r),
                ),
              ),
              child: Text(
                'sos_view_details'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 15.sp,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pilgrim portrait with SOS warning badge for alert cards.
class _SosCardAvatar extends StatelessWidget {
  final String? gender;
  final String? imageUrl;
  final double size;

  const _SosCardAvatar({
    required this.gender,
    required this.imageUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final badgeSize = size * 0.36;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.error, width: 2),
              color: const Color(0xFFFFE4E6),
            ),
            child: ClipOval(
              child: PilgrimGenderAvatar(
                gender: gender,
                size: size,
                imageUrl: imageUrl,
              ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Icon(
                Symbols.warning,
                color: Colors.white,
                size: badgeSize * 0.58,
                fill: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
