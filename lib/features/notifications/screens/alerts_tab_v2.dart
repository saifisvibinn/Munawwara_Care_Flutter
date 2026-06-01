import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../calling/data/call_history_api.dart';
import '../../calling/widgets/call_history_list_view.dart';
import '../../moderator/providers/moderator_provider.dart';
import '../../moderator/providers/moderator_resolved_sos_provider.dart';
import '../../moderator/providers/moderator_sos_engagement_provider.dart';
import '../../moderator/widgets/moderator_active_sos_panel.dart';
import '../../moderator/widgets/moderator_resolved_sos_list.dart';
import '../../../core/services/notification_service.dart';
import '../providers/notification_provider.dart';
import '../widgets/moderator_updates_tab.dart';

/// Alerts Tab
///
/// - Moderator: Active SOS, Resolved SOS, Call history (missed included)
/// - Pilgrim: Call history (full list, or [pilgrimMissedCallsOnly] when opened
///   from the home missed-calls entry).
///
/// The old "All alerts" notification list was removed.
class AlertsTab extends ConsumerStatefulWidget {
  final VoidCallback? onBack;

  /// Pilgrim only: show only missed calls (e.g. home badge). Moderators ignore.
  final bool pilgrimMissedCallsOnly;

  /// Moderator only: open a specific alerts sub-tab (0–3).
  final int? initialModeratorTabIndex;

  const AlertsTab({
    super.key,
    this.onBack,
    this.pilgrimMissedCallsOnly = false,
    this.initialModeratorTabIndex,
  });

  @override
  ConsumerState<AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends ConsumerState<AlertsTab>
    with SingleTickerProviderStateMixin {
  TabController? _moderatorTabController;
  int _moderatorTabIndex = 0;
  int _callHistoryReloadSeed = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // When opening Alerts, mark notifications as read so the bell badge
      // reflects "still unread" notifications only.
      unawaited(ref.read(notificationProvider.notifier).fetch(markAllAsRead: true));
      unawaited(NotificationService.onAlertsTabOpened());
      if (ref.read(authProvider).role == 'moderator') {
        unawaited(ref.read(moderatorSosEngagementProvider.notifier).refresh());
        unawaited(ref.read(moderatorResolvedSosProvider.notifier).refresh());
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
    final initial = widget.initialModeratorTabIndex?.clamp(0, 3) ?? 0;
    _moderatorTabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: initial,
    );
    _moderatorTabIndex = initial;
    _moderatorTabController!.addListener(() {
      if (!mounted) return;
      final next = _moderatorTabController!.index;
      if (_moderatorTabIndex == next) return;
      setState(() => _moderatorTabIndex = next);
    });
  }

  Future<void> _refresh() async {
    if (ref.read(authProvider).role == 'moderator') {
      await ref.read(moderatorSosEngagementProvider.notifier).refresh();
      await ref.read(moderatorResolvedSosProvider.notifier).refresh();
      await ref.read(notificationProvider.notifier).refetch();
    }
  }

  Future<void> _clearResolvedSos() async {
    await ref.read(moderatorResolvedSosProvider.notifier).clearAll();
  }

  Future<void> _clearCallHistory() async {
    await CallHistoryApi.clearCallHistory();
    if (!mounted) return;
    setState(() => _callHistoryReloadSeed++);
  }

  Widget _header({required bool isDark, required bool isModerator}) {
    final showClearResolved = isModerator && _moderatorTabIndex == 1;
    final showClearCalls = !isModerator || _moderatorTabIndex == 2;
    return Padding(
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
          if (showClearResolved)
            TextButton(
              onPressed: _clearResolvedSos,
              child: Text(
                'clear_resolved_sos'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          if (showClearCalls)
            TextButton(
              onPressed: _clearCallHistory,
              child: Text(
                'clear_call_history'.tr(),
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
  }

  Widget _moderatorActiveSosTab({
    required List<ModeratorGroup> groups,
  }) {
    final engagements = ref.watch(moderatorSosEngagementProvider).value ?? [];
    final rows = buildModeratorSosBannerRows(groups, engagements);
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
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white70
                  : AppColors.textMutedDark,
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
        children: [
          ModeratorActiveSosPanel(
            groups: groups,
            onSosResolved: () => _moderatorTabController?.animateTo(1),
          ),
        ],
      ),
    );
  }

  Widget _moderatorResolvedSosTab({required bool isDark}) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refresh,
      child: ModeratorResolvedSosList(isDark: isDark),
    );
  }

  Widget _callHistoryTab({required bool missedOnly, required bool isModerator}) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refresh,
      child: CallHistoryListView(
        key: ValueKey('${_callHistoryReloadSeed}_$missedOnly'),
        missedOnly: missedOnly,
        highlightUnreadMissed: !isModerator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isModerator = ref.watch(authProvider).role == 'moderator';
    final groups =
        isModerator ? ref.watch(moderatorProvider).groups : <ModeratorGroup>[];

    if (isModerator) _ensureModeratorTabController();

    if (isModerator && _moderatorTabController != null) {
      final tc = _moderatorTabController!;
      return SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(isDark: isDark, isModerator: true),
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
                Tab(text: 'call_history_title'.tr()),
                Tab(text: 'alerts_tab_updates'.tr()),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: tc,
                children: [
                  _moderatorActiveSosTab(groups: groups),
                  _moderatorResolvedSosTab(isDark: isDark),
                  _callHistoryTab(missedOnly: false, isModerator: true),
                  RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _refresh,
                    child: const ModeratorUpdatesTab(),
                  ),
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
          _header(isDark: isDark, isModerator: false),
          SizedBox(height: 12.h),
          Expanded(
            child: _callHistoryTab(
              missedOnly: widget.pilgrimMissedCallsOnly,
              isModerator: false,
            ),
          ),
        ],
      ),
    );
  }
}

