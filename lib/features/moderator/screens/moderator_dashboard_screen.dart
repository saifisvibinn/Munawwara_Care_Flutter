import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/moderator_provider.dart';
import 'create_group_screen.dart';
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
  int _currentTab = 0; // 0=Home, 1=Alerts, 2=Chat, 3=Profile
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(moderatorProvider.notifier).loadDashboard();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: IndexedStack(
        index: _currentTab,
        children: [
          _GroupsHomeTab(searchController: _searchController),
          const _PlaceholderTab(icon: Symbols.notifications, label: 'Alerts'),
          const _PlaceholderTab(icon: Symbols.chat_bubble, label: 'Chat'),
          const _PlaceholderTab(icon: Symbols.person, label: 'Profile'),
        ],
      ),
      floatingActionButton: SizedBox(
        width: 56.w,
        height: 56.w,
        child: FloatingActionButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const CreateGroupScreen(),
            ),
          ),
          backgroundColor: AppColors.primary,
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
                                'My Groups',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 24.sp,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textDark,
                                ),
                              ),
                              SizedBox(height: 2.h),
                              Text(
                                'Manage your active pilgrimages',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 13.sp,
                                  color: AppColors.textMutedLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 42.w,
                          height: 42.w,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1A2C24)
                                : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF2D4A3A)
                                  : const Color(0xFFE2E8F0),
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
                            Symbols.notifications,
                            size: 20.w,
                            color: isDark
                                ? const Color(0xFFCBD5E1)
                                : const Color(0xFF475569),
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
                                  ? const Color(0xFF1A2C24)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14.r),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF2D4A3A)
                                    : const Color(0xFFE2E8F0),
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
                                hintText: 'Search groups...',
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
                                ? const Color(0xFF1A2C24)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF2D4A3A)
                                  : const Color(0xFFE2E8F0),
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
                            Symbols.filter_list,
                            size: 20.w,
                            color: isDark
                                ? const Color(0xFFCBD5E1)
                                : const Color(0xFF475569),
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
            if (!state.isLoading && state.error != null)
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
                          'Retry',
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
                    if (i < groups.length) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: 16.h),
                        child: _GroupCard(group: groups[i]),
                      );
                    }
                    // Last item: Create New Group button
                    return Padding(
                      padding: EdgeInsets.only(bottom: 24.h),
                      child: const _CreateGroupButton(),
                    );
                  }, childCount: groups.length + 1),
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
                  'Active SOS Alert',
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
                'View',
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

class _GroupCard extends StatelessWidget {
  final ModeratorGroup group;
  const _GroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ModeratorGroupMapScreen(group: group),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A2C24) : Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(
            color: isDark ? const Color(0xFF2D4A3A) : const Color(0xFFF1F5F4),
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
            // Watermark icon (top-right)
            Positioned(
              top: 0,
              right: 0,
              child: Padding(
                padding: EdgeInsets.all(14.w),
                child: Opacity(
                  opacity: 0.07,
                  child: Icon(
                    Symbols.mosque,
                    size: 100.w,
                    color: isDark ? Colors.white : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(18.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status + SOS badge row
                  Row(
                    children: [
                      _StatusBadge(),
                      const Spacer(),
                      if (group.sosCount > 0) _SosBadge(count: group.sosCount),
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
                      color: isDark ? Colors.white : AppColors.textDark,
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
                              ? const Color(0xFF2D4A3A)
                              : const Color(0xFFF1F5F4),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _StatCell(
                            label: 'PILGRIMS',
                            value: '${group.totalPilgrims}',
                            valueColor: isDark
                                ? Colors.white
                                : AppColors.textDark,
                          ),
                        ),
                        _VertDivider(isDark: isDark),
                        Expanded(
                          child: _StatCell(
                            label: 'ONLINE',
                            value: '${group.onlineCount}',
                            valueColor: const Color(0xFF16A34A),
                          ),
                        ),
                        _VertDivider(isDark: isDark),
                        Expanded(
                          child: _StatCell(
                            label: 'BATT LOW',
                            value: group.batteryLowCount > 0
                                ? '${group.batteryLowCount}'
                                : '—',
                            valueColor: group.batteryLowCount > 0
                                ? const Color(0xFFF59E0B)
                                : AppColors.textMutedLight,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 14.h),

                  // View on Map link
                  Row(
                    children: [
                      Text(
                        'View on Map',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 13.sp,
                          color: AppColors.primary,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Symbols.arrow_forward,
                        size: 18.w,
                        color: AppColors.primary,
                      ),
                    ],
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
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: const Color(0xFFD1FAE5),
        borderRadius: BorderRadius.circular(100.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7.w,
            height: 7.w,
            decoration: const BoxDecoration(
              color: Color(0xFF10B981),
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 5.w),
          Text(
            'Active',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 11.sp,
              color: const Color(0xFF065F46),
            ),
          ),
        ],
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
      color: isDark ? const Color(0xFF2D4A3A) : const Color(0xFFF1F5F4),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create New Group Button
// ─────────────────────────────────────────────────────────────────────────────

class _CreateGroupButton extends StatelessWidget {
  const _CreateGroupButton();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
      ),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 24.h),
        decoration: BoxDecoration(
          border: Border.all(
            color: isDark ? const Color(0xFF2D4A3A) : const Color(0xFFCBD5E1),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(24.r),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1A2C24)
                    : const Color(0xFFF1F5F4),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Symbols.add,
                size: 24.w,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Create New Group',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 13.sp,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Nav
// ─────────────────────────────────────────────────────────────────────────────

class _ModBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _ModBottomNav({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      height: 70.h,
      color: Colors.white,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      padding: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Symbols.grid_view,
            label: 'Home',
            index: 0,
            current: currentIndex,
            onTap: onTap,
          ),
          _NavItem(
            icon: Symbols.notifications,
            label: 'Alerts',
            index: 1,
            current: currentIndex,
            onTap: onTap,
            badge: true,
          ),
          SizedBox(width: 56.w),
          _NavItem(
            icon: Symbols.chat_bubble,
            label: 'Chat',
            index: 2,
            current: currentIndex,
            onTap: onTap,
          ),
          _NavItem(
            icon: Symbols.person,
            label: 'Profile',
            index: 3,
            current: currentIndex,
            onTap: onTap,
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

  const _NavItem({
    required this.icon,
    required this.label,
    required this.index,
    required this.current,
    required this.onTap,
    this.badge = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = index == current;
    return GestureDetector(
      onTap: () => onTap(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 60.w,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: 24.w,
                  fill: isSelected ? 1 : 0,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textMutedLight,
                ),
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
                color: isSelected
                    ? AppColors.primary
                    : AppColors.textMutedLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Placeholder Tabs
// ─────────────────────────────────────────────────────────────────────────────

class _PlaceholderTab extends StatelessWidget {
  final IconData icon;
  final String label;
  const _PlaceholderTab({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48.w, color: AppColors.textMutedLight),
          SizedBox(height: 12.h),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 16.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.textMutedLight,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Coming soon',
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
