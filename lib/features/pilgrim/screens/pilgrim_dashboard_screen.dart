import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/helpers/chat_notification_helper.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/location_permission_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/map/app_map_tiles.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../calling/providers/call_provider.dart';
import '../../calling/providers/missed_calls_unread_provider.dart';
import '../../calling/screens/voice_call_screen.dart';
import '../../calling/native_call_coordinator.dart' show isNavigatingToCall;
import '../../notifications/providers/notification_provider.dart';
import '../../shared/providers/message_provider.dart';
import '../../shared/providers/suggested_area_provider.dart';
import '../providers/pilgrim_provider.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/home_tab/home_cards.dart';
import '../widgets/home_tab/home_tab.dart';
import '../widgets/map_tab/pilgrim_map_tab.dart';
import '../widgets/sos/sos_home_phase.dart';
import 'group_details_screen.dart';
import 'group_inbox_screen.dart';
import 'mecca_hotspots_screen.dart';
import 'pilgrim_notifications_screen.dart';
import 'pilgrim_profile_screen.dart';
import 'qibla_compass_screen.dart';

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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _isInitializingDashboard = true;
  // Bottom nav
  int _currentTab = 0;

  // Notifier to trigger chat scroll-to-bottom on tab switch
  final ValueNotifier<int> _chatScrollNotifier = ValueNotifier<int>(0);

  // SOS hold animation
  late AnimationController _sosHoldController;
  late AnimationController _sosPulseController;
  Timer? _sosTimer;
  Timer? _sosCountdownTimer;
  bool _isSosHolding = false;
  int _sosCountdown = 3;
  Timer? _weatherRefreshTimer;

  /// Post-SOS help session: status line progression (no auto-call).
  Timer? _sosHelpPhaseTimer;
  String _sosHelpStatusKey = 'sos_status_notifying';
  String _sosModeratorName = '';

  /// Drives SOS block: idle disc, help session panel, or post–voice-call closure.
  SosHomePhase _sosHomePhase = SosHomePhase.idle;
  /// The moderator who last called the pilgrim during this SOS (for callback).
  String? _sosCallbackModeratorId;
  bool _hasModeratorCalledForThisSos = false;
  Timer? _sosResolvedUiTimer;
  bool _showResolvedSosCard = false;

  static const _prefsSosUiPrefix = 'pilgrim_sos_ui_v1';

  String _prefsKey(String activeSosId) => '$_prefsSosUiPrefix:$activeSosId';

  Future<void> _persistSosUi() async {
    final active = ref.read(pilgrimProvider).activeSosId?.trim();
    if (active == null || active.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey(active), <String>[
        _sosHomePhase.name,
        _sosHelpStatusKey,
        _sosModeratorName,
        _sosCallbackModeratorId ?? '',
        _hasModeratorCalledForThisSos ? '1' : '0',
        _showResolvedSosCard ? '1' : '0',
      ]);
    } catch (_) {}
  }

  Future<void> _restoreSosUiIfNeeded() async {
    final p = ref.read(pilgrimProvider);
    final active = p.activeSosId?.trim();
    if (active == null || active.isEmpty) return;
    if (!p.sosActive) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_prefsKey(active));
      if (raw == null || raw.length < 6) return;

      final phaseStr = raw[0];
      final statusKey = raw[1];
      final modName = raw[2];
      final cbId = raw[3];
      final hasCalled = raw[4] == '1';
      final showResolved = raw[5] == '1';

      final phase =
          SosHomePhase.values.where((e) => e.name == phaseStr).firstOrNull;

      if (!mounted) return;
      _stopSosHelpTimers();
      setState(() {
        _sosHomePhase = phase ?? SosHomePhase.helpSession;
        _sosHelpStatusKey = statusKey.isNotEmpty
            ? statusKey
            : (hasCalled ? 'sos_status_being_handled' : 'sos_status_waiting');
        _sosModeratorName = modName;
        _sosCallbackModeratorId = cbId.isNotEmpty ? cbId : null;
        _hasModeratorCalledForThisSos = hasCalled;
        _showResolvedSosCard = showResolved;
      });
    } catch (_) {}
  }

  Future<void> _clearPersistedSosUi({String? sosId}) async {
    final id = sosId?.trim() ?? ref.read(pilgrimProvider).activeSosId?.trim();
    if (id == null || id.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey(id));
    } catch (_) {}
  }

  // Location
  StreamSubscription<Position>? _locationSub;
  StreamSubscription<ServiceStatus>? _serviceStatusSub;
  bool _isGpsEnabled = true;
  bool _hasLocPermission = true;
  final Battery _battery = Battery();
  final MapController _mapController = MapController();
  LatLng? _myLatLng;
  /// True after opening the map tab before the first GPS fix (recenter then).
  bool _pilgrimMapAwaitingFirstFix = false;
  WeatherAlert _weatherAlert = const WeatherAlert.loading();
  DateTime? _lastWeatherFetchAt;

  // SFX player for incoming chat messages
  final AudioPlayer _sfxPlayer = AudioPlayer();

  // Named reconnect handler so offConnected can find it.
  void _onSocketConnected() {
    if (!mounted) return;
    final reconnectGroupId = ref.read(pilgrimProvider).groupInfo?.groupId;
    if (reconnectGroupId != null) {
      SocketService.emit('join_group', reconnectGroupId);
    }
  }

  void _refreshRealtimeState({bool forceDashboard = false}) {
    if (!mounted) return;
    ref.read(notificationProvider.notifier).refetch();
    ref.read(pilgrimProvider.notifier).loadDashboard(force: forceDashboard);
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkLocationPermission());
      _loadWeatherAlert(force: true);
      ref.read(missedCallsUnreadProvider.notifier).refresh();
      if (_locationSub == null) {
        unawaited(_initLocation());
      }
    }
  }

  Future<void> _checkLocationPermission() async {
    final hasLoc = await hasLocationAlwaysPermission();
    if (mounted && _hasLocPermission != hasLoc) {
      setState(() => _hasLocPermission = hasLoc);
    }
    if (!hasLoc && mounted) {
      context.go('/location-onboarding');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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

    unawaited(_initLocationHealth());

    // GPS + permission: start immediately (do not wait for map tab or dashboard).
    unawaited(_initLocation());

    // Load data after first frame so the provider is ready
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      AppLogger.d('[PilgrimDashboard] Starting loadDashboard...');
      try {
        await ref.read(authProvider.notifier).hydrateFromCache();
        await ref.read(pilgrimProvider.notifier).hydrateFromCache();
        await ref.read(pilgrimProvider.notifier).loadDashboard();
        // Hot restart resilience: if SOS is still active, restore last known
        // UI status (being handled / callback) instead of resetting to "sent".
        await _restoreSosUiIfNeeded();
        final groupId = ref.read(pilgrimProvider).groupInfo?.groupId;
        AppLogger.d('[PilgrimDashboard] Dashboard loaded. GroupId: $groupId');

        if (groupId != null) {
          ref.read(messageProvider.notifier).fetchUnreadCount(groupId);
        }
      } catch (e) {
        AppLogger.e('[PilgrimDashboard] Error loading dashboard: $e');
      }
      if (mounted) {
        setState(() => _isInitializingDashboard = false);
      }

      // Connect socket with this pilgrim's identity
      final auth = ref.read(authProvider);
      if (auth.userId != null) {
        // Re-join group room on every (re)connect. Register BEFORE connect so we
        // can't miss a fast connect on hot restart.
        SocketService.onConnected(_onSocketConnected);

        final socketUrl = ApiService.socketOrigin;
        SocketService.connect(
          serverUrl: socketUrl,
          userId: auth.userId!,
          role: auth.role ?? 'pilgrim',
        );
        ref.read(callProvider.notifier).reRegisterListeners();
        
        AppLogger.d(
          '[PilgrimDashboard] Socket status: ${SocketService.isConnected ? 'Connected' : 'Connecting...'}',
        );

        // If we're already connected, join immediately (and trigger beacon sync).
        _onSocketConnected();

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
        // Group join is handled by _onSocketConnected (initial + every reconnect)
        // Listen for moderator navigation beacon
        SocketService.on('mod_nav_beacon', (data) {
          if (!mounted) return;
          try {
            // socket.io can deliver data as Map<dynamic,dynamic> — cast safely
            final map = Map<String, dynamic>.from(data as Map);
            final modId = map['moderatorId'] as String? ?? '';
            final modName = map['moderatorName'] as String? ?? 'Moderator';
            final enabled = map['enabled'] as bool? ?? false;
            final lat = (map['lat'] as num?)?.toDouble();
            final lng = (map['lng'] as num?)?.toDouble();
            ref
                .read(pilgrimProvider.notifier)
                .updateModeratorBeacon(modId, modName, enabled, lat, lng);
          } catch (e) {
            AppLogger.e('[PilgrimDashboard] mod_nav_beacon handler error: $e');
          }
        });

        // Listen for removal from group
        SocketService.on('removed-from-group', (data) {
          if (!mounted) return;
          try {
            final map = Map<String, dynamic>.from(data as Map);
            final groupId = map['group_id']?.toString();
            if (groupId != null) {
              SocketService.emit('leave_group', groupId);
            }

            _stopSosHelpTimers();
            _sosCallbackModeratorId = null;
            _hasModeratorCalledForThisSos = false;
            if (mounted) {
              setState(() => _sosHomePhase = SosHomePhase.idle);
            }
            // Clear all group-related state immediately
            ref.read(pilgrimProvider.notifier).clearGroupState();
            // Clear suggested areas
            ref.read(suggestedAreaProvider.notifier).clear();
            // Show notification to user
            final groupName = map['group_name'] as String? ?? 'the group';
            StandardSnackBar.showWarning(
              context,
              'You have been removed from $groupName',
              duration: const Duration(seconds: 5),
            );
            // Reload from server to confirm state (force bypasses throttle)
            ref.read(pilgrimProvider.notifier).loadDashboard(force: true);
          } catch (e) {
            AppLogger.e('[PilgrimDashboard] removed-from-group handler error: $e');
          }
        });

        // Listen for new group messages — append silently to avoid flicker
        SocketService.on('new_message', (data) {
          if (!mounted) return;
          AppLogger.d('[PilgrimDashboard] Socket event: new_message | Data: $data');
          try {
            final map = Map<String, dynamic>.from(data as Map);
            AppLogger.d(
              '[PilgrimDashboard] is_urgent value in map: ${map['is_urgent']} (type: ${map['is_urgent'].runtimeType})',
            );
            final groupId = ref.read(pilgrimProvider).groupInfo?.groupId;
            if (groupId == null) {
              AppLogger.w('[PilgrimDashboard] groupInfo.groupId is null');
              return;
            }
            // Append the single message without a full reload (no spinner)
            final appended =
                ref.read(messageProvider.notifier).appendMessage(map);
            if (!appended) {
              return;
            }

            // Don't show popup or play sound when app is not interactively
            // foreground (binding reflects engine state; avoids false "resumed"
            // before the first lifecycle callback).
            if (WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) {
              AppLogger.d(
                '[PilgrimDashboard] App not resumed (binding), skipping popup',
              );
              return;
            }

            // Don't show popup if user is actively reading this chat
            if (ref.read(messageProvider).activeGroupId == groupId) {
              AppLogger.d('[PilgrimDashboard] User is reading chat, skipping popup');
              return;
            }

            // Show in-app popup for the incoming message
            unawaited(
              ChatNotificationHelper.showIncomingMessage(
                context: context,
                ref: ref,
                map: map,
                onViewChat: () {
                  setState(() => _currentTab = 3);
                  ref.read(messageProvider.notifier).markAllRead(groupId);
                  _chatScrollNotifier.value++;
                },
              ),
            );
          } catch (e) {
            AppLogger.e('[PilgrimDashboard] new_message handler error: $e');
          }
        });

        // Listen for deleted messages — remove silently to avoid flicker
        SocketService.on('message_deleted', (data) {
          if (!mounted) return;
          try {
            final map = Map<String, dynamic>.from(data as Map);
            final messageId = map['message_id'] as String?;
            if (messageId != null) {
              ref.read(messageProvider.notifier).removeMessage(messageId);
            }
          } catch (e) {
            AppLogger.e('[PilgrimDashboard] message_deleted handler error: $e');
          }
        });

        // Listen for suggested area / meetpoint additions
        SocketService.on('area_added', (data) {
          if (!mounted) return;
          try {
            final map = Map<String, dynamic>.from(data as Map);
            ref.read(suggestedAreaProvider.notifier).appendArea(map);
          } catch (e) {
            AppLogger.e('[PilgrimDashboard] area_added handler error: $e');
          }
        });

        // Listen for suggested area / meetpoint deletions
        SocketService.on('area_deleted', (data) {
          if (!mounted) return;
          try {
            final map = Map<String, dynamic>.from(data as Map);
            final areaId = map['area_id'] as String?;
            if (areaId != null) {
              ref.read(suggestedAreaProvider.notifier).removeArea(areaId);
            }
          } catch (e) {
            AppLogger.e('[PilgrimDashboard] area_deleted handler error: $e');
          }
        });

        // Listen for notification refresh (new area/meetpoint/SOS notifications)
        // refetch() updates the full list + badge without auto-marking as read
        SocketService.on('notification_refresh', (_) {
          _refreshRealtimeState();
        });


        // Listen for missed calls — refresh notifications so badge + list update
        SocketService.on('missed-call-received', (_) {
          _refreshRealtimeState();
          ref.read(missedCallsUnreadProvider.notifier).refresh();
        });

        // Keep pilgrim dashboard synced when group composition/meta changes
        SocketService.on('group_updated', (_) {
          _refreshRealtimeState(forceDashboard: true);
        });
        SocketService.on('group_deleted', (_) {
          _refreshRealtimeState(forceDashboard: true);
        });

        // Listen for remote force logout (e.g., code refreshed by moderator)
        SocketService.on('force_logout', (_) {
          if (!mounted) return;
          ref.read(authProvider.notifier).logout();
          context.go('/login');
          StandardSnackBar.showError(context, 'Your login code was refreshed. You have been logged out.', duration: const Duration(seconds: 5));
        });

        // Listen for group membership changes (moderator controlled)
        SocketService.on('added-to-group', (data) {
          if (!mounted) return;
          // Immediately join the socket room using the payload group_id so
          // the server can sync the active beacon right away — before the
          // async provider refresh completes. This prevents a race condition
          // where the beacon sync arrives while groupInfo is still null.
          final payload = data is Map<String, dynamic> ? data : <String, dynamic>{};
          final newGroupId = payload['group_id']?.toString();
          if (newGroupId != null) {
            SocketService.emit('join_group', newGroupId);
          }
          // Use loadDashboard(force:true) instead of ref.invalidate —
          // invalidate resets to empty state but build() never calls
          // loadDashboard, leaving groupInfo permanently null.
          ref.read(pilgrimProvider.notifier).loadDashboard(force: true).then((_) {
            if (!mounted) return;
            final gId = ref.read(pilgrimProvider).groupInfo?.groupId ?? newGroupId;
            if (gId != null) {
              ref.read(suggestedAreaProvider.notifier).load(gId);
            }
          });
        });

        // Moderator acknowledged SOS — update status and cancel the auto-call
        // so the pilgrim is not forced into a group ring once help is underway.
        SocketService.on('sos-handling', (data) {
          if (!mounted) return;
          try {
            final map = Map<String, dynamic>.from(data as Map);
            if (!ref.read(pilgrimProvider).sosActive) return;

            final myGroup = ref.read(pilgrimProvider).groupInfo?.groupId;
            final evtGroup = map['group_id']?.toString();
            if (myGroup != null &&
                evtGroup != null &&
                evtGroup != myGroup) {
              return;
            }

            final sid = map['sos_id']?.toString().trim();
            final active = ref.read(pilgrimProvider).activeSosId?.trim();
            // Ignore only when both IDs are present and clearly differ
            // (fixes missed cancels when one side omits or formats ids).
            if (sid != null &&
                sid.isNotEmpty &&
                active != null &&
                active.isNotEmpty &&
                sid != active) {
              return;
            }

            final modName = map['moderator_name']?.toString() ?? '';
            _stopSosHelpTimers();
            setState(() {
              _sosHelpStatusKey = 'sos_status_reviewing';
              if (modName.isNotEmpty) _sosModeratorName = modName;
            });
            unawaited(_persistSosUi());
          } catch (e) {
            AppLogger.e('[PilgrimDashboard] sos-handling handler error: $e');
          }
        });

        SocketService.on('sos-resolved', (data) {
          if (!mounted) return;
          try {
            final map = Map<String, dynamic>.from(data as Map);
            final sid = map['sos_id']?.toString().trim();
            final active = ref.read(pilgrimProvider).activeSosId?.trim();
            if (sid != null &&
                sid.isNotEmpty &&
                active != null &&
                active.isNotEmpty &&
                sid != active) {
              return;
            }

            _stopSosHelpTimers();
            _sosCallbackModeratorId = null;
            _hasModeratorCalledForThisSos = false;
            _sosResolvedUiTimer?.cancel();
            _sosResolvedUiTimer = null;
            ref.read(pilgrimProvider.notifier).cancelSOS();
            if (!mounted) return;
            setState(() {
              _sosHomePhase = SosHomePhase.helpSession;
              _sosHelpStatusKey = 'sos_status_resolved_friendly';
              _sosModeratorName = '';
              _showResolvedSosCard = true;
            });
            unawaited(_clearPersistedSosUi(sosId: active));
            _sosResolvedUiTimer = Timer(const Duration(seconds: 30), () {
              if (!mounted) return;
              setState(() {
                _showResolvedSosCard = false;
                _sosHomePhase = SosHomePhase.idle;
                _sosHelpStatusKey = 'sos_status_notifying';
              });
            });
          } catch (e) {
            AppLogger.e('[PilgrimDashboard] sos-resolved handler error: $e');
          }
        });
      }
      // Fetch notification badge count
      ref.read(notificationProvider.notifier).fetchUnreadCount();
      ref.read(missedCallsUnreadProvider.notifier).refresh();
      // Fire weather load immediately (don't await — let it run in parallel)
      _loadWeatherAlert(force: true);
      final profileOk = await ref.read(authProvider.notifier).fetchProfile();
      if (!mounted) return;
      if (!profileOk) {
        context.go('/login');
        return;
      }
      // Load suggested areas if in a group
      final gIdForAreas = ref.read(pilgrimProvider).groupInfo?.groupId;
      if (gIdForAreas != null) {
        ref.read(suggestedAreaProvider.notifier).load(gIdForAreas);
      }
      _weatherRefreshTimer ??= Timer.periodic(const Duration(hours: 3), (_) {
        if (!mounted) return;
        _loadWeatherAlert(force: true);
      });
    });
  }

  @override
  void dispose() {
    _chatScrollNotifier.dispose();
    _sosHoldController.dispose();
    _sosPulseController.dispose();
    _mapController.dispose();
    _sosTimer?.cancel();
    _sosCountdownTimer?.cancel();
    _stopSosHelpTimers();
    _sosResolvedUiTimer?.cancel();
    _sosResolvedUiTimer = null;
    _sosCallbackModeratorId = null;
    _hasModeratorCalledForThisSos = false;
    _weatherRefreshTimer?.cancel();
    _serviceStatusSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _locationSub?.cancel();
    _sfxPlayer.dispose();
    ChatNotificationHelper.dispose();
    SocketService.off('mod_nav_beacon');
    SocketService.off('removed-from-group');
    SocketService.off('new_message');
    SocketService.off('message_deleted');
    SocketService.off('area_added');
    SocketService.off('area_deleted');
    SocketService.off('notification_refresh');
    SocketService.off('missed-call-received');
    SocketService.off('group_updated');
    SocketService.off('group_deleted');
    SocketService.off('added-to-group');
    SocketService.off('force_logout');
    SocketService.off('sos-handling');
    SocketService.off('sos-resolved');
    SocketService.offConnected(_onSocketConnected);
    super.dispose();
  }

  void _stopSosHelpTimers() {
    _sosHelpPhaseTimer?.cancel();
    _sosHelpPhaseTimer = null;
  }

  void _startSosHelpSessionTimers() {
    _stopSosHelpTimers();
    if (!mounted) return;
    setState(() => _sosHelpStatusKey = 'sos_status_notifying');
    unawaited(_persistSosUi());
    _sosHelpPhaseTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (!ref.read(pilgrimProvider).sosActive) return;
      setState(() => _sosHelpStatusKey = 'sos_status_waiting');
      unawaited(_persistSosUi());
    });
  }

  // ── In-app popup for incoming messages ───────────────────────────────────
  // Extracted to ChatNotificationHelper



  // ── Location ────────────────────────────────────────────────────────────────

  bool _isUsableLastKnown(Position p) {
    final age = DateTime.now().difference(p.timestamp);
    if (age > const Duration(hours: 8)) return false;
    final acc = p.accuracy;
    if (acc.isInfinite || acc < 0) return false;
    return acc <= 8000;
  }

  Future<void> _applyPilgrimGpsPosition(Position pos) async {
    if (!mounted) return;
    final ll = LatLng(pos.latitude, pos.longitude);
    setState(() => _myLatLng = ll);
    _loadWeatherAlert(
      latitude: pos.latitude,
      longitude: pos.longitude,
      force: false,
    );
    int? battery;
    try {
      final lvl = await _battery.batteryLevel;
      battery = lvl;
      ref.read(pilgrimProvider.notifier).setBattery(lvl);
    } catch (_) {}
    if (!mounted) return;
    ref.read(pilgrimProvider.notifier).updateLocation(
          latitude: pos.latitude,
          longitude: pos.longitude,
          batteryPercent: battery,
        );
    if (_pilgrimMapAwaitingFirstFix && _currentTab == 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _currentTab != 1) return;
        final target = _myLatLng ?? AppMapTiles.fallbackMapCenter;
        _mapController.move(target, AppMapTiles.clampMapZoom(15));
        setState(() => _pilgrimMapAwaitingFirstFix = false);
      });
    }
  }

  void _recenterPilgrimMapOnMe() {
    if (!mounted) return;
    final target = _myLatLng ?? AppMapTiles.fallbackMapCenter;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.move(target, AppMapTiles.clampMapZoom(15));
    });
  }

  Future<void> _initLocationHealth() async {
    _isGpsEnabled = await Geolocator.isLocationServiceEnabled();
    _hasLocPermission = await hasLocationAlwaysPermission();
    if (mounted) setState(() {});

    _serviceStatusSub = Geolocator.getServiceStatusStream().listen((status) {
      if (mounted) {
        setState(() => _isGpsEnabled = (status == ServiceStatus.enabled));
      }
    });
  }

  Future<void> _initLocation() async {
    await _locationSub?.cancel();
    _locationSub = null;

    final ok = await hasLocationAlwaysPermission();
    if (!ok) return;
    if (!mounted) return;

    // 1) Cached / fused location — map + backend update immediately when usable.
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && _isUsableLastKnown(last)) {
        await _applyPilgrimGpsPosition(last);
      }
    } catch (_) {}

    // 2) Fast network-assisted fix (avoids waiting on cold GPS alone).
    try {
      final quick = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        ),
      );
      await _applyPilgrimGpsPosition(quick);
    } catch (_) {}

    // 3) Ongoing updates — medium accuracy reaches first fix much faster than high.
    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 12,
      ),
    ).listen((pos) {
      unawaited(_applyPilgrimGpsPosition(pos));
    });
  }

  Future<void> _loadWeatherAlert({
    double? latitude,
    double? longitude,
    bool force = false,
  }) async {
    if (!force &&
        _lastWeatherFetchAt != null &&
        DateTime.now().difference(_lastWeatherFetchAt!) <
            const Duration(minutes: 5)) {
      return;
    }
    double lat;
    double lng;

    if (latitude != null && longitude != null) {
      lat = latitude;
      lng = longitude;
    } else if (_myLatLng != null) {
      lat = _myLatLng!.latitude;
      lng = _myLatLng!.longitude;
    } else {
      // No location yet — grab current position from GPS
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 5),
          ),
        );
        lat = pos.latitude;
        lng = pos.longitude;
        _myLatLng = LatLng(lat, lng);
      } catch (_) {
        // GPS unavailable — fall back to Mecca
        lat = AppMapTiles.fallbackMapCenter.latitude;
        lng = AppMapTiles.fallbackMapCenter.longitude;
      }
    }

    try {
      final response = await Dio().get(
        'https://api.open-meteo.com/v1/forecast',
        queryParameters: {
          'latitude': lat,
          'longitude': lng,
          'current': 'temperature_2m,weather_code,is_day',
          'forecast_days': 1,
        },
      );

      final payload = response.data as Map<String, dynamic>;
      final current = payload['current'] as Map<String, dynamic>?;
      final temp = (current?['temperature_2m'] as num?)?.toDouble();
      final weatherCode = (current?['weather_code'] as num?)?.toInt() ?? 0;
      final isDayRaw = (current?['is_day'] as num?)?.round() ?? 1;
      final isDaytime = isDayRaw != 0;

      if (temp == null) throw Exception('Missing temperature payload');

      if (!mounted) return;
      setState(() {
        _weatherAlert = _buildWeatherAlert(
          temp,
          weatherCode,
          isDaytime: isDaytime,
        );
        _lastWeatherFetchAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _weatherAlert = WeatherAlert(
          temperatureC: 0,
          condition: 'weather_unavailable'.tr(),
          cardTip: 'weather_card_error_short'.tr(),
          detailTip: 'weather_detail_error_body'.tr(),
          icon: Icons.cloud_off,
          iconColor: AppColors.textMutedLight,
          isLoading: false,
          isError: true,
        );
        // Don't set _lastWeatherFetchAt on error so it retries immediately
      });
    }
  }

  WeatherAlert _buildWeatherAlert(
    double temperatureC,
    int weatherCode, {
    required bool isDaytime,
  }) {
    final temp = temperatureC.round();
    final condition = _weatherCondition(weatherCode, temp);
    final keys = _weatherTipKeys(weatherCode, temp, isDaytime);
    final icon = _weatherIcon(weatherCode, temp);
    final iconColor = _weatherIconColor(weatherCode, temp);

    return WeatherAlert(
      temperatureC: temp,
      condition: condition,
      cardTip: keys.cardKey.tr(),
      detailTip: keys.detailKey.tr(),
      icon: icon,
      iconColor: iconColor,
      isLoading: false,
      isError: false,
    );
  }

  IconData _weatherIcon(int weatherCode, int temperatureC) {
    if (_isRainCode(weatherCode)) return Icons.umbrella;
    if (weatherCode == 45 || weatherCode == 48) return Icons.masks;
    if (temperatureC <= 14 || (weatherCode >= 71 && weatherCode <= 77)) {
      return Icons.ac_unit;
    }
    if (temperatureC >= 36) return Icons.local_fire_department;
    if (weatherCode <= 1) return Icons.wb_sunny;
    if (weatherCode == 2 || weatherCode == 3) return Icons.cloud;
    if (weatherCode >= 95) return Icons.thunderstorm;
    return Icons.wb_sunny;
  }

  Color _weatherIconColor(int weatherCode, int temperatureC) {
    if (_isRainCode(weatherCode)) return const Color(0xFF2F80ED);
    if (weatherCode == 45 || weatherCode == 48) return const Color(0xFF8B6D4E);
    if (temperatureC <= 16 || (weatherCode >= 71 && weatherCode <= 77)) {
      return const Color(0xFF56CCF2);
    }
    if (temperatureC >= 36) return const Color(0xFFE67E22);
    if (weatherCode <= 1) return const Color(0xFFFFA726);
    if (weatherCode == 2 || weatherCode == 3) return const Color(0xFF90A4AE);
    if (weatherCode >= 95) return const Color(0xFF6C5CE7);
    return AppColors.primary;
  }

  String _weatherCondition(int weatherCode, int temperatureC) {
    if (_isRainCode(weatherCode)) return 'weather_rainy'.tr();
    if (weatherCode == 45 || weatherCode == 48) return 'weather_sandy'.tr();
    if (temperatureC <= 16 || (weatherCode >= 71 && weatherCode <= 77)) {
      return 'weather_cold'.tr();
    }
    if (temperatureC >= 36) return 'weather_extreme_heat'.tr();
    if (weatherCode <= 1) return 'weather_sunny'.tr();
    if (weatherCode == 2 || weatherCode == 3) return 'weather_cloudy'.tr();
    if (weatherCode >= 95) return 'weather_storm'.tr();
    return 'weather_clear'.tr();
  }

  /// Short line for the dashboard card (`weather_card_*`) and long body
  /// (`weather_reminder_*` / legacy detail keys).
  ({
    String cardKey,
    String detailKey,
  }) _weatherTipKeys(
    int weatherCode,
    int temperatureC,
    bool isDaytime,
  ) {
    if (temperatureC <= 16 || (weatherCode >= 71 && weatherCode <= 77)) {
      return (
        cardKey: 'weather_card_jacket',
        detailKey: 'weather_reminder_jacket',
      );
    }
    if (weatherCode >= 95) {
      return (
        cardKey: 'weather_card_storm',
        detailKey: 'weather_reminder_storm',
      );
    }
    if (_isRainCode(weatherCode)) {
      return (cardKey: 'weather_card_rain', detailKey: 'weather_reminder_rain');
    }
    if (weatherCode == 45 || weatherCode == 48) {
      return (cardKey: 'weather_card_mask', detailKey: 'weather_reminder_mask');
    }
    if (isDaytime && temperatureC >= 32) {
      return (
        cardKey: 'weather_card_heat_sun',
        detailKey: 'weather_reminder_heat_sun_umbrella',
      );
    }
    if (!isDaytime && temperatureC >= 30) {
      return (
        cardKey: 'weather_card_hot_night',
        detailKey: 'weather_reminder_hot_night_hydrate',
      );
    }
    if (isDaytime && temperatureC >= 28 && temperatureC < 32) {
      return (
        cardKey: 'weather_card_warm',
        detailKey: 'weather_reminder_warm_hijaz',
      );
    }
    if (weatherCode <= 1) {
      return (
        cardKey: 'weather_card_sunny',
        detailKey: 'weather_reminder_sun_hijaz',
      );
    }
    return (
      cardKey: 'weather_card_default',
      detailKey: 'weather_reminder_default',
    );
  }

  bool _isRainCode(int code) {
    return code == 51 ||
        code == 53 ||
        code == 55 ||
        code == 56 ||
        code == 57 ||
        code == 61 ||
        code == 63 ||
        code == 65 ||
        code == 66 ||
        code == 67 ||
        code == 80 ||
        code == 81 ||
        code == 82;
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

    if (ok) {
      if (mounted) {
        setState(() {
          _sosHomePhase = SosHomePhase.helpSession;
        });
      }
      _startSosHelpSessionTimers();
      unawaited(_persistSosUi());
    } else {
      // Get the actual error message from the provider
      final errorMsg = ref.read(pilgrimProvider).error ?? 'sos_failed'.tr();

      StandardSnackBar.showError(context, errorMsg);
    }
  }

  Future<void> _cancelSOS() async {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        title: Text(
          'sos_cancel_confirm_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        content: Text(
          'sos_cancel_confirm_body'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            color: isDark ? Colors.white70 : AppColors.textDark,
            height: 1.45,
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    'sos_cancel_confirm_keep'.tr(),
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: () => Navigator.pop(dialogCtx, true),
                  child: Text(
                    'sos_cancel_confirm_yes'.tr(),
                    style: const TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _performCancelSOS();
  }

  void _performCancelSOS() {
    _stopSosHelpTimers();
    _sosResolvedUiTimer?.cancel();
    _sosResolvedUiTimer = null;
    final call = ref.read(callProvider);
    if (call.status == CallStatus.calling ||
        call.status == CallStatus.ringing) {
      ref.read(callProvider.notifier).cancelOutgoingRing();
    }
    if (mounted) {
      setState(() {
        _sosHelpStatusKey = 'sos_status_notifying';
        _sosHomePhase = SosHomePhase.idle;
        _sosModeratorName = '';
        _sosCallbackModeratorId = null;
        _hasModeratorCalledForThisSos = false;
        _showResolvedSosCard = false;
      });
    }
    unawaited(_clearPersistedSosUi());
    final pilgrimState = ref.read(pilgrimProvider);
    final groupId = pilgrimState.groupInfo?.groupId;
    final sosId = pilgrimState.activeSosId;

    ref.read(pilgrimProvider.notifier).cancelSOS();

    if (groupId != null) {
      final payload = <String, dynamic>{
        'groupId': groupId,
        'pilgrimId': ref.read(authProvider).userId,
      };
      if (sosId != null) payload['sos_id'] = sosId;
      SocketService.emit('sos_cancel', payload);
    }
    if (!mounted) return;
    StandardSnackBar.showSuccess(context, 'sos_cancelled'.tr());
  }

  // ── Navigate to Moderator ──────────────────────────────────────────────────

  Future<void> _navigateToModerator(ModeratorBeacon beacon) async {
    final lat = beacon.lat;
    final lng = beacon.lng;
    final googleMapsWeb = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
    );
    try {
      await launchUrl(googleMapsWeb, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Ignore
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pilgrimState = ref.watch(pilgrimProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isInitializingDashboard) {
      return Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : const Color(0xfff1f5f3),
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
                    fontFamily: 'Lexend',
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

    final notifCount = ref.watch(notificationProvider).unreadCount;
    final missedCallUnread = ref.watch(missedCallsUnreadProvider);

    // Fallback: if an incoming call was accepted and we're connected,
    // navigate to VoiceCallScreen from here.
    ref.listen(callProvider, (prev, next) {
      // Moderator called the pilgrim while SOS is active:
      // - immediately hide Cancel and show "being handled"
      // - remember the moderator for callback
      final sosActive = ref.read(pilgrimProvider).sosActive;
      final incomingModeratorCall =
          sosActive && prev?.status != CallStatus.ringing &&
              next.status == CallStatus.ringing &&
              (next.remoteUserId?.isNotEmpty ?? false);
      if (incomingModeratorCall) {
        _sosCallbackModeratorId = next.remoteUserId;
        _hasModeratorCalledForThisSos = true;
        if (mounted) {
          setState(() {
            _sosHelpStatusKey = 'sos_status_being_handled';
          });
        }
        unawaited(_persistSosUi());
      }

      if (next.status == CallStatus.connected &&
          prev?.status == CallStatus.ringing &&
          mounted &&
          !isNavigatingToCall &&
          !VoiceCallScreen.isActive) {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const VoiceCallScreen()));
      }
      if (next.status == CallStatus.ended && prev != null) {
        final wasInVoice = prev.status == CallStatus.calling ||
            prev.status == CallStatus.ringing ||
            prev.status == CallStatus.connected;
        final shouldShowCallback =
            wasInVoice && ref.read(pilgrimProvider).sosActive &&
                _hasModeratorCalledForThisSos &&
                (_sosCallbackModeratorId?.isNotEmpty ?? false);
        if (shouldShowCallback && mounted) {
          setState(() => _sosHelpStatusKey = 'sos_status_callback_available');
          unawaited(_persistSosUi());
        }
      }
    });

    ref.listen(authProvider, (prev, next) {
      // Role sync polling removed in moderator-first workflow
    });

    ref.listen(pilgrimProvider, (prev, next) {
      if (prev?.sosActive != true && next.sosActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!ref.read(pilgrimProvider).sosActive) return;
          if (_sosHomePhase != SosHomePhase.idle) return;
          setState(() {
            _sosHomePhase = SosHomePhase.helpSession;
            _sosHelpStatusKey = 'sos_status_waiting';
            _sosModeratorName = '';
            _sosCallbackModeratorId = null;
            _hasModeratorCalledForThisSos = false;
            _showResolvedSosCard = false;
          });
        });
      }
      if (prev?.sosActive == true && next.sosActive == false) {
        _stopSosHelpTimers();
        _sosResolvedUiTimer?.cancel();
        _sosResolvedUiTimer = null;
        _sosCallbackModeratorId = null;
        _hasModeratorCalledForThisSos = false;
        if (mounted) {
          setState(() {
            _sosHelpStatusKey = 'sos_status_notifying';
            _sosHomePhase = SosHomePhase.idle;
            _sosModeratorName = '';
            _showResolvedSosCard = false;
          });
        }
      }
      final prevGroupId = prev?.groupInfo?.groupId;
      final nextGroupId = next.groupInfo?.groupId;
      if (prevGroupId != nextGroupId) {
        if (prevGroupId != null) {
          SocketService.emit('leave_group', prevGroupId);
        }
        if (nextGroupId != null) {
          SocketService.emit('join_group', nextGroupId);
        }
      }
      final chatGid = next.groupInfo?.groupId;
      final chatMsgState = ref.read(messageProvider);
      if (_currentTab == 3 && chatGid != null) {
        if (chatMsgState.activeGroupId != chatGid) {
          ref.read(messageProvider.notifier).setActiveGroup(chatGid);
        }
      } else if (chatMsgState.activeGroupId != null) {
        ref.read(messageProvider.notifier).setActiveGroup(null);
      }
    });

    final tabs = [
      PilgrimHomeTab(
        pilgrimState: pilgrimState,
        authFullName: ref.watch(authProvider).fullName,
        isDark: isDark,
        weatherAlert: _weatherAlert,
        sosPulseController: _sosPulseController,
        sosHoldController: _sosHoldController,
        isSosHolding: _isSosHolding,
        onSosHoldStart: _onSosHoldStart,
        onSosHoldEnd: _onSosHoldEnd,
        onRefresh: () async {
          await ref.read(pilgrimProvider.notifier).loadDashboard();
          final gId = ref.read(pilgrimProvider).groupInfo?.groupId;
          if (gId != null) {
            await ref.read(suggestedAreaProvider.notifier).load(gId);
          }
          await _loadWeatherAlert(force: true);
        },
        sosCountdown: _sosCountdown,
        onCancelSos: _cancelSOS,
        onCallBackSos: () async {
          final to = _sosCallbackModeratorId;
          if (to == null || to.isEmpty) return;
          if (!ref.read(pilgrimProvider).sosActive) return;
          if (ref.read(callProvider).isInCall) return;
          await ref.read(callProvider.notifier).startCall(
                remoteUserId: to,
                remoteUserName: 'call_support_display_name'.tr(),
              );
        },
        showResolvedSosCard: _showResolvedSosCard,
        sosHelpStatusKey: _sosHelpStatusKey,
        sosModeratorName: _sosModeratorName,
        sosHomePhase: _sosHomePhase,
        navBeacons: pilgrimState.navBeacons,
        isGpsEnabled: _isGpsEnabled,
        hasLocPermission: _hasLocPermission,
        onLocationInactiveTap: () async {
          if (!_hasLocPermission) {
            await requestLocationPermissionsFlow();
            await _checkLocationPermission();
          } else if (!_isGpsEnabled) {
            await Geolocator.openLocationSettings();
          }
        },
        myLocation: _myLatLng,
        onNavigateToModerator: _navigateToModerator,
        notificationCount: notifCount,
        onNotificationTap: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (_) => const PilgrimNotificationsScreen(),
                ),
              )
              .then((_) {
                // Refresh badge when coming back
                ref.read(notificationProvider.notifier).fetchUnreadCount();
              });
        },
        missedCallUnreadCount: missedCallUnread,
        onMissedCallsTap: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const PilgrimNotificationsScreen(missedCallsOnly: true),
                ),
              )
              .then((_) {
                ref.read(missedCallsUnreadProvider.notifier).refresh();
              });
        },
        onSettingsTap: () => setState(() => _currentTab = 4),
        onGroupCardTap: () {
          if (pilgrimState.groupInfo != null) {
            final hasModerator = pilgrimState.groupInfo!.moderators.isNotEmpty;
            final firstModerator = hasModerator
                ? pilgrimState.groupInfo!.moderators.first
                : null;
            showGroupDetailsBottomSheet(
              context,
              moderatorName: firstModerator?.fullName,
              moderatorLat: firstModerator?.lat,
              moderatorLng: firstModerator?.lng,
              hotelName: pilgrimState.groupInfo!.hotelName,
              roomNumber: pilgrimState.groupInfo!.roomNumber,
              busNumber: pilgrimState.groupInfo!.busNumber,
              driverName: pilgrimState.groupInfo!.driverName,
              checkIn: pilgrimState.groupInfo!.checkIn,
              checkOut: pilgrimState.groupInfo!.checkOut,
              daysRemaining: pilgrimState.groupInfo!.daysRemaining,
            );
          } else {
            // No group — do nothing (limbo state, moderator will assign)
          }
        },
        onHotspotsTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MeccaHotspotsScreen(anchorLocation: _myLatLng),
            ),
          );
        },
        onWeatherTap: () => showWeatherDetailBottomSheet(context, _weatherAlert),
      ),
      PilgrimMapTab(
        myLocation: _myLatLng,
        mapController: _mapController,
        pilgrimState: pilgrimState,
        profileGender: pilgrimState.profile?.gender,
        areas: ref.watch(suggestedAreaProvider).areas,
      ),
      const QiblaCompassScreen(),
      pilgrimState.groupInfo != null
          ? GroupInboxScreen(
              groupId: pilgrimState.groupInfo!.groupId,
              groupName: pilgrimState.groupInfo!.groupName,
              scrollNotifier: _chatScrollNotifier,
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
          ref.read(messageProvider.notifier).setActiveGroup(null);
        }
      },
      child: Scaffold(
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : const Color(0xfff1f5f3),
        body: Column(
          children: [
            if (pilgrimState.usingOfflineSnapshot)
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
                              fontFamily: 'Lexend',
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
            Expanded(child: IndexedStack(index: _currentTab, children: tabs)),
          ],
        ),
        bottomNavigationBar: PilgrimBottomNav(
          currentIndex: _currentTab,
          onTap: (i) {
            final leavingMap = _currentTab == 1 && i != 1;
            setState(() {
              if (leavingMap) {
                _pilgrimMapAwaitingFirstFix = false;
              }
              _currentTab = i;
              if (i == 1 && _myLatLng == null) {
                _pilgrimMapAwaitingFirstFix = true;
              }
            });
            final chatGid = ref.read(pilgrimProvider).groupInfo?.groupId;
            if (i == 3 && chatGid != null) {
              ref.read(messageProvider.notifier).setActiveGroup(chatGid);
            } else {
              ref.read(messageProvider.notifier).setActiveGroup(null);
            }
            // Refresh weather when switching to Home tab
            if (i == 0) {
              _loadWeatherAlert(force: true);
            }
            // Reload + mark read + scroll when opening Chat tab
            if (i == 3) {
              _chatScrollNotifier.value++;
            }
            if (i == 1) {
              _recenterPilgrimMapOnMe();
            }
          },
          unreadMessages: ref.watch(messageProvider).unreadCount,
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
        ],
      ),
    );
  }
}