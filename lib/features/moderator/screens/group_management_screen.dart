import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/widgets/custom_dialog.dart';
import '../../../core/widgets/standard_snackbar.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/location_permission_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/map/app_map_marker_cluster.dart';
import '../../../core/map/app_map_tiles.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_popup_menu.dart';
import '../providers/moderator_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../calling/providers/call_provider.dart';
import '../../calling/screens/voice_call_screen.dart';
import '../../shared/providers/suggested_area_provider.dart';
import 'group_messages_screen.dart';
import 'individual_messages_screen.dart';
import '../widgets/pilgrim_profile_sheet.dart';
import '../widgets/area_picker_screen.dart';
import '../widgets/moderator_map_widgets.dart';
import '../widgets/pilgrim_marker_layout.dart';
import '../widgets/active_meetpoint_card.dart';
import '../../shared/models/suggested_area_model.dart';
import '../../shared/widgets/pilgrim_gender_avatar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Beacon state: static map survives hot-reload (widget recreation).
// SharedPreferences is the fallback for full app restarts.
// ─────────────────────────────────────────────────────────────────────────────
final Map<String, bool> _navBeaconCache = {};

// ─────────────────────────────────────────────────────────────────────────────
// Group Management Screen  (map-first + manage pilgrims/moderators)
// ─────────────────────────────────────────────────────────────────────────────

enum _ModInviteStep { qr, code, email }

class GroupManagementScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String currentUserId;

  const GroupManagementScreen({
    super.key,
    required this.groupId,
    required this.currentUserId,
  });

  @override
  ConsumerState<GroupManagementScreen> createState() =>
      _GroupManagementScreenState();
}

class _GroupManagementScreenState extends ConsumerState<GroupManagementScreen> {
  final _mapController = MapController();
  final _dssController = DraggableScrollableController();
  final _searchController = TextEditingController();
  final ValueNotifier<double> _sheetExtent = ValueNotifier(0.28);
  String _searchQuery = '';

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  LatLng? _myLocation;
  StreamSubscription<Position>? _locationSub;
  String? _focusedPilgrimId;
  bool _navBeaconEnabled = false;
  Timer? _meetpointExpiryTimer;
  bool _isAutoDeletingMeetpoint = false;

  @override
  void initState() {
    super.initState();
    // Synchronously restore from Riverpod (survives hot reload, no flicker)
    _navBeaconEnabled = _navBeaconCache[widget.groupId] ?? false;
    _initLocation();
    _loadBeaconState();
    // Join the group socket room so moderator receives group events
    SocketService.emit('join_group', widget.groupId);
    _searchController.addListener(() {
      if (mounted) setState(() => _searchQuery = _searchController.text);
    });
    // Load suggested areas & meetpoints
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(suggestedAreaProvider.notifier).load(widget.groupId);
      _autoDeleteExpiredMeetpointIfNeeded();
    });
    // Real-time area sync
    SocketService.on('area_added', (data) {
      if (!mounted) return;
      ref
          .read(suggestedAreaProvider.notifier)
          .appendArea(data as Map<String, dynamic>);
      _autoDeleteExpiredMeetpointIfNeeded();
    });
    SocketService.on('area_deleted', (data) {
      if (!mounted) return;
      final map = data as Map<String, dynamic>;
      final areaId = map['area_id'] as String?;
      if (areaId != null) {
        ref.read(suggestedAreaProvider.notifier).removeArea(areaId);
      }
    });
    // Real-time pilgrim updates
    SocketService.on('location_update', (data) {
      if (!mounted) return;
      final map = Map<String, dynamic>.from(data as Map);
      final pilgrimId = map['pilgrimId']?.toString();
      final lat = (map['latitude'] as num?)?.toDouble();
      final lng = (map['longitude'] as num?)?.toDouble();
      final batteryRaw = map['battery_percent'];
      final battery = batteryRaw is int
          ? batteryRaw
          : (batteryRaw as num?)?.toInt();
      if (pilgrimId != null && lat != null && lng != null) {
        ref
            .read(moderatorProvider.notifier)
            .updatePilgrimLocation(pilgrimId, lat, lng, battery);
      }
    });
    SocketService.on('status_update', (data) {
      if (!mounted) return;
      final map = data as Map<String, dynamic>;
      final pilgrimId = map['pilgrimId'] as String?;
      final active = map['active'] == true;
      final lastStr = map['last_active_at']?.toString();
      DateTime lastActiveAt = DateTime.now();
      if (lastStr != null) {
        lastActiveAt = DateTime.tryParse(lastStr) ?? DateTime.now();
      }
      if (pilgrimId != null) {
        ref
            .read(moderatorProvider.notifier)
            .updatePilgrimStatus(pilgrimId, active, lastActiveAt);
      }
    });
    // Re-join group room & re-emit beacon on every reconnect (server state is lost on restart)
    SocketService.onConnected(_onSocketConnected);
    _meetpointExpiryTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _autoDeleteExpiredMeetpointIfNeeded();
    });
  }

  // Named reconnect handler so offConnected can find it.
  void _onSocketConnected() {
    if (!mounted) return;
    SocketService.emit('join_group', widget.groupId);
    // Re-sync beacon state if it was enabled
    if (_navBeaconEnabled && _myLocation != null) {
      final auth = ref.read(authProvider);
      SocketService.emit('mod_nav_beacon', {
        'groupId': widget.groupId,
        'enabled': true,
        'lat': _myLocation!.latitude,
        'lng': _myLocation!.longitude,
        'moderatorId': auth.userId,
        'moderatorName': auth.fullName ?? 'Moderator',
      });
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _dssController.dispose();
    _searchController.dispose();
    _locationSub?.cancel();
    _meetpointExpiryTimer?.cancel();
    SocketService.off('area_added');
    SocketService.off('area_deleted');
    SocketService.off('location_update');
    SocketService.off('status_update');
    SocketService.offConnected(_onSocketConnected);
    // Do NOT emit leave_group here — the moderator dashboard still needs
    // to receive new_message and other group events while on the groups list.
    super.dispose();
  }

  Future<void> _autoDeleteExpiredMeetpointIfNeeded() async {
    if (!mounted || _isAutoDeletingMeetpoint) return;
    final expiredMeetpoints = ref.read(suggestedAreaProvider).expiredMeetpoints;
    if (expiredMeetpoints.isEmpty) return;
    // Delete only one expired meetpoint per tick to avoid bulk deletions/spam.
    final target = expiredMeetpoints.first;

    _isAutoDeletingMeetpoint = true;
    try {
      final ok = await ref
          .read(suggestedAreaProvider.notifier)
          .deleteArea(widget.groupId, target.id);
      if (ok) {
        if (mounted) {
          StandardSnackBar.showSuccess(context, 'area_deleted'.tr());
        }
      }
    } finally {
      _isAutoDeletingMeetpoint = false;
    }
  }

  // ── Location ──────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    final ok = await hasLocationAlwaysPermission();
    if (!ok || !mounted) return;

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        final age = DateTime.now().difference(last.timestamp);
        final acc = last.accuracy;
        final accOk = !acc.isInfinite && acc >= 0 && acc <= 8000;
        if (age <= const Duration(hours: 8) && accOk) {
          setState(() => _myLocation = LatLng(last.latitude, last.longitude));
          _mapController.move(_myLocation!, AppMapTiles.clampMapZoom(15));
        }
      }
    } catch (_) {}

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      _mapController.move(_myLocation!, AppMapTiles.clampMapZoom(15));

      if (_navBeaconEnabled) {
        final auth = ref.read(authProvider);
        SocketService.emit('mod_nav_beacon', {
          'groupId': widget.groupId,
          'enabled': true,
          'lat': pos.latitude,
          'lng': pos.longitude,
          'moderatorId': auth.userId,
          'moderatorName': auth.fullName ?? 'Moderator',
        });
      }
    } on TimeoutException catch (_) {
      // Keep _myLocation from last-known if set; stream still updates later.
    } catch (_) {}

    _locationSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 25,
          ),
        ).listen((pos) {
          if (mounted) {
            setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
            // Keep beacon coords fresh while enabled
            if (_navBeaconEnabled) {
              final auth = ref.read(authProvider);
              SocketService.emit('mod_nav_beacon', {
                'groupId': widget.groupId,
                'enabled': true,
                'lat': pos.latitude,
                'lng': pos.longitude,
                'moderatorId': auth.userId,
                'moderatorName': auth.fullName ?? 'Moderator',
              });
            }
          }
        });
  }

  // ── Map helpers ───────────────────────────────────────────────────────────

  void _focusPilgrim(PilgrimInGroup p) {
    if (!p.hasLocation) {
      StandardSnackBar.showWarning(
        context,
        '${p.firstName} has no location data yet',
      );
      return;
    }
    setState(() => _focusedPilgrimId = p.id);
    _mapController.move(LatLng(p.lat!, p.lng!), AppMapTiles.clampMapZoom(17));
    _dssController.animateTo(
      0.28,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _navigateToPilgrim(PilgrimInGroup p) async {
    if (!p.hasLocation) {
      StandardSnackBar.showWarning(
        context,
        '${p.firstName} ${'group_not_found'.tr()}',
      );
      return;
    }
    final lat = p.lat!;
    final lng = p.lng!;
    // Try Google Maps app first (works even when app is installed)
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
      // Final fallback — open in browser
      await launchUrl(googleMapsWeb, mode: LaunchMode.externalApplication);
    }
  }

  // ── Navigation Beacon ───────────────────────────────────────────────────────

  Future<void> _loadBeaconState() async {
    // Only load from SharedPreferences if Riverpod doesn't already have a
    // persisted value (i.e. this is a full app restart, not a hot reload).
    if (_navBeaconEnabled) return; // Riverpod already restored it
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool('nav_beacon_${widget.groupId}') ?? false;
    if (!mounted || !saved) return;
    setState(() => _navBeaconEnabled = true);
    _navBeaconCache[widget.groupId] = true;
    // Re-emit so pilgrims see beacon immediately (only if we have coordinates)
    if (_myLocation != null) {
      final auth = ref.read(authProvider);
      SocketService.emit('mod_nav_beacon', {
        'groupId': widget.groupId,
        'enabled': true,
        'lat': _myLocation!.latitude,
        'lng': _myLocation!.longitude,
        'moderatorId': auth.userId,
        'moderatorName': auth.fullName ?? 'Moderator',
      });
    }
  }

  void _toggleNavBeacon(ModeratorGroup group) {
    final newVal = !_navBeaconEnabled;
    setState(() => _navBeaconEnabled = newVal);
    // Persist in Riverpod (hot-reload safe) and SharedPreferences (restart safe)
    _navBeaconCache[group.id] = newVal;
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setBool('nav_beacon_${group.id}', newVal),
    );
    final auth = ref.read(authProvider);
    if (!newVal) {
      // Turning OFF — always emit immediately so pilgrims lose the beacon
      SocketService.emit('mod_nav_beacon', {
        'groupId': group.id,
        'enabled': false,
        'lat': null,
        'lng': null,
        'moderatorId': auth.userId,
        'moderatorName': auth.fullName ?? 'Moderator',
      });
    } else if (_myLocation != null) {
      // Turning ON and we already have a GPS fix — emit now
      SocketService.emit('mod_nav_beacon', {
        'groupId': group.id,
        'enabled': true,
        'lat': _myLocation!.latitude,
        'lng': _myLocation!.longitude,
        'moderatorId': auth.userId,
        'moderatorName': auth.fullName ?? 'Moderator',
      });
    }
    // If turning ON but no GPS fix yet: _navBeaconEnabled is now true, and
    // _initLocation's first-fix handler will emit as soon as coords arrive.
    if (newVal) {
      StandardSnackBar.showSuccess(context, 'nav_beacon_on'.tr());
    } else {
      StandardSnackBar.showInfo(context, 'nav_beacon_off'.tr());
    }
  }

  // ── Add Pilgrim ───────────────────────────────────────────────────────────

  // ── Remove pilgrim ────────────────────────────────────────────────────────

  Future<bool> _confirmRemovePilgrim(
    ModeratorGroup group,
    PilgrimInGroup pilgrim,
  ) async {
    final confirmed = await StandardDialog.show<bool>(
      context: context,
      title: 'group_remove_title',
      content: 'group_remove_confirm_body',
      contentNamedArgs: {'name': pilgrim.fullName},
      confirmText: 'group_remove_confirm',
      cancelText: 'group_remove_cancel',
      isDestructive: true,
    );
    if (confirmed == true && mounted) {
      final (ok, err) = await ref
          .read(moderatorProvider.notifier)
          .removePilgrimFromGroup(group.id, pilgrim.id);
      if (mounted) {
        if (ok) {
          StandardSnackBar.showSuccess(
            context,
            'group_remove_success_msg'.tr(
              namedArgs: {'name': pilgrim.firstName},
            ),
          );
        } else {
          StandardSnackBar.showError(context, err ?? 'group_not_found'.tr());
        }
      }
      return ok;
    }
    return false;
  }

  // ── Call pilgrim ──────────────────────────────────────────

  void _showCallSheet(PilgrimInGroup pilgrim) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Consumer(
        builder: (ctx, ref, child) {
          final cooldownSeconds = ref.watch(callProvider).cooldownSeconds;
          return Container(
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
            Text(
              '${'group_call_prefix'.tr()} ${pilgrim.firstName}',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 17.sp,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
            SizedBox(height: 20.h),
            Row(
              children: [
                // ── Carrier call ────────────────────────────────────
                if (pilgrim.phoneNumber != null)
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        Navigator.pop(ctx);
                        final uri = Uri(
                          scheme: 'tel',
                          path: pilgrim.phoneNumber,
                        );
                        if (await canLaunchUrl(uri)) launchUrl(uri);
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          vertical: 18.h,
                          horizontal: 12.w,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.backgroundDark
                              : const Color(0xFFF0F0F8),
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 52.w,
                              height: 52.w,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Symbols.smartphone,
                                color: Colors.white,
                                size: 26.w,
                              ),
                            ),
                            SizedBox(height: 10.h),
                            Text(
                              'group_phone_call'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                                fontSize: 13.sp,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.textDark,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              'group_phone_call_sub'.tr(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 10.sp,
                                color: AppColors.textMutedLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (pilgrim.phoneNumber != null) SizedBox(width: 12.w),
                // ── Internet call ─────────────────────────────────
                Expanded(
                  child: GestureDetector(
                    onTap: cooldownSeconds > 0 ? null : () {
                      Navigator.pop(ctx);
                      // Initiate WebRTC call
                      ref
                          .read(callProvider.notifier)
                          .startCall(
                            remoteUserId: pilgrim.id,
                            remoteUserName: pilgrim.fullName,
                            remotePeerGender: pilgrim.gender,
                          );
                      Navigator.push(
                        ctx,
                        MaterialPageRoute(
                          builder: (_) => VoiceCallScreen(
                            initialPeerName: pilgrim.fullName,
                            initialPeerGender: pilgrim.gender,
                          ),
                        ),
                      );
                    },
                    child: Opacity(
                      opacity: cooldownSeconds > 0 ? 0.5 : 1.0,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          vertical: 18.h,
                          horizontal: 12.w,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8C97A).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(
                            color: const Color(0xFFE8C97A).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 52.w,
                              height: 52.w,
                              decoration: const BoxDecoration(
                                color: Color(0xFFB0924A),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Symbols.wifi_calling_3,
                                color: Colors.white,
                                size: 26.w,
                              ),
                            ),
                            SizedBox(height: 10.h),
                            Text(
                              cooldownSeconds > 0 ? '${'group_internet_call'.tr()} ($cooldownSeconds)' : 'group_internet_call'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                                fontSize: 13.sp,
                                color: isDark ? Colors.white : AppColors.textDark,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              'group_internet_call_sub'.tr(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 10.sp,
                                color: AppColors.textMutedLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
      ),
    );
  }

  // ── Pilgrim profile sheet ──────────────────────────────────────────────────

  void _showPilgrimProfile(PilgrimInGroup pilgrim) {
    final currentUserId = ref.read(authProvider).userId ?? '';
    showPilgrimProfileSheet(context, pilgrim, widget.groupId, currentUserId);
  }

  void _openPrivateChat(PilgrimInGroup pilgrim) {
    final currentUserId = ref.read(authProvider).userId ?? '';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => IndividualMessagesScreen(
          groupId: widget.groupId,
          groupName: 'msg_private_header'.tr(),
          recipientId: pilgrim.id,
          recipientName: pilgrim.fullName,
          currentUserId: currentUserId,
          recipientLanguage: pilgrim.language,
        ),
      ),
    );
  }

  // ── Leave Group Handlers ──────────────────────────────────────────────────

  Future<void> _handleLeaveGroup(ModeratorGroup group) async {
    final auth = ref.read(authProvider);
    final userId = auth.userId;
    if (userId == null) return;

    final isCreator = group.createdBy == userId;
    final otherMods = group.moderators.where((m) => m.id != userId).toList();

    if (otherMods.isEmpty) {
      // Case 1: Only moderator
      _showOnlyModeratorLeaveDialog(group);
      return;
    }

    if (isCreator) {
      // Case 2: Creator reassign
      _showReassignDialog(group, otherMods);
      return;
    }

    // Case 3: Normal leave
    _showNormalLeaveDialog(group, otherMods);
  }

  void _showOnlyModeratorLeaveDialog(ModeratorGroup group) {
    StandardDialog.show(
      context: context,
      title: 'group_leave_only_mod_title',
      content: 'group_leave_only_mod_desc',
      confirmText: 'group_delete_permanently',
      cancelText: 'area_cancel',
      isDestructive: true,
    ).then((confirmed) async {
      if (confirmed == true) {
        final (ok, err) = await ref
            .read(moderatorProvider.notifier)
            .deleteGroup(group.id);
        if (mounted && ok) {
          Navigator.of(context).pop(); // pop management screen
        } else if (mounted && err != null) {
          StandardSnackBar.showError(context, err);
        }
      }
    });
  }

  void _showReassignDialog(
    ModeratorGroup group,
    List<GroupModerator> otherMods,
  ) {
    String? selectedModId;
    StandardDialog.show(
      context: context,
      title: 'group_leave_reassign_title',
      confirmText: 'group_leave_reassign_btn',
      cancelText: 'area_cancel',
      isDestructive: true,
      contentWidget: StatefulBuilder(
        builder: (ctx, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'group_leave_reassign_desc'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : AppColors.textMutedLight,
              ),
            ),
            SizedBox(height: 16.h),
            RadioGroup<String>(
              groupValue: selectedModId,
              onChanged: (val) => setDialogState(() => selectedModId = val),
              child: Column(
                children: otherMods
                    .map(
                      (mod) => RadioListTile<String>(
                        title: Text(
                          mod.fullName,
                          style: const TextStyle(fontFamily: 'Lexend'),
                        ),
                        value: mod.id,
                        activeColor: AppColors.primary,
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    ).then((confirmed) async {
      if (confirmed == true && selectedModId != null) {
        final (ok, err) = await ref
            .read(moderatorProvider.notifier)
            .leaveGroup(group.id, newCreatorId: selectedModId);
        if (mounted && ok) {
          Navigator.of(context).pop(); // pop management screen
        } else if (mounted && err != null) {
          StandardSnackBar.showError(context, err);
        }
      }
    });
  }

  void _showNormalLeaveDialog(
    ModeratorGroup group,
    List<GroupModerator> otherMods,
  ) {
    StandardDialog.show(
      context: context,
      title: 'group_leave_confirm_title',
      confirmText: 'group_leave_reassign_btn',
      cancelText: 'area_cancel',
      isDestructive: true,
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'group_leave_confirm_desc'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14.sp,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white70
                  : AppColors.textMutedLight,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'group_leave_remaining_mods'.tr(),
            style: const TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8.h),
          ...otherMods.map(
            (mod) => Text(
              '• ${mod.fullName}',
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed == true) {
        final (ok, err) = await ref
            .read(moderatorProvider.notifier)
            .leaveGroup(group.id);
        if (mounted && ok) {
          Navigator.of(context).pop(); // pop management screen
        } else if (mounted && err != null) {
          StandardSnackBar.showError(context, err);
        }
      }
    });
  }

  // ── Moderator management sheet ────────────────────────────────────────────

  void _showManageSheet(ModeratorGroup group) {
    // Refresh group data in the background so the moderator list is always up-to-date
    ref.read(moderatorProvider.notifier).refreshGroup(group.id);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ModeratorManageSheet(
        group: group,
        currentUserId: widget.currentUserId,
        isCreator: group.createdBy == widget.currentUserId,
      ),
    );
  }

  // ── Filtered list ─────────────────────────────────────────────────────────

  List<PilgrimInGroup> _getFiltered(ModeratorGroup group) {
    if (_searchQuery.isEmpty) return group.pilgrims;
    final q = _searchQuery.toLowerCase();
    return group.pilgrims.where((p) {
      return p.fullName.toLowerCase().contains(q) ||
          (p.nationalId?.toLowerCase().contains(q) ?? false) ||
          (p.phoneNumber?.contains(q) ?? false);
    }).toList();
  }

  // ── Area/Meetpoint Actions ────────────────────────────────────────────────

  void _showAreaActions(ModeratorGroup group, SuggestedAreaState areaState) {
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
            SizedBox(height: 20.h),
            Text(
              'area_manage_title'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 18.sp,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
            SizedBox(height: 20.h),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _openAreaPicker(group, 'suggestion');
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        vertical: 20.h,
                        horizontal: 12.w,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.surfaceDark
                            : AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(
                          color: isDark
                              ? AppColors.primary.withValues(alpha: 0.25)
                              : AppColors.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 52.w,
                            height: 52.w,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Symbols.add_location,
                              color: Colors.white,
                              size: 26.w,
                            ),
                          ),
                          SizedBox(height: 12.h),
                          Text(
                            'area_suggest'.tr(),
                            textAlign: TextAlign.center,
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
                SizedBox(width: 12.w),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      if (areaState.hasMeetpoint) {
                        StandardSnackBar.showWarning(
                          context,
                          'area_meetpoint_exists'.tr(),
                        );
                        return;
                      }
                      _openAreaPicker(group, 'meetpoint');
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        vertical: 20.h,
                        horizontal: 12.w,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0x22DC2626)
                            : const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(
                          color: isDark
                              ? const Color(0x33DC2626)
                              : const Color(0xFFFECACA),
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 52.w,
                            height: 52.w,
                            decoration: const BoxDecoration(
                              color: Color(0xFFDC2626),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Symbols.crisis_alert,
                              color: Colors.white,
                              size: 26.w,
                            ),
                          ),
                          SizedBox(height: 12.h),
                          Text(
                            'area_meetpoint'.tr(),
                            textAlign: TextAlign.center,
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
              ],
            ),
            if (areaState.areas.isNotEmpty) ...[
              SizedBox(height: 16.h),
              Divider(color: Colors.grey.shade200),
              SizedBox(height: 8.h),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  _showAreaList(group, areaState);
                },
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.backgroundDark
                        : const Color(0xFFF0F0F8),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Symbols.list,
                        size: 18.w,
                        color: isDark
                            ? AppColors.textLight
                            : AppColors.textDark,
                      ),
                      SizedBox(width: 8.w),
                      Text(
                        'area_view_all'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 14.sp,
                          color: isDark
                              ? AppColors.textLight
                              : AppColors.textDark,
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 2.h,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Text(
                          '${areaState.areas.length}',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 12.sp,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAreaList(ModeratorGroup group, SuggestedAreaState areaState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final liveAreaState = ref.watch(suggestedAreaProvider);
          return Container(
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
                  child: liveAreaState.areas.isEmpty
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
                          itemCount: liveAreaState.areas.length,
                          itemBuilder: (_, i) {
                            final area = liveAreaState.areas[i];
                            return Container(
                              margin: EdgeInsets.only(bottom: 10.h),
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                color: area.isMeetpoint
                                    ? (isDark
                                          ? const Color(0xFF450a0a)
                                          : const Color(0xFFFEF2F2))
                                    : (isDark
                                          ? AppColors.backgroundDark
                                          : const Color(0xFFF0F0F8)),
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(
                                  color: area.isMeetpoint
                                      ? (isDark
                                            ? const Color(0xFF991b1b)
                                            : const Color(0xFFFECACA))
                                      : Colors.transparent,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36.w,
                                    height: 36.w,
                                    decoration: BoxDecoration(
                                      color: area.isMeetpoint
                                          ? const Color(0xFFDC2626)
                                          : AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      area.isMeetpoint
                                          ? Symbols.crisis_alert
                                          : Symbols.pin_drop,
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
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
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
                                            ),
                                            SizedBox(width: 6.w),
                                            Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 6.w,
                                                vertical: 2.h,
                                              ),
                                              decoration: BoxDecoration(
                                                color: area.isMeetpoint
                                                    ? const Color(
                                                        0xFFDC2626,
                                                      ).withValues(alpha: 0.15)
                                                    : AppColors.primary
                                                          .withValues(
                                                            alpha: 0.15,
                                                          ),
                                                borderRadius:
                                                    BorderRadius.circular(6.r),
                                              ),
                                              child: Text(
                                                area.isMeetpoint
                                                    ? 'area_meetpoint'.tr()
                                                    : 'area_suggestion_label'
                                                          .tr(),
                                                style: TextStyle(
                                                  fontFamily: 'Lexend',
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 9.sp,
                                                  color: area.isMeetpoint
                                                      ? const Color(0xFFDC2626)
                                                      : AppColors.primary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (area.description.isNotEmpty)
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
                                    ),
                                  ),
                                  // Focus on map
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      _mapController.move(
                                        LatLng(area.latitude, area.longitude),
                                        AppMapTiles.clampMapZoom(17),
                                      );
                                    },
                                    child: Container(
                                      width: 32.w,
                                      height: 32.w,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.1,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Symbols.my_location,
                                        size: 15.w,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 6.w),
                                  // Edit
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              AreaPickerScreen(
                                                groupId: group.id,
                                                areaType: area.areaType,
                                                existingArea: area,
                                              ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      width: 32.w,
                                      height: 32.w,
                                      decoration: BoxDecoration(
                                        color: AppColors.info.withValues(
                                          alpha: 0.1,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Symbols.edit,
                                        size: 15.w,
                                        color: AppColors.info,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 6.w),
                                  // Delete
                                  GestureDetector(
                                    onTap: () async {
                                      if (area.isMeetpoint) {
                                        final shouldDelete =
                                            await StandardDialog.show<bool>(
                                              context: context,
                                              title:
                                                  'area_delete_meetpoint_confirm_title',
                                              content:
                                                  'area_delete_meetpoint_confirm_message',
                                              confirmText: 'msg_delete_confirm',
                                              cancelText: 'area_cancel',
                                              isDestructive: true,
                                            ) ??
                                            false;

                                        if (!shouldDelete) return;
                                      }

                                      final ok = await ref
                                          .read(suggestedAreaProvider.notifier)
                                          .deleteArea(group.id, area.id);
                                      if (!context.mounted) return;
                                      if (ok) {
                                        StandardSnackBar.showSuccess(
                                          context,
                                          'area_deleted'.tr(),
                                        );
                                      }
                                    },
                                    child: Container(
                                      width: 32.w,
                                      height: 32.w,
                                      decoration: BoxDecoration(
                                        color: Colors.red.withValues(
                                          alpha: 0.1,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Symbols.delete,
                                        size: 15.w,
                                        color: Colors.red,
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
          );
        },
      ),
    );
  }

  Future<void> _handleDeleteArea(SuggestedArea area) async {
    if (area.isMeetpoint) {
      final shouldDelete =
          await StandardDialog.show<bool>(
            context: context,
            title: 'area_delete_meetpoint_confirm_title',
            content: 'area_delete_meetpoint_confirm_message',
            confirmText: 'msg_delete_confirm',
            cancelText: 'area_cancel',
            isDestructive: true,
          ) ??
          false;
      if (!shouldDelete) return;
    }

    final group = ref.read(moderatorProvider).currentGroup;
    if (group == null) return;

    final ok = await ref
        .read(suggestedAreaProvider.notifier)
        .deleteArea(group.id, area.id);
    if (!mounted) return;
    if (ok) {
      StandardSnackBar.showSuccess(context, 'area_deleted'.tr());
    }
  }

  void _openAreaPicker(ModeratorGroup group, String areaType) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AreaPickerScreen(
          groupId: group.id,
          areaType: areaType,
          initialCenter: _myLocation,
        ),
      ),
    );
  }

  // ── Map Controls ──────────────────────────────────────────────────────────

  /// Recenter button — positioned above the bottom sheet at any snap height.
  Widget _buildMapControls() {
    final hasLocation = _myLocation != null;
    return ValueListenableBuilder<double>(
      valueListenable: _sheetExtent,
      builder: (context, extent, child) {
        // Calculate padding based on screen height and sheet extent
        // extent is a fraction of the screen (e.g., 0.1 to 0.72)
        final screenHeight = MediaQuery.of(context).size.height;
        final bottomPadding = (screenHeight * extent) + 16.h;

        return Positioned(
          bottom: bottomPadding,
          right: 16.w,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Recenter pill ────────────────────────────────────────────────
              GestureDetector(
                onTap: () {
                  if (_myLocation != null) {
                    _mapController.move(
                      _myLocation!,
                      AppMapTiles.clampMapZoom(16),
                    );
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: EdgeInsets.symmetric(
                    horizontal: 14.w,
                    vertical: 10.h,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(24.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.35 : 0.12,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Live location indicator dot
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: 8.w,
                        height: 8.w,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasLocation
                              ? const Color(0xFF22C55E) // green = GPS locked
                              : const Color(
                                  0xFFF59E0B,
                                ), // amber = waiting for GPS
                          boxShadow: hasLocation
                              ? [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF22C55E,
                                    ).withValues(alpha: 0.5),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : [],
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Icon(
                        Symbols.my_location,
                        size: 18.w,
                        color: hasLocation
                            ? AppColors.primary
                            : (isDark
                                  ? Colors.white54
                                  : AppColors.textMutedLight),
                      ),
                      SizedBox(width: 6.w),
                      Text(
                        'my_location'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 12.sp,
                          color: hasLocation
                              ? (isDark ? Colors.white : AppColors.textDark)
                              : (isDark
                                    ? Colors.white54
                                    : AppColors.textMutedLight),
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
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final group = ref
        .watch(moderatorProvider)
        .groups
        .cast<ModeratorGroup?>()
        .firstWhere((g) => g?.id == widget.groupId, orElse: () => null);

    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: Text('dashboard_my_groups'.tr())),
        body: Center(child: Text('group_not_found'.tr())),
      );
    }

    final locatedPilgrims = group.pilgrims.where((p) => p.hasLocation).toList();
    final filtered = _getFiltered(group);
    final areaState = ref.watch(suggestedAreaProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          // ── Map (full screen) ─────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation ?? AppMapTiles.fallbackMapCenter,
              initialZoom: AppMapTiles.clampMapZoom(14),
              minZoom: AppMapTiles.mapMinZoom,
              maxZoom: AppMapTiles.mapMaxZoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              ...AppMapTiles.baseLayers(isDark: isDark),
              AppMapMarkerCluster.layer(
                markers: [
                  ...PilgrimMarkerLayout.pointsForMarkers(locatedPilgrims).map((
                    item,
                  ) {
                    final selected = _focusedPilgrimId == item.pilgrim.id;
                    final sz = PilgrimMapMarker.mapMarkerSize(
                      context,
                      isSelected: selected,
                    );
                    return Marker(
                      point: item.point,
                      width: sz.width,
                      height: sz.height,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => _focusPilgrim(item.pilgrim),
                        child: Padding(
                          padding: PilgrimMapMarker.mapMarkerPadding(),
                          child: PilgrimMapMarker(
                            pilgrim: item.pilgrim,
                            isSelected: selected,
                            isSOS: item.pilgrim.hasSOS,
                          ),
                        ),
                      ),
                    );
                  }),
                  for (var area in areaState.areas)
                    Marker(
                      point: LatLng(area.latitude, area.longitude),
                      width: 100.w,
                      height: 82.h,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => _showAreaList(group, areaState),
                        child: AreaMapMarker(area: area),
                      ),
                    ),
                ],
              ),
              if (_myLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _myLocation!,
                      width: 20.w,
                      height: 20.w,
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ── Top overlay bar ───────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: CircleButton(
                        icon: Symbols.arrow_back,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.w,
                        vertical: 10.h,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surfaceDark : Colors.white,
                        borderRadius: BorderRadius.circular(14.r),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.3 : 0.08,
                            ),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 30.w,
                            height: 30.w,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Symbols.group,
                              color: AppColors.primary,
                              size: 16.w,
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                group.groupName,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.sp,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textDark,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${group.onlineCount}/${group.totalPilgrims} ${'dashboard_stat_online'.tr()}',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 11.sp,
                                  color: AppColors.textMutedLight,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Map Controls ──────────────────────────────────────────────────
          _buildMapControls(),

          // ── Top-right 3-dot menu ──────────────────────────────────────────
          Positioned(
            top: 12.h,
            right: 14.w,
            child: SafeArea(
              child: SizedBox(
                width: 40.w,
                height: 40.w,
                child: PopupMenuButton<String>(
                  tooltip: '',
                  padding: EdgeInsets.zero,
                  offset: AppPopupMenu.offsetBelowCircular40,
                  shape: AppPopupMenu.panelShape(),
                  constraints: AppPopupMenu.panelConstraints(),
                  color: AppPopupMenu.panelColor(isDark),
                  onSelected: (value) {
                    switch (value) {
                      case 'nav':
                        _toggleNavBeacon(group);
                      case 'manage':
                        _showManageSheet(group);
                      case 'areas':
                        _showAreaActions(group, areaState);
                      case 'leave':
                        _handleLeaveGroup(group);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'nav',
                      child: AppPopupMenu.actionRow(
                        icon: Symbols.navigation,
                        label: _navBeaconEnabled
                            ? 'group_menu_disable_beacon'.tr()
                            : 'group_menu_enable_beacon'.tr(),
                        isDark: isDark,
                        iconColor: _navBeaconEnabled
                            ? AppColors.primary
                            : (isDark
                                  ? Colors.white70
                                  : AppColors.textMutedLight),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'manage',
                      child: AppPopupMenu.actionRow(
                        icon: Symbols.settings,
                        label: 'group_menu_manage'.tr(),
                        isDark: isDark,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'areas',
                      child: AppPopupMenu.actionRow(
                        icon: Symbols.pin_drop,
                        label: 'group_menu_areas'.tr(),
                        isDark: isDark,
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'leave',
                      child: AppPopupMenu.actionRow(
                        icon: Symbols.exit_to_app,
                        label: 'group_leave_option'.tr(),
                        isDark: isDark,
                        destructive: true,
                      ),
                    ),
                  ],
                  child: Container(
                    width: 40.w,
                    height: 40.w,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.3 : 0.10,
                          ),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Symbols.more_vert,
                      size: 22.w,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                  ),
                ),
              ),
            ),
          ),

          Positioned.fill(
            child: NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                _sheetExtent.value = notification.extent;
                return false; // Let it bubble up if needed
              },
              child: DraggableScrollableSheet(
                controller: _dssController,
                expand: false,
                initialChildSize: 0.28,
                minChildSize: 0.1,
                maxChildSize: 0.72,
                snap: true,
                snapSizes: const [0.1, 0.28, 0.72],
                builder: (ctx, scrollController) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24.r),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.3 : 0.08,
                        ),
                        blurRadius: 16,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      // Drag handle
                      SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.only(top: 12.h, bottom: 8.h),
                            child: Container(
                              width: 36.w,
                              height: 4.h,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white24
                                    : const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(2.r),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Sheet header
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 10.h),
                          child: Row(
                            children: [
                              Text(
                                group.totalPilgrims == 0
                                    ? 'group_no_pilgrims'.tr()
                                    : '${group.totalPilgrims} Pilgrims',
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15.sp,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textDark,
                                ),
                              ),
                              const Spacer(),
                              // Chat button with label
                              GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => GroupMessagesScreen(
                                      groupId: group.id,
                                      groupName: group.groupName,
                                      currentUserId: widget.currentUserId,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 34.w,
                                      height: 34.w,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Symbols.chat_bubble,
                                        size: 16.w,
                                        color: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 6.w),
                                    Text(
                                      'group_menu_chat'.tr(),
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13.sp,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 8.w),
                              if (group.sosCount > 0)
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.w,
                                    vertical: 4.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF1F2),
                                    borderRadius: BorderRadius.circular(100.r),
                                    border: Border.all(
                                      color: const Color(0xFFFFE4E6),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Symbols.warning,
                                        size: 12.w,
                                        color: const Color(0xFFDC2626),
                                        fill: 1,
                                      ),
                                      SizedBox(width: 3.w),
                                      Text(
                                        '${group.sosCount} SOS',
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11.sp,
                                          color: const Color(0xFFDC2626),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      // Active Meetpoint Card (if exists)
                      if (areaState.activeMeetpoint != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.w),
                            child: ActiveMeetpointCard(
                              activeMp: areaState.activeMeetpoint!,
                              isDark: isDark,
                              onDelete: () =>
                                  _handleDeleteArea(areaState.activeMeetpoint!),
                              onTap: () {
                                _mapController.move(
                                  LatLng(
                                    areaState.activeMeetpoint!.latitude,
                                    areaState.activeMeetpoint!.longitude,
                                  ),
                                  AppMapTiles.clampMapZoom(17),
                                );
                                _dssController.animateTo(
                                  0.08,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                              },
                            ),
                          ),
                        ),
                      // Search bar
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 10.h),
                          child: Container(
                            height: 40.h,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.backgroundDark
                                  : const Color(0xFFF0F0F8),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: TextField(
                              controller: _searchController,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 13.sp,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.textDark,
                              ),
                              decoration: InputDecoration(
                                hintText: 'group_search_hint'.tr(),
                                hintStyle: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 13.sp,
                                  color: AppColors.textMutedLight,
                                ),
                                prefixIcon: Icon(
                                  Symbols.search,
                                  size: 18.w,
                                  color: AppColors.textMutedLight,
                                ),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(
                                          Symbols.close,
                                          size: 16.w,
                                          color: AppColors.textMutedLight,
                                        ),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 11.h,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Pilgrim tiles
                      if (filtered.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Text(
                              _searchQuery.isNotEmpty
                                  ? 'group_no_matches'.tr()
                                  : 'group_no_pilgrims'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                color: AppColors.textMutedLight,
                                fontSize: 13.sp,
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate((ctx, i) {
                              final p = filtered[i];
                              return Dismissible(
                                key: ValueKey(p.id),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (_) =>
                                    _confirmRemovePilgrim(group, p),
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: EdgeInsets.only(right: 20.w),
                                  margin: EdgeInsets.only(bottom: 8.h),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(16.r),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Symbols.person_remove,
                                        color: Colors.white,
                                        size: 22.w,
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        'group_remove_confirm'.tr(),
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10.sp,
                                          fontFamily: 'Lexend',
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                child: _PilgrimManageTile(
                                  pilgrim: p,
                                  isSelected: _focusedPilgrimId == p.id,
                                  onTap: () => _focusPilgrim(p),
                                  onNavigate: () => _navigateToPilgrim(p),
                                  onChat: () => _openPrivateChat(p),
                                  onCall: () => _showCallSheet(p),
                                  onRemove: () =>
                                      _confirmRemovePilgrim(group, p),
                                  onViewProfile: () => _showPilgrimProfile(p),
                                ),
                              );
                            }, childCount: filtered.length),
                          ),
                        ),
                    ],
                  ),
                ),
              ), // DraggableScrollableSheet
            ), // NotificationListener
          ), // Positioned.fill
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QR share bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _QrShareSheet extends StatefulWidget {
  final ModeratorGroup group;
  const _QrShareSheet({required this.group});

  @override
  State<_QrShareSheet> createState() => _QrShareSheetState();
}

class _QrShareSheetState extends State<_QrShareSheet> {
  Uint8List? _qrBytes;
  bool _loading = true;
  String? _error;
  bool _isSharing = false;
  final GlobalKey _posterKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadQr();
  }

  Future<void> _loadQr() async {
    try {
      final resp = await ApiService.dio.get('/groups/${widget.group.id}/qr');
      final qrCode = resp.data['qr_code'] as String?;
      if (qrCode != null) {
        final b64 = qrCode.contains(',') ? qrCode.split(',').last : qrCode;
        setState(() {
          _qrBytes = base64Decode(b64);
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'group_not_found'.tr();
        });
      }
    } on DioException catch (e) {
      setState(() {
        _loading = false;
        _error = ApiService.parseError(e);
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _sharePoster() async {
    if (_qrBytes == null) return;
    setState(() => _isSharing = true);
    try {
      final boundary =
          _posterKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Boundary not found');

      final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) throw Exception('Failed to encode image');
      final Uint8List pngBytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/invite_${widget.group.groupCode}.png');
      await file.writeAsBytes(pngBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Join ${widget.group.groupName}',
        text:
            'Join my Munawwara group!\n\nGroup: ${widget.group.groupName}\nCode: ${widget.group.groupCode}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('group_share_failed'.tr(args: ['$e']))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final creator = widget.group.moderators
        .where((m) => m.id == widget.group.createdBy)
        .toList();
    final String modName = creator.isNotEmpty
        ? creator.first.fullName
        : 'Moderator';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -10000,
          top: -10000,
          child: RepaintBoundary(
            key: _posterKey,
            child: _InvitePosterWidget(
              group: widget.group,
              moderatorName: modName,
              qrBytes: _qrBytes ?? Uint8List(0),
            ),
          ),
        ),
        Container(
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
              SizedBox(height: 20.h),
              Text(
                'group_scan_join'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 18.sp,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'group_scan_join_sub'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.sp,
                  color: AppColors.textMutedLight,
                ),
              ),
              SizedBox(height: 20.h),
              Container(
                width: 200.w,
                height: 200.w,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE8C97A), width: 2),
                  borderRadius: BorderRadius.circular(12.r),
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                ),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12.sp,
                            color: Colors.red,
                          ),
                        ),
                      )
                    : _qrBytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10.r),
                        child: Image.memory(_qrBytes!, fit: BoxFit.contain),
                      )
                    : const SizedBox.shrink(),
              ),
              SizedBox(height: 16.h),
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.backgroundDark
                      : const Color(0xFFF0F0F8),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: const Color(0xFFE8C97A).withValues(alpha: 0.5),
                  ),
                ),
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'group_code_label'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFB0924A),
                            letterSpacing: 1.2,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          widget.group.groupCode,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 22.sp,
                            letterSpacing: 4,
                            color: const Color(0xFFB0924A),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: widget.group.groupCode),
                        );
                        StandardSnackBar.showSuccess(
                          context,
                          'group_code_copied'.tr(),
                        );
                      },
                      child: Container(
                        width: 36.w,
                        height: 36.w,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8C97A).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Icon(
                          Symbols.content_copy,
                          size: 18.w,
                          color: const Color(0xFFB0924A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12.h),
              SizedBox(
                width: double.infinity,
                height: 50.h,
                child: OutlinedButton.icon(
                  onPressed: _isSharing || _qrBytes == null
                      ? null
                      : _sharePoster,
                  icon: _isSharing
                      ? SizedBox(
                          width: 18.w,
                          height: 18.w,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                      : Icon(
                          Symbols.share,
                          size: 18.w,
                          color: AppColors.primary,
                        ),
                  label: Text(
                    _isSharing ? 'Generating...' : 'group_share_invite'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                      color: AppColors.primary,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InvitePosterWidget extends StatelessWidget {
  final ModeratorGroup group;
  final String moderatorName;
  final Uint8List qrBytes;

  const _InvitePosterWidget({
    required this.group,
    required this.moderatorName,
    required this.qrBytes,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
      child: Container(
        width: 400.w,
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/static/logo.jpeg',
              width: 80.w,
              height: 80.w,
              fit: BoxFit.cover,
            ),
            SizedBox(height: 16.h),
            Text(
              group.groupName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 24.sp,
                color: AppColors.textDark,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Moderated by $moderatorName',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                color: AppColors.textMutedLight,
              ),
            ),
            SizedBox(height: 32.h),
            Text(
              'SCAN TO JOIN',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 18.sp,
                color: AppColors.textDark,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 16.h),
            if (qrBytes.isNotEmpty)
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE8C97A), width: 3),
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8.r),
                  child: Image.memory(qrBytes, width: 220.w, height: 220.w),
                ),
              ),
            SizedBox(height: 32.h),
            Text(
              'Or join using code:',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                color: AppColors.textMutedLight,
              ),
            ),
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0F8),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: const Color(0xFFE8C97A).withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                group.groupCode,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 28.sp,
                  letterSpacing: 6,
                  color: const Color(0xFFB0924A),
                ),
              ),
            ),
            SizedBox(height: 32.h),
            Text(
              'Download Munawwara Care to get started.',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 12.sp,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Moderator management bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ModeratorManageSheet extends ConsumerWidget {
  final ModeratorGroup group;
  final String currentUserId;
  final bool isCreator;

  const _ModeratorManageSheet({
    required this.group,
    required this.currentUserId,
    required this.isCreator,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liveGroup =
        ref
            .watch(moderatorProvider)
            .groups
            .cast<ModeratorGroup?>()
            .firstWhere((g) => g?.id == group.id, orElse: () => null) ??
        group;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 32.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'group_moderators'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 17.sp,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
          if (!isCreator) ...[
            SizedBox(height: 4.h),
            Text(
              'group_moderators_sub'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 11.sp,
                color: AppColors.textMutedLight,
              ),
            ),
          ],
          SizedBox(height: 12.h),
          ...liveGroup.moderators.map(
            (mod) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                radius: 20.r,
                backgroundColor: const Color(
                  0xFF6C63FF,
                ).withValues(alpha: 0.15),
                child: Text(
                  mod.initials,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 12.sp,
                    color: const Color(0xFF6C63FF),
                  ),
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      mod.fullName,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                  ),
                  if (mod.id == liveGroup.createdBy)
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.w,
                        vertical: 2.h,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8C97A).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                      child: Text(
                        'group_creator'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFB0924A),
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: mod.email != null
                  ? Text(
                      mod.email!,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 11.sp,
                        color: AppColors.textMutedLight,
                      ),
                    )
                  : null,
              trailing: (isCreator && mod.id != liveGroup.createdBy)
                  ? GestureDetector(
                      onTap: () async {
                        final (ok, err) = await ref
                            .read(moderatorProvider.notifier)
                            .removeModeratorFromGroup(liveGroup.id, mod.id);
                        if (context.mounted) {
                          if (ok) {
                            StandardSnackBar.showSuccess(
                              context,
                              '${mod.fullName} ${'group_remove_confirm'.tr().toLowerCase()}',
                            );
                          } else {
                            StandardSnackBar.showError(
                              context,
                              err ?? 'group_not_found'.tr(),
                            );
                          }
                        }
                      },
                      child: Container(
                        width: 34.w,
                        height: 34.w,
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Symbols.person_remove,
                          size: 16.w,
                          color: Colors.red,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
          if (isCreator) ...[
            SizedBox(height: 12.h),
            SizedBox(
              width: double.infinity,
              height: 50.h,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await _showInviteSheet(context, liveGroup);
                },
                icon: Icon(
                  Symbols.person_add,
                  size: 18.w,
                  color: const Color(0xFF6C63FF),
                ),
                label: Text(
                  'group_invite_mod'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 14.sp,
                    color: const Color(0xFF6C63FF),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF6C63FF), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showInviteSheet(
    BuildContext context,
    ModeratorGroup g,
  ) async {
    final snackContext = context;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) =>
          _ModeratorInviteSheet(group: g, snackContext: snackContext),
    );
  }
}

class _ModeratorInviteSheet extends ConsumerStatefulWidget {
  final ModeratorGroup group;
  final BuildContext snackContext;

  const _ModeratorInviteSheet({
    required this.group,
    required this.snackContext,
  });

  @override
  ConsumerState<_ModeratorInviteSheet> createState() =>
      _ModeratorInviteSheetState();
}

class _ModeratorInviteSheetState extends ConsumerState<_ModeratorInviteSheet> {
  late final TextEditingController _emailCtrl;
  _ModInviteStep _step = _ModInviteStep.qr;
  bool _loading = false;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20.w,
        20.h,
        20.w,
        MediaQuery.of(context).viewInsets.bottom + 32.h,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                margin: EdgeInsets.only(bottom: 20.h),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            if (_step == _ModInviteStep.qr) ...[
              Text(
                'group_invite_mod'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 16.sp,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
              SizedBox(height: 20.h),
              Center(
                child: Container(
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: widget.group.groupCode,
                    version: QrVersions.auto,
                    size: 180.w,
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'scan_to_join_mod'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13.sp,
                  color: isDark
                      ? AppColors.textMutedLight
                      : Colors.grey.shade600,
                ),
              ),
              SizedBox(height: 8.h),
              TextButton(
                onPressed: () => setState(() => _step = _ModInviteStep.code),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                child: Text(
                  'not_working_enter_code'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 14.sp,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _step = _ModInviteStep.email;
                  _fieldError = null;
                }),
                child: Text(
                  'tab_email'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 14.sp,
                    color: isDark
                        ? AppColors.textMutedLight
                        : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
            if (_step == _ModInviteStep.code) ...[
              Text(
                'share_this_code'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13.sp,
                  color: isDark
                      ? AppColors.textMutedLight
                      : Colors.grey.shade600,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20.h),
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Text(
                  widget.group.groupCode,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 28.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                    color: AppColors.primary,
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: widget.group.groupCode),
                  );
                  StandardSnackBar.showSuccess(
                    widget.snackContext,
                    'create_group_code_copied'.tr(),
                  );
                },
                icon: Icon(Symbols.content_copy, size: 18.w),
                label: Text('copy_code'.tr()),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  textStyle: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _step = _ModInviteStep.qr),
                child: Text(
                  'QR Code'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 14.sp,
                    color: AppColors.primary,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _step = _ModInviteStep.email;
                  _fieldError = null;
                }),
                child: Text(
                  'tab_email'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 14.sp,
                    color: isDark
                        ? AppColors.textMutedLight
                        : Colors.grey.shade700,
                  ),
                ),
              ),
            ],
            if (_step == _ModInviteStep.email) ...[
              Text(
                'group_invite_mod_desc'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13.sp,
                  color: isDark
                      ? AppColors.textMutedLight
                      : Colors.grey.shade600,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20.h),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'group_invite_email_hint'.tr(),
                  errorText: _fieldError,
                  filled: true,
                  fillColor: isDark
                      ? AppColors.backgroundDark
                      : Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              SizedBox(
                width: double.infinity,
                height: 50.h,
                child: ElevatedButton(
                  onPressed: _loading
                      ? null
                      : () async {
                          final raw = _emailCtrl.text.trim();
                          final emails = raw
                              .split(RegExp(r'[,\n; ]+'))
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toSet()
                              .toList();
                          final hasInvalid =
                              emails.isEmpty ||
                              emails.any((e) => !e.contains('@'));

                          if (hasInvalid) {
                            setState(() => _fieldError = 'email_invalid'.tr());
                            return;
                          }
                          setState(() {
                            _loading = true;
                            _fieldError = null;
                          });
                          final (ok, err) = await ref
                              .read(moderatorProvider.notifier)
                              .inviteModerators(widget.group.id, emails);
                          if (!mounted) return;
                          if (ok) {
                            Navigator.pop(context);
                            StandardSnackBar.showSuccess(
                              widget.snackContext,
                              'group_invite_success'.tr(),
                            );
                          } else {
                            setState(() {
                              _loading = false;
                              _fieldError = err == 'email_invalid'
                                  ? 'email_invalid'.tr()
                                  : (err ?? 'error_generic'.tr());
                            });
                          }
                        },
                  child: _loading
                      ? SizedBox(
                          width: 20.w,
                          height: 20.w,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text('invite_send'.tr()),
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _step = _ModInviteStep.qr;
                  _fieldError = null;
                }),
                child: Text(
                  'QR Code'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 14.sp,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim tile in the bottom sheet (focus + navigate + remove)
// ─────────────────────────────────────────────────────────────────────────────

class _PilgrimManageTile extends StatelessWidget {
  final PilgrimInGroup pilgrim;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onNavigate;
  final VoidCallback onChat;
  final VoidCallback? onCall;
  final VoidCallback? onRemove;
  final VoidCallback? onViewProfile;

  const _PilgrimManageTile({
    required this.pilgrim,
    required this.isSelected,
    required this.onTap,
    required this.onNavigate,
    required this.onChat,
    this.onCall,
    this.onRemove,
    this.onViewProfile,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final battColor = switch (pilgrim.batteryStatus) {
      BatteryStatus.good => const Color(0xFF16A34A),
      BatteryStatus.medium => const Color(0xFFF59E0B),
      BatteryStatus.low => const Color(0xFFDC2626),
      BatteryStatus.unknown => AppColors.textMutedLight,
    };

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.08)
              : pilgrim.hasSOS
              ? (isDark ? const Color(0xFF2D1515) : const Color(0xFFFFF1F2))
              : (isDark ? AppColors.backgroundDark : const Color(0xFFF0F0F8)),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.4)
                : pilgrim.hasSOS
                ? (isDark ? const Color(0xFF5C2020) : const Color(0xFFFFE4E6))
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            // Avatar + online/location dot (tappable → profile sheet)
            GestureDetector(
              onTap: onViewProfile,
              child: Stack(
                children: [
                  Container(
                    width: 40.w,
                    height: 40.w,
                    padding: pilgrim.hasSOS
                        ? EdgeInsets.zero
                        : EdgeInsets.all(1.5.w),
                    decoration: BoxDecoration(
                      color: pilgrim.hasSOS
                          ? const Color(0xFFDC2626)
                          : AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: pilgrim.hasSOS
                        ? Center(
                            child: Icon(
                              Symbols.warning,
                              color: Colors.white,
                              size: 18.w,
                              fill: 1,
                            ),
                          )
                        : PilgrimGenderAvatar(
                            gender: pilgrim.gender,
                            size: 37.w,
                          ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 10.w,
                      height: 10.w,
                      decoration: BoxDecoration(
                        color: pilgrim.isOnline
                            ? const Color(0xFF16A34A)
                            : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? AppColors.surfaceDark : Colors.white,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 10.w),
            // Name + last seen
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pilgrim.fullName,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 13.sp,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (pilgrim.lastSeenText.isNotEmpty)
                    Text(
                      pilgrim.lastSeenText,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 11.sp,
                        color: AppColors.textMutedLight,
                      ),
                    ),
                ],
              ),
            ),
            // Battery
            if (pilgrim.batteryPercent != null) ...[
              SizedBox(width: 6.w),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.battery_5_bar, size: 12.w, color: battColor),
                  SizedBox(width: 2.w),
                  Text(
                    '${pilgrim.batteryPercent}%',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 10.sp,
                      color: battColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            SizedBox(width: 4.w),
            // 3-dot options menu
            PopupMenuButton<String>(
              tooltip: '',
              padding: EdgeInsets.zero,
              icon: Icon(
                Symbols.more_vert,
                size: 18.w,
                color: isDark ? AppColors.primary : AppColors.textMutedLight,
              ),
              iconSize: 18.w,
              offset: AppPopupMenu.offsetRowTrailingMore,
              shape: AppPopupMenu.panelShape(),
              constraints: AppPopupMenu.panelConstraints(),
              color: AppPopupMenu.panelColor(isDark),
              onSelected: (value) {
                switch (value) {
                  case 'profile':
                    onViewProfile?.call();
                  case 'navigate':
                    onNavigate();
                  case 'chat':
                    onChat();
                  case 'call':
                    onCall?.call();
                  case 'remove':
                    onRemove?.call();
                }
              },
              itemBuilder: (_) => [
                if (onViewProfile != null)
                  PopupMenuItem(
                    value: 'profile',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.person,
                      label: 'manage_view_full_profile'.tr(),
                      isDark: isDark,
                      iconColor: AppColors.primary,
                    ),
                  ),
                PopupMenuItem(
                  value: 'navigate',
                  child: AppPopupMenu.actionRow(
                    icon: Symbols.near_me,
                    label: 'area_navigate'.tr(),
                    isDark: isDark,
                    iconColor: AppColors.primary,
                  ),
                ),
                PopupMenuItem(
                  value: 'chat',
                  child: AppPopupMenu.actionRow(
                    icon: Symbols.chat,
                    label: 'tab_chat'.tr(),
                    isDark: isDark,
                    iconColor: AppColors.primary,
                  ),
                ),
                if (onCall != null)
                  PopupMenuItem(
                    value: 'call',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.call,
                      label: 'group_call_prefix'.tr(),
                      isDark: isDark,
                      iconColor: const Color(0xFF16A34A),
                    ),
                  ),
                if (onRemove != null)
                  PopupMenuItem(
                    value: 'remove',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.person_remove,
                      label: 'group_remove_confirm'.tr(),
                      isDark: isDark,
                      destructive: true,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
