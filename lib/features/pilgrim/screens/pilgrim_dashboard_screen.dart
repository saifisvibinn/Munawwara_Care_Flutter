import 'dart:async';
import 'dart:ui' as ui;
import 'package:battery_plus/battery_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../calling/providers/call_provider.dart';
import '../../calling/screens/incoming_call_screen.dart';
import '../../notifications/providers/notification_provider.dart';
import '../../notifications/screens/alerts_tab.dart';
import '../../shared/providers/message_provider.dart';
import '../../shared/providers/suggested_area_provider.dart';
import '../../shared/models/suggested_area_model.dart';
import '../providers/pilgrim_provider.dart';
import 'group_inbox_screen.dart';
import 'join_group_screen.dart';
import 'pilgrim_profile_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim Dashboard Screen
// ─────────────────────────────────────────────────────────────────────────────

class PilgrimDashboardScreen extends ConsumerStatefulWidget {
  const PilgrimDashboardScreen({super.key});

  @override
  ConsumerState<PilgrimDashboardScreen> createState() =>
      _PilgrimDashboardScreenState();
}

class _PilgrimDashboardScreenState extends ConsumerState<PilgrimDashboardScreen>
    with TickerProviderStateMixin {
  // Bottom nav
  int _currentTab = 0;

  // SOS hold animation
  late AnimationController _sosHoldController;
  late AnimationController _sosPulseController;
  Timer? _sosTimer;
  Timer? _sosCountdownTimer;
  bool _isSosHolding = false;
  int _sosCountdown = 3;

  // Location
  StreamSubscription<Position>? _locationSub;
  final Battery _battery = Battery();
  final MapController _mapController = MapController();
  LatLng? _myLatLng;

  // Named reconnect handler so offConnected can find it.
  void _onSocketConnected() {
    if (!mounted) return;
    final reconnectGroupId = ref.read(pilgrimProvider).groupInfo?.groupId;
    if (reconnectGroupId != null) {
      SocketService.emit('join_group', reconnectGroupId);
    }
  }

  @override
  void initState() {
    super.initState();

    // SOS hold progress ring (fills in 3 s)
    _sosHoldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // SOS pulse (idle pulsing glow)
    _sosPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    // Eagerly initialise callProvider so its socket listeners are registered
    // in SocketService._pendingListeners BEFORE the socket is connected below.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(callProvider.notifier).reRegisterListeners();
    });

    // Load data after first frame so the provider is ready
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(pilgrimProvider.notifier).loadDashboard();
      final groupId = ref.read(pilgrimProvider).groupInfo?.groupId;
      if (groupId != null) {
        ref.read(messageProvider.notifier).fetchUnreadCount(groupId);
      }
      // Connect socket with this pilgrim's identity
      final auth = ref.read(authProvider);
      if (auth.userId != null) {
        final socketUrl = ApiService.baseUrl.replaceFirst(RegExp(r'/api$'), '');
        SocketService.connect(
          serverUrl: socketUrl,
          userId: auth.userId!,
          role: auth.role ?? 'pilgrim',
        );
        ref.read(callProvider.notifier).reRegisterListeners();
        // Join group socket room so we receive group-scoped events
        final gId = ref.read(pilgrimProvider).groupInfo?.groupId;
        if (gId != null) SocketService.emit('join_group', gId);
        // Re-join group room on every reconnect (so beacon state is re-synced)
        SocketService.onConnected(_onSocketConnected);
        // Listen for moderator navigation beacon
        SocketService.on('mod_nav_beacon', (data) {
          if (!mounted) return;
          final map = data as Map<String, dynamic>;
          final modId = map['moderatorId'] as String? ?? '';
          final modName = map['moderatorName'] as String? ?? 'Moderator';
          final enabled = map['enabled'] as bool? ?? false;
          final lat = (map['lat'] as num?)?.toDouble();
          final lng = (map['lng'] as num?)?.toDouble();
          ref
              .read(pilgrimProvider.notifier)
              .updateModeratorBeacon(modId, modName, enabled, lat, lng);
        });

        // Listen for new group messages — append silently to avoid flicker
        SocketService.on('new_message', (data) {
          if (!mounted) return;
          final groupId = ref.read(pilgrimProvider).groupInfo?.groupId;
          if (groupId == null) return;
          // Append the single message without a full reload (no spinner)
          ref
              .read(messageProvider.notifier)
              .appendMessage(data as Map<String, dynamic>);
          if (_currentTab == 3) {
            // User is on Chat tab → mark as read immediately
            ref.read(messageProvider.notifier).markAllRead(groupId);
          }
          // unreadCount was already bumped by appendMessage for other tabs
        });

        // Listen for deleted messages — remove silently to avoid flicker
        SocketService.on('message_deleted', (data) {
          if (!mounted) return;
          final map = data as Map<String, dynamic>;
          final messageId = map['message_id'] as String?;
          if (messageId != null) {
            ref.read(messageProvider.notifier).removeMessage(messageId);
          }
        });

        // Listen for suggested area / meetpoint additions
        SocketService.on('area_added', (data) {
          if (!mounted) return;
          ref
              .read(suggestedAreaProvider.notifier)
              .appendArea(data as Map<String, dynamic>);
        });

        // Listen for suggested area / meetpoint deletions
        SocketService.on('area_deleted', (data) {
          if (!mounted) return;
          final map = data as Map<String, dynamic>;
          final areaId = map['area_id'] as String?;
          if (areaId != null) {
            ref.read(suggestedAreaProvider.notifier).removeArea(areaId);
          }
        });

        // Listen for notification refresh (new area/meetpoint/SOS notifications)
        // refetch() updates the full list + badge without auto-marking as read
        SocketService.on('notification_refresh', (_) {
          if (!mounted) return;
          ref.read(notificationProvider.notifier).refetch();
        });
      }
      // Fetch notification badge count
      ref.read(notificationProvider.notifier).fetchUnreadCount();
      // Load suggested areas if in a group
      final gIdForAreas = ref.read(pilgrimProvider).groupInfo?.groupId;
      if (gIdForAreas != null) {
        ref.read(suggestedAreaProvider.notifier).load(gIdForAreas);
      }
      _initLocation();
    });
  }

  @override
  void dispose() {
    _sosHoldController.dispose();
    _sosPulseController.dispose();
    _mapController.dispose();
    _sosTimer?.cancel();
    _sosCountdownTimer?.cancel();
    _locationSub?.cancel();
    SocketService.off('mod_nav_beacon');
    SocketService.off('new_message');
    SocketService.off('message_deleted');
    SocketService.off('area_added');
    SocketService.off('area_deleted');
    SocketService.off('notification_refresh');
    SocketService.offConnected(_onSocketConnected);
    super.dispose();
  }

  // ── Location ────────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) return;
    if (!mounted) return;

    _locationSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 20, // metres
          ),
        ).listen((pos) async {
          final ll = LatLng(pos.latitude, pos.longitude);
          setState(() => _myLatLng = ll);
          int? battery;
          try {
            final lvl = await _battery.batteryLevel;
            battery = lvl;
            ref.read(pilgrimProvider.notifier).setBattery(lvl);
          } catch (_) {}
          ref
              .read(pilgrimProvider.notifier)
              .updateLocation(
                latitude: pos.latitude,
                longitude: pos.longitude,
                batteryPercent: battery,
              );
        });
  }

  // ── SOS Logic ───────────────────────────────────────────────────────────────

  void _onSosHoldStart() {
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    setState(() {
      _isSosHolding = true;
      _sosCountdown = 3;
    });
    _sosHoldController.forward(from: 0);
    _sosTimer = Timer(const Duration(seconds: 3), _fireSOS);
    _sosCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_sosCountdown > 1) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.alert);
        setState(() => _sosCountdown--);
      }
    });
  }

  void _onSosHoldEnd() {
    if (!_isSosHolding) return;
    _sosHoldController.reverse();
    _sosTimer?.cancel();
    _sosCountdownTimer?.cancel();
    setState(() {
      _isSosHolding = false;
      _sosCountdown = 3;
    });
  }

  Future<void> _fireSOS() async {
    _sosCountdownTimer?.cancel();
    HapticFeedback.vibrate();
    setState(() {
      _isSosHolding = false;
      _sosCountdown = 3;
    });
    _sosHoldController.value = 0;
    final ok = await ref.read(pilgrimProvider.notifier).triggerSOS();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ok ? Colors.red.shade700 : Colors.grey.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        content: Text(
          ok ? 'sos_sent'.tr() : 'sos_failed'.tr(),
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  void _cancelSOS() {
    ref.read(pilgrimProvider.notifier).cancelSOS();
    final groupId = ref.read(pilgrimProvider).groupInfo?.groupId;
    if (groupId != null) {
      SocketService.emit('sos_cancel', {
        'groupId': groupId,
        'pilgrimId': ref.read(authProvider).userId,
      });
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        content: Text(
          'sos_cancelled'.tr(),
          style: const TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  // ── Join Group ──────────────────────────────────────────────────────────────

  Future<void> _openJoinGroup() async {
    final result = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const JoinGroupScreen()));
    if (result == true && mounted) {
      await ref.read(pilgrimProvider.notifier).loadDashboard();
      final gId = ref.read(pilgrimProvider).groupInfo?.groupId;
      if (gId != null) {
        SocketService.emit('join_group', gId);
        ref.read(messageProvider.notifier).fetchUnreadCount(gId);
      }
    }
  }

  // ── Navigate to Moderator ──────────────────────────────────────────────────

  Future<void> _navigateToModerator(ModeratorBeacon beacon) async {
    final lat = beacon.lat;
    final lng = beacon.lng;
    final googleMapsApp = Uri.parse('google.navigation:q=$lat,$lng&mode=w');
    final googleMapsWeb = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
    );
    try {
      if (await canLaunchUrl(googleMapsApp)) {
        await launchUrl(googleMapsApp);
      } else {
        await launchUrl(googleMapsWeb, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(googleMapsWeb, mode: LaunchMode.externalApplication);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pilgrimState = ref.watch(pilgrimProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Show incoming call screen when a call arrives
    ref.listen(callProvider, (_, next) {
      if (next.status == CallStatus.ringing && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const IncomingCallScreen(),
          ),
        );
      }
    });

    final notifCount = ref.watch(notificationProvider).unreadCount;

    final tabs = [
      _HomeTab(
        pilgrimState: pilgrimState,
        isDark: isDark,
        sosPulseController: _sosPulseController,
        sosHoldController: _sosHoldController,
        isSosHolding: _isSosHolding,
        onSosHoldStart: _onSosHoldStart,
        onSosHoldEnd: _onSosHoldEnd,
        onRefresh: () => ref.read(pilgrimProvider.notifier).loadDashboard(),
        sosCountdown: _sosCountdown,
        onCancelSos: _cancelSOS,
        navBeacons: pilgrimState.navBeacons,
        onNavigateToModerator: _navigateToModerator,
        notificationCount: notifCount,
        onNotificationTap: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (_) => const _PilgrimNotificationsScreen(),
                ),
              )
              .then((_) {
                // Refresh badge when coming back
                ref.read(notificationProvider.notifier).fetchUnreadCount();
              });
        },
        onJoinGroup: _openJoinGroup,
      ),
      _PilgrimMapTab(
        myLocation: _myLatLng,
        mapController: _mapController,
        pilgrimState: pilgrimState,
        areas: ref.watch(suggestedAreaProvider).areas,
      ),
      const _PlaceholderTab(icon: Symbols.calendar_month, label: 'tab_plan'),
      pilgrimState.groupInfo != null
          ? GroupInboxScreen(
              groupId: pilgrimState.groupInfo!.groupId,
              groupName: pilgrimState.groupInfo!.groupName,
            )
          : const _PlaceholderTab(
              icon: Symbols.chat_bubble,
              label: 'pilgrim_no_group',
            ),
      const PilgrimProfileScreen(),
    ];

    return PopScope(
      canPop: _currentTab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          setState(() => _currentTab = 0);
        }
      },
      child: Scaffold(
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : const Color(0xfff1f5f3),
        body: IndexedStack(index: _currentTab, children: tabs),
        floatingActionButton: SizedBox(
          width: 56.w,
          height: 56.w,
          child: FloatingActionButton(
            onPressed: _openJoinGroup,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            elevation: 6,
            child: Icon(Symbols.qr_code_scanner, size: 26.w),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
        bottomNavigationBar: _BottomNav(
          currentIndex: _currentTab,
          onTap: (i) {
            setState(() => _currentTab = i);
            // Reload + mark messages as read when opening Chat tab
            if (i == 3) {
              final groupId = ref.read(pilgrimProvider).groupInfo?.groupId;
              if (groupId != null) {
                ref.read(messageProvider.notifier).loadMessages(groupId);
                ref.read(messageProvider.notifier).markAllRead(groupId);
              }
            }
          },
          unreadMessages: ref.watch(messageProvider).unreadCount,
          isDark: isDark,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Home Tab
// ─────────────────────────────────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  final PilgrimState pilgrimState;
  final bool isDark;
  final AnimationController sosPulseController;
  final AnimationController sosHoldController;
  final bool isSosHolding;
  final VoidCallback onSosHoldStart;
  final VoidCallback onSosHoldEnd;
  final Future<void> Function() onRefresh;
  final int sosCountdown;
  final VoidCallback onCancelSos;
  final Map<String, ModeratorBeacon> navBeacons;
  final void Function(ModeratorBeacon) onNavigateToModerator;
  final int notificationCount;
  final VoidCallback onNotificationTap;
  final VoidCallback onJoinGroup;

  const _HomeTab({
    required this.pilgrimState,
    required this.isDark,
    required this.sosPulseController,
    required this.sosHoldController,
    required this.isSosHolding,
    required this.onSosHoldStart,
    required this.onSosHoldEnd,
    required this.onRefresh,
    required this.sosCountdown,
    required this.onCancelSos,
    required this.navBeacons,
    required this.onNavigateToModerator,
    required this.notificationCount,
    required this.onNotificationTap,
    required this.onJoinGroup,
  });

  @override
  Widget build(BuildContext context) {
    final profile = pilgrimState.profile;
    final group = pilgrimState.groupInfo;

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: onRefresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Header ──────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 0),
                child: Row(
                  children: [
                    // Logo
                    Container(
                      width: 52.w,
                      height: 52.w,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Symbols.mosque,
                        size: 26.w,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MUNAWWARA CARE',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                          ),
                          Text(
                            pilgrimState.isLoading
                                ? '${'pilgrim_id_prefix'.tr()} ...'
                                : '${'pilgrim_id_prefix'.tr()} ${profile?.displayId ?? '------'}',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12.sp,
                              color: AppColors.textMutedLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Notification bell
                    GestureDetector(
                      onTap: onNotificationTap,
                      child: Stack(
                        children: [
                          Container(
                            width: 42.w,
                            height: 42.w,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.surfaceDark
                                  : Colors.white,
                              shape: BoxShape.circle,
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
                              size: 22.w,
                              color: isDark
                                  ? Colors.white70
                                  : AppColors.textDark,
                            ),
                          ),
                          if (notificationCount > 0)
                            Positioned(
                              top: 2.w,
                              right: 0,
                              child: Container(
                                padding: EdgeInsets.all(3.w),
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                                constraints: BoxConstraints(
                                  minWidth: 16.w,
                                  minHeight: 16.w,
                                ),
                                child: Text(
                                  notificationCount > 9
                                      ? '9+'
                                      : '$notificationCount',
                                  style: TextStyle(
                                    fontSize: 9.sp,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
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

            SliverToBoxAdapter(child: SizedBox(height: 28.h)),

            // ── Greeting ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'greeting_prefix'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 28.sp,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    Text(
                      pilgrimState.isLoading
                          ? '...'
                          : (profile?.firstName ?? ''),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 32.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Row(
                      children: [
                        Container(
                          width: 10.w,
                          height: 10.w,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'status_safe_label'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            color: isDark ? Colors.white70 : AppColors.textDark,
                          ),
                        ),
                        Text(
                          ' ${'status_safe'.tr()}',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(child: SizedBox(height: 24.h)),

            // ── Info Cards ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Row(
                  children: [
                    // Group card
                    Expanded(
                      child: _InfoCard(
                        isDark: isDark,
                        icon: Symbols.groups,
                        iconColor: AppColors.primary,
                        label: 'card_my_group'.tr(),
                        value: group?.groupName ?? 'card_no_group'.tr(),
                        badge: null,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    // Location sharing card
                    Expanded(
                      child: _InfoCard(
                        isDark: isDark,
                        icon: Symbols.location_on,
                        iconColor: AppColors.primary,
                        label: 'card_sharing'.tr(),
                        value: pilgrimState.isSharingLocation
                            ? 'card_active'.tr()
                            : 'card_paused'.tr(),
                        badge: pilgrimState.batteryLevel != null
                            ? '🔋 ${pilgrimState.batteryLevel}%'
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(child: SizedBox(height: 40.h)),

            // ── SOS Button ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Center(
                child: Column(
                  children: [
                    _SosButton(
                      pulseController: sosPulseController,
                      holdController: sosHoldController,
                      isHolding: isSosHolding,
                      isLoading: pilgrimState.isSosLoading,
                      sosActive: pilgrimState.sosActive,
                      countdown: sosCountdown,
                      onHoldStart: onSosHoldStart,
                      onHoldEnd: onSosHoldEnd,
                    ),
                    SizedBox(height: 20.h),
                    Text(
                      'sos_title'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      pilgrimState.sosActive
                          ? 'sos_active_label'.tr()
                          : isSosHolding
                          ? ''
                          : 'sos_hold_hint'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13.sp,
                        color: pilgrimState.sosActive
                            ? Colors.red.shade600
                            : AppColors.textMutedLight,
                        fontWeight: pilgrimState.sosActive
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                    if (pilgrimState.sosActive) ...[
                      SizedBox(height: 12.h),
                      GestureDetector(
                        onTap: onCancelSos,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 28.w,
                            vertical: 10.h,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.red.shade400,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(20.r),
                          ),
                          child: Text(
                            'sos_cancel'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w700,
                              fontSize: 14.sp,
                              color: Colors.red.shade500,
                            ),
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 24.h),
                  ],
                ),
              ),
            ),

            // ── Navigate to Moderator ────────────────────────────────────
            if (navBeacons.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : Colors.white,
                      borderRadius: BorderRadius.circular(20.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 8.h),
                          child: Row(
                            children: [
                              Icon(
                                Symbols.my_location,
                                size: 18.w,
                                color: AppColors.primary,
                              ),
                              SizedBox(width: 8.w),
                              Text(
                                'nav_to_moderator'.tr(),
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.sp,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        ...navBeacons.values.map(
                          (beacon) => Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16.w,
                              vertical: 10.h,
                            ),
                            child: Row(
                              children: [
                                // Avatar
                                Container(
                                  width: 40.w,
                                  height: 40.w,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Symbols.person_pin_circle,
                                    size: 22.w,
                                    color: AppColors.primary,
                                  ),
                                ),
                                SizedBox(width: 12.w),
                                // Name
                                Expanded(
                                  child: Text(
                                    beacon.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14.sp,
                                      color: isDark
                                          ? Colors.white
                                          : AppColors.textDark,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 10.w),
                                // Navigate button
                                GestureDetector(
                                  onTap: () => onNavigateToModerator(beacon),
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 14.w,
                                      vertical: 9.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(14.r),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.primary.withOpacity(
                                            0.35,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Symbols.navigation,
                                          color: Colors.white,
                                          size: 16.w,
                                        ),
                                        SizedBox(width: 6.w),
                                        Text(
                                          'nav_go'.tr(),
                                          style: TextStyle(
                                            fontFamily: 'Lexend',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.sp,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 8.h),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SOS Button Widget
// ─────────────────────────────────────────────────────────────────────────────

class _SosButton extends StatefulWidget {
  final AnimationController pulseController;
  final AnimationController holdController;
  final bool isHolding;
  final bool isLoading;
  final bool sosActive;
  final int countdown;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  const _SosButton({
    required this.pulseController,
    required this.holdController,
    required this.isHolding,
    required this.isLoading,
    required this.sosActive,
    required this.countdown,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  @override
  State<_SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<_SosButton>
    with SingleTickerProviderStateMixin {
  bool _isPressed = false;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onDown() {
    setState(() => _isPressed = true);
    _scaleController.forward();
  }

  void _onUp() {
    setState(() => _isPressed = false);
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    const double size = 180;
    const double ringStroke = 6;

    return GestureDetector(
      onLongPressDown: (_) => _onDown(),
      onLongPressStart: (_) => widget.onHoldStart(),
      onLongPressEnd: (_) {
        _onUp();
        widget.onHoldEnd();
      },
      onLongPressCancel: () {
        _onUp();
        widget.onHoldEnd();
      },
      child: AnimatedBuilder(
        animation: _scaleAnim,
        builder: (_, child) =>
            Transform.scale(scale: _scaleAnim.value, child: child),
        child: SizedBox(
          width: size.w,
          height: size.w,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulse glow
              AnimatedBuilder(
                animation: widget.pulseController,
                builder: (_, _) {
                  final scale = 1.0 + 0.15 * widget.pulseController.value;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: size.w,
                      height: size.w,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withOpacity(
                          0.15 * widget.pulseController.value,
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Main red circle
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: (size - 20).w,
                height: (size - 20).w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: _isPressed || widget.isHolding
                        ? [Colors.red.shade600, Colors.red.shade900]
                        : [
                            widget.sosActive
                                ? Colors.red.shade300
                                : Colors.red.shade400,
                            widget.sosActive
                                ? Colors.red.shade700
                                : Colors.red.shade700,
                          ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(
                        _isPressed || widget.isHolding ? 0.25 : 0.45,
                      ),
                      blurRadius: _isPressed || widget.isHolding ? 14 : 30,
                      spreadRadius: _isPressed || widget.isHolding ? 1 : 4,
                    ),
                  ],
                ),
                child: widget.isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      )
                    : widget.isHolding
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${widget.countdown}',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 56.sp,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'sec',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14.sp,
                              color: Colors.white70,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.sosActive ? 'ACTIVE' : '505',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 20.sp,
                              fontWeight: FontWeight.w900,
                              color: Colors.white.withOpacity(0.6),
                              letterSpacing: 2,
                            ),
                          ),
                          Text(
                            'SOS',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 28.sp,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 4,
                            ),
                          ),
                        ],
                      ),
              ),

              // Hold progress ring
              if (widget.isHolding)
                AnimatedBuilder(
                  animation: widget.holdController,
                  builder: (_, _) => SizedBox(
                    width: size.w,
                    height: size.w,
                    child: CircularProgressIndicator(
                      value: widget.holdController.value,
                      strokeWidth: ringStroke,
                      color: Colors.white,
                      backgroundColor: Colors.white.withOpacity(0.2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Info Card Widget
// ─────────────────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String? badge;

  const _InfoCard({
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42.w,
                height: 42.w,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 22.w, color: iconColor),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12.sp,
              color: AppColors.textMutedLight,
            ),
          ),
          SizedBox(height: 2.h),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (badge != null) ...[
                SizedBox(width: 4.w),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Navigation Bar
// ─────────────────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int unreadMessages;
  final bool isDark;

  const _BottomNav({
    required this.currentIndex,
    required this.onTap,
    required this.unreadMessages,
    required this.isDark,
  });

  // Tabs that appear in the nav bar (skip index 2 which is the FAB slot)
  static const _navMap = [0, 1, 3, 4];

  @override
  Widget build(BuildContext context) {
    final labels = [
      'tab_home'.tr(),
      'tab_map'.tr(),
      'tab_chat'.tr(),
      'settings_title'.tr(),
    ];
    final icons = [
      Symbols.home,
      Symbols.map,
      Symbols.chat_bubble,
      Symbols.settings,
    ];
    final tabIndices = _navMap;
    final badges = [0, 0, unreadMessages, 0];

    return BottomAppBar(
      color: isDark ? AppColors.surfaceDark : Colors.white,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      padding: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      height: 66.h,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Left two tabs
          ...List.generate(2, (slot) {
            final i = tabIndices[slot];
            final isSelected = i == currentIndex;
            return GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 60.w,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 44.w,
                      height: 32.h,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withOpacity(0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Icon(
                        icons[slot],
                        size: 22.w,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textMutedLight,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      labels[slot],
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 10.sp,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textMutedLight,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          }),

          // Center gap for FAB
          SizedBox(width: 60.w),

          // Right two tabs (chat + settings)
          ...List.generate(2, (slot) {
            final listSlot = slot + 2; // slots 2 & 3 in our lists
            final i = tabIndices[listSlot];
            final isSelected = i == currentIndex;
            return GestureDetector(
              onTap: () => onTap(i),
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
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44.w,
                          height: 32.h,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withOpacity(0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Icon(
                            icons[listSlot],
                            size: 22.w,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textMutedLight,
                          ),
                        ),
                        if (badges[listSlot] > 0)
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              padding: EdgeInsets.all(3.w),
                              decoration: const BoxDecoration(
                                color: Colors.orange,
                                shape: BoxShape.circle,
                              ),
                              constraints: BoxConstraints(
                                minWidth: 14.w,
                                minHeight: 14.w,
                              ),
                              child: Text(
                                badges[listSlot] > 9
                                    ? '9+'
                                    : '${badges[listSlot]}',
                                style: TextStyle(
                                  fontSize: 9.sp,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      labels[listSlot],
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 10.sp,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textMutedLight,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Map Tab
// ─────────────────────────────────────────────────────────────────────────────

class _PilgrimMapTab extends StatelessWidget {
  final LatLng? myLocation;
  final MapController mapController;
  final PilgrimState pilgrimState;
  final List<SuggestedArea> areas;

  const _PilgrimMapTab({
    required this.myLocation,
    required this.mapController,
    required this.pilgrimState,
    required this.areas,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final group = pilgrimState.groupInfo;

    return Stack(
      children: [
        // Map
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: myLocation ?? const LatLng(21.3891, 39.8579),
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.munawwaracare.app',
            ),
            // Suggested areas & meetpoints
            if (areas.isNotEmpty)
              MarkerLayer(
                markers: [
                  for (var area in areas)
                    Marker(
                      point: LatLng(area.latitude, area.longitude),
                      width: 80.w,
                      height: 82.h,
                      child: GestureDetector(
                        onTap: () => _showAreaInfo(context, area),
                        child: _PilgrimAreaMarker(area: area),
                      ),
                    ),
                ],
              ),
            // My location
            if (myLocation != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: myLocation!,
                    width: 60.w,
                    height: 72.h,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 46.w,
                          height: 46.w,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.5),
                                blurRadius: 10,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: Icon(
                            Symbols.person,
                            color: Colors.white,
                            size: 22.w,
                          ),
                        ),
                        Container(
                          margin: EdgeInsets.only(top: 2.h),
                          padding: EdgeInsets.symmetric(
                            horizontal: 5.w,
                            vertical: 2.h,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            'You',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w700,
                              fontSize: 10.sp,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),

        // Top overlay: group name
        if (group != null)
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(14.w),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 16.r,
                      backgroundColor: AppColors.primary.withOpacity(0.15),
                      child: Icon(
                        Symbols.group,
                        color: AppColors.primary,
                        size: 16.w,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      group.groupName,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 13.sp,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Center FAB (my location)
        Positioned(
          right: 14.w,
          bottom: 14.h,
          child: GestureDetector(
            onTap: () {
              if (myLocation != null) {
                mapController.move(myLocation!, 15);
              }
            },
            child: Container(
              width: 48.w,
              height: 48.w,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Symbols.my_location,
                color: isDark ? Colors.white : AppColors.textDark,
                size: 22.w,
              ),
            ),
          ),
        ),

        // Meetpoint pin button (only when active meetpoint exists)
        if (areas.any((a) => a.isMeetpoint))
          Positioned(
            right: 14.w,
            bottom: 74.h,
            child: GestureDetector(
              onTap: () {
                final mp = areas.firstWhere((a) => a.isMeetpoint);
                mapController.move(LatLng(mp.latitude, mp.longitude), 17);
                _showAreaInfo(context, mp);
              },
              child: Container(
                width: 48.w,
                height: 48.w,
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFDC2626).withOpacity(0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  Symbols.crisis_alert,
                  color: Colors.white,
                  size: 22.w,
                ),
              ),
            ),
          ),

        // Suggestions pin button (only when suggestions exist)
        if (areas.any((a) => !a.isMeetpoint))
          Positioned(
            right: 14.w,
            bottom: areas.any((a) => a.isMeetpoint) ? 134.h : 74.h,
            child: _SuggestionsCycleButton(
              areas: areas.where((a) => !a.isMeetpoint).toList(),
              mapController: mapController,
              onAreaSelected: (area) => _showAreaInfo(context, area),
            ),
          ),

        // No location message
        if (myLocation == null)
          Center(
            child: Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Symbols.location_off,
                    size: 40.w,
                    color: AppColors.textMutedLight,
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'pilgrim_locating'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: AppColors.textMutedLight,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim Notifications Screen — wraps AlertsTab in a Scaffold with back nav
// ─────────────────────────────────────────────────────────────────────────────

class _PilgrimNotificationsScreen extends StatelessWidget {
  const _PilgrimNotificationsScreen();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : const Color(0xfff1f5f3),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(8.w, 12.h, 20.w, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: isDark ? Colors.white : AppColors.textDark,
                      size: 20.sp,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            const Expanded(child: AlertsTab()),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Placeholder Tab
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
          Icon(icon, size: 48, color: AppColors.textMutedLight),
          const SizedBox(height: 12),
          Text(
            label.tr(),
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontSize: 16,
              color: AppColors.textMutedLight,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'pilgrim_coming_soon'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13,
              color: AppColors.textMutedLight.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim area marker (suggestions = primary, meetpoints = red)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// Suggestions button (tapping shows all suggested areas in a list)
// ─────────────────────────────────────────────────────────────────────────────

class _SuggestionsCycleButton extends StatefulWidget {
  final List<SuggestedArea> areas;
  final MapController mapController;
  final void Function(SuggestedArea) onAreaSelected;
  const _SuggestionsCycleButton({
    required this.areas,
    required this.mapController,
    required this.onAreaSelected,
  });

  @override
  State<_SuggestionsCycleButton> createState() =>
      _SuggestionsCycleButtonState();
}

class _SuggestionsCycleButtonState extends State<_SuggestionsCycleButton> {
  void _showAreaList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.65,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'area_view_all'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 17.sp,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
            SizedBox(height: 16.h),
            Flexible(
              child: widget.areas.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.w),
                        child: Text(
                          'area_empty'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13.sp,
                            color: AppColors.textMutedLight,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.areas.length,
                      itemBuilder: (_, i) {
                        final area = widget.areas[i];
                        return Container(
                          margin: EdgeInsets.only(bottom: 10.h),
                          padding: EdgeInsets.all(12.w),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.backgroundDark
                                : const Color(0xFFF0F0F8),
                            borderRadius: BorderRadius.circular(14.r),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36.w,
                                height: 36.w,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Symbols.pin_drop,
                                  color: Colors.white,
                                  size: 18.w,
                                ),
                              ),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      area.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.sp,
                                        color: isDark
                                            ? Colors.white
                                            : AppColors.textDark,
                                      ),
                                    ),
                                    if (area.description.isNotEmpty) ...[
                                      SizedBox(height: 3.h),
                                      Text(
                                        area.description,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 11.sp,
                                          color: AppColors.textMutedLight,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              GestureDetector(
                                onTap: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: ctx,
                                    builder: (dialogCtx) => AlertDialog(
                                      backgroundColor: isDark
                                          ? AppColors.surfaceDark
                                          : Colors.white,
                                      title: Text(
                                        'area_navigate_confirm_title'.tr(),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          color: isDark
                                              ? Colors.white
                                              : AppColors.textDark,
                                        ),
                                      ),
                                      content: Text(
                                        'area_navigate_confirm_message'.tr(),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          color: isDark
                                              ? Colors.white70
                                              : AppColors.textDark,
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogCtx, false),
                                          child: Text(
                                            'area_cancel'.tr(),
                                            style: const TextStyle(
                                              fontFamily: 'Lexend',
                                              color: AppColors.textMutedLight,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogCtx, true),
                                          child: Text(
                                            'area_open_maps'.tr(),
                                            style: const TextStyle(
                                              fontFamily: 'Lexend',
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    final lat = area.latitude;
                                    final lng = area.longitude;
                                    final googleMapsApp = Uri.parse(
                                      'google.navigation:q=$lat,$lng&mode=w',
                                    );
                                    final googleMapsWeb = Uri.parse(
                                      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
                                    );
                                    try {
                                      if (await canLaunchUrl(googleMapsApp)) {
                                        await launchUrl(googleMapsApp);
                                      } else {
                                        await launchUrl(
                                          googleMapsWeb,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      }
                                    } catch (_) {
                                      await launchUrl(
                                        googleMapsWeb,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    }
                                  }
                                },
                                child: Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.w,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Symbols.navigation,
                                        size: 20.w,
                                        color: AppColors.primary,
                                        fill: 1,
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        'area_navigate'.tr(),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 9.sp,
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                        ),
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
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.areas.length;
    return GestureDetector(
      onTap: () {
        if (widget.areas.isEmpty) return;
        _showAreaList();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.45),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(
              Symbols.pin_drop,
              color: Colors.white,
              size: 22.w,
              fill: 1,
            ),
          ),
          if (count > 1)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                width: 18.w,
                height: 18.w,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 10.sp,
                      color: AppColors.primary,
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

// ─────────────────────────────────────────────────────────────────────────────
// Area info bottom sheet + marker
// ─────────────────────────────────────────────────────────────────────────────

void _showAreaInfo(BuildContext context, SuggestedArea area) {
  final isMeetpoint = area.isMeetpoint;
  final color = isMeetpoint ? const Color(0xFFDC2626) : AppColors.primary;
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 32.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(height: 16.h),
          Container(
            width: 56.w,
            height: 56.w,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isMeetpoint ? Symbols.crisis_alert : Symbols.pin_drop,
              color: color,
              size: 28.w,
              fill: 1,
            ),
          ),
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              isMeetpoint
                  ? 'area_meetpoint'.tr()
                  : 'area_suggestion_label'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 10.sp,
                color: color,
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            area.name,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 17.sp,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
            textAlign: TextAlign.center,
          ),
          if (area.description.isNotEmpty) ...[
            SizedBox(height: 6.h),
            Text(
              area.description,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                color: AppColors.textMutedLight,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          SizedBox(height: 6.h),
          Text(
            '${'area_by'.tr()} ${area.createdByName}',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11.sp,
              color: AppColors.textMutedLight,
            ),
          ),
          SizedBox(height: 20.h),
          SizedBox(
            width: double.infinity,
            height: 50.h,
            child: ElevatedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: ctx,
                  builder: (dialogCtx) => AlertDialog(
                    backgroundColor: isDark
                        ? AppColors.surfaceDark
                        : Colors.white,
                    title: Text(
                      'area_navigate_confirm_title'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    content: Text(
                      'area_navigate_confirm_message'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        color: isDark ? Colors.white70 : AppColors.textDark,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, false),
                        child: Text(
                          'area_cancel'.tr(),
                          style: const TextStyle(
                            fontFamily: 'Lexend',
                            color: AppColors.textMutedLight,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx, true),
                        child: Text(
                          'area_open_maps'.tr(),
                          style: const TextStyle(
                            fontFamily: 'Lexend',
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  Navigator.pop(ctx);
                  final lat = area.latitude;
                  final lng = area.longitude;
                  final googleMapsApp = Uri.parse(
                    'google.navigation:q=$lat,$lng&mode=w',
                  );
                  final googleMapsWeb = Uri.parse(
                    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
                  );
                  try {
                    if (await canLaunchUrl(googleMapsApp)) {
                      await launchUrl(googleMapsApp);
                    } else {
                      await launchUrl(
                        googleMapsWeb,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  } catch (_) {
                    await launchUrl(
                      googleMapsWeb,
                      mode: LaunchMode.externalApplication,
                    );
                  }
                }
              },
              icon: Icon(
                Symbols.navigation,
                size: 20.w,
                color: Colors.white,
                fill: 1,
              ),
              label: Text(
                'area_navigate'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 15.sp,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.r),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PilgrimAreaMarker extends StatelessWidget {
  final SuggestedArea area;
  const _PilgrimAreaMarker({required this.area});

  @override
  Widget build(BuildContext context) {
    final color = area.isMeetpoint
        ? const Color(0xFFDC2626)
        : AppColors.primary;
    final icon = area.isMeetpoint ? Symbols.crisis_alert : Symbols.pin_drop;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10.r),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.35),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
            border: Border.all(color: color, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14.w, color: color, fill: 1),
              SizedBox(width: 4.w),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 56.w),
                child: Text(
                  area.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 9.sp,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Triangle tail
        CustomPaint(
          size: Size(10.w, 6.h),
          painter: _AreaTailPainter(color: color),
        ),
        // Circle dot
        Container(
          width: 10.w,
          height: 10.w,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: 6,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AreaTailPainter extends CustomPainter {
  final Color color;
  const _AreaTailPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_AreaTailPainter old) => old.color != color;
}
