import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/open_maps_navigation.dart';
import '../../moderator/providers/moderator_resolved_sos_provider.dart';
import '../../moderator/providers/moderator_sos_engagement_provider.dart';
import '../../moderator/services/moderator_sos_engagement_store.dart';
import '../../moderator/widgets/moderator_resolved_sos_list.dart';
import '../../moderator/services/sos_alert_coordinator.dart';
import '../models/notification_model.dart';
import '../providers/notification_provider.dart';
import '../../moderator/providers/moderator_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../moderator/widgets/moderator_active_sos_panel.dart';
import '../../moderator/widgets/pilgrim_profile_sheet.dart';
import 'package:dio/dio.dart';
import '../../../core/services/api_service.dart';
import '../../../core/widgets/custom_dialog.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../pilgrim/providers/pilgrim_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Alerts Tab — shown when the user taps "Alerts" in the bottom nav
// ─────────────────────────────────────────────────────────────────────────────

(double, double)? _sosAlertNotificationLatLng(Map<String, dynamic>? data) {
  if (data == null) return null;
  double? lat;
  double? lng;
  final loc = data['location'];
  if (loc is Map) {
    final m = Map<String, dynamic>.from(loc);
    lat =
        (m['lat'] as num?)?.toDouble() ??
        double.tryParse(m['lat']?.toString() ?? '');
    lng =
        (m['lng'] as num?)?.toDouble() ??
        double.tryParse(m['lng']?.toString() ?? '');
  }
  lat ??= double.tryParse(data['lat']?.toString() ?? '');
  lng ??= double.tryParse(data['lng']?.toString() ?? '');
  if (lat == null || lng == null) return null;
  return (lat, lng);
}

class AlertsTab extends ConsumerStatefulWidget {
  final VoidCallback? onBack;
  const AlertsTab({super.key, this.onBack});

  @override
  ConsumerState<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends ConsumerState<AlertsTab>
    with SingleTickerProviderStateMixin {
  TabController? _moderatorTabController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationProvider.notifier).fetch();
      if (ref.read(authProvider).role == 'moderator') {
        unawaited(
          ref.read(moderatorSosEngagementProvider.notifier).refresh(),
        );
        unawaited(
          ref.read(moderatorResolvedSosProvider.notifier).refresh(),
        );
      }
    });
  }

  @override
  void dispose() {
    _moderatorTabController?.dispose();
    super.dispose();
  }

  void _ensureModeratorTabController() {
    if (_moderatorTabController != null) return;
    if (ref.read(authProvider).role != 'moderator') return;
    _moderatorTabController = TabController(length: 3, vsync: this);
  }

  Future<void> _acceptInvitation(String invId) async {
    try {
      StandardDialog.showLoading(context);

      final res = await ApiService.dio.post('/invitations/$invId/accept');

      if (!mounted) return;
      StandardDialog.hide(context); // close dialog

      if (res.statusCode == 200 || res.statusCode == 201) {
        // Reload dashboard so groupInfo is populated
        final role = ref.read(authProvider).role;
        if (role == 'moderator') {
          await ref.read(moderatorProvider.notifier).loadDashboard();
        } else {
          await ref.read(pilgrimProvider.notifier).loadDashboard();
        }

        ref.read(notificationProvider.notifier).fetch();

        if (!mounted) return;

        StandardSnackBar.showSuccess(
          context,
          res.data['message']?.toString() ?? 'Invitation accepted!',
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      StandardDialog.hide(context); // close dialog

      StandardSnackBar.showError(context, ApiService.parseError(e));
    } catch (e) {
      if (!mounted) return;
      StandardDialog.hide(context); // close dialog

      StandardSnackBar.showError(context, 'An unexpected error occurred');
    }
  }

  Future<void> _declineInvitation(String invId) async {
    try {
      StandardDialog.showLoading(context);

      final res = await ApiService.dio.post('/invitations/$invId/decline');

      if (!mounted) return;
      StandardDialog.hide(context); // close dialog

      if (res.statusCode == 200 || res.statusCode == 201) {
        // Remove or update the notification by fetching
        ref.read(notificationProvider.notifier).fetch();

        StandardSnackBar.showSuccess(
          context,
          res.data['message']?.toString() ?? 'Invitation declined.',
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      StandardDialog.hide(context); // close dialog

      StandardSnackBar.showError(context, ApiService.parseError(e));
    } catch (e) {
      if (!mounted) return;
      StandardDialog.hide(context); // close dialog

      StandardSnackBar.showError(context, 'An unexpected error occurred');
    }
  }

  Future<void> _refreshAlerts() async {
    await ref.read(notificationProvider.notifier).fetch();
    if (ref.read(authProvider).role == 'moderator') {
      await ref.read(moderatorSosEngagementProvider.notifier).refresh();
      await ref.read(moderatorResolvedSosProvider.notifier).refresh();
    }
  }

  Widget _notificationsList({
    required bool isDark,
    required NotificationState state,
  }) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (state.error != null) {
      return _ErrorView(
        error: state.error!,
        onRetry: () => ref.read(notificationProvider.notifier).fetch(),
      );
    }
    if (state.notifications.isEmpty) {
      return const _EmptyView();
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshAlerts,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 100.h),
        itemCount: state.notifications.length,
        separatorBuilder: (_, _) => SizedBox(height: 8.h),
        itemBuilder: (ctx, i) {
          final n = state.notifications[i];
          return _NotificationTile(
            notification: n,
            isDark: isDark,
            onDelete: () =>
                ref.read(notificationProvider.notifier).delete(n.id),
            onAcceptInvitation: (id) => _acceptInvitation(id),
            onDeclineInvitation: (id) => _declineInvitation(id),
          );
        },
      ),
    );
  }

  Widget _moderatorActiveSosTab({
    required bool isDark,
    required List<ModeratorGroup> modGroups,
  }) {
    final engagements =
        ref.watch(moderatorSosEngagementProvider).value ?? [];
    final rows = buildModeratorSosBannerRows(modGroups, engagements);
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Text(
            'moderator_active_sos_empty'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : AppColors.textMutedDark,
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshAlerts,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
        children: [
          ModeratorActiveSosPanel(
            groups: modGroups,
            onSosResolved: () {
              _moderatorTabController?.animateTo(1);
            },
          ),
        ],
      ),
    );
  }

  Widget _moderatorResolvedSosTab({required bool isDark}) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refreshAlerts,
      child: ModeratorResolvedSosList(isDark: isDark),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isModerator = ref.watch(authProvider).role == 'moderator';
    final modGroups = isModerator
        ? ref.watch(moderatorProvider).groups
        : <ModeratorGroup>[];

    if (isModerator) {
      _ensureModeratorTabController();
    }

    final header = Padding(
      padding: EdgeInsets.fromLTRB(
        widget.onBack != null ? 4.w : 20.w,
        16.h,
        20.w,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.onBack != null)
            IconButton(
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: isDark ? Colors.white : AppColors.textDark,
                size: 20.sp,
              ),
              onPressed: widget.onBack,
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'alerts_title'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 24.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'alerts_subtitle'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13.sp,
                    color: AppColors.textMutedLight,
                  ),
                ),
              ],
            ),
          ),
          if (state.notifications.any((n) => n.read))
            TextButton(
              onPressed: () =>
                  ref.read(notificationProvider.notifier).clearRead(),
              child: Text(
                'alerts_clear_read'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );

    if (isModerator && _moderatorTabController != null) {
      final tc = _moderatorTabController!;
      return SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            SizedBox(height: 8.h),
            TabBar(
              controller: tc,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textMutedLight,
              indicatorColor: AppColors.primary,
              labelStyle: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 12.sp,
              ),
              unselectedLabelStyle: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
                fontSize: 12.sp,
              ),
              tabs: [
                Tab(text: 'moderator_alerts_tab_active_sos'.tr()),
                Tab(text: 'moderator_alerts_tab_resolved'.tr()),
                Tab(text: 'moderator_alerts_tab_all'.tr()),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: tc,
                children: [
                  _moderatorActiveSosTab(
                    isDark: isDark,
                    modGroups: modGroups,
                  ),
                  _moderatorResolvedSosTab(isDark: isDark),
                  _notificationsList(isDark: isDark, state: state),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          SizedBox(height: 12.h),
          Expanded(
            child: _notificationsList(isDark: isDark, state: state),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification tile — swipe right to dismiss
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationTile extends ConsumerWidget {
  final AppNotification notification;
  final bool isDark;
  final VoidCallback onDelete;
  final void Function(String)? onAcceptInvitation;
  final void Function(String)? onDeclineInvitation;

  const _NotificationTile({
    required this.notification,
    required this.isDark,
    required this.onDelete,
    this.onAcceptInvitation,
    this.onDeclineInvitation,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final bg = isDark ? const Color(0xFF1A2C24) : Colors.white;
    final bool isInvitation = n.type == 'group_invitation';

    Widget content = Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16.r),
        border: n.read
            ? null
            : Border(left: BorderSide(color: n.iconColor, width: 3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(14.w),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon chip
            Container(
              width: 38.w,
              height: 38.w,
              decoration: BoxDecoration(
                color: isDark ? AppColors.iconBgDark : AppColors.iconBgLight,
                shape: BoxShape.circle,
              ),
              child: Icon(n.icon, size: 18.w, color: n.iconColor),
            ),
            SizedBox(width: 12.w),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: n.read
                                ? FontWeight.w500
                                : FontWeight.w700,
                            fontSize: 13.sp,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        _formatDate(n.createdAt),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 10.sp,
                          color: AppColors.textMutedLight,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    n.message,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : AppColors.textMutedLight,
                      height: 1.4,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  // Type badge + inline action button row
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 2.h,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.iconBgDark
                              : AppColors.iconBgLight,
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                        child: Text(
                          n.typeLabel.toUpperCase(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 9.sp,
                            fontWeight: FontWeight.w700,
                            color: n.iconColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (n.type == 'sos_alert' &&
                          n.data?['pilgrim_id'] != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_sosAlertNotificationLatLng(n.data) !=
                                null) ...[
                              GestureDetector(
                                onTap: () async {
                                  final d = n.data!;
                                  final pId = d['pilgrim_id']?.toString() ?? '';
                                  final gId = d['group_id']?.toString() ?? '';
                                  final sidStr = d['sos_id']?.toString();
                                  if (pId.isNotEmpty && gId.isNotEmpty) {
                                    SosAlertCoordinator.emitModeratorHandling(
                                      pilgrimId: pId,
                                      groupId: gId,
                                      sosId: sidStr,
                                    );
                                  }
                                  final ll = _sosAlertNotificationLatLng(
                                    n.data,
                                  )!;
                                  final ok =
                                      await OpenMapsNavigation.confirmAndLaunch(
                                        context,
                                        ll.$1,
                                        ll.$2,
                                      );
                                  if (!ok || !context.mounted) return;
                                  final sid =
                                      n.data!['sos_id']?.toString() ?? '';
                                  if (sid.isNotEmpty) {
                                    await ModeratorSosEngagementStore.markNavigatedSuccess(
                                      sid,
                                    );
                                    await ref
                                        .read(
                                          moderatorSosEngagementProvider
                                              .notifier,
                                        )
                                        .refresh();
                                  }
                                },
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10.w,
                                    vertical: 4.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(8.r),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Symbols.navigation,
                                        size: 12.w,
                                        color: Colors.white,
                                        fill: 1,
                                      ),
                                      SizedBox(width: 4.w),
                                      Text(
                                        'explore_navigate'.tr(),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10.sp,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(width: 6.w),
                            ],
                            GestureDetector(
                              onTap: () {
                                final d = n.data!;
                                final pId = d['pilgrim_id'] as String;
                                final gId = d['group_id'] as String?;
                                final sidStr = d['sos_id']?.toString();
                                if (gId != null &&
                                    gId.isNotEmpty &&
                                    pId.isNotEmpty) {
                                  SosAlertCoordinator.emitModeratorHandling(
                                    pilgrimId: pId,
                                    groupId: gId,
                                    sosId: sidStr,
                                  );
                                }
                                final modState = ref.read(moderatorProvider);
                                PilgrimInGroup? pilgrim;
                                for (final g in modState.groups) {
                                  try {
                                    pilgrim = g.pilgrims.firstWhere(
                                      (p) => p.id == pId,
                                    );
                                    break;
                                  } catch (_) {}
                                }
                                if (pilgrim != null && gId != null) {
                                  final uid =
                                      ref.read(authProvider).userId ?? '';
                                  showPilgrimProfileSheet(
                                    context,
                                    pilgrim,
                                    gId,
                                    uid,
                                  );
                                } else {
                                  StandardSnackBar.showWarning(
                                    context,
                                    'Pilgrim not found in your groups',
                                  );
                                }
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 10.w,
                                  vertical: 4.h,
                                ),
                                decoration: BoxDecoration(
                                  color: n.iconColor,
                                  borderRadius: BorderRadius.circular(8.r),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Symbols.person,
                                      size: 12.w,
                                      color: Colors.white,
                                      fill: 1,
                                    ),
                                    SizedBox(width: 4.w),
                                    Text(
                                      'View Profile',
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 10.sp,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  // Navigate button for area/meetpoint notifications
                  if ((n.type == 'suggested_area' || n.type == 'meetpoint') &&
                      n.data?['location'] != null) ...[
                    SizedBox(height: 8.h),
                    GestureDetector(
                      onTap: () {
                        final loc = n.data!['location'] as Map<String, dynamic>;
                        final lat = (loc['lat'] as num).toDouble();
                        final lng = (loc['lng'] as num).toDouble();
                        final url = Uri.parse(
                          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
                        );
                        launchUrl(url, mode: LaunchMode.externalApplication);
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 7.h,
                        ),
                        decoration: BoxDecoration(
                          color: n.iconColor,
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Symbols.navigation,
                              size: 14.w,
                              color: Colors.white,
                              fill: 1,
                            ),
                            SizedBox(width: 4.w),
                            Text(
                              'area_navigate'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w700,
                                fontSize: 11.sp,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  // Join Group button for group invitations
                  if (n.type == 'group_invitation') ...[
                    SizedBox(height: 8.h),
                    if (n.data?['status'] != null)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 5.h,
                        ),
                        decoration: BoxDecoration(
                          color: n.data!['status'] == 'accepted'
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(
                            color: n.data!['status'] == 'accepted'
                                ? Colors.green.shade400
                                : Colors.red.shade400,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              n.data!['status'] == 'accepted'
                                  ? Symbols.check_circle
                                  : Symbols.cancel,
                              size: 14.w,
                              color: n.data!['status'] == 'accepted'
                                  ? Colors.green.shade400
                                  : Colors.red.shade400,
                              fill: 1,
                            ),
                            SizedBox(width: 6.w),
                            Text(
                              (n.data!['status'] == 'accepted'
                                      ? 'invite_status_accepted'
                                      : 'invite_status_declined')
                                  .tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w700,
                                fontSize: 11.sp,
                                color: n.data!['status'] == 'accepted'
                                    ? Colors.green.shade400
                                    : Colors.red.shade400,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              final invId = n.data?['invitation_id']
                                  ?.toString();
                              if (invId != null && onAcceptInvitation != null) {
                                onAcceptInvitation!(invId);
                              } else {
                                StandardSnackBar.showError(
                                  context,
                                  'Invalid invitation data',
                                );
                              }
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12.w,
                                vertical: 7.h,
                              ),
                              decoration: BoxDecoration(
                                color: n.iconColor,
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Symbols.group_add,
                                    size: 14.w,
                                    color: Colors.white,
                                    fill: 1,
                                  ),
                                  SizedBox(width: 4.w),
                                  Text(
                                    'invite_accept'.tr(),
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11.sp,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          GestureDetector(
                            onTap: () {
                              final invId = n.data?['invitation_id']
                                  ?.toString();
                              if (invId != null &&
                                  onDeclineInvitation != null) {
                                onDeclineInvitation!(invId);
                              } else {
                                StandardSnackBar.showError(
                                  context,
                                  'Invalid invitation data',
                                );
                              }
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12.w,
                                vertical: 7.h,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                border: Border.all(
                                  color: Colors.red.shade400,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Symbols.close,
                                    size: 14.w,
                                    color: Colors.red.shade400,
                                    fill: 1,
                                  ),
                                  SizedBox(width: 4.w),
                                  Text(
                                    'invite_decline'.tr(),
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11.sp,
                                      color: Colors.red.shade400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ],
              ),
            ),
            // Unread dot
            if (!n.read) ...[
              SizedBox(width: 6.w),
              Container(
                width: 8.w,
                height: 8.w,
                decoration: BoxDecoration(
                  color: n.iconColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (isInvitation) {
      return content;
    }

    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: 20.w),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16.r),
        ),
        child: Icon(Symbols.delete, color: Colors.white, size: 22.w),
      ),
      onDismissed: (_) => onDelete(),
      child: content,
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'alerts_just_now'.tr();
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(date);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / Error states
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.notifications_off,
            size: 56.w,
            color: AppColors.textMutedLight,
          ),
          SizedBox(height: 12.h),
          Text(
            'alerts_empty'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textMutedLight,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            "alerts_all_caught_up".tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              color: AppColors.textMutedLight,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.error_outline, size: 48.w, color: Colors.red.shade400),
          SizedBox(height: 12.h),
          Text(
            error,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              color: AppColors.textMutedLight,
            ),
          ),
          SizedBox(height: 16.h),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Symbols.refresh),
            label: Text('alerts_retry'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
