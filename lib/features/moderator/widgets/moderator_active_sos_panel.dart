import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/open_maps_navigation.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../notifications/providers/notification_provider.dart';
import '../providers/moderator_provider.dart';
import '../providers/moderator_resolved_sos_provider.dart';
import '../providers/moderator_sos_engagement_provider.dart';
import '../services/moderator_resolved_sos_store.dart';
import '../services/moderator_sos_engagement_store.dart';
import '../services/sos_alert_coordinator.dart';
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

/// Carousel + cards for open SOS incidents (moderator Alerts tab).
class ModeratorActiveSosPanel extends ConsumerStatefulWidget {
  final List<ModeratorGroup> groups;
  /// After marking resolved: refresh lists and optionally switch to All alerts.
  final VoidCallback? onSosResolved;

  const ModeratorActiveSosPanel({
    super.key,
    required this.groups,
    this.onSosResolved,
  });

  @override
  ConsumerState<ModeratorActiveSosPanel> createState() =>
      _ModeratorActiveSosPanelState();
}

class _ModeratorActiveSosPanelState
    extends ConsumerState<ModeratorActiveSosPanel> {
  static const _carouselViewportFraction = 0.88;

  PageController? _pageController;
  int _currentPage = 0;

  PageController _carouselController() => _pageController ??= PageController(
    viewportFraction: _carouselViewportFraction,
  );

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engagementAsync = ref.watch(moderatorSosEngagementProvider);
    final engagements = engagementAsync.value ?? [];
    final rows = buildModeratorSosBannerRows(widget.groups, engagements);
    if (rows.isEmpty) return const SizedBox.shrink();

    if (rows.length == 1) {
      return ModeratorSosBannerCard(
        row: rows.first,
        onSosResolved: widget.onSosResolved,
      );
    }

    final pc = _carouselController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !pc.hasClients) return;
      final maxIdx = rows.length - 1;
      if (_currentPage > maxIdx) {
        setState(() => _currentPage = maxIdx);
        pc.jumpToPage(maxIdx);
      }
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 232.h,
          child: PageView.builder(
            controller: pc,
            itemCount: rows.length,
            padEnds: true,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                child: ModeratorSosBannerCard(
                  row: rows[index],
                  onSosResolved: widget.onSosResolved,
                ),
              );
            },
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'dashboard_sos_swipe_hint'.tr(
            namedArgs: {
              'current': '${_currentPage + 1}',
              'total': '${rows.length}',
            },
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 11.sp,
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.textMutedLight
                : AppColors.textMutedDark,
          ),
        ),
        SizedBox(height: 6.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(rows.length, (i) {
            final active = i == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              margin: EdgeInsets.symmetric(horizontal: 3.w),
              width: active ? 20.w : 7.w,
              height: 7.w,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4.r),
                color: active
                    ? const Color(0xFFDC2626)
                    : const Color(0xFFDC2626).withValues(alpha: 0.28),
              ),
            );
          }),
        ),
      ],
    );
  }
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
      SocketService.emit('sos_resolve', payload);
      ref.read(moderatorProvider.notifier).markPilgrimSOS(pId, active: false);
      await ModeratorSosEngagementStore.removeAllEntriesForPilgrim(pId);
      await ref.read(moderatorResolvedSosProvider.notifier).addResolved(resolved);
      await ref.read(moderatorSosEngagementProvider.notifier).refresh();
      await ref.read(moderatorProvider.notifier).loadDashboard(silently: true);
      await ref.read(notificationProvider.notifier).refetch();
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
      final ok = await OpenMapsNavigation.confirmAndLaunch(
        context,
        row.lat!,
        row.lng!,
      );
      if (!ok || !context.mounted) return;
      final sk = row.storageKey;
      if (sk != null) {
        final next = await ModeratorSosEngagementStore.markNavigatedSuccess(sk);
        await ref.read(moderatorSosEngagementProvider.notifier).refresh();
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

    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 14.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        border: Border.all(color: const Color(0xFFFDE5C6)),
        borderRadius: BorderRadius.circular(18.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFE4E6),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Symbols.warning,
                  color: Color(0xFFDC2626),
                  size: 22.w,
                  fill: 1,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'sos_active_alert_title'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w800,
                        fontSize: 16.sp,
                        color: AppColors.textDark,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'dashboard_sos_banner_subtitle'.tr(
                        namedArgs: {
                          'name': row.displayName,
                          'group': row.groupLabel.isEmpty ? '—' : row.groupLabel,
                        },
                      ),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMutedDark,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
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
                  color: AppColors.textMutedDark,
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    row.claimedStatusLabel,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMutedDark,
                    ),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 14.h),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: resolveSos,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD6B48C)),
                    foregroundColor: const Color(0xFFD6B48C),
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                  icon: Icon(Symbols.check_circle, size: 18.sp, fill: 1),
                  label: Text(
                    'sos_moderator_resolve'.tr(),
                    style: const TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: hasNav ? navigateToSos : null,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD6B48C)),
                    foregroundColor: const Color(0xFFD6B48C),
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                  icon: Icon(Symbols.navigation, size: 18.sp, fill: 1),
                  label: Text(
                    'explore_navigate'.tr(),
                    style: const TextStyle(fontFamily: 'Lexend'),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 170.w,
              child: FilledButton(
                onPressed: viewDetails,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18.r),
                  ),
                ),
                child: Text(
                  'dashboard_view'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 13.sp,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
