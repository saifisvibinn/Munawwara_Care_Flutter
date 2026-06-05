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

import '../../shared/helpers/chat_notification_helper.dart';
import '../../shared/helpers/message_visibility.dart';
import '../../shared/services/message_realtime_binder.dart';
import '../../shared/helpers/deferred_urgent_chat_popup.dart';
import '../../../core/bootstrap/app_startup_coordinator.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/location_permission_service.dart';
import '../../../core/services/oem_settings_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/map/app_map_tiles.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/keep_alive_tab.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/services/callkit_service.dart';
import '../../calling/providers/call_provider.dart';
import '../../calling/providers/missed_calls_unread_provider.dart';
import '../../calling/screens/voice_call_screen.dart';
import '../../calling/native_call_coordinator.dart' show isNavigatingToCall;
import '../../notifications/providers/notification_provider.dart';
import '../../shared/providers/message_provider.dart';
import '../../shared/providers/suggested_area_provider.dart';
import '../helpers/moderator_navigation.dart';
import '../providers/pilgrim_provider.dart';
import '../services/pilgrim_sos_coordinator.dart';
import '../widgets/bottom_nav.dart';
import '../../../core/widgets/support_dialogs.dart';
import '../widgets/home_tab/home_cards.dart';
import '../widgets/home_tab/home_tab.dart';
import '../widgets/map_tab/pilgrim_map_tab.dart';
import '../widgets/sos/sos_home_phase.dart';
import '../../muslim/screens/islamic_corner_hub_screen.dart';
import 'group_details_screen.dart';
import 'group_inbox_screen.dart';
import 'mecca_hotspots_screen.dart';
import 'pilgrim_notifications_screen.dart';
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _isInitializingDashboard = true;
  // Bottom nav
  int _currentTab = 0;
  late final PageController _pageController = PageController(initialPage: 0);

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
  LatLng? _lastWeatherFetchLatLng;
  static const Duration _weatherMinRefreshInterval = Duration(minutes: 5);
  static const double _weatherLocationRefreshMeters = 1500;

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

  void _refreshRealtimeState({bool forceDashboard = false}) {
    if (!mounted) return;
    ref.read(notificationProvider.notifier).refetch();
    ref.read(pilgrimProvider.notifier).loadDashboard(force: forceDashboard);
  }

  /// Urgent socket messages received while !resumed are queued; see
  /// [DeferredUrgentChatPopup].
  Future<void> _flushDeferredUrgentChatPopup() async {
    final map = DeferredUrgentChatPopup.takePending();
    if (map == null || !mounted) return;
    final myId = ref.read(authProvider).userId ?? '';
    if (!isRawMessageVisibleToUser(map, myId)) return;
    final groupId = ref.read(pilgrimProvider).groupInfo?.groupId;
    final gid = map['group_id']?.toString();
    if (groupId == null || gid != groupId) return;
    if (ref.read(messageProvider).activeGroupId == groupId) {
      AppLogger.d(
        '[PilgrimDashboard] In chat, skip deferred urgent popup',
      );
      return;
    }
    await ChatNotificationHelper.showIncomingMessage(
      context: context,
      ref: ref,
      map: map,
      onViewChat: () {
        _goToTab(3);
        ref.read(messageProvider.notifier).markAllRead(groupId);
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkRequiredPermissions());
      _loadWeatherAlert(force: true);
      ref.read(missedCallsUnreadProvider.notifier).refresh();
      if (_locationSub == null) {
        unawaited(_initLocation());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_flushDeferredUrgentChatPopup());
        unawaited(_applyPendingModeratorResolvedFromPush());
      });
    }
  }

  /// FCM in background only sets a prefs flag; apply resolved card on resume.
  Future<void> _applyPendingModeratorResolvedFromPush() async {
    if (!mounted) return;
    await PilgrimSosCoordinator.applyPendingModeratorResolvedIfAny();
  }

  int _permissionsCheckGate = 0;

  Future<void> _checkRequiredPermissions() async {
    if (OemSettingsService.isOnboardingSkippedForSession) return;

    final gate = OemSettingsService.onboardingGate;
    final checkId = ++_permissionsCheckGate;

    final hasLoc = await hasLocationAlwaysPermission();
    if (!mounted ||
        checkId != _permissionsCheckGate ||
        OemSettingsService.isOnboardingSkippedForSession ||
        gate != OemSettingsService.onboardingGate) {
      return;
    }
    if (_hasLocPermission != hasLoc) {
      setState(() => _hasLocPermission = hasLoc);
    }

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

  Future<void> _promptPermissionsForLocationUse() async {
    final showOnboarding =
        await OemSettingsService.shouldShowOnboardingForLocationUse();
    if (!mounted) return;
    if (showOnboarding) {
      context.go('/device-care-onboarding');
      return;
    }
    await requestLocationPermissionsFlow(context);
    await _checkRequiredPermissions();
  }

  /// Moderator marked SOS resolved — show friendly card, then allow new SOS.
  void _applyModeratorResolvedUi({String? sosIdForPrefs}) {
    if (!mounted) return;

    _stopSosHelpTimers();
    _sosCallbackModeratorId = null;
    _hasModeratorCalledForThisSos = false;
    _sosResolvedUiTimer?.cancel();
    _sosResolvedUiTimer = null;

    _showResolvedSosCard = true; // Sync update to avoid race with Riverpod listener

    setState(() {
      _sosHomePhase = SosHomePhase.helpSession;
      _sosHelpStatusKey = 'sos_status_resolved_friendly';
      _sosModeratorName = '';
      _showResolvedSosCard = true;
    });

    final clearId =
        sosIdForPrefs?.trim() ??
        ref.read(pilgrimProvider).activeSosId?.trim();
    if (clearId != null && clearId.isNotEmpty) {
      unawaited(_clearPersistedSosUi(sosId: clearId));
    }

    ref.read(pilgrimProvider.notifier).cancelSOS();

    _sosResolvedUiTimer = Timer(const Duration(seconds: 30), () {
      if (!mounted) return;
      setState(() {
        _showResolvedSosCard = false;
        _sosHomePhase = SosHomePhase.idle;
        _sosHelpStatusKey = 'sos_status_notifying';
      });
      SupportDialogs.showRating(context, isContextual: true);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PilgrimSosCoordinator.onModeratorResolvedUi = _applyModeratorResolvedUi;

    // SOS hold progress ring (fills in 3 s)
    _sosHoldController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // SOS pulse (idle pulsing glow)
    _sosPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    ref.listenManual(callProvider, (prev, next) {
      final sosActive = ref.read(pilgrimProvider).sosActive;
      final incomingModeratorCall =
          sosActive &&
          prev?.status != CallStatus.ringing &&
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

      if (next.status == CallStatus.ended && prev != null) {
        final wasInVoice =
            prev.status == CallStatus.calling ||
            prev.status == CallStatus.ringing ||
            prev.status == CallStatus.connecting ||
            prev.status == CallStatus.connected;
        final shouldShowCallback =
            wasInVoice &&
            ref.read(pilgrimProvider).sosActive &&
            _hasModeratorCalledForThisSos &&
            (_sosCallbackModeratorId?.isNotEmpty ?? false);
        if (shouldShowCallback && mounted) {
          setState(() => _sosHelpStatusKey = 'sos_status_callback_available');
          unawaited(_persistSosUi());
        }
      }
    });
    ref.listenManual(pilgrimProvider, (prev, next) {
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
        if (_showResolvedSosCard) {
          return;
        }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _sosPulseController.repeat(reverse: true);
      }
      unawaited(_checkRequiredPermissions());
      unawaited(ref.read(authProvider.notifier).ensureFcmTokenRegistered());
      unawaited(_bootstrapDashboard());
    });
  }

  Future<void> _bootstrapDashboard() async {
    if (AppStartupCoordinator.consumeDashboardPrimed()) {
      if (mounted) {
        setState(() => _isInitializingDashboard = false);
      }
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_finishPilgrimWarmup());
      });
      return;
    }

    try {
      await ref.read(authProvider.notifier).hydrateFromCache();
      await ref.read(pilgrimProvider.notifier).hydrateFromCache();
      if (mounted) {
        setState(() => _isInitializingDashboard = false);
      }
    } catch (e) {
      AppLogger.e('[PilgrimDashboard] Error loading dashboard: $e');
      if (mounted) {
        setState(() => _isInitializingDashboard = false);
      }
    }

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadRemoteDashboardState());
    });
  }

  Future<void> _loadRemoteDashboardState() async {
    final pilgrim = ref.read(pilgrimProvider);
    final hasCached =
        pilgrim.profile != null || pilgrim.groupInfo != null;

    try {
      await ref.read(pilgrimProvider.notifier).loadDashboard(
        silently: hasCached,
      );
      await _restoreSosUiIfNeeded();
      final groupId = ref.read(pilgrimProvider).groupInfo?.groupId;
      AppLogger.d('[PilgrimDashboard] Dashboard loaded. GroupId: $groupId');

      if (groupId != null) {
        ref.read(messageProvider.notifier).fetchUnreadCount(groupId);
      }
    } catch (e) {
      AppLogger.e('[PilgrimDashboard] Error loading dashboard: $e');
    }

    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_finishPilgrimWarmup());
    });
  }

  Future<void> _finishPilgrimWarmup() async {
    await _restoreSosUiIfNeeded();
    await PilgrimSosCoordinator.applyPendingModeratorResolvedIfAny();
    final groupId = ref.read(pilgrimProvider).groupInfo?.groupId;
    if (groupId != null) {
      ref.read(messageProvider.notifier).fetchUnreadCount(groupId);
    }
    unawaited(_initLocationHealth());
    await _initLocation();
    _connectPilgrimRealtime();
    await _finishDashboardWarmup();
  }

  void _connectPilgrimRealtime() {
    final auth = ref.read(authProvider);
    if (auth.userId != null) {
        // Re-join group room on every (re)connect. Register BEFORE connect so we
        // can't miss a fast connect on hot restart.
        SocketService.onConnected(_onSocketConnected);

        final socketUrl = ApiService.socketOrigin;
        MessageRealtimeBinder.bindDeleteListener();
        SocketService.connect(
          serverUrl: socketUrl,
          userId: auth.userId!,
          role: auth.role ?? 'pilgrim',
        );
        // Note: CallNotifier.build() already registers call socket listeners on
        // first access, and SocketService.connect() re-applies them on every
        // reconnect via _applyPendingListeners(). No manual reRegisterListeners()
        // needed here — calling it would cause duplicate handler registration.
        AppLogger.d(
          '[PilgrimDashboard] Socket status: ${SocketService.isConnected ? 'Connected' : 'Connecting...'}',
        );

        // If we're already connected, join immediately (and trigger beacon sync).
        _onSocketConnected();

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
              'msg_removed_from_group'.tr(args: [groupName]),
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
            final myId = ref.read(authProvider).userId ?? '';
            if (!isRawMessageVisibleToUser(map, myId)) {
              AppLogger.d(
                '[PilgrimDashboard] Ignoring private message for another pilgrim',
              );
              return;
            }
            // Append the single message without a full reload (no spinner)
            final msgNotifier = ref.read(messageProvider.notifier);
            final appended = msgNotifier.appendMessage(map);
            if (!appended) {
              AppLogger.w(
                '[PilgrimDashboard] appendMessage failed — refetching chat',
              );
              unawaited(msgNotifier.loadMessages(groupId, force: true));
              return;
            }

            // Don't show popup or play sound when app is not interactively
            // foreground (binding reflects engine state; avoids false "resumed"
            // before the first lifecycle callback).
            if (WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) {
              AppLogger.d(
                '[PilgrimDashboard] App not resumed — deferring urgent popup',
              );
              if (ref.read(messageProvider).activeGroupId != groupId) {
                DeferredUrgentChatPopup.offerIfUrgent(map);
              }
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
                  _goToTab(3);
                  ref.read(messageProvider.notifier).markAllRead(groupId);
                },
              ),
            );
          } catch (e) {
            AppLogger.e('[PilgrimDashboard] new_message handler error: $e');
          }
        });

        // message_deleted: global [MessageRealtimeBinder] (bootstrap + below)

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
          StandardSnackBar.showError(context, 'msg_force_logout'.tr(), duration: const Duration(seconds: 5));
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
            if (_showResolvedSosCard) return;

            final myGroup = ref.read(pilgrimProvider).groupInfo?.groupId;
            final evtGroup = map['group_id']?.toString();
            if (myGroup != null &&
                evtGroup != null &&
                evtGroup.isNotEmpty &&
                evtGroup != myGroup) {
              return;
            }

            final sid = map['sos_id']?.toString().trim();
            _applyModeratorResolvedUi(sosIdForPrefs: sid);
          } catch (e) {
            AppLogger.e('[PilgrimDashboard] sos-resolved handler error: $e');
          }
        });
    }
  }

  Future<void> _finishDashboardWarmup() async {
    if (!mounted) return;
    ref.read(notificationProvider.notifier).fetchUnreadCount();
    ref.read(missedCallsUnreadProvider.notifier).refresh();
    unawaited(_loadWeatherAlert(force: true));
    final auth = ref.read(authProvider);
    if (!auth.isAuthenticated) {
      context.go('/login');
      return;
    }
    final gIdForAreas = ref.read(pilgrimProvider).groupInfo?.groupId;
    if (gIdForAreas != null) {
      ref.read(suggestedAreaProvider.notifier).load(gIdForAreas);
    }
    _weatherRefreshTimer ??= Timer.periodic(const Duration(hours: 3), (_) {
      if (!mounted) return;
      _loadWeatherAlert(force: true);
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
    if (PilgrimSosCoordinator.onModeratorResolvedUi == _applyModeratorResolvedUi) {
      PilgrimSosCoordinator.onModeratorResolvedUi = null;
    }
    _pageController.dispose();
    super.dispose();
  }

  /// Runs map/chat/home side effects when the visible tab changes.
  void _applyTabSideEffects(int index) {
    final chatGid = ref.read(pilgrimProvider).groupInfo?.groupId;
    if (index == 3 && chatGid != null) {
      ref.read(messageProvider.notifier).setActiveGroup(chatGid);
    } else {
      ref.read(messageProvider.notifier).setActiveGroup(null);
    }
    if (index == 0) {
      unawaited(_loadWeatherAlert(force: true));
    }
    if (index == 3) {
      _chatScrollNotifier.value++;
    }
    if (index == 1) {
      _recenterPilgrimMapOnMe();
    }
  }

  void _handlePageChanged(int index) {
    if (_currentTab == index) return;
    final previousTab = _currentTab;
    setState(() {
      if (previousTab == 1 && index != 1) {
        _pilgrimMapAwaitingFirstFix = false;
      }
      _currentTab = index;
      if (index == 1 && _myLatLng == null) {
        _pilgrimMapAwaitingFirstFix = true;
      }
    });
    _applyTabSideEffects(index);
  }

  void _openProfileScreen() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => const PilgrimProfileScreen(),
      ),
    );
  }

  /// Swipe uses [PageView] physics; programmatic navigation uses [jumpToPage].
  void _goToTab(int index, {bool animate = false}) {
    if (_currentTab == index &&
        (!_pageController.hasClients ||
            (_pageController.page?.round() ?? _currentTab) == index)) {
      return;
    }
    if (!_pageController.hasClients) {
      final previousTab = _currentTab;
      setState(() {
        if (previousTab == 1 && index != 1) {
          _pilgrimMapAwaitingFirstFix = false;
        }
        _currentTab = index;
        if (index == 1 && _myLatLng == null) {
          _pilgrimMapAwaitingFirstFix = true;
        }
      });
      _applyTabSideEffects(index);
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

  /// Skips duplicate fetches unless [force] is set, the cache expired, or the
  /// device moved far enough that local weather may differ.
  bool _shouldSkipWeatherFetch({
    required bool force,
    required double latitude,
    required double longitude,
  }) {
    if (force) return false;
    if (_lastWeatherFetchAt == null || _lastWeatherFetchLatLng == null) {
      return false;
    }
    final movedMeters = Geolocator.distanceBetween(
      _lastWeatherFetchLatLng!.latitude,
      _lastWeatherFetchLatLng!.longitude,
      latitude,
      longitude,
    );
    if (movedMeters >= _weatherLocationRefreshMeters) return false;
    return DateTime.now().difference(_lastWeatherFetchAt!) <
        _weatherMinRefreshInterval;
  }

  /// Resolves coordinates for Open-Meteo. Never falls back to a fixed city —
  /// wrong-city weather is worse than a short loading state.
  Future<LatLng?> _resolveWeatherCoordinates({
    double? latitude,
    double? longitude,
  }) async {
    if (latitude != null && longitude != null) {
      return LatLng(latitude, longitude);
    }
    if (_myLatLng != null) return _myLatLng;
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
      final ll = LatLng(pos.latitude, pos.longitude);
      if (mounted) setState(() => _myLatLng = ll);
      return ll;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadWeatherAlert({
    double? latitude,
    double? longitude,
    bool force = false,
  }) async {
    final coords = await _resolveWeatherCoordinates(
      latitude: latitude,
      longitude: longitude,
    );
    if (coords == null) {
      if (!mounted) return;
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _weatherAlert = WeatherAlert(
            temperatureC: 0,
            conditionKey: 'weather_unavailable',
            cardTipKey: 'weather_card_error_short',
            detailTipKey: 'weather_detail_error_body',
            icon: Icons.location_off,
            iconColor: AppColors.textMutedLight,
            isLoading: false,
            isError: true,
          );
        });
      }
      return;
    }

    if (_shouldSkipWeatherFetch(
      force: force,
      latitude: coords.latitude,
      longitude: coords.longitude,
    )) {
      return;
    }

    final lat = coords.latitude;
    final lng = coords.longitude;

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
        _lastWeatherFetchLatLng = coords;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _weatherAlert = WeatherAlert(
          temperatureC: 0,
          conditionKey: 'weather_unavailable',
          cardTipKey: 'weather_card_error_short',
          detailTipKey: 'weather_detail_error_body',
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
    final keys = _weatherTipKeys(weatherCode, temp, isDaytime);
    final icon = _weatherIcon(weatherCode, temp, isDaytime: isDaytime);
    final iconColor = _weatherIconColor(weatherCode, temp, isDaytime: isDaytime);

    return WeatherAlert(
      temperatureC: temp,
      conditionKey: _weatherConditionKey(
        weatherCode,
        temp,
        isDaytime: isDaytime,
      ),
      cardTipKey: keys.cardKey,
      detailTipKey: keys.detailKey,
      icon: icon,
      iconColor: iconColor,
      isLoading: false,
      isError: false,
    );
  }

  IconData _weatherIcon(
    int weatherCode,
    int temperatureC, {
    required bool isDaytime,
  }) {
    if (_isRainCode(weatherCode)) return Icons.water_drop;
    if (weatherCode == 45 || weatherCode == 48) return Icons.foggy;
    if (temperatureC <= 14 || (weatherCode >= 71 && weatherCode <= 77)) {
      return Icons.ac_unit;
    }
    if (temperatureC >= 36) return Icons.local_fire_department;
    if (weatherCode >= 95) return Icons.thunderstorm;
    if (weatherCode == 2 || weatherCode == 3) return Icons.cloud;
    if (weatherCode <= 1) {
      return isDaytime ? Icons.wb_sunny : Icons.nightlight_round;
    }
    return Icons.wb_sunny;
  }

  Color _weatherIconColor(
    int weatherCode,
    int temperatureC, {
    required bool isDaytime,
  }) {
    if (_isRainCode(weatherCode)) return const Color(0xFF2F80ED);
    if (weatherCode == 45 || weatherCode == 48) return const Color(0xFF78909C);
    if (temperatureC <= 16 || (weatherCode >= 71 && weatherCode <= 77)) {
      return const Color(0xFF56CCF2);
    }
    if (temperatureC >= 36) return const Color(0xFFE67E22);
    if (weatherCode >= 95) return const Color(0xFF6C5CE7);
    if (weatherCode == 2 || weatherCode == 3) return const Color(0xFF90A4AE);
    if (weatherCode <= 1) {
      return isDaytime ? const Color(0xFFFFA726) : const Color(0xFF5C6BC0);
    }
    return AppColors.primary;
  }

  String _weatherConditionKey(
    int weatherCode,
    int temperatureC, {
    required bool isDaytime,
  }) {
    if (_isRainCode(weatherCode)) return 'weather_rainy';
    if (weatherCode == 45 || weatherCode == 48) return 'weather_foggy';
    if (temperatureC <= 16 || (weatherCode >= 71 && weatherCode <= 77)) {
      return 'weather_cold';
    }
    if (temperatureC >= 36) return 'weather_extreme_heat';
    if (weatherCode >= 95) return 'weather_storm';
    if (weatherCode == 2 || weatherCode == 3) return 'weather_cloudy';
    if (weatherCode <= 1) {
      return isDaytime ? 'weather_sunny' : 'weather_clear';
    }
    return 'weather_clear';
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
    await _performCancelSOS();
  }

  Future<void> _performCancelSOS() async {
    _stopSosHelpTimers();
    _sosResolvedUiTimer?.cancel();
    _sosResolvedUiTimer = null;
    final call = ref.read(callProvider);
    if (call.status == CallStatus.calling ||
        call.status == CallStatus.ringing ||
        call.status == CallStatus.connecting) {
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
      final pilgrimId = ref.read(authProvider).userId;
      final payload = <String, dynamic>{
        'groupId': groupId,
        'pilgrimId': pilgrimId,
      };
      if (sosId != null) payload['sos_id'] = sosId;

      if (SocketService.isConnected) {
        SocketService.emit('sos_cancel', payload);
      } else {
        final ok = await ref
            .read(pilgrimProvider.notifier)
            .cancelSosRemote(sosId: sosId);
        if (!ok && mounted) {
          StandardSnackBar.showError(
            context,
            ref.read(pilgrimProvider).error ?? 'error_generic'.tr(),
          );
          return;
        }
      }
    }
    if (!mounted) return;
    StandardSnackBar.showSuccess(context, 'sos_cancelled'.tr());
  }

  // ── Navigate to Moderator ──────────────────────────────────────────────────

  Future<void> _navigateToModerator(ModeratorBeacon beacon) =>
      launchModeratorBeaconDirections(beacon);

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

    final missedCallUnread = ref.watch(missedCallsUnreadProvider);

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
          if (ref.read(callProvider).cooldownSeconds > 0) return;
          await ref.read(callProvider.notifier).startCall(
                remoteUserId: to,
                remoteUserName: 'call_support_display_name'.tr(),
              );
        },
        showResolvedSosCard: _showResolvedSosCard,
        sosHelpStatusKey: _sosHelpStatusKey,
        sosModeratorName: _sosModeratorName,
        navBeacons: pilgrimState.navBeacons,
        isGpsEnabled: _isGpsEnabled,
        hasLocPermission: _hasLocPermission,
        onLocationInactiveTap: () async {
          if (!_hasLocPermission) {
            await _promptPermissionsForLocationUse();
          } else if (!_isGpsEnabled) {
            await Geolocator.openLocationSettings();
          }
        },
        myLocation: _myLatLng,
        onNavigateToModerator: _navigateToModerator,
        callCooldownSeconds: ref.watch(callProvider).cooldownSeconds,
        missedCallUnreadCount: missedCallUnread,
        onMissedCallsTap: () {
          unawaited(NotificationService.onAlertsTabOpened());
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
        onSettingsTap: _openProfileScreen,
        onGroupCardTap: () {
          if (pilgrimState.groupInfo != null) {
            final group = pilgrimState.groupInfo!;

            showGroupDetailsBottomSheet(
              context,
              moderators: group.moderators,
              createdBy: group.createdBy,
              navBeacons: pilgrimState.navBeacons,
              pilgrimLocation: _myLatLng,
              hotelName: group.hotelName,
              roomNumber: group.roomNumber,
              checkIn: group.checkIn,
              checkOut: group.checkOut,
              daysRemaining: group.daysRemaining,
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
      const IslamicCornerHubScreen(),
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
    ];

    return PopScope(
      canPop: _currentTab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _goToTab(0);
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
            Expanded(
              child: DashboardTabPageView(
                controller: _pageController,
                backgroundColor: isDark
                    ? AppColors.backgroundDark
                    : const Color(0xfff1f5f3),
                onPageChanged: _handlePageChanged,
                children: tabs,
              ),
            ),
          ],
        ),
        bottomNavigationBar: PilgrimBottomNav(
          currentIndex: _currentTab,
          onTap: (index) => _goToTab(index, animate: false),
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