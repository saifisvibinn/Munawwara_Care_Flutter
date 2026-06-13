import 'dart:async';

import 'package:cupertino_liquid_glass/cupertino_liquid_glass.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/foundation.dart' show kIsWeb, listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'dart:ui' as ui;
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/bootstrap/app_startup_coordinator.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/oem_settings_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_liquid_glass_bottom_bar.dart';
import '../../../core/widgets/keep_alive_tab.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/services/callkit_service.dart';
import '../../calling/providers/call_provider.dart';
import '../../calling/screens/voice_call_screen.dart';
import '../../calling/native_call_coordinator.dart' show isNavigatingToCall;
import '../../../core/router/app_router.dart' show AppRouter;
import '../../invitations/providers/invitation_provider.dart';
import '../../invitations/widgets/pending_invitations_section.dart';
import '../../notifications/providers/notification_provider.dart';
import '../routes/moderator_alerts_reveal_route.dart';
import '../providers/moderator_provider.dart';
import 'pilgrim_provisioning_screen.dart';
import 'create_group_screen.dart';
import 'join_group_screen.dart';
import 'moderator_profile_screen.dart';
import 'group_management_screen.dart';
import 'group_messages_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'system_reminders_screen.dart';
import '../../pilgrim/screens/resources_screen.dart';
import '../widgets/moderator_groups_speed_dial.dart';
import '../services/moderator_global_nav_beacon_controller.dart';
import '../services/moderator_sos_engagement_store.dart';
import '../services/sos_alert_coordinator.dart';
import '../../shared/services/message_realtime_binder.dart';
import '../providers/moderator_sos_engagement_provider.dart';
import '../../shared/helpers/message_visibility.dart';
import '../../shared/providers/message_provider.dart';

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
    extends ConsumerState<ModeratorDashboardScreen>
    with RouteAware, WidgetsBindingObserver {
  bool _isInitializingDashboard = true;
  int _currentTab =
      0; // 0=Groups, 1=Provisioning, 2=Reminders, 3=Profile
  late final PageController _pageController = PageController(initialPage: 0);
  final _searchController = TextEditingController();
  ModeratorGlobalNavBeaconController? _globalNavBeacon;

  // ── RouteAware: re-join group rooms when returning from sub-screens ────────
  @override
  void didPopNext() {
    // Called when a route that was pushed on top of this one has been popped,
    // returning focus to this screen. Re-join all rooms in case a sub-screen
    // (e.g. GroupManagementScreen) cleared our socket room memberships.
    _joinAllGroupRooms();
    unawaited(_globalNavBeacon?.sync(emitImmediateFix: true) ?? Future.value());
    if (NotificationService.hasPendingSosAlert) {
      NotificationService.showPendingSosAlertIfAny();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Join every group room so we receive group-scoped socket events (SOS, etc.)
  void _joinAllGroupRooms() {
    for (final g in ref.read(moderatorProvider).groups) {
      SocketService.emit('join_group', g.id);
    }
  }

  /// Named reconnect callback so offConnected can remove it.
  void _onSocketConnected() {
    if (!mounted) return;
    _joinAllGroupRooms();
    unawaited(_globalNavBeacon?.emitSnapshotIfNeeded() ?? Future.value());
  }

  void _reconcileCallsAfterSocketReady() {
    if (!mounted) return;
    unawaited(CallKitService.instance.recoverStaleIncomingCallGuards());
    unawaited(
      ref.read(callProvider.notifier).reconcileCallStateAfterProcessDeath(),
    );
    if (!mounted) return;
    ref.read(callProvider.notifier).checkPendingAcceptedCall();
    ref.read(callProvider.notifier).checkPendingDeclinedCall();
  }

  void _refreshRealtimeState() {
    if (!mounted) return;
    unawaited(() async {
      ref.read(notificationProvider.notifier).refetch();
      await ref.read(pendingInvitationsProvider.notifier).fetchPending();
      await ref.read(moderatorProvider.notifier).loadDashboard(
            silently: true,
            force: true,
          );
      if (!mounted) return;
      // After dashboard refresh, ensure we are subscribed to all group rooms
      // (important for newly invited moderators).
      _joinAllGroupRooms();
    }());
  }

  Future<void> _onSosAlertArrived(dynamic data) async {
    if (!mounted) return;
    // Update badge/list without auto-clearing unread count.
    ref.read(notificationProvider.notifier).refetch();

    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{};
    final pid = map['pilgrim_id']?.toString();
    if (pid != null && pid.isNotEmpty) {
      ref.read(moderatorProvider.notifier).markPilgrimSOS(pid, active: true);
    }

    // In-app dialog (deduped). Do not show a second local notification — FCM
    // already surfaces one tray notification when applicable.
    await SosAlertCoordinator.showOnceFromMap(map);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !kIsWeb) {
      unawaited(() async {
        await _checkRequiredPermissions();
        if (mounted) {
          unawaited(
            ref.read(pendingInvitationsProvider.notifier).fetchPending(),
          );
          unawaited(
            _globalNavBeacon?.sync(emitImmediateFix: true) ?? Future.value(),
          );
        }
      }());
    }
  }

  int _permissionsCheckGate = 0;

  Future<void> _checkRequiredPermissions() async {
    if (OemSettingsService.isOnboardingSkippedForSession) return;

    final gate = OemSettingsService.onboardingGate;
    final checkId = ++_permissionsCheckGate;

    final showOnboarding = await OemSettingsService.shouldShowOnboardingOnResume(
      gate: gate,
    );
    if (!mounted ||
        checkId != _permissionsCheckGate ||
        OemSettingsService.isOnboardingSkippedForSession ||
        gate != OemSettingsService.onboardingGate) {
      return;
    }
    if (showOnboarding) {
      context.go('/device-care-onboarding');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<ModeratorState>(moderatorProvider, (prev, next) {
      final pa = [...?prev?.groups.map((g) => g.id)]..sort();
      final na = next.groups.map((g) => g.id).toList()..sort();
      if (!listEquals(pa, na)) {
        unawaited(
          _globalNavBeacon?.sync(emitImmediateFix: true) ?? Future.value(),
        );
      }
    });
    ref.listenManual(callProvider, (prev, next) {
      if (next.status == CallStatus.connected &&
          (prev?.status == CallStatus.ringing || prev?.status == CallStatus.connecting) &&
          mounted &&
          !isNavigatingToCall &&
          !VoiceCallScreen.isActive) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const VoiceCallScreen()),
        );
      }
      if (next.status == CallStatus.calling &&
          prev?.status != CallStatus.calling &&
          mounted &&
          !isNavigatingToCall &&
          !VoiceCallScreen.isActive) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const VoiceCallScreen()),
        );
      }
      if (next.status == CallStatus.connecting &&
          (prev?.status == CallStatus.calling || prev?.status == CallStatus.ringing) &&
          mounted &&
          !isNavigatingToCall &&
          !VoiceCallScreen.isActive) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const VoiceCallScreen()),
        );
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkRequiredPermissions());
      unawaited(ref.read(authProvider.notifier).ensureFcmTokenRegistered());
      unawaited(_bootstrapDashboard());
    });
  }

  Future<void> _bootstrapDashboard() async {
    final route = ModalRoute.of(context);
    if (route != null) {
      AppRouter.moderatorRouteObserver.subscribe(this, route);
    }

    if (AppStartupCoordinator.consumeDashboardPrimed()) {
      if (mounted) {
        setState(() => _isInitializingDashboard = false);
      }
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_finishModeratorWarmup());
      });
      return;
    }

    await ref.read(authProvider.notifier).hydrateFromCache();
    await ref.read(moderatorProvider.notifier).hydrateFromCache();
    if (mounted) {
      setState(() => _isInitializingDashboard = false);
    }

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadRemoteDashboardState());
    });
  }

  Future<void> _loadRemoteDashboardState() async {
    final hasCached = ref.read(moderatorProvider).groups.isNotEmpty;
    await ref.read(moderatorProvider.notifier).loadDashboard(
      silently: hasCached,
    );
    if (!mounted) return;
    await _finishModeratorWarmup();
  }

  Future<void> _finishModeratorWarmup() async {
    await ref.read(moderatorSosEngagementProvider.notifier).refresh();
    unawaited(ref.read(pendingInvitationsProvider.notifier).fetchPending());
    if (!mounted) return;
    _connectModeratorRealtime();
    if (!mounted) return;
    NotificationService.markModeratorDashboardReady();
  }

  void _connectModeratorRealtime() {
    final auth = ref.read(authProvider);
    if (auth.userId != null) {
        _globalNavBeacon = ModeratorGlobalNavBeaconController(ref);
        final socketUrl = ApiService.socketOrigin;
        // Register before connect so a fast handshake never misses join + beacon.
        SocketService.onConnected(_onSocketConnected);
        SocketService.connect(
          serverUrl: socketUrl,
          userId: auth.userId!,
          role: auth.role ?? 'moderator',
        );
        // Note: CallNotifier.build() already registers call socket listeners on
        // first access, and SocketService.connect() re-applies them on every
        // reconnect via _applyPendingListeners(). No manual reRegisterListeners()
        // needed here — calling it would cause duplicate handler registration.
        // Check if there's a pending call accepted from native call screen.
        // Must run AFTER the socket handshake so the call-answer emit goes through.
        if (SocketService.isConnected) {
          _reconcileCallsAfterSocketReady();
        } else {
          void checkOnce() {
            SocketService.offConnected(checkOnce);
            _reconcileCallsAfterSocketReady();
          }

          SocketService.onConnected(checkOnce);
        }
        if (mounted) {
          ref.read(notificationProvider.notifier).fetchUnreadCount();
        }
        if (SocketService.isConnected) {
          _onSocketConnected();
        }
        unawaited(
          _globalNavBeacon?.sync(emitImmediateFix: true) ?? Future.value(),
        );
        SosAlertCoordinator.bindCancelListeners();
        SocketService.on('sos-alert-received', _onSosAlertArrived);
        SocketService.on('sos-alert-cancelled', (data) async {
          if (!mounted) return;
          final map = data is Map
              ? Map<String, dynamic>.from(data)
              : <String, dynamic>{};
          await SosAlertCoordinator.handleCancelledFromMap(map);
        });
        // Cross-moderator status updates (reviewing / in-call)
        SocketService.on('sos-moderator-responding', (data) async {
          if (!mounted || data is! Map) return;
          final map = Map<String, dynamic>.from(data);
          final pid = map['pilgrim_id']?.toString() ?? '';
          final gid = map['group_id']?.toString() ?? '';
          final modId = map['moderator_id']?.toString() ?? '';
          final modName = map['moderator_name']?.toString() ?? '';
          if (pid.isEmpty || gid.isEmpty || modId.isEmpty) return;
          final sid = map['sos_id']?.toString();
          final sk = (sid != null && sid.isNotEmpty) ? sid : 'c_${pid}_$gid';
          await ModeratorSosEngagementStore.upsertModeratorStatus(
            storageKey: sk,
            pilgrimId: pid,
            groupId: gid,
            pilgrimName: map['pilgrim_name']?.toString() ?? '',
            groupName: map['group_name']?.toString() ?? '',
            moderatorId: modId,
            moderatorName: modName,
            status: 'reviewing',
          );
          SosAlertCoordinator.dismissIfOpenForStorageKey(
            sk,
            reasonMessage: modName.trim().isEmpty
                ? 'sos_claimed_handled_by_other_mod'.tr()
                : 'sos_claimed_being_reviewed_by'.tr(
                    namedArgs: {'name': modName},
                  ),
          );
          await ref.read(moderatorSosEngagementProvider.notifier).refresh();
        });
        SocketService.on('sos-moderator-in-call', (data) async {
          if (!mounted || data is! Map) return;
          final map = Map<String, dynamic>.from(data);
          final pid = map['pilgrim_id']?.toString() ?? '';
          final gid = map['group_id']?.toString() ?? '';
          final modId = map['moderator_id']?.toString() ?? '';
          final modName = map['moderator_name']?.toString() ?? '';
          if (pid.isEmpty || gid.isEmpty || modId.isEmpty) return;
          final sid = map['sos_id']?.toString();
          final sk = (sid != null && sid.isNotEmpty) ? sid : 'c_${pid}_$gid';
          await ModeratorSosEngagementStore.upsertModeratorStatus(
            storageKey: sk,
            pilgrimId: pid,
            groupId: gid,
            pilgrimName: map['pilgrim_name']?.toString() ?? '',
            groupName: map['group_name']?.toString() ?? '',
            moderatorId: modId,
            moderatorName: modName,
            status: 'in_call',
          );
          SosAlertCoordinator.dismissIfOpenForStorageKey(
            sk,
            reasonMessage: modName.trim().isEmpty
                ? 'sos_claimed_in_call_other_mod'.tr()
                : 'sos_claimed_in_call_with'.tr(namedArgs: {'name': modName}),
          );
          await ref.read(moderatorSosEngagementProvider.notifier).refresh();
        });
        // Listen for missed calls — refresh notification/list + groups
        SocketService.on('missed-call-received', (_) {
          _refreshRealtimeState();
        });
        // Listen for notification refresh (invitations, areas, etc.)
        SocketService.on('notification_refresh', (_) {
          _refreshRealtimeState();
        });
        // Group membership/list changes from any device should refresh dashboard
        SocketService.on('group_updated', (_) {
          _refreshRealtimeState();
        });
        SocketService.on('group_deleted', (_) {
          _refreshRealtimeState();
        });
        SocketService.on('added-to-group', (data) {
          // Critical: join the new room immediately so SOS realtime works.
          if (data is Map) {
            final map = Map<String, dynamic>.from(data);
            final gid = map['group_id']?.toString();
            if (gid != null && gid.trim().isNotEmpty) {
              SocketService.emit('join_group', gid.trim());
            }
          }
          _refreshRealtimeState();
        });
        SocketService.on('profile_updated', (_) {
          ref.read(authProvider.notifier).fetchProfile();
          _refreshRealtimeState();
        });
        SocketService.on('wakel_updated', (_) {
          ref.read(authProvider.notifier).fetchProfile();
          _refreshRealtimeState();
        });
        SocketService.on('removed-from-group', (_) {
          _refreshRealtimeState();
        });

        // Listen for new group messages globally
        SocketService.on('new_message', (data) {
          if (!mounted) return;
          AppLogger.d(
            '[ModeratorDashboard] Socket event: new_message | Data: $data',
          );
          try {
            // socket.io can deliver data as Map<dynamic,dynamic> — cast safely
            final map = Map<String, dynamic>.from(data as Map);
            AppLogger.d(
              '[ModeratorDashboard] is_urgent value in map: ${map['is_urgent']} (type: ${map['is_urgent'].runtimeType})',
            );
            final groupId = map['group_id']?.toString();
            if (groupId == null) {
              AppLogger.w(
                '[ModeratorDashboard] Error: group_id is null in payload',
              );
              return;
            }

            final currentUserId = ref.read(authProvider).userId ?? '';
            if (!isRawMessageVisibleToUser(
              map,
              currentUserId,
              isModerator: true,
            )) {
              return;
            }

            // Append to message provider so chat is up-to-date if viewed
            ref.read(messageProvider.notifier).appendMessage(map);

            // Ignore own messages — don't badge for what we sent
            final senderRaw = map['sender_id'];
            final senderId = (senderRaw is Map)
                ? senderRaw['_id']?.toString()
                : senderRaw?.toString();

            if (senderId == currentUserId) {
              AppLogger.d(
                '[ModeratorDashboard] Message from self, skipping badge',
              );
              return;
            }

            // If the user is actively reading this chat, clear count
            if (ref.read(messageProvider).activeGroupId == groupId) {
              ref.read(moderatorProvider.notifier).clearUnreadCount(groupId);
              AppLogger.d(
                '[ModeratorDashboard] User reading chat, skipping badge',
              );
              return;
            }

            // Instantly increment unread count for UI badge
            AppLogger.d(
              '[ModeratorDashboard] Incrementing badge for group: $groupId',
            );
            ref.read(moderatorProvider.notifier).incrementUnreadCount(groupId);
          } catch (e) {
            AppLogger.e('[ModeratorDashboard] new_message handler error: $e');
          }
        });

        MessageRealtimeBinder.bindDeleteListener();
    }
  }

  @override
  void dispose() {
    NotificationService.markModeratorDashboardNotReady();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    unawaited(SosAlertCoordinator.stopAlertSpeech());
    AppRouter.moderatorRouteObserver.unsubscribe(this);
    SocketService.off('sos-alert-received');
    SocketService.off('sos-moderator-responding');
    SocketService.off('sos-moderator-in-call');
    SocketService.off('missed-call-received');
    SocketService.off('notification_refresh');
    SocketService.off('group_updated');
    SocketService.off('group_deleted');
    SocketService.off('added-to-group');
    SocketService.off('removed-from-group');
    SocketService.off('new_message');
    SocketService.off('profile_updated');
    SocketService.off('wakel_updated');
    SocketService.offConnected(_onSocketConnected);
    _globalNavBeacon?.dispose();
    _globalNavBeacon = null;
    _pageController.dispose();
    super.dispose();
  }

  /// Syncs tab index and rebuilds [isTabActive] children after swipe or tap.
  void _handlePageChanged(int index) {
    if (_currentTab == index) return;
    setState(() => _currentTab = index);
  }

  /// Swipe uses [PageView] physics; programmatic navigation uses [jumpToPage].
  void _goToTab(int index, {bool animate = false}) {
    if (_currentTab == index &&
        (!_pageController.hasClients ||
            (_pageController.page?.round() ?? _currentTab) == index)) {
      return;
    }
    if (!_pageController.hasClients) {
      setState(() => _currentTab = index);
      return;
    }
    if (animate) {
      unawaited(
        _pageController.animateToPage(
          index,
          duration: dashboardTabAnimDuration,
          curve: dashboardTabAnimCurve,
        ),
      );
    } else {
      _pageController.jumpToPage(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final moderatorState = ref.watch(moderatorProvider);

    if (_isInitializingDashboard) {
      return Scaffold(
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : const Color(0xfff1f5f3),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 34.w,
                  height: 34.w,
                  child: const CircularProgressIndicator(strokeWidth: 3),
                ),
                SizedBox(height: 14.h),
                Text(
                  'app_loading'.tr(),
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : AppColors.textMutedDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: _currentTab == 0,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop && _currentTab != 0) {
          _goToTab(0);
        }
      },
      child: Scaffold(
        extendBody: true,
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : const Color(0xFFF0F0F8),
        body: Stack(
          children: [
            Column(
              children: [
                if (moderatorState.usingOfflineSnapshot)
                  Material(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 8.h,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Symbols.cloud_off,
                              size: 18.w,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: Text(
                                'offline_showing_saved_data'.tr(),
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w500,
                                  color: isDark
                                      ? Colors.white70
                                      : AppColors.textDark,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: DashboardTabPageView(
                    controller: _pageController,
                    backgroundColor: isDark
                        ? AppColors.backgroundDark
                        : const Color(0xfff1f5f3),
                    onPageChanged: _handlePageChanged,
                    children: [
                      _GroupsHomeTab(
                        searchController: _searchController,
                        onNotificationTap: () =>
                            openModeratorAlertsWithReveal(context),
                      ),
                      PilgrimProvisioningScreen(
                        isTabActive: _currentTab == 1,
                      ),
                      SystemRemindersScreen(
                        isTabActive: _currentTab == 2,
                      ),
                      const ModeratorProfileScreen(),
                    ],
                  ),
                ),
              ],
            ),
            // FAB lives in the body Stack — Scaffold's floatingActionButton slot
            // clips/constrains hit targets for tall expanded menus, so "Join Group"
            // often received no taps.
            if (_currentTab == 0)
              PositionedDirectional(
                end: 16.w,
                bottom: 88.h,
                child: ModeratorGroupsSpeedDial(
                  onCreateGroup: () =>
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (_) => const CreateGroupScreen(),
                        ),
                      ),
                  onJoinGroup: () =>
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (_) => const JoinGroupScreen(),
                        ),
                      ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: _ModBottomNav(
          currentIndex: _currentTab,
          onTap: (index) => _goToTab(index, animate: false),
        ),
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
  lowBatteryPriority,
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
  List<ModeratorGroup> _displayGroups = const [];
  List<ModeratorGroup>? _lastSourceGroups;
  GroupSortType? _lastSortType;
  bool? _lastAscending;

  void _syncFilteredGroups(List<ModeratorGroup> source) {
    final query = widget.searchController.text.toLowerCase();
    if (identical(_lastSourceGroups, source) &&
        _searchQuery == query &&
        _lastSortType == _sortType &&
        _lastAscending == _isAscending) {
      return;
    }
    _searchQuery = query;
    _lastSourceGroups = source;
    _lastSortType = _sortType;
    _lastAscending = _isAscending;
    _displayGroups = _filteredAndSorted(source);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(
          ref.read(pendingInvitationsProvider.notifier).fetchPending(),
        );
      }
    });
    _loadSortPreferences();
    widget.searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = widget.searchController.text.toLowerCase();
          _lastSourceGroups = null;
        });
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
        _lastSourceGroups = null;
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
        list.sort(
          (a, b) => _isAscending
              ? a.totalPilgrims.compareTo(b.totalPilgrims)
              : b.totalPilgrims.compareTo(a.totalPilgrims),
        );
        break;
      case GroupSortType.moderatorCount:
        list.sort(
          (a, b) => _isAscending
              ? a.moderatorCount.compareTo(b.moderatorCount)
              : b.moderatorCount.compareTo(a.moderatorCount),
        );
        break;
      case GroupSortType.mostOnline:
        list.sort(
          (a, b) => _isAscending
              ? a.onlineCount.compareTo(b.onlineCount)
              : b.onlineCount.compareTo(a.onlineCount),
        );
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
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 8.h,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'reset'.tr(),
                        style: TextStyle(
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
                            setState(
                              () => _sortType = GroupSortType.alphabetical,
                            );
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
                            setState(
                              () => _sortType = GroupSortType.newestToOldest,
                            );
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
                            setState(
                              () => _sortType = GroupSortType.oldestToNewest,
                            );
                            _saveSortPreferences();
                            Navigator.pop(ctx);
                          },
                          isDark: isDark,
                        ),
                        _SortOption(
                          label: 'sort_pilgrim_count'.tr(),
                          icon: Symbols.groups,
                          isSelected: _sortType == GroupSortType.pilgrimCount,
                          isAscending: _sortType == GroupSortType.pilgrimCount
                              ? _isAscending
                              : null,
                          onTap: () {
                            if (_sortType == GroupSortType.pilgrimCount) {
                              setState(() => _isAscending = !_isAscending);
                              setSheetState(() {});
                            } else {
                              setState(() {
                                _sortType = GroupSortType.pilgrimCount;
                                _isAscending =
                                    false; // Default to Descending for counts
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
                          isAscending: _sortType == GroupSortType.moderatorCount
                              ? _isAscending
                              : null,
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
                          isAscending: _sortType == GroupSortType.mostOnline
                              ? _isAscending
                              : null,
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
                          isSelected:
                              _sortType == GroupSortType.lowBatteryPriority,
                          onTap: () {
                            setState(
                              () =>
                                  _sortType = GroupSortType.lowBatteryPriority,
                            );
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
    _syncFilteredGroups(state.groups);
    final groups = _displayGroups;
    final showEmptyState =
        !state.isLoading && state.error == null && groups.isEmpty;

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          await ref.read(pendingInvitationsProvider.notifier).fetchPending();
          await ref
              .read(moderatorProvider.notifier)
              .loadDashboard(force: true);
        },
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
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const ResourcesScreen(),
                                  ),
                                );
                              },
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
                                      color: Colors.black.withValues(
                                        alpha: 0.06,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.business_center_rounded,
                                  size: 22.w,
                                  color: isDark
                                      ? AppColors.primary
                                      : const Color(0xFF8A6A30),
                                ),
                              ),
                            ),
                            SizedBox(width: 8.w),
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
                                          color: Colors.black.withValues(
                                            alpha: 0.06,
                                          ),
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
                                      child: _CountBadge(
                                        count: notifCount,
                                        isDark: isDark,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    SizedBox(height: 16.h),
                    const PendingInvitationsSection(),
                    SizedBox(height: 20.h),

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
                                fontSize: 14.sp,
                                color: isDark
                                    ? const Color(0xFFE2E8F0)
                                    : AppColors.textDark,
                              ),
                              decoration: InputDecoration(
                                hintText: 'dashboard_search_groups'.tr(),
                                hintStyle: TextStyle(
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
                          fontSize: 14.sp,
                          color: AppColors.textMutedLight,
                        ),
                      ),
                      SizedBox(height: 16.h),
                      TextButton.icon(
                        onPressed: () => ref
                            .read(moderatorProvider.notifier)
                            .loadDashboard(force: true),
                        icon: Icon(
                          Symbols.refresh,
                          size: 18.w,
                          color: AppColors.primary,
                        ),
                        label: Text(
                          'dashboard_retry'.tr(),
                          style: TextStyle(
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
                        bottom: i == groups.length - 1 ? 20.h : 12.h,
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
      StandardSnackBar.showSuccess(context, 'msg_group_deleted'.tr(args: [group.groupName]));
    } else {
      StandardSnackBar.showError(context, err ?? 'msg_group_delete_failed'.tr());
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
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: isDark ? AppColors.backgroundDark : const Color(0xFFE2E2F0),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(14.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.groupName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 17.sp,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF1A1A4E),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2.h),
                        Row(
                          children: [
                            Icon(
                              Symbols.tag,
                              size: 12.w,
                              color: AppColors.textMutedLight,
                            ),
                            SizedBox(width: 4.w),
                            Text(
                              group.groupCode,
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: AppColors.textMutedLight,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (group.sosCount > 0) ...[
                    _SosBadge(count: group.sosCount),
                    SizedBox(width: 6.w),
                  ],
                  GestureDetector(
                    onTap: () => _confirmDelete(context, ref),
                    child: Container(
                      width: 32.w,
                      height: 32.w,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF3D1515)
                            : const Color(0xFFFEE2E2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFEF4444).withValues(
                            alpha: 0.35,
                          ),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Symbols.delete,
                        size: 18.w,
                        color: const Color(0xFFDC2626),
                        fill: 1,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12.h),
              Container(
                padding: EdgeInsets.only(top: 10.h),
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
              SizedBox(height: 12.h),
              IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // View on Map
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              final userId =
                                  ref.read(authProvider).userId ?? '';
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GroupManagementScreen(
                                    groupId: group.id,
                                    currentUserId: userId,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              alignment: Alignment.center,
                              padding: EdgeInsets.symmetric(
                                vertical: 8.h,
                                horizontal: 10.w,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(
                                        0xFF6B7BAE,
                                      ).withValues(alpha: 0.1)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10.r),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(
                                          0xFF6B7BAE,
                                        ).withValues(alpha: 0.2)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Symbols.map,
                                    size: 16.w,
                                    color: const Color(0xFF6B7BAE),
                                  ),
                                  SizedBox(width: 6.w),
                                  Expanded(
                                    child: Text(
                                      'dashboard_view_on_map'.tr(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12.sp,
                                        height: 1.2,
                                        color: const Color(0xFF6B7BAE),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 4.w),
                                  Transform.scale(
                                    scaleX:
                                        Directionality.of(context) ==
                                            ui.TextDirection.rtl
                                        ? -1
                                        : 1,
                                    child: Icon(
                                      Symbols.arrow_forward,
                                      size: 13.w,
                                      color: const Color(0xFF6B7BAE),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              final userId =
                                  ref.read(authProvider).userId ?? '';
                              // Clear unread count when opening
                              ref
                                  .read(moderatorProvider.notifier)
                                  .clearUnreadCount(group.id);
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => GroupMessagesScreen(
                                    groupId: group.id,
                                    groupName: group.groupName,
                                    currentUserId: userId,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              alignment: Alignment.center,
                              padding: EdgeInsets.symmetric(
                                vertical: 8.h,
                                horizontal: 10.w,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(
                                        0xFF6B7BAE,
                                      ).withValues(alpha: 0.1)
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10.r),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(
                                          0xFF6B7BAE,
                                        ).withValues(alpha: 0.2)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Stack(
                                clipBehavior: Clip.none,
                                alignment: Alignment.center,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Symbols.chat_bubble,
                                        size: 16.w,
                                        color: const Color(0xFF6B7BAE),
                                      ),
                                      SizedBox(width: 6.w),
                                      Expanded(
                                        child: Text(
                                          'chat'.tr(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12.sp,
                                            color: const Color(0xFF6B7BAE),
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 4.w),
                                      Transform.scale(
                                        scaleX:
                                            Directionality.of(context) ==
                                                ui.TextDirection.rtl
                                            ? -1
                                            : 1,
                                        child: Icon(
                                          Symbols.arrow_forward,
                                          size: 13.w,
                                          color: const Color(0xFF6B7BAE),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (group.unreadCount > 0)
                                    Positioned(
                                      top: -2,
                                      right: -2,
                                      child: _CountBadge(
                                        count: group.unreadCount,
                                        isDark: isDark,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  final bool isDark;

  const _CountBadge({required this.count, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? AppColors.backgroundDark : Colors.white,
          width: 2.w,
        ),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: TextStyle(
          fontSize: 9.sp,
          fontWeight: FontWeight.w700,
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
            fontWeight: FontWeight.w500,
            fontSize: 9.sp,
            color: AppColors.textMutedLight,
            letterSpacing: 0.4,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16.sp,
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
      height: 32.h,
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
    final isDark =
        AppTheme.isDarkEffective(ref.watch(themeProvider), context);

    final items = [
      LiquidGlassBottomBarItem(
        icon: Symbols.groups,
        label: 'nav_groups'.tr(),
      ),
      LiquidGlassBottomBarItem(
        icon: Symbols.inbox,
        label: 'nav_provisioning'.tr(),
      ),
      LiquidGlassBottomBarItem(
        icon: Symbols.notifications_active,
        label: 'nav_reminders'.tr(),
      ),
      LiquidGlassBottomBarItem(
        icon: Symbols.person,
        label: 'nav_profile'.tr(),
      ),
    ];

    return AppLiquidGlassBottomBar(
      currentIndex: currentIndex,
      onTap: onTap,
      items: items,
      isDark: isDark,
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
