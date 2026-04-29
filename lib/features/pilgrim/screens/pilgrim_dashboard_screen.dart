import 'dart:async';
import 'dart:ui' as ui;
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
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/helpers/chat_notification_helper.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/in_app_popup.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../calling/providers/call_provider.dart';
import '../../calling/screens/voice_call_screen.dart';
import '../../../main.dart' show isNavigatingToCall;
import '../../notifications/providers/notification_provider.dart';
import '../../notifications/screens/alerts_tab.dart';
import '../../shared/providers/message_provider.dart';
import '../../shared/providers/suggested_area_provider.dart';
import '../../shared/models/suggested_area_model.dart';
import '../../shared/models/message_model.dart';
import '../providers/pilgrim_provider.dart';
import 'group_details_screen.dart';
import 'group_inbox_screen.dart';
import 'mecca_hotspots_screen.dart';
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
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
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

  // Location
  StreamSubscription<Position>? _locationSub;
  final Battery _battery = Battery();
  final MapController _mapController = MapController();
  LatLng? _myLatLng;
  _WeatherAlert _weatherAlert = const _WeatherAlert.loading();
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


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      _loadWeatherAlert(force: true);
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

    // Load data after first frame so the provider is ready
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      print('[PilgrimDashboard] Starting loadDashboard...');
      try {
        await ref.read(pilgrimProvider.notifier).loadDashboard();
        final groupId = ref.read(pilgrimProvider).groupInfo?.groupId;
        print('[PilgrimDashboard] Dashboard loaded. GroupId: $groupId');
        
        if (groupId != null) {
          ref.read(messageProvider.notifier).fetchUnreadCount(groupId);
        }
      } catch (e) {
        print('[PilgrimDashboard] Error loading dashboard: $e');
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
        
        print('[PilgrimDashboard] Socket status: ${SocketService.isConnected ? 'Connected' : 'Connecting...'}');

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
        // Join group socket room so we receive group-scoped events
        final gId = ref.read(pilgrimProvider).groupInfo?.groupId;
        if (gId != null) {
          print('[PilgrimDashboard] Emitting join_group for $gId');
          SocketService.emit('join_group', gId);
        } else {
          print('[PilgrimDashboard] Warning: Cannot join room, groupId is null');
        }
        // Re-join group room on every reconnect (so beacon state is re-synced)
        SocketService.onConnected(_onSocketConnected);
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
            debugPrint('[PilgrimDashboard] mod_nav_beacon handler error: $e');
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
            debugPrint('[PilgrimDashboard] removed-from-group handler error: $e');
          }
        });

        // Listen for new group messages — append silently to avoid flicker
        SocketService.on('new_message', (data) {
          if (!mounted) return;
          print('[PilgrimDashboard] Socket event: new_message | Data: $data');
          try {
            final map = Map<String, dynamic>.from(data as Map);
            print('[PilgrimDashboard] is_urgent value in map: ${map['is_urgent']} (type: ${map['is_urgent'].runtimeType})');
            final groupId = ref.read(pilgrimProvider).groupInfo?.groupId;
            if (groupId == null) {
              print('[PilgrimDashboard] Error: groupInfo.groupId is null');
              return;
            }
            // Append the single message without a full reload (no spinner)
            ref.read(messageProvider.notifier).appendMessage(map);

            // Don't show popup or play sound when app is not in foreground
            if (_lifecycleState != AppLifecycleState.resumed) {
              print('[PilgrimDashboard] App not resumed, skipping popup');
              return;
            }

            // Don't show popup if user is actively reading this chat
            if (ref.read(messageProvider).activeGroupId == groupId) {
              print('[PilgrimDashboard] User is reading chat, skipping popup');
              return;
            }

            // Show in-app popup for the incoming message
            ChatNotificationHelper.showIncomingMessage(
              context: context,
              ref: ref,
              map: map,
              onViewChat: () {
                setState(() => _currentTab = 3);
                ref.read(messageProvider.notifier).markAllRead(groupId);
                _chatScrollNotifier.value++;
              },
            );
          } catch (e) {
            debugPrint('[PilgrimDashboard] new_message handler error: $e');
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
            debugPrint('[PilgrimDashboard] message_deleted handler error: $e');
          }
        });

        // Listen for suggested area / meetpoint additions
        SocketService.on('area_added', (data) {
          if (!mounted) return;
          try {
            final map = Map<String, dynamic>.from(data as Map);
            ref.read(suggestedAreaProvider.notifier).appendArea(map);
          } catch (e) {
            debugPrint('[PilgrimDashboard] area_added handler error: $e');
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
            debugPrint('[PilgrimDashboard] area_deleted handler error: $e');
          }
        });

        // Listen for notification refresh (new area/meetpoint/SOS notifications)
        // refetch() updates the full list + badge without auto-marking as read
        SocketService.on('notification_refresh', (_) {
          if (!mounted) return;
          ref.read(notificationProvider.notifier).refetch();
        });


        // Listen for missed calls — refresh notifications so badge + list update
        SocketService.on('missed-call-received', (_) {
          if (!mounted) return;
          ref.read(notificationProvider.notifier).refetch();
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


      }
      // Fetch notification badge count
      ref.read(notificationProvider.notifier).fetchUnreadCount();
      // Fire weather load immediately (don't await — let it run in parallel)
      _loadWeatherAlert(force: true);
      _initLocation();
      await ref.read(authProvider.notifier).fetchProfile();
      if (!mounted) return;
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
    _weatherRefreshTimer?.cancel();
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
    SocketService.off('force_logout');
    SocketService.offConnected(_onSocketConnected);
    super.dispose();
  }

  // ── In-app popup for incoming messages ───────────────────────────────────
  // Extracted to ChatNotificationHelper



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
          ref
              .read(pilgrimProvider.notifier)
              .updateLocation(
                latitude: pos.latitude,
                longitude: pos.longitude,
                batteryPercent: battery,
              );
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
        lat = 21.3891;
        lng = 39.8579;
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

      if (temp == null) throw Exception('Missing temperature payload');

      if (!mounted) return;
      setState(() {
        _weatherAlert = _buildWeatherAlert(temp, weatherCode);
        _lastWeatherFetchAt = DateTime.now();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _weatherAlert = const _WeatherAlert.error(
          'Unable to fetch weather now. It will retry automatically.',
        );
        // Don't set _lastWeatherFetchAt on error so it retries immediately
      });
    }
  }

  _WeatherAlert _buildWeatherAlert(double temperatureC, int weatherCode) {
    final temp = temperatureC.round();
    final condition = _weatherCondition(weatherCode, temp);
    final reminder = _weatherReminder(weatherCode, temp);
    final icon = _weatherIcon(weatherCode, temp);
    final iconColor = _weatherIconColor(weatherCode, temp);

    return _WeatherAlert(
      temperatureC: temp,
      condition: condition,
      reminder: reminder,
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
    if (temperatureC <= 14 || (weatherCode >= 71 && weatherCode <= 77)) {
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
    if (temperatureC <= 14 || (weatherCode >= 71 && weatherCode <= 77)) {
      return 'weather_cold'.tr();
    }
    if (temperatureC >= 36) return 'weather_extreme_heat'.tr();
    if (weatherCode <= 1) return 'weather_sunny'.tr();
    if (weatherCode == 2 || weatherCode == 3) return 'weather_cloudy'.tr();
    if (weatherCode >= 95) return 'weather_storm'.tr();
    return 'weather_clear'.tr();
  }

  String _weatherReminder(int weatherCode, int temperatureC) {
    if (temperatureC <= 14 || (weatherCode >= 71 && weatherCode <= 77)) {
      return 'weather_reminder_jacket'.tr();
    }
    if (temperatureC >= 36) {
      return 'weather_reminder_hydrate'.tr();
    }
    if (weatherCode == 45 || weatherCode == 48) {
      return 'weather_reminder_mask'.tr();
    }
    if (_isRainCode(weatherCode) || weatherCode <= 1) {
      return 'weather_reminder_umbrella'.tr();
    }
    return 'weather_reminder_default'.tr();
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
      // Show call options dialog
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _SosCallOptionsSheet(
          onCancel: () {
            Navigator.pop(ctx);
            _cancelSOS();
          },
          onInternetCall: () {
            final mods = ref.read(pilgrimProvider).groupInfo?.moderators ?? [];
            if (mods.isNotEmpty) {
              final shuffledMods = List.of(mods)..shuffle();
              
              // Map to List<Map<String, String>>
              final autoRouteMods = shuffledMods.map((m) => {
                'id': m.id,
                'name': m.fullName,
              }).toList();
              
              final firstMod = autoRouteMods.removeAt(0);

              Navigator.pop(ctx);
              
              ref.read(callProvider.notifier).startCall(
                remoteUserId: firstMod['id']!,
                remoteUserName: firstMod['name']!,
              );
              
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => VoiceCallScreen(
                  autoRouteMods: autoRouteMods,
                  onAllBusy: () {
                    if (mounted) {
                      StandardSnackBar.showError(context, 'sos_all_busy_warning');
                    }
                  },
                )),
              );
            } else {
              StandardSnackBar.showWarning(context, 'dash_no_moderator_call');
            }
          },
          onNormalCall: () async {
            final mods = ref.read(pilgrimProvider).groupInfo?.moderators ?? [];
            if (mods.isEmpty) {
              if (mounted) {
                StandardSnackBar.showWarning(context, 'dash_no_mod_phone');
              }
              return;
            }
            
            Navigator.pop(ctx); // Close SOS Options Sheet
            final isDark = Theme.of(context).brightness == Brightness.dark;
            
            showModalBottomSheet(
              context: context,
              backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
              ),
              builder: (ctx2) {
                return SafeArea(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 16.w),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'select_moderator_to_call'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 16.h),
                        ...mods.map((mod) {
                          final hasPhone = mod.phoneNumber != null && mod.phoneNumber!.isNotEmpty;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: AppColors.primary,
                              child: Text(
                                mod.fullName.isNotEmpty ? mod.fullName[0].toUpperCase() : 'M',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            title: Text(
                              mod.fullName,
                              style: TextStyle(fontFamily: 'Lexend', fontSize: 16.sp),
                            ),
                            subtitle: hasPhone 
                              ? Text(mod.phoneNumber!, style: const TextStyle(fontFamily: 'Lexend', color: Colors.grey))
                              : Text('dash_no_mod_phone'.tr(), style: TextStyle(fontFamily: 'Lexend', color: Colors.red.shade300)),
                            trailing: Icon(Icons.call, color: hasPhone ? Colors.green : Colors.grey),
                            onTap: hasPhone ? () async {
                              Navigator.pop(ctx2);
                              final cleanPhone = mod.phoneNumber!.replaceAll(RegExp(r'[^\d+]'), '');
                              final uri = Uri.parse('tel:$cleanPhone');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              } else if (mounted) {
                                StandardSnackBar.showError(context, 'dash_error_dialer');
                              }
                            } : null,
                          );
                        }),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    } else {
      // Get the actual error message from the provider
      final errorMsg = ref.read(pilgrimProvider).error ?? 'sos_failed'.tr();

      StandardSnackBar.showError(context, errorMsg);
    }
  }

  void _cancelSOS() {
    final pilgrimState = ref.read(pilgrimProvider);
    final groupId = pilgrimState.groupInfo?.groupId;
    final sosId = pilgrimState.activeSosId;
    
    ref.read(pilgrimProvider.notifier).cancelSOS();
    
    if (groupId != null) {
      SocketService.emit('sos_cancel', {
        'groupId': groupId,
        'pilgrimId': ref.read(authProvider).userId,
        'sos_id': ?sosId,
      });
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

    final notifCount = ref.watch(notificationProvider).unreadCount;

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

    ref.listen(authProvider, (prev, next) {
      // Role sync polling removed in moderator-first workflow
    });

    ref.listen(pilgrimProvider, (prev, next) {
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
    });

    final tabs = [
      _HomeTab(
        pilgrimState: pilgrimState,
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
        navBeacons: pilgrimState.navBeacons,
        myLocation: _myLatLng,
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
        onSettingsTap: () => setState(() => _currentTab = 4),
        onGroupCardTap: () {
          if (pilgrimState.groupInfo != null) {
            final hasModerator = pilgrimState.groupInfo!.moderators.isNotEmpty;
            final firstModerator = hasModerator
                ? pilgrimState.groupInfo!.moderators.first
                : null;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => GroupDetailsScreen(
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
                ),
              ),
            );
          } else {
            // No group — do nothing (limbo state, moderator will assign)
          }
        },
        onHotspotsTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MeccaHotspotsScreen()),
          );
        },
      ),
      _PilgrimMapTab(
        myLocation: _myLatLng,
        mapController: _mapController,
        pilgrimState: pilgrimState,
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
        }
      },
      child: Scaffold(
        backgroundColor: isDark
            ? AppColors.backgroundDark
            : const Color(0xfff1f5f3),
        body: IndexedStack(index: _currentTab, children: tabs),
        bottomNavigationBar: _BottomNav(
          currentIndex: _currentTab,
          onTap: (i) {
            setState(() => _currentTab = i);
            // Refresh weather when switching to Home tab
            if (i == 0) {
              _loadWeatherAlert(force: true);
            }
            // Reload + mark read + scroll when opening Chat tab
            if (i == 3) {
              _chatScrollNotifier.value++;
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
// Home Tab (Redesigned)
// ─────────────────────────────────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  final PilgrimState pilgrimState;
  final bool isDark;
  final _WeatherAlert weatherAlert;
  final AnimationController sosPulseController;
  final AnimationController sosHoldController;
  final bool isSosHolding;
  final VoidCallback onSosHoldStart;
  final VoidCallback onSosHoldEnd;
  final Future<void> Function() onRefresh;
  final int sosCountdown;
  final VoidCallback onCancelSos;
  final Map<String, ModeratorBeacon> navBeacons;
  final LatLng? myLocation;
  final void Function(ModeratorBeacon) onNavigateToModerator;
  final int notificationCount;
  final VoidCallback onNotificationTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onGroupCardTap;
  final VoidCallback onHotspotsTap;

  const _HomeTab({
    required this.pilgrimState,
    required this.isDark,
    required this.weatherAlert,
    required this.sosPulseController,
    required this.sosHoldController,
    required this.isSosHolding,
    required this.onSosHoldStart,
    required this.onSosHoldEnd,
    required this.onRefresh,
    required this.sosCountdown,
    required this.onCancelSos,
    required this.navBeacons,
    this.myLocation,
    required this.onNavigateToModerator,
    required this.notificationCount,
    required this.onNotificationTap,
    required this.onSettingsTap,
    required this.onGroupCardTap,
    required this.onHotspotsTap,
  });

  @override
  Widget build(BuildContext context) {
    final profile = pilgrimState.profile;
    final group = pilgrimState.groupInfo;
    final headerBg = isDark ? AppColors.backgroundDark : const Color(0xFFFFF7ED);
    final headerText = isDark ? Colors.white : AppColors.textDark;
    final headerMuted = isDark ? Colors.white70 : AppColors.textMutedDark;
    final iconContainerBg = isDark ? Colors.white.withValues(alpha: 0.1) : AppColors.primary.withValues(alpha: 0.1);

    return Container(
      color: headerBg,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: onRefresh,
          child: CustomScrollView(
            // AlwaysScrollableScrollPhysics is required by RefreshIndicator.
            // The empty-space issue is handled by SliverFillRemaining below
            // so the body never artificially expands past its content.
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // ── Header Section ─────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top row: Avatar + ID + Settings
                      Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10.r),
                            child: Image.asset(
                              'assets/static/logo.jpeg',
                              width: 34.w,
                              height: 34.w,
                              fit: BoxFit.cover,
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Text(
                            'Munawwara Care',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: onSettingsTap,
                            child: Container(
                              padding: EdgeInsets.all(10.w),
                              decoration: BoxDecoration(
                                color: iconContainerBg,
                                borderRadius: BorderRadius.circular(14.r),
                              ),
                              child: Icon(
                                Symbols.settings,
                                size: 22.w,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 18.h),

                      // Greeting + Name (Multi-line)
                      Text(
                        'home_greeting'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 22.sp,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        pilgrimState.isLoading
                            ? '...'
                            : (profile?.shortName ?? ''),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 32.sp,
                          fontWeight: FontWeight.w800,
                          color: headerText,
                          height: 1.1,
                        ),
                      ),
                      SizedBox(height: 20.h),

                      // Sharing Status indicator (Full width badge style)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                        decoration: BoxDecoration(
                          color: iconContainerBg,
                          borderRadius: BorderRadius.circular(16.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              myLocation == null ? Symbols.location_off : Icons.navigation_rounded,
                              color: myLocation == null ? Colors.red : AppColors.primary,
                              size: 18.w,
                            ),
                            SizedBox(width: 10.w),
                            Text(
                              'home_location_sharing'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 13.sp,
                                color: headerMuted,
                              ),
                            ),
                            SizedBox(width: 6.w),
                            Text(
                              pilgrimState.isSharingLocation
                                  ? 'card_active'.tr()
                                  : 'card_paused'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Main Body ──────────────────────────────────────────────────
              // When there are no beacons: SliverFillRemaining fills the exact
              // remaining viewport with no dead-space and no over-scroll gap.
              // When beacons are present: SliverToBoxAdapter lets the list grow
              // naturally so the user can scroll down to reach the beacon card.
              if (navBeacons.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _HomeBody(
                    isDark: isDark,
                    pilgrimState: pilgrimState,
                    group: group,
                    weatherAlert: weatherAlert,
                    sosPulseController: sosPulseController,
                    sosHoldController: sosHoldController,
                    isSosHolding: isSosHolding,
                    sosCountdown: sosCountdown,
                    onSosHoldStart: onSosHoldStart,
                    onSosHoldEnd: onSosHoldEnd,
                    onCancelSos: onCancelSos,
                    onGroupCardTap: onGroupCardTap,
                    onHotspotsTap: onHotspotsTap,
                    navBeacons: navBeacons,
                    myLocation: myLocation,
                    onNavigateToModerator: onNavigateToModerator,
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: _HomeBody(
                    isDark: isDark,
                    pilgrimState: pilgrimState,
                    group: group,
                    weatherAlert: weatherAlert,
                    sosPulseController: sosPulseController,
                    sosHoldController: sosHoldController,
                    isSosHolding: isSosHolding,
                    sosCountdown: sosCountdown,
                    onSosHoldStart: onSosHoldStart,
                    onSosHoldEnd: onSosHoldEnd,
                    onCancelSos: onCancelSos,
                    onGroupCardTap: onGroupCardTap,
                    onHotspotsTap: onHotspotsTap,
                    navBeacons: navBeacons,
                    myLocation: myLocation,
                    onNavigateToModerator: onNavigateToModerator,
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
// _HomeBody — shared body content rendered inside both SliverFillRemaining and
// SliverToBoxAdapter so beacon / no-beacon layouts stay in sync.
// ─────────────────────────────────────────────────────────────────────────────

class _HomeBody extends StatelessWidget {
  final bool isDark;
  final PilgrimState pilgrimState;
  final GroupInfo? group;
  final _WeatherAlert weatherAlert;
  final AnimationController sosPulseController;
  final AnimationController sosHoldController;
  final bool isSosHolding;
  final int sosCountdown;
  final VoidCallback onSosHoldStart;
  final VoidCallback onSosHoldEnd;
  final VoidCallback onCancelSos;
  final VoidCallback onGroupCardTap;
  final VoidCallback onHotspotsTap;
  final Map<String, ModeratorBeacon> navBeacons;
  final LatLng? myLocation;
  final void Function(ModeratorBeacon) onNavigateToModerator;

  const _HomeBody({
    required this.isDark,
    required this.pilgrimState,
    required this.group,
    required this.weatherAlert,
    required this.sosPulseController,
    required this.sosHoldController,
    required this.isSosHolding,
    required this.sosCountdown,
    required this.onSosHoldStart,
    required this.onSosHoldEnd,
    required this.onCancelSos,
    required this.onGroupCardTap,
    required this.onHotspotsTap,
    required this.navBeacons,
    this.myLocation,
    required this.onNavigateToModerator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        borderRadius: BorderRadius.vertical(top: Radius.circular(36.r)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 20.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Card Grid ──────────────────────────────────────────────────
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: _GroupCardNew(
                      groupName: group?.groupName ?? 'card_no_group'.tr(),
                      onTap: onGroupCardTap,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _WeatherCardNew(alert: weatherAlert),
                        ),
                        SizedBox(height: 12.h),
                        _ExploreCardNew(onTap: onHotspotsTap),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 32.h),

            // ── SOS ────────────────────────────────────────────────────────
            Center(
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
                  if (pilgrimState.sosActive) ...[
                    SizedBox(height: 16.h),
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
                ],
              ),
            ),
            SizedBox(height: 32.h),

            // ── Navigate to Moderator (only when beacon active) ────────────
            if (navBeacons.isNotEmpty)
              Container(
                margin: EdgeInsets.only(bottom: 24.h),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
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
                          Icon(Symbols.my_location,
                              size: 18.w, color: AppColors.primary),
                          SizedBox(width: 8.w),
                          Text(
                            'nav_to_moderator'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w700,
                              fontSize: 14.sp,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    ...(() {
                      final list = navBeacons.values.toList();
                      if (myLocation != null) {
                        list.sort((a, b) {
                          final dA = Geolocator.distanceBetween(
                            myLocation!.latitude,
                            myLocation!.longitude,
                            a.lat,
                            a.lng,
                          );
                          final dB = Geolocator.distanceBetween(
                            myLocation!.latitude,
                            myLocation!.longitude,
                            b.lat,
                            b.lng,
                          );
                          return dA.compareTo(dB);
                        });
                      }
                      return list.map((beacon) {
                        double? dist;
                        if (myLocation != null) {
                          dist = Geolocator.distanceBetween(
                            myLocation!.latitude,
                            myLocation!.longitude,
                            beacon.lat,
                            beacon.lng,
                          );
                        }
                        String distStr = '';
                        if (dist != null) {
                          if (dist < 1000) {
                            distStr = '${dist.toStringAsFixed(0)}m';
                          } else {
                            distStr = '${(dist / 1000).toStringAsFixed(1)}km';
                          }
                        }

                        return Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16.w, vertical: 10.h),
                          child: Row(
                            children: [
                              Container(
                                width: 40.w,
                                height: 40.w,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.iconBgDark
                                      : AppColors.iconBgLight,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Symbols.person_pin_circle,
                                    size: 22.w, color: AppColors.primary),
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
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
                                    if (distStr.isNotEmpty)
                                      Text(
                                        distStr,
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 12.sp,
                                          color: isDark
                                              ? Colors.white70
                                              : AppColors.textMutedDark,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 10.w),
                              GestureDetector(
                                onTap: () => onNavigateToModerator(beacon),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 14.w, vertical: 9.h),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(14.r),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.35),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Symbols.navigation,
                                          color: Colors.white, size: 16.w),
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
                        );
                      }).toList();
                    })(),
                    SizedBox(height: 8.h),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// New Card Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _WeatherCardNew extends StatelessWidget {
  final _WeatherAlert alert;
  const _WeatherCardNew({required this.alert});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(alert.icon, color: AppColors.accentGold, size: 28.w),
          SizedBox(height: 8.h),
          Text(
            alert.isLoading
                ? '...'
                : alert.isError
                ? '--'
                : '${alert.temperatureC}\u00b0C',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 26.sp,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            alert.isLoading
                ? 'weather_loading'.tr()
                : alert.isError
                ? 'weather_unavailable'.tr()
                : alert.condition,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.primary : AppColors.primaryDark,
            ),
          ),
          SizedBox(height: 4.h),
          Expanded(
            child: Text(
              alert.isLoading ? 'weather_loading_hint'.tr() : alert.reminder,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 11.sp,
                color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupCardNew extends StatelessWidget {
  final String groupName;
  final VoidCallback onTap;

  const _GroupCardNew({required this.groupName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.groups, color: AppColors.primary, size: 36.w),
            SizedBox(height: 16.h),
            Text(
              'home_my_group'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: 4.h),
            Expanded(
              child: Text(
                groupName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 24.sp,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.textDark,
                  height: 1.1,
                ),
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'home_tap_details'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 12.sp,
                color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExploreCardNew extends StatelessWidget {
  final VoidCallback onTap;
  const _ExploreCardNew({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 16.h),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.navigation_rounded,
                color: AppColors.primary,
                size: 20.w,
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'home_explore'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
            const Spacer(),
            Icon(
              Symbols.arrow_forward_ios,
              size: 14.w,
              color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
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
  late AnimationController _scaleController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  void _onDown() {
    _scaleController.forward();
    HapticFeedback.mediumImpact();
  }

  void _onUp() {
    _scaleController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    const double size = 190;
    const double ringStroke = 8;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onLongPressDown: (_) => _onDown(),
      onLongPressStart: (_) {
        HapticFeedback.heavyImpact();
        widget.onHoldStart();
      },
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
              // ── Layered Animated Glows ─────────────────────────────────────
              AnimatedBuilder(
                animation: widget.pulseController,
                builder: (_, _) {
                  final p = widget.pulseController.value;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer faint glow
                      Transform.scale(
                        scale: 1.0 + (0.6 * p),
                        child: Container(
                          width: (size - 10).w,
                          height: (size - 10).w,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red.withValues(alpha: 0.15 * (1 - p)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.2 * (1 - p)),
                                blurRadius: 25 * p,
                                spreadRadius: 10 * p,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Inner pulse
                      Transform.scale(
                        scale: 1.0 + (0.3 * p),
                        child: Container(
                          width: (size - 20).w,
                          height: (size - 20).w,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red.withValues(alpha: 0.25 * (1 - p)),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

              // ── Holding Progress Ring ──────────────────────────────────────
              if (widget.isHolding)
                AnimatedBuilder(
                  animation: widget.holdController,
                  builder: (_, _) => SizedBox(
                    width: size.w,
                    height: size.w,
                    child: CircularProgressIndicator(
                      value: widget.holdController.value,
                      strokeWidth: ringStroke.w,
                      color: Colors.white,
                      backgroundColor: Colors.white24,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                ),

              // ── Main Button Surface ────────────────────────────────────────
              Container(
                width: (size - 24).w,
                height: (size - 24).w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.sosActive
                        ? [Colors.red.shade400, Colors.red.shade700]
                        : [const Color(0xFFFF4B4B), const Color(0xFFC41E3A)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: widget.sosActive ? 0.3 : 0.5),
                      blurRadius: 24,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                    // Inner highlight
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.2),
                      blurRadius: 0,
                      spreadRadius: -4,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: widget.isLoading
                    ? Center(
                        child: SizedBox(
                          width: 40.w,
                          height: 40.w,
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 4,
                          ),
                        ),
                      )
                    : widget.isHolding
                        ? _SosHoldingContent(countdown: widget.countdown)
                        : _SosIdleContent(sosActive: widget.sosActive),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SosHoldingContent extends StatelessWidget {
  final int countdown;
  const _SosHoldingContent({required this.countdown});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$countdown',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 68.sp,
            fontWeight: FontWeight.w900,
            color: Colors.white,
          ),
        ),
        Text(
          'SECONDS',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 12.sp,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.7),
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

class _SosIdleContent extends StatelessWidget {
  final bool sosActive;
  const _SosIdleContent({required this.sosActive});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'sos_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 48.sp,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: 4,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          sosActive ? 'sos_active_text'.tr() : 'sos_hold_label'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14.sp,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: 0.8),
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Weather Alert Model
// ─────────────────────────────────────────────────────────────────────────────

class _WeatherAlert {
  final int temperatureC;
  final String condition;
  final String reminder;
  final IconData icon;
  final Color iconColor;
  final bool isLoading;
  final bool isError;

  const _WeatherAlert({
    required this.temperatureC,
    required this.condition,
    required this.reminder,
    required this.icon,
    required this.iconColor,
    required this.isLoading,
    required this.isError,
  });

  const _WeatherAlert.loading()
    : temperatureC = 0,
      condition = 'Loading weather',
      reminder = 'Checking local weather conditions...',
      icon = Icons.wb_sunny,
      iconColor = AppColors.primary,
      isLoading = true,
      isError = false;

  const _WeatherAlert.error(String message)
    : temperatureC = 0,
      condition = 'Weather unavailable',
      reminder = message,
      icon = Icons.cloud_off,
      iconColor = AppColors.textMutedLight,
      isLoading = false,
      isError = true;
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

  // Maps nav-bar slot → tab index in the IndexedStack.
  // Slot 0 = Home (0), Slot 1 = Map (1), Slot 2 = Qibla (2), Slot 3 = Chat (3)
  static const _tabIndices = [0, 1, 2, 3];

  @override
  Widget build(BuildContext context) {
    final labels = [
      'tab_home'.tr(),
      'tab_map'.tr(),
      'tab_qibla'.tr(),
      'tab_chat'.tr(),
    ];
    final icons = [
      Symbols.home,
      Symbols.map,
      Symbols.explore,
      Symbols.chat_bubble,
    ];
    // Badge counts per slot (only chat has a badge)
    final badges = [0, 0, 0, unreadMessages];

    final bgColor = isDark ? AppColors.surfaceDark : Colors.white;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(
          top: BorderSide(color: dividerColor, width: 1),
        ),
      ),
      height: 66.h + MediaQuery.of(context).padding.bottom,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Row(
        children: List.generate(4, (slot) {
          final tabIndex = _tabIndices[slot];
          final isSelected = tabIndex == currentIndex;
          final badge = badges[slot];

          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(tabIndex),
              behavior: HitTestBehavior.opaque,
              child: Column(
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
                              ? (isDark
                                  ? AppColors.iconBgDark
                                  : AppColors.iconBgLight)
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
                      if (badge > 0)
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
                              badge > 9 ? '9+' : '$badge',
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
                    labels[slot],
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 10.sp,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
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
                      width: 120.w,
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
                                color: AppColors.primary.withValues(alpha: 0.5),
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
                      color: Colors.black.withValues(alpha: 0.08),
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
                      backgroundColor: isDark
                          ? AppColors.iconBgDark
                          : AppColors.iconBgLight,
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
                color: isDark ? AppColors.iconBgDark : AppColors.iconBgLight,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
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
                      color: const Color(0xFFDC2626).withValues(alpha: 0.45),
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
        child: AlertsTab(onBack: () => Navigator.of(context).pop()),
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
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            widget.mapController.move(
                              LatLng(area.latitude, area.longitude),
                              widget.mapController.camera.zoom > 16.0
                                  ? widget.mapController.camera.zoom
                                  : 16.5,
                            );
                            widget.onAreaSelected(area);
                          },
                          child: Container(
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                      final googleMapsWeb = Uri.parse(
                                        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
                                      );
                                      try {
                                        await launchUrl(
                                          googleMapsWeb,
                                          mode: LaunchMode.externalApplication,
                                        );
                                      } catch (_) {}
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
                  color: AppColors.primary.withValues(alpha: 0.45),
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
              color: color.withValues(alpha: 0.12),
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
              color: color.withValues(alpha: 0.12),
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
          Text(
            '${'area_by'.tr()} ${area.createdByName}',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11.sp,
              color: AppColors.textMutedLight,
            ),
          ),
          if (isMeetpoint && area.meetpointTime != null) ...[
            SizedBox(height: 16.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36.w,
                    height: 36.w,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Symbols.schedule, color: color, size: 20.w),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat('hh:mm a').format(area.meetpointTime!),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 16.sp,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        if (area.reminderMinutes != null)
                          Text(
                            area.reminderMinutes! > 0
                                ? 'area_reminder_mins'.tr(args: [area.reminderMinutes.toString()])
                                : 'area_reminder_at_time'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 11.sp,
                              color: AppColors.textMutedLight,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx);
                  final lat = area.latitude;
                  final lng = area.longitude;
                  final googleMapsWeb = Uri.parse(
                    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
                  );
                  try {
                    await launchUrl(
                      googleMapsWeb,
                      mode: LaunchMode.externalApplication,
                    );
                  } catch (_) {}
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
                color: color.withValues(alpha: 0.35),
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
              Flexible(
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
                color: color.withValues(alpha: 0.5),
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

// ─────────────────────────────────────────────────────────────────────────────
// SOS Call Options Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _SosCallOptionsSheet extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onInternetCall;
  final VoidCallback onNormalCall;

  const _SosCallOptionsSheet({
    required this.onCancel,
    required this.onInternetCall,
    required this.onNormalCall,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(28.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 32.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grab handle
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 20.h),

            // SOS active indicator
            Container(
              width: 60.w,
              height: 60.w,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: Colors.red.shade600,
                size: 32.w,
              ),
            ),
            SizedBox(height: 12.h),

            Text(
              'sos_sent_title'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 20.sp,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade600,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'sos_sent_body'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                color: AppColors.textMutedLight,
                height: 1.5,
              ),
            ),
            SizedBox(height: 24.h),

            // Internet Call Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onInternetCall,
                icon: Icon(Icons.wifi_calling_3_rounded, size: 20.w),
                label: Text(
                  'sos_call_internet'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                ),
              ),
            ),
            SizedBox(height: 10.h),

            // Normal Call Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onNormalCall,
                icon: Icon(Icons.phone_rounded, size: 20.w),
                label: Text(
                  'sos_call_normal'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                ),
              ),
            ),
            SizedBox(height: 10.h),

            // Cancel SOS Button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade400,
                  padding: EdgeInsets.symmetric(vertical: 12.h),
                ),
                child: Text(
                  'sos_cancel_btn'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
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
