import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../calling/providers/call_provider.dart';
import '../../calling/screens/voice_call_screen.dart';
import '../../../main.dart' show isNavigatingToCall;
import '../../notifications/providers/notification_provider.dart';
import '../../notifications/screens/alerts_tab.dart';
import '../providers/moderator_provider.dart';
import 'create_group_screen.dart';
import 'moderator_profile_screen.dart';
import 'group_management_screen.dart';
import 'moderator_group_map_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Moderator Dashboard Screen
// ─────────────────────────────────────────────────────────────────────────────

class ModeratorDashboardScreen extends ConsumerStatefulWidget {
  const ModeratorDashboardScreen({super.key});

  @override
  ConsumerState<ModeratorDashboardScreen> createState() =>
      _ModeratorDashboardScreenState();
}

class _ModeratorDashboardScreenState
    extends ConsumerState<ModeratorDashboardScreen> {
  int _currentTab = 0; // 0=Home, 1=Alerts
  final _searchController = TextEditingController();
  final _alertTts = FlutterTts();

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Join every group room so we receive group-scoped socket events (SOS, etc.)
  void _joinAllGroupRooms() {
    for (final g in ref.read(moderatorProvider).groups) {
      SocketService.emit('join_group', g.id);
    }
  }

  /// Named reconnect callback so offConnected can remove it.
  void _onSocketConnected() {
    if (mounted) _joinAllGroupRooms();
  }

  Future<void> _onSosAlertArrived(dynamic data) async {
    if (!mounted) return;
    // Refresh the alerts list immediately
    ref.read(notificationProvider.notifier).fetch();
    // Auto-navigate to Alerts tab so the moderator sees it
    setState(() => _currentTab = 1);
    // Speak the alert aloud
    final map = data is Map ? data : <String, dynamic>{};
    final name = map['pilgrim_name'] as String? ?? 'A pilgrim';
    await _alertTts.setVolume(1.0);
    await _alertTts.setSpeechRate(0.42);
    await _alertTts.speak('SOS Alert! $name needs immediate help!');
    // Show a persistent red SnackBar
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.r),
        ),
        content: Row(
          children: [
            const Icon(Symbols.sos, color: Colors.white, size: 22),
            SizedBox(width: 10.w),
            Expanded(
              child: Text(
                '🚨 SOS — $name',
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 14.sp,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () => setState(() => _currentTab = 1),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(moderatorProvider.notifier).loadDashboard();
      // Connect socket with this moderator's identity
      final auth = ref.read(authProvider);
      if (auth.userId != null) {
        final socketUrl = ApiService.baseUrl.replaceFirst(RegExp(r'/api$'), '');
        SocketService.connect(
          serverUrl: socketUrl,
          userId: auth.userId!,
          role: auth.role ?? 'moderator',
        );
        // Make sure call provider's listeners are registered
        ref.read(callProvider.notifier).reRegisterListeners();
        // Check if there's a pending call accepted from native call screen
        ref.read(callProvider.notifier).checkPendingAcceptedCall();
        // Fetch unread notification count for badge
        ref.read(notificationProvider.notifier).fetchUnreadCount();
        // Join all group rooms so we receive SOS events
        _joinAllGroupRooms();
        // Re-join on reconnect
        SocketService.onConnected(_onSocketConnected);
        // Listen for real-time SOS alerts
        SocketService.on('sos-alert-received', _onSosAlertArrived);
        // Listen for SOS cancellations
        SocketService.on('sos-alert-cancelled', (_) {
          if (!mounted) return;
          _alertTts.stop();
          ref.read(notificationProvider.notifier).fetch();
        });
        // Listen for missed calls — refresh notification badge + list
        SocketService.on('missed-call-received', (_) {
          if (!mounted) return;
          ref.read(notificationProvider.notifier).refetch();
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _alertTts.stop();
    SocketService.off('sos-alert-received');
    SocketService.off('sos-alert-cancelled');
    SocketService.off('missed-call-received');
    SocketService.offConnected(_onSocketConnected);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Fallback: if an incoming call was accepted and we're connected,
    // navigate to VoiceCallScreen from here.
    ref.listen(callProvider, (prev, next) {
      if (next.status == CallStatus.connected &&
          prev?.status == CallStatus.ringing &&
          mounted &&
          !isNavigatingToCall &&
          !VoiceCallScreen.isActive) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const VoiceCallScreen()));
      }
    });

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : const Color(0xFFF0F0F8),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _GroupsHomeTab(searchController: _searchController),
          const AlertsTab(),
        ],
      ),
      floatingActionButton: SizedBox(
        width: 56.w,
        height: 56.w,
        child: FloatingActionButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CreateGroupScreen())),
          backgroundColor: const Color(0xFFF97316),
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          elevation: 6,
          child: Icon(Symbols.add, size: 28.w),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _ModBottomNav(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Groups Home Tab
// ─────────────────────────────────────────────────────────────────────────────

class _GroupsHomeTab extends ConsumerStatefulWidget {
  final TextEditingController searchController;
  const _GroupsHomeTab({required this.searchController});

  @override
  ConsumerState<_GroupsHomeTab> createState() => _GroupsHomeTabState();
}

class _GroupsHomeTabState extends ConsumerState<_GroupsHomeTab> {
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(() {
      if (mounted) {
        setState(
          () => _searchQuery = widget.searchController.text.toLowerCase(),
        );
      }
    });
  }

  List<ModeratorGroup> _filtered(List<ModeratorGroup> groups) {
    if (_searchQuery.isEmpty) return groups;
    return groups
        .where((g) => g.groupName.toLowerCase().contains(_searchQuery))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(moderatorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groups = _filtered(state.groups);
    final anySOS = state.groups.any((g) => g.sosCount > 0);

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async =>
            ref.read(moderatorProvider.notifier).loadDashboard(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Header + search ──
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'dashboard_my_groups'.tr(),
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w800,
                                  fontSize: 28.sp,
                                  color: isDark
                                      ? Colors.white
                                      : const Color(0xFF1A1A4E),
                                ),
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                'dashboard_subtitle'.tr(),
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 13.sp,
                                  color: AppColors.textMutedLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ModeratorProfileScreen(),
                            ),
                          ),
                          child: Container(
                            width: 44.w,
                            height: 44.w,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF383018)
                                  : const Color(0xFFEEEEFB),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF5A4A28)
                                    : const Color(0xFFD0D0F0),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Symbols.person,
                              size: 22.w,
                              color: isDark
                                  ? const Color(0xFFD4B896)
                                  : const Color(0xFF8A6A30),
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 20.h),

                    // SOS Alert Banner
                    if (anySOS) ...[
                      _SosAlertBanner(groups: state.groups),
                      SizedBox(height: 16.h),
                    ],

                    // Search + Filter row
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 48.h,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF272210)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14.r),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF383018)
                                    : const Color(0xFFE2E2F0),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: widget.searchController,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 14.sp,
                                color: isDark
                                    ? const Color(0xFFE2E8F0)
                                    : AppColors.textDark,
                              ),
                              decoration: InputDecoration(
                                hintText: 'dashboard_search_groups'.tr(),
                                hintStyle: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14.sp,
                                  color: AppColors.textMutedLight,
                                ),
                                prefixIcon: Icon(
                                  Symbols.search,
                                  size: 20.w,
                                  color: AppColors.textMutedLight,
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 14.h,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Container(
                          width: 48.w,
                          height: 48.h,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF272210)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF383018)
                                  : const Color(0xFFE2E2F0),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Icon(
                            Symbols.tune,
                            size: 20.w,
                            color: isDark
                                ? const Color(0xFFD4B896)
                                : const Color(0xFF8A6A30),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: 20.h),
                  ],
                ),
              ),
            ),

            // ── Loading ──
            if (state.isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                ),
              ),

            // ── Error ──
            if (!state.isLoading && state.error != null && state.groups.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 20.w,
                    vertical: 32.h,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Symbols.wifi_off,
                        size: 48.w,
                        color: AppColors.textMutedLight,
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        state.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 14.sp,
                          color: AppColors.textMutedLight,
                        ),
                      ),
                      SizedBox(height: 16.h),
                      TextButton.icon(
                        onPressed: () => ref
                            .read(moderatorProvider.notifier)
                            .loadDashboard(),
                        icon: Icon(
                          Symbols.refresh,
                          size: 18.w,
                          color: AppColors.primary,
                        ),
                        label: Text(
                          'dashboard_retry'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Group cards list ──
            if (!state.isLoading)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate((ctx, i) {
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: i == groups.length - 1 ? 24.h : 16.h,
                      ),
                      child: _GroupCard(group: groups[i]),
                    );
                  }, childCount: groups.length),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SOS Alert Banner
// ─────────────────────────────────────────────────────────────────────────────

class _SosAlertBanner extends StatelessWidget {
  final List<ModeratorGroup> groups;
  const _SosAlertBanner({required this.groups});

  @override
  Widget build(BuildContext context) {
    final sosGroups = groups.where((g) => g.sosCount > 0).toList();
    final first = sosGroups.first;
    final pilgrimName = first.pilgrims
        .firstWhere((p) => p.hasSOS, orElse: () => first.pilgrims.first)
        .fullName;

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        border: Border.all(color: const Color(0xFFFFE4E6)),
        borderRadius: BorderRadius.circular(16.r),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: const BoxDecoration(
              color: Color(0xFFFFE4E6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Symbols.warning,
              color: Color(0xFFDC2626),
              size: 20.w,
              fill: 1,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'dashboard_sos_active'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 13.sp,
                    color: AppColors.textDark,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'Pilgrim $pilgrimName triggered an SOS in ${first.groupName}.',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.sp,
                    color: const Color(0xFF475569),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ModeratorGroupMapScreen(group: first),
              ),
            ),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                'dashboard_view'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 12.sp,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Group Card
// ─────────────────────────────────────────────────────────────────────────────

class _GroupCard extends ConsumerWidget {
  final ModeratorGroup group;
  const _GroupCard({required this.group});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _DeleteGroupSheet(groupName: group.groupName),
    );
    if (confirmed != true) return;
    final (ok, err) = await ref
        .read(moderatorProvider.notifier)
        .deleteGroup(group.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '"${group.groupName}" deleted.'
              : (err ?? 'Failed to delete group'),
          style: const TextStyle(fontFamily: 'Lexend'),
        ),
        backgroundColor: ok ? const Color(0xFF1E293B) : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () {
        final userId = ref.read(authProvider).userId ?? '';
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                GroupManagementScreen(groupId: group.id, currentUserId: userId),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF272210) : Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(
            color: isDark ? const Color(0xFF383018) : const Color(0xFFEEEEF8),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative mosque illustration
            Positioned(
              right: 74.w,
              top: 14.h,
              child: Opacity(
                opacity: isDark ? 0.18 : 1.0,
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFFFD5A0), Color(0xFFFFB06A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
                  blendMode: BlendMode.srcIn,
                  child: Icon(Symbols.mosque, size: 110.w, color: Colors.white),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(18.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status + SOS badge + menu row
                  Row(
                    children: [
                      _StatusBadge(),
                      const Spacer(),
                      if (group.sosCount > 0) ...[
                        _SosBadge(count: group.sosCount),
                        SizedBox(width: 6.w),
                      ],
                      // Delete button
                      GestureDetector(
                        onTap: () => _confirmDelete(context, ref),
                        child: Container(
                          width: 34.w,
                          height: 34.w,
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Symbols.delete_outline,
                            size: 18.w,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 14.h),

                  // Group name
                  Text(
                    group.groupName,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 20.sp,
                      color: isDark ? Colors.white : const Color(0xFF1A1A4E),
                    ),
                  ),

                  SizedBox(height: 4.h),

                  // Group code
                  Row(
                    children: [
                      Icon(
                        Symbols.tag,
                        size: 14.w,
                        color: AppColors.textMutedLight,
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        group.groupCode,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.sp,
                          color: AppColors.textMutedLight,
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 18.h),

                  // Stats grid
                  Container(
                    padding: EdgeInsets.only(top: 14.h),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(
                          color: isDark
                              ? const Color(0xFF383018)
                              : const Color(0xFFEEEEF8),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatCell(
                            label: 'dashboard_stat_pilgrims'.tr(),
                            value: '${group.totalPilgrims}',
                            valueColor: const Color(0xFFF97316),
                          ),
                        ),
                        _VertDivider(isDark: isDark),
                        Expanded(
                          child: _StatCell(
                            label: 'dashboard_stat_online'.tr(),
                            value: '${group.onlineCount}',
                            valueColor: const Color(0xFFF97316),
                          ),
                        ),
                        _VertDivider(isDark: isDark),
                        Expanded(
                          child: _StatCell(
                            label: 'dashboard_stat_batt_low'.tr(),
                            value: group.batteryLowCount > 0
                                ? '${group.batteryLowCount}'
                                : '—',
                            valueColor: group.batteryLowCount > 0
                                ? const Color(0xFFF97316)
                                : AppColors.textMutedLight,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 14.h),

                  // View on Map link
                  GestureDetector(
                    onTap: () {
                      final userId = ref.read(authProvider).userId ?? '';
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => GroupManagementScreen(
                            groupId: group.id,
                            currentUserId: userId,
                          ),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Text(
                          'dashboard_view_on_map'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            fontSize: 13.sp,
                            color: const Color(0xFF6B7BAE),
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Symbols.arrow_forward,
                          size: 18.w,
                          color: const Color(0xFF6B7BAE),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: const Color(0xFFF97316),
        borderRadius: BorderRadius.circular(100.r),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF97316).withOpacity(0.30),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        'dashboard_active'.tr(),
        style: TextStyle(
          fontFamily: 'Lexend',
          fontWeight: FontWeight.w700,
          fontSize: 12.sp,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _SosBadge extends StatelessWidget {
  final int count;
  const _SosBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        border: Border.all(color: const Color(0xFFFFE4E6)),
        borderRadius: BorderRadius.circular(100.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.warning,
            size: 13.w,
            color: const Color(0xFFDC2626),
            fill: 1,
          ),
          SizedBox(width: 4.w),
          Text(
            '$count SOS',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 11.sp,
              color: const Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _StatCell({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w500,
            fontSize: 9.sp,
            color: AppColors.textMutedLight,
            letterSpacing: 0.4,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          value,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 20.sp,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _VertDivider extends StatelessWidget {
  final bool isDark;
  const _VertDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40.h,
      color: isDark ? const Color(0xFF383018) : const Color(0xFFEEEEF8),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Delete Group Confirmation Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _DeleteGroupSheet extends StatelessWidget {
  final String groupName;
  const _DeleteGroupSheet({required this.groupName});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: EdgeInsets.fromLTRB(12.w, 0, 12.w, 24.h),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF272210) : Colors.white,
        borderRadius: BorderRadius.circular(28.r),
      ),
      padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 12.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF383018) : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(height: 20.h),
          // Warning icon
          Container(
            width: 56.w,
            height: 56.w,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Symbols.delete_forever,
              size: 28.w,
              color: const Color(0xFFDC2626),
              fill: 1,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'dashboard_delete_title'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 18.sp,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'dashboard_delete_body'.tr(namedArgs: {'name': groupName}),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              color: AppColors.textMutedLight,
              height: 1.5,
            ),
          ),
          SizedBox(height: 24.h),
          // Delete button
          SizedBox(
            width: double.infinity,
            height: 50.h,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                ),
              ),
              child: Text(
                'dashboard_delete_confirm'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 14.sp,
                ),
              ),
            ),
          ),
          SizedBox(height: 10.h),
          // Cancel button
          SizedBox(
            width: double.infinity,
            height: 50.h,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                ),
              ),
              child: Text(
                'dashboard_delete_cancel'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 14.sp,
                  color: AppColors.textMutedLight,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Nav
// ─────────────────────────────────────────────────────────────────────────────

class _ModBottomNav extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _ModBottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return BottomAppBar(
      height: 70.h,
      color: isDark ? AppColors.surfaceDark : Colors.white,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      padding: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withOpacity(isDark ? 0.4 : 0.12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(
            child: _NavItem(
              icon: Symbols.home,
              label: 'dashboard_nav_home'.tr(),
              index: 0,
              current: currentIndex,
              onTap: onTap,
              activeColor: AppColors.primary,
            ),
          ),
          SizedBox(width: 64.w),
          Expanded(
            child: _NavItem(
              icon: Symbols.notifications,
              label: 'dashboard_nav_alerts'.tr(),
              index: 1,
              current: currentIndex,
              onTap: onTap,
              badge: ref.watch(notificationProvider).unreadCount > 0,
              activeColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int current;
  final ValueChanged<int> onTap;
  final bool badge;
  final Color activeColor;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
    required this.activeColor,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = index == current;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isSelected
        ? activeColor
        : (isDark ? const Color(0xFF7A6E58) : AppColors.textMutedLight);
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 24.w, fill: isSelected ? 1 : 0, color: color),
                if (badge)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      width: 8.w,
                      height: 8.w,
                      decoration: BoxDecoration(
                        color: Colors.red.shade500,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 3.h),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 10.sp,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
