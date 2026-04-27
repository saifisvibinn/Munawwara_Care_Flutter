import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:ui' as ui;
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../calling/providers/call_provider.dart';
import '../../calling/screens/voice_call_screen.dart';
import '../../../main.dart' show isNavigatingToCall;
import '../../../core/services/notification_service.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../notifications/screens/alerts_tab.dart';
import '../providers/moderator_provider.dart';
import 'pilgrim_provisioning_screen.dart';
import 'create_group_screen.dart';
import 'moderator_profile_screen.dart';
import 'group_management_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'moderator_group_map_screen.dart';
import 'system_reminders_screen.dart';

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
  int _currentTab =
      0; // 0=Groups, 1=Provisioning, 2=Reminders, 3=Profile, 4=Alerts
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
    setState(() => _currentTab = 4);
    
    final map = data is Map ? data : <String, dynamic>{};
    final name = map['pilgrim_name'] as String? ?? 'A pilgrim';

    // Show a system notification
    NotificationService.instance.showUrgentNotification(
      title: '🚨 SOS Alert!',
      body: '$name needs immediate help!',
      data: {'type': 'urgent'},
    );

    // Speak the alert aloud
    await _alertTts.setVolume(1.0);
    await _alertTts.setSpeechRate(0.42);
    await _alertTts.speak('SOS Alert! $name needs immediate help!');
    // Show a persistent red SnackBar
    if (!mounted) return;
    StandardSnackBar.show(
      context,
      message: '🚨 SOS — $name',
      type: SnackBarType.error,
      duration: const Duration(seconds: 8),
      actionLabel: 'View',
      onAction: () => setState(() => _currentTab = 4),
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
        // Check if there's a pending call accepted from native call screen.
        // Must run AFTER the socket handshake so the call-answer emit goes through.
        if (SocketService.isConnected) {
          ref.read(callProvider.notifier).checkPendingAcceptedCall();
          ref.read(callProvider.notifier).checkPendingDeclinedCall();
        } else {
          void checkOnce() {
            ref.read(callProvider.notifier).checkPendingAcceptedCall();
            ref.read(callProvider.notifier).checkPendingDeclinedCall();
            SocketService.offConnected(checkOnce);
          }

          SocketService.onConnected(checkOnce);
        }
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
        // Listen for notification refresh (invitations, areas, etc.)
        SocketService.on('notification_refresh', (_) {
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
    SocketService.off('notification_refresh');
    SocketService.offConnected(_onSocketConnected);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final moderatorState = ref.watch(moderatorProvider);

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

    final hasGroups = moderatorState.groups.isNotEmpty;
    final showEmptyGroupsArrow =
        _currentTab == 0 &&
        !moderatorState.isLoading &&
        moderatorState.error == null &&
        !hasGroups;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : const Color(0xFFF0F0F8),
      body: Stack(
        children: [
          IndexedStack(
            index: _currentTab,
            children: [
              _GroupsHomeTab(
                searchController: _searchController,
                onNotificationTap: () => setState(() => _currentTab = 4),
              ), // 0: Groups
              const PilgrimProvisioningScreen(), // 1: Provisioning
              const SystemRemindersScreen(), // 2: Reminders
              const ModeratorProfileScreen(), // 3: Profile
              const AlertsTab(), // 4: Alerts
            ],
          ),
          if (showEmptyGroupsArrow)
            IgnorePointer(
              child: Align(
                alignment: AlignmentDirectional.bottomEnd,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(end: 64.w, bottom: 100.h),
                  child: Transform.rotate(
                    angle: Directionality.of(context) == ui.TextDirection.rtl ? 0.6 : -0.6,
                    child: Icon(
                      Symbols.arrow_downward,
                      size: 32.w,
                      color: isDark
                          ? const Color(0xFFD4B896)
                          : const Color(0xFF1A1A4E),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _currentTab == 0
          ? SizedBox(
              width: 56.w,
              height: 56.w,
              child: FloatingActionButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
                ),
                backgroundColor: const Color(0xFFF97316),
                foregroundColor: Colors.white,
                shape: const CircleBorder(),
                elevation: 6,
                child: Icon(Symbols.add, size: 28.w),
              ),
            )
          : null,
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

enum GroupSortType {
  alphabetical,
  oldestToNewest,
  newestToOldest,
  pilgrimCount,
  moderatorCount,
  mostOnline,
  lowBatteryPriority
}

class _GroupsHomeTab extends ConsumerStatefulWidget {
  final TextEditingController searchController;
  final VoidCallback onNotificationTap;

  const _GroupsHomeTab({
    required this.searchController,
    required this.onNotificationTap,
  });

  @override
  ConsumerState<_GroupsHomeTab> createState() => _GroupsHomeTabState();
}

class _GroupsHomeTabState extends ConsumerState<_GroupsHomeTab> {
  String _searchQuery = '';
  GroupSortType _sortType = GroupSortType.oldestToNewest;
  bool _isAscending = false;

  @override
  void initState() {
    super.initState();
    _loadSortPreferences();
    widget.searchController.addListener(() {
      if (mounted) {
        setState(
          () => _searchQuery = widget.searchController.text.toLowerCase(),
        );
      }
    });
  }

  Future<void> _loadSortPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final sortIndex = prefs.getInt('mod_group_sort_type');
    final isAsc = prefs.getBool('mod_group_sort_asc');
    if (mounted) {
      setState(() {
        if (sortIndex != null && sortIndex < GroupSortType.values.length) {
          _sortType = GroupSortType.values[sortIndex];
        }
        if (isAsc != null) {
          _isAscending = isAsc;
        }
      });
    }
  }

  Future<void> _saveSortPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('mod_group_sort_type', _sortType.index);
    await prefs.setBool('mod_group_sort_asc', _isAscending);
  }

  List<ModeratorGroup> _filteredAndSorted(List<ModeratorGroup> groups) {
    var list = groups.toList();
    if (_searchQuery.isNotEmpty) {
      list = list
          .where((g) => g.groupName.toLowerCase().contains(_searchQuery))
          .toList();
    }

    // Sort
    switch (_sortType) {
      case GroupSortType.alphabetical:
        list.sort((a, b) => a.groupName.compareTo(b.groupName));
        break;
      case GroupSortType.oldestToNewest:
        list.sort((a, b) {
          final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return da.compareTo(db);
        });
        break;
      case GroupSortType.newestToOldest:
        list.sort((a, b) {
          final da = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final db = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return db.compareTo(da);
        });
        break;
      case GroupSortType.pilgrimCount:
        list.sort((a, b) => _isAscending
            ? a.totalPilgrims.compareTo(b.totalPilgrims)
            : b.totalPilgrims.compareTo(a.totalPilgrims));
        break;
      case GroupSortType.moderatorCount:
        list.sort((a, b) => _isAscending
            ? a.moderatorCount.compareTo(b.moderatorCount)
            : b.moderatorCount.compareTo(a.moderatorCount));
        break;
      case GroupSortType.mostOnline:
        list.sort((a, b) => _isAscending
            ? a.onlineCount.compareTo(b.onlineCount)
            : b.onlineCount.compareTo(a.onlineCount));
        break;
      case GroupSortType.lowBatteryPriority:
        list.sort((a, b) => b.batteryLowCount.compareTo(a.batteryLowCount));
        break;
    }

    return list;
  }

  void _showSortBottomSheet(bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 32.h),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                ),
                SizedBox(height: 20.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'filter_sort_title'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w800,
                        fontSize: 20.sp,
                        color: isDark ? Colors.white : const Color(0xFF1A1A4E),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _sortType = GroupSortType.oldestToNewest;
                          _isAscending = false;
                        });
                        _saveSortPreferences();
                        Navigator.pop(ctx);
                      },
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'reset'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20.h),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SortOption(
                          label: 'sort_az'.tr(),
                          icon: Symbols.sort_by_alpha,
                          isSelected: _sortType == GroupSortType.alphabetical,
                          onTap: () {
                            setState(() => _sortType = GroupSortType.alphabetical);
                            _saveSortPreferences();
                            Navigator.pop(ctx);
                          },
                          isDark: isDark,
                        ),
                        _SortOption(
                          label: 'sort_newest'.tr(),
                          icon: Symbols.schedule,
                          isSelected: _sortType == GroupSortType.newestToOldest,
                          onTap: () {
                            setState(() => _sortType = GroupSortType.newestToOldest);
                            _saveSortPreferences();
                            Navigator.pop(ctx);
                          },
                          isDark: isDark,
                        ),
                        _SortOption(
                          label: 'sort_oldest'.tr(),
                          icon: Symbols.calendar_month,
                          isSelected: _sortType == GroupSortType.oldestToNewest,
                          onTap: () {
                            setState(() => _sortType = GroupSortType.oldestToNewest);
                            _saveSortPreferences();
                            Navigator.pop(ctx);
                          },
                          isDark: isDark,
                        ),
                        _SortOption(
                          label: 'sort_pilgrim_count'.tr(),
                          icon: Symbols.groups,
                          isSelected: _sortType == GroupSortType.pilgrimCount,
                          isAscending: _sortType == GroupSortType.pilgrimCount ? _isAscending : null,
                          onTap: () {
                            if (_sortType == GroupSortType.pilgrimCount) {
                              setState(() => _isAscending = !_isAscending);
                              setSheetState(() {});
                            } else {
                              setState(() {
                                _sortType = GroupSortType.pilgrimCount;
                                _isAscending = false; // Default to Descending for counts
                              });
                              Navigator.pop(ctx);
                            }
                            _saveSortPreferences();
                          },
                          isDark: isDark,
                        ),
                        _SortOption(
                          label: 'sort_mod_count'.tr(),
                          icon: Symbols.shield_person,
                          isSelected: _sortType == GroupSortType.moderatorCount,
                          isAscending: _sortType == GroupSortType.moderatorCount ? _isAscending : null,
                          onTap: () {
                            if (_sortType == GroupSortType.moderatorCount) {
                              setState(() => _isAscending = !_isAscending);
                              setSheetState(() {});
                            } else {
                              setState(() {
                                _sortType = GroupSortType.moderatorCount;
                                _isAscending = false;
                              });
                              Navigator.pop(ctx);
                            }
                            _saveSortPreferences();
                          },
                          isDark: isDark,
                        ),
                        _SortOption(
                          label: 'sort_most_online'.tr(),
                          icon: Symbols.bolt,
                          isSelected: _sortType == GroupSortType.mostOnline,
                          isAscending: _sortType == GroupSortType.mostOnline ? _isAscending : null,
                          onTap: () {
                            if (_sortType == GroupSortType.mostOnline) {
                              setState(() => _isAscending = !_isAscending);
                              setSheetState(() {});
                            } else {
                              setState(() {
                                _sortType = GroupSortType.mostOnline;
                                _isAscending = false;
                              });
                              Navigator.pop(ctx);
                            }
                            _saveSortPreferences();
                          },
                          isDark: isDark,
                        ),
                        _SortOption(
                          label: 'sort_low_battery'.tr(),
                          icon: Symbols.battery_alert,
                          isSelected: _sortType == GroupSortType.lowBatteryPriority,
                          onTap: () {
                            setState(() => _sortType = GroupSortType.lowBatteryPriority);
                            _saveSortPreferences();
                            Navigator.pop(ctx);
                          },
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(moderatorProvider);
    final notifCount = ref.watch(notificationProvider).unreadCount;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groups = _filteredAndSorted(state.groups);
    final showEmptyState =
        !state.isLoading && state.error == null && groups.isEmpty;
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
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GestureDetector(
                              onTap: widget.onNotificationTap,
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 44.w,
                                    height: 44.w,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppColors.iconBgDark
                                          : AppColors.iconBgLight,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isDark
                                            ? AppColors.backgroundDark
                                            : const Color(0xFFD0D0F0),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.06),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Symbols.notifications,
                                      size: 22.w,
                                      color: isDark
                                          ? AppColors.primary
                                          : const Color(0xFF8A6A30),
                                    ),
                                  ),
                                  if (notifCount > 0)
                                    Positioned(
                                      top: -2,
                                      right: -2,
                                      child: Container(
                                        padding: EdgeInsets.all(4.w),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isDark
                                                ? AppColors.backgroundDark
                                                : Colors.white,
                                            width: 2.w,
                                          ),
                                        ),
                                        child: Text(
                                          notifCount > 99
                                              ? '99+'
                                              : notifCount.toString(),
                                          style: TextStyle(
                                            fontFamily: 'Lexend',
                                            fontSize: 9.sp,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            SizedBox(width: 12.w),
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
                                      ? AppColors.iconBgDark
                                      : AppColors.iconBgLight,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.backgroundDark
                                        : const Color(0xFFD0D0F0),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.06),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Symbols.person,
                                  size: 22.w,
                                  color: isDark
                                      ? AppColors.primary
                                      : const Color(0xFF8A6A30),
                                ),
                              ),
                            ),
                          ],
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
                                  ? AppColors.surfaceDark
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14.r),
                              border: Border.all(
                                color: isDark
                                    ? AppColors.backgroundDark
                                    : const Color(0xFFE2E2F0),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
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
                        GestureDetector(
                          onTap: () => _showSortBottomSheet(isDark),
                          child: Container(
                            width: 48.w,
                            height: 48.h,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.surfaceDark
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(14.r),
                              border: Border.all(
                                color: isDark
                                    ? AppColors.backgroundDark
                                    : const Color(0xFFE2E2F0),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  Symbols.tune,
                                  size: 20.w,
                                  color: isDark
                                      ? AppColors.primary
                                      : const Color(0xFF8A6A30),
                                ),
                                if (_sortType != GroupSortType.oldestToNewest)
                                  Positioned(
                                    top: 12.h,
                                    right: 12.w,
                                    child: Container(
                                      width: 6.w,
                                      height: 6.w,
                                      decoration: const BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
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

            // ── Empty State ──
            if (showEmptyState)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _GroupsEmptyState(isDark: isDark),
              ),

            // ── Group cards list ──
            if (!state.isLoading && groups.isNotEmpty)
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

class _GroupsEmptyState extends StatelessWidget {
  final bool isDark;
  const _GroupsEmptyState({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, 6.h, 24.w, 0),
      child: Column(
        children: [
          SizedBox(height: 6.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            child: Image.asset(
              isDark
                  ? 'assets/static/empty_groups_dark.png'
                  : 'assets/static/empty_groups_light.png',
              width: 330.w,
              height: 270.h,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Icon(
                Symbols.mosque,
                size: 220.w,
                color: isDark
                    ? const Color(0xFF7FA6CE)
                    : const Color(0xFF7FA6CE),
              ),
            ),
          ),
          SizedBox(height: 14.h),
          Text(
            'dashboard_empty_title'.tr(),
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w800,
              fontSize: 30.sp,
              color: isDark ? Colors.white : const Color(0xFF1A1A4E),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'dashboard_empty_subtitle'.tr(),
            textAlign: TextAlign.center,
            maxLines: 3,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14.sp,
              height: 1.3,
              color: isDark ? const Color(0xFFCBD5E1) : AppColors.textDark,
            ),
          ),
          SizedBox(height: 96.h),
        ],
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
            color: Colors.red.withValues(alpha: 0.06),
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
    if (ok) {
      StandardSnackBar.showSuccess(context, '"${group.groupName}" deleted.');
    } else {
      StandardSnackBar.showError(context, err ?? 'Failed to delete group');
    }
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
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(
            color: isDark ? AppColors.backgroundDark : const Color(0xFFEEEEF8),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Decorative mosque illustration
            Positioned(
              right: context.locale.languageCode == 'ar' ? null : 54.w,
              left: context.locale.languageCode == 'ar' ? 54.w : null,
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
                  child: Transform.scale(
                    scaleX: context.locale.languageCode == 'ar' ? -1 : 1,
                    child: Icon(
                      Symbols.mosque,
                      size: 110.w,
                      color: Colors.white,
                    ),
                  ),
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
                            color: Colors.red.withValues(alpha: 0.1),
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
                            label: 'dashboard_stat_moderators'.tr(),
                            value: '${group.moderatorCount}',
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
                        Transform.scale(
                          scaleX: Directionality.of(context) == ui.TextDirection.rtl ? -1 : 1,
                          child: Icon(
                            Symbols.arrow_forward,
                            size: 18.w,
                            color: const Color(0xFF6B7BAE),
                          ),
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
            color: const Color(0xFFF97316).withValues(alpha: 0.30),
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
      padding: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(
            child: _NavItem(
              icon: Symbols.groups,
              label: 'GROUPS',
              index: 0,
              current: currentIndex,
              onTap: onTap,
              badge: false,
              activeColor: AppColors.primary,
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Symbols.inbox,
              label: 'PROVISIONING',
              index: 1,
              current: currentIndex,
              onTap: onTap,
              badge: false,
              activeColor: AppColors.primary,
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Symbols.notifications_active,
              label: 'REMINDERS',
              index: 2,
              current: currentIndex,
              onTap: onTap,
              badge: false,
              activeColor: AppColors.primary,
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Symbols.person,
              label: 'PROFILE',
              index: 3,
              current: currentIndex,
              onTap: onTap,
              badge: false,
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
    required this.badge,
    required this.activeColor,
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
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 9.sp,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final bool? isAscending;
  final VoidCallback onTap;
  final bool isDark;

  const _SortOption({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.isDark,
    this.isAscending,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : AppColors.primary.withValues(alpha: 0.05))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 22.w,
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? Colors.white70 : AppColors.textDark),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 15.sp,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? Colors.white : AppColors.textDark),
                ),
              ),
            ),
            if (isSelected && isAscending != null)
              Padding(
                padding: EdgeInsetsDirectional.only(end: 8.w),
                child: Icon(
                  isAscending! ? Symbols.arrow_upward : Symbols.arrow_downward,
                  size: 20.w,
                  color: AppColors.primary,
                ),
              ),
            if (isSelected)
              Icon(
                Symbols.check_circle,
                size: 20.w,
                color: AppColors.primary,
                fill: 1,
              ),
          ],
        ),
      ),
    );
  }
}
