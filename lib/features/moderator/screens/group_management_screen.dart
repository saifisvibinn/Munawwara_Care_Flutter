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
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/api_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/moderator_provider.dart';
import '../../auth/providers/auth_provider.dart';
import '../../calling/providers/call_provider.dart';
import '../../calling/screens/voice_call_screen.dart';
import '../../shared/providers/suggested_area_provider.dart';
import '../../shared/models/suggested_area_model.dart';
import 'group_messages_screen.dart';
import 'individual_messages_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Beacon state: static map survives hot-reload (widget recreation).
// SharedPreferences is the fallback for full app restarts.
// ─────────────────────────────────────────────────────────────────────────────
final Map<String, bool> _navBeaconCache = {};

// ─────────────────────────────────────────────────────────────────────────────
// Group Management Screen  (map-first + manage pilgrims/moderators)
// ─────────────────────────────────────────────────────────────────────────────

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
  String _searchQuery = '';

  bool get isDark => Theme.of(context).brightness == Brightness.dark;

  LatLng? _myLocation;
  StreamSubscription<Position>? _locationSub;
  String? _focusedPilgrimId;
  bool _navBeaconEnabled = false;

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
    });
    // Real-time area sync
    SocketService.on('area_added', (data) {
      if (!mounted) return;
      ref
          .read(suggestedAreaProvider.notifier)
          .appendArea(data as Map<String, dynamic>);
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
      final map = data as Map<String, dynamic>;
      final pilgrimId = map['pilgrimId'] as String?;
      final lat = map['latitude'] as double?;
      final lng = map['longitude'] as double?;
      final battery = map['battery_percent'] as int?;
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
  }

  @override
  void dispose() {
    _mapController.dispose();
    _dssController.dispose();
    _searchController.dispose();
    _locationSub?.cancel();
    SocketService.off('area_added');
    SocketService.off('area_deleted');
    SocketService.off('location_update');
    SocketService.off('status_update');
    SocketService.emit('leave_group', widget.groupId);
    super.dispose();
  }

  // ── Location ──────────────────────────────────────────────────────────────

  Future<void> _initLocation() async {
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted || !mounted) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      _mapController.move(_myLocation!, 15);
    } catch (_) {}
    _locationSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 30,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.firstName} has no location data yet')),
      );
      return;
    }
    setState(() => _focusedPilgrimId = p.id);
    _mapController.move(LatLng(p.lat!, p.lng!), 17);
    _dssController.animateTo(
      0.28,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _navigateToPilgrim(PilgrimInGroup p) async {
    if (!p.hasLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${p.firstName} ${'group_not_found'.tr()}')),
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
    // Re-emit so pilgrims see beacon immediately
    final auth = ref.read(authProvider);
    SocketService.emit('mod_nav_beacon', {
      'groupId': widget.groupId,
      'enabled': true,
      'lat': _myLocation?.latitude,
      'lng': _myLocation?.longitude,
      'moderatorId': auth.userId,
      'moderatorName': auth.fullName ?? 'Moderator',
    });
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
    SocketService.emit('mod_nav_beacon', {
      'groupId': group.id,
      'enabled': newVal,
      'lat': _myLocation?.latitude,
      'lng': _myLocation?.longitude,
      'moderatorId': auth.userId,
      'moderatorName': auth.fullName ?? 'Moderator',
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newVal ? 'nav_beacon_on'.tr() : 'nav_beacon_off'.tr()),
        backgroundColor: newVal ? AppColors.primary : Colors.grey.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ── Add Pilgrim ───────────────────────────────────────────────────────────

  Future<void> _showAddPilgrimOptions(ModeratorGroup group) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AddPilgrimChoiceSheet(
        group: group,
        onManual: () async {
          Navigator.pop(ctx);
          await _showAddPilgrimManual(group);
        },
        onQr: () async {
          Navigator.pop(ctx);
          await _showQrSheet(group);
        },
      ),
    );
  }

  Future<void> _showAddPilgrimManual(ModeratorGroup group) async {
    final ctrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          bool loading = false;
          String? fieldError;

          Future<void> submit() async {
            final val = ctrl.text.trim();
            if (val.isEmpty) {
              setSheetState(() => fieldError = 'group_add_enter_id'.tr());
              return;
            }
            setSheetState(() {
              loading = true;
              fieldError = null;
            });
            final (ok, err) = await ref
                .read(moderatorProvider.notifier)
                .addPilgrimToGroup(group.id, val);
            if (ctx.mounted) {
              if (ok) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('group_add_success'.tr())),
                );
              } else {
                setSheetState(() {
                  loading = false;
                  fieldError = err ?? 'group_not_found'.tr();
                });
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
              ),
              padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 28.h),
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
                  Row(
                    children: [
                      Container(
                        width: 40.w,
                        height: 40.w,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Symbols.person_add,
                          color: AppColors.primary,
                          size: 20.w,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'group_add_pilgrim'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w700,
                              fontSize: 18.sp,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                          ),
                          Text(
                            'group_add_identifier_hint'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 12.sp,
                              color: AppColors.textMutedLight,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 20.h),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                    decoration: InputDecoration(
                      hintText: 'group_add_enter_id'.tr(),
                      hintStyle: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13.sp,
                        color: AppColors.textMutedLight,
                      ),
                      errorText: fieldError,
                      prefixIcon: Icon(
                        Symbols.search,
                        size: 20.w,
                        color: AppColors.textMutedLight,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppColors.backgroundDark
                          : const Color(0xFFF0F0F8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 14.h,
                        horizontal: 16.w,
                      ),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  SizedBox(height: 16.h),
                  SizedBox(
                    width: double.infinity,
                    height: 52.h,
                    child: ElevatedButton(
                      onPressed: loading ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                        elevation: 0,
                      ),
                      child: loading
                          ? SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'group_add_to_group'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                                fontSize: 15.sp,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showQrSheet(ModeratorGroup group) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _QrShareSheet(group: group),
    );
  }

  // ── Remove pilgrim ────────────────────────────────────────────────────────

  Future<bool> _confirmRemovePilgrim(
    ModeratorGroup group,
    PilgrimInGroup pilgrim,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(
          'group_remove_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 17.sp,
          ),
        ),
        content: Text(
          '${'group_remove_body'.tr()} ${pilgrim.fullName}?',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14.sp,
            color: AppColors.textMutedLight,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'group_remove_cancel'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                color: AppColors.textMutedLight,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'group_remove_confirm'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final (ok, err) = await ref
          .read(moderatorProvider.notifier)
          .removePilgrimFromGroup(group.id, pilgrim.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? '${pilgrim.firstName} ${'group_remove_confirm'.tr().toLowerCase()}'
                  : err ?? 'group_not_found'.tr(),
            ),
            backgroundColor: ok ? null : Colors.red,
          ),
        );
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
      builder: (_) => Container(
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
                        Navigator.pop(context);
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
                            color: AppColors.primary.withOpacity(0.2),
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
                    onTap: () {
                      Navigator.pop(context);
                      // Initiate WebRTC call
                      ref
                          .read(callProvider.notifier)
                          .startCall(
                            remoteUserId: pilgrim.id,
                            remoteUserName: pilgrim.fullName,
                          );
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const VoiceCallScreen(),
                        ),
                      );
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        vertical: 18.h,
                        horizontal: 12.w,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8C97A).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(
                          color: const Color(0xFFE8C97A).withOpacity(0.4),
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
                            'group_internet_call'.tr(),
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Pilgrim profile sheet ──────────────────────────────────────────────────

  void _showPilgrimProfile(PilgrimInGroup pilgrim) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final battColor = switch (pilgrim.batteryStatus) {
          BatteryStatus.good => const Color(0xFF16A34A),
          BatteryStatus.medium => const Color(0xFFF59E0B),
          BatteryStatus.low => const Color(0xFFDC2626),
          BatteryStatus.unknown => AppColors.textMutedLight,
        };
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
              SizedBox(height: 20.h),
              // Avatar
              Container(
                width: 72.w,
                height: 72.w,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    pilgrim.initials,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 26.sp,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12.h),
              Text(
                pilgrim.fullName,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 20.sp,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
              SizedBox(height: 4.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8.w,
                    height: 8.w,
                    decoration: BoxDecoration(
                      color: pilgrim.isOnline
                          ? const Color(0xFF16A34A)
                          : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Text(
                    pilgrim.isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      color: pilgrim.isOnline
                          ? const Color(0xFF16A34A)
                          : AppColors.textMutedLight,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Container(
                    width: 8.w,
                    height: 8.w,
                    decoration: BoxDecoration(
                      color: pilgrim.hasLocation
                          ? AppColors.primary
                          : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Text(
                    pilgrim.hasLocation ? 'Location sharing ON' : 'No location',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      color: pilgrim.hasLocation
                          ? AppColors.primary
                          : AppColors.textMutedLight,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              Divider(color: Colors.grey.shade200),
              SizedBox(height: 12.h),
              // Info rows
              if (pilgrim.nationalId != null)
                _ProfileRow(
                  icon: Symbols.badge,
                  label: 'National ID',
                  value: pilgrim.nationalId!,
                ),
              if (pilgrim.phoneNumber != null)
                _ProfileRow(
                  icon: Symbols.phone,
                  label: 'Phone',
                  value: pilgrim.phoneNumber!,
                ),
              if (pilgrim.batteryPercent != null)
                _ProfileRow(
                  icon: Symbols.battery_5_bar,
                  label: 'Battery',
                  value: '${pilgrim.batteryPercent}%',
                  valueColor: battColor,
                ),
              if (pilgrim.lastSeenText.isNotEmpty)
                _ProfileRow(
                  icon: Symbols.schedule,
                  label: 'Last seen',
                  value: pilgrim.lastSeenText,
                ),
              SizedBox(height: 20.h),
              // Message Button
              SizedBox(
                width: double.infinity,
                height: 48.h,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => IndividualMessagesScreen(
                          groupId: widget.groupId,
                          groupName: 'group_name'
                              .tr(), // Provide actual group name if available remotely, but this works
                          recipientId: pilgrim.id,
                          recipientName: pilgrim.fullName,
                          currentUserId: widget.currentUserId,
                        ),
                      ),
                    );
                  },
                  icon: Icon(Symbols.chat, color: Colors.white, size: 20.w),
                  label: Text(
                    'Message',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              SizedBox(height: 12.h),
            ],
          ),
        );
      },
    );
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
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.3),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('area_meetpoint_exists'.tr()),
                            backgroundColor: Colors.orange.shade700,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
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
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(color: const Color(0xFFFECACA)),
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
                      Icon(Symbols.list, size: 18.w, color: AppColors.textDark),
                      SizedBox(width: 8.w),
                      Text(
                        'area_view_all'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 14.sp,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8.w,
                          vertical: 2.h,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.15),
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
                                    ? const Color(0xFFFEF2F2)
                                    : isDark
                                    ? AppColors.backgroundDark
                                    : const Color(0xFFF0F0F8),
                                borderRadius: BorderRadius.circular(14.r),
                                border: Border.all(
                                  color: area.isMeetpoint
                                      ? const Color(0xFFFECACA)
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
                                                      ).withOpacity(0.15)
                                                    : AppColors.primary
                                                          .withOpacity(0.15),
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
                                        17,
                                      );
                                    },
                                    child: Container(
                                      width: 32.w,
                                      height: 32.w,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(
                                          0.1,
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
                                  // Delete
                                  GestureDetector(
                                    onTap: () async {
                                      final ok = await ref
                                          .read(suggestedAreaProvider.notifier)
                                          .deleteArea(group.id, area.id);
                                      if (ok && mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text('area_deleted'.tr()),
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12.r),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: Container(
                                      width: 32.w,
                                      height: 32.w,
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.1),
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

  void _openAreaPicker(ModeratorGroup group, String areaType) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AreaPickerScreen(
          groupId: group.id,
          areaType: areaType,
          initialCenter: _myLocation,
        ),
      ),
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

    return Scaffold(
      body: Stack(
        children: [
          // ── Map (full screen) ─────────────────────────────────────────────
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _myLocation ?? const LatLng(21.3891, 39.8579),
              initialZoom: 14,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.munawwaracare.app',
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
                              color: AppColors.primary.withOpacity(0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (var p in locatedPilgrims)
                    Marker(
                      point: LatLng(p.lat!, p.lng!),
                      width: 64.w,
                      height: 72.h,
                      child: GestureDetector(
                        onTap: () => _focusPilgrim(p),
                        child: _PilgrimMapMarker(
                          pilgrim: p,
                          isSelected: _focusedPilgrimId == p.id,
                        ),
                      ),
                    ),
                ],
              ),
              // Suggested area & meetpoint markers
              MarkerLayer(
                markers: [
                  for (var area in areaState.areas)
                    Marker(
                      point: LatLng(area.latitude, area.longitude),
                      width: 80.w,
                      height: 82.h,
                      child: _AreaMapMarker(area: area),
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
                      child: _CircleButton(
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
                            color: Colors.black.withOpacity(
                              isDark ? 0.3 : 0.08,
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
                              color: AppColors.primary.withOpacity(0.15),
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
                  offset: const Offset(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  constraints: BoxConstraints(minWidth: 200.w),
                  color: isDark ? AppColors.surfaceDark : null,
                  onSelected: (value) {
                    switch (value) {
                      case 'add':
                        _showAddPilgrimOptions(group);
                      case 'nav':
                        _toggleNavBeacon(group);
                      case 'manage':
                        _showManageSheet(group);
                      case 'areas':
                        _showAreaActions(group, areaState);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'add',
                      child: Row(
                        children: [
                          Icon(
                            Symbols.person_add,
                            size: 18.w,
                            color: AppColors.primary,
                          ),
                          SizedBox(width: 12.w),
                          Text(
                            'group_add_pilgrim'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14.sp,
                              color: isDark ? Colors.white : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'nav',
                      child: Row(
                        children: [
                          Icon(
                            Symbols.navigation,
                            size: 18.w,
                            color: _navBeaconEnabled
                                ? AppColors.primary
                                : (isDark
                                      ? Colors.white70
                                      : AppColors.textMutedLight),
                          ),
                          SizedBox(width: 12.w),
                          Text(
                            _navBeaconEnabled
                                ? 'Disable Beacon'
                                : 'Enable Beacon',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14.sp,
                              color: isDark ? Colors.white : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'manage',
                      child: Row(
                        children: [
                          Icon(
                            Symbols.settings,
                            size: 18.w,
                            color: isDark ? Colors.white70 : AppColors.textDark,
                          ),
                          SizedBox(width: 12.w),
                          Text(
                            'Manage Group',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14.sp,
                              color: isDark ? Colors.white : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'areas',
                      child: Row(
                        children: [
                          Icon(
                            Symbols.pin_drop,
                            size: 18.w,
                            color: isDark ? Colors.white70 : AppColors.textDark,
                          ),
                          SizedBox(width: 12.w),
                          Text(
                            'Suggested Areas',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14.sp,
                              color: isDark ? Colors.white : null,
                            ),
                          ),
                        ],
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
                          color: Colors.black.withOpacity(isDark ? 0.3 : 0.10),
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

          // ── Pilgrim list sheet ────────────────────────────────────────────
          Positioned.fill(
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
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
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
                                    'Chat',
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
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search pilgrims...',
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
                                onCall: () => _showCallSheet(p),
                                onRemove: () => _confirmRemovePilgrim(group, p),
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
          ), // Positioned(bottom: 0)
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Pilgrim choice sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AddPilgrimChoiceSheet extends StatelessWidget {
  final ModeratorGroup group;
  final VoidCallback onManual;
  final VoidCallback onQr;

  const _AddPilgrimChoiceSheet({
    required this.group,
    required this.onManual,
    required this.onQr,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
          SizedBox(height: 20.h),
          Text(
            'group_add_pilgrim_how'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 18.sp,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'group_add_pilgrim'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              color: AppColors.textMutedLight,
            ),
          ),
          SizedBox(height: 24.h),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onManual,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      vertical: 20.h,
                      horizontal: 12.w,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.3),
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
                            Symbols.person_search,
                            color: Colors.white,
                            size: 26.w,
                          ),
                        ),
                        SizedBox(height: 12.h),
                        Text(
                          'group_add_manually'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 14.sp,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'group_add_manually_sub'.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 11.sp,
                            color: AppColors.textMutedLight,
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
                  onTap: onQr,
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      vertical: 20.h,
                      horizontal: 12.w,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8C97A).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(
                        color: const Color(0xFFE8C97A).withOpacity(0.4),
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
                            Symbols.qr_code,
                            color: Colors.white,
                            size: 26.w,
                          ),
                        ),
                        SizedBox(height: 12.h),
                        Text(
                          'group_share_qr'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 14.sp,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'group_scan_join_sub'.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 11.sp,
                            color: AppColors.textMutedLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to share: $e')));
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
                    color: const Color(0xFFE8C97A).withOpacity(0.5),
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
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('group_code_copied'.tr())),
                        );
                      },
                      child: Container(
                        width: 36.w,
                        height: 36.w,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8C97A).withOpacity(0.2),
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
                  color: const Color(0xFFE8C97A).withOpacity(0.5),
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
              'Only the group creator can add or remove moderators.'.tr(),
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
                backgroundColor: const Color(0xFF6C63FF).withOpacity(0.15),
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
                        color: const Color(0xFFE8C97A).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20.r),
                      ),
                      child: Text(
                        'Creator',
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? '${mod.fullName} ${'group_remove_confirm'.tr().toLowerCase()}'
                                    : err ?? 'group_not_found'.tr(),
                              ),
                              backgroundColor: ok ? null : Colors.red,
                            ),
                          );
                        }
                      },
                      child: Container(
                        width: 34.w,
                        height: 34.w,
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
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
                  await _showInviteSheet(context, ref, liveGroup);
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
    WidgetRef ref,
    ModeratorGroup g,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          bool loading = false;
          String? fieldError;

          Future<void> submit() async {
            final val = ctrl.text.trim();
            if (val.isEmpty || !val.contains('@')) {
              setSheetState(() => fieldError = 'group_invite_send'.tr());
              return;
            }
            setSheetState(() {
              loading = true;
              fieldError = null;
            });
            final (ok, err) = await ref
                .read(moderatorProvider.notifier)
                .inviteModerator(g.id, val);
            if (ctx.mounted) {
              if (ok) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('group_invite_send'.tr())),
                );
              } else {
                setSheetState(() {
                  loading = false;
                  fieldError = err ?? 'group_not_found'.tr();
                });
              }
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
              ),
              padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 28.h),
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
                    'group_invite_mod'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 18.sp,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'group_invite_mod_sub'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      color: AppColors.textMutedLight,
                    ),
                  ),
                  SizedBox(height: 20.h),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                    decoration: InputDecoration(
                      hintText: 'group_invite_mod'.tr().toLowerCase(),
                      hintStyle: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13.sp,
                        color: AppColors.textMutedLight,
                      ),
                      errorText: fieldError,
                      prefixIcon: Icon(
                        Symbols.email,
                        size: 20.w,
                        color: AppColors.textMutedLight,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? AppColors.backgroundDark
                          : const Color(0xFFF0F0F8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: const BorderSide(
                          color: Color(0xFF6C63FF),
                          width: 1.5,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 14.h,
                        horizontal: 16.w,
                      ),
                    ),
                    onSubmitted: (_) => submit(),
                  ),
                  SizedBox(height: 16.h),
                  SizedBox(
                    width: double.infinity,
                    height: 52.h,
                    child: ElevatedButton(
                      onPressed: loading ? null : submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                        elevation: 0,
                      ),
                      child: loading
                          ? SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              'group_invite_send'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w600,
                                fontSize: 15.sp,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
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
  final VoidCallback? onCall;
  final VoidCallback? onRemove;
  final VoidCallback? onViewProfile;

  const _PilgrimManageTile({
    required this.pilgrim,
    required this.isSelected,
    required this.onTap,
    required this.onNavigate,
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
              ? AppColors.primary.withOpacity(0.08)
              : pilgrim.hasSOS
              ? (isDark ? const Color(0xFF2D1515) : const Color(0xFFFFF1F2))
              : (isDark ? AppColors.backgroundDark : const Color(0xFFF0F0F8)),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withOpacity(0.4)
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
                    decoration: BoxDecoration(
                      color: pilgrim.hasSOS
                          ? const Color(0xFFDC2626)
                          : AppColors.primary.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: pilgrim.hasSOS
                          ? Icon(
                              Symbols.warning,
                              color: Colors.white,
                              size: 18.w,
                              fill: 1,
                            )
                          : Text(
                              pilgrim.initials,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w700,
                                fontSize: 13.sp,
                                color: AppColors.primaryDark,
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 10.w,
                      height: 10.w,
                      decoration: BoxDecoration(
                        color: pilgrim.hasLocation
                            ? AppColors.primary
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
                color: AppColors.textMutedLight,
              ),
              iconSize: 18.w,
              offset: const Offset(-20, 36),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.r),
              ),
              constraints: BoxConstraints(minWidth: 180.w),
              onSelected: (value) {
                switch (value) {
                  case 'profile':
                    onViewProfile?.call();
                  case 'navigate':
                    onNavigate();
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
                    child: Row(
                      children: [
                        Icon(
                          Symbols.person,
                          size: 16.w,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 10.w),
                        Text(
                          'View Profile',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'navigate',
                  child: Row(
                    children: [
                      Icon(
                        Symbols.near_me,
                        size: 16.w,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 10.w),
                      Text(
                        'Navigate',
                        style: TextStyle(fontFamily: 'Lexend', fontSize: 13.sp),
                      ),
                    ],
                  ),
                ),
                if (onCall != null)
                  PopupMenuItem(
                    value: 'call',
                    child: Row(
                      children: [
                        Icon(
                          Symbols.call,
                          size: 16.w,
                          color: const Color(0xFF16A34A),
                        ),
                        SizedBox(width: 10.w),
                        Text(
                          'Call',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (onRemove != null)
                  PopupMenuItem(
                    value: 'remove',
                    child: Row(
                      children: [
                        Icon(
                          Symbols.person_remove,
                          size: 16.w,
                          color: Colors.red,
                        ),
                        SizedBox(width: 10.w),
                        Text(
                          'Remove',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13.sp,
                            color: Colors.red,
                          ),
                        ),
                      ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim map marker
// ─────────────────────────────────────────────────────────────────────────────

class _PilgrimMapMarker extends StatelessWidget {
  final PilgrimInGroup pilgrim;
  final bool isSelected;

  const _PilgrimMapMarker({required this.pilgrim, this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    final isSOS = pilgrim.hasSOS;
    final color = isSOS ? const Color(0xFFDC2626) : AppColors.primaryDark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isSelected ? 42.w : 36.w,
          height: isSelected ? 42.w : 36.w,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.amber : Colors.white,
              width: isSelected ? 3 : 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(isSelected ? 0.7 : 0.45),
                blurRadius: isSelected ? 12 : 8,
                spreadRadius: isSelected ? 4 : 2,
              ),
            ],
          ),
          child: isSOS
              ? Icon(Symbols.warning, color: Colors.white, size: 18.w, fill: 1)
              : Center(
                  child: Text(
                    pilgrim.initials,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: isSelected ? 12.sp : 10.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
        ),
        CustomPaint(
          size: Size(10.w, 6.h),
          painter: _MarkerTailPainter(color: color),
        ),
      ],
    );
  }
}

class _MarkerTailPainter extends CustomPainter {
  final Color color;
  const _MarkerTailPainter({required this.color});

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
  bool shouldRepaint(_MarkerTailPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : Colors.white;
    final fg = isDark ? Colors.white : AppColors.textDark;
    final sz = 42.w;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: sz,
        height: sz,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: bg == Colors.white
                  ? Colors.black.withOpacity(0.1)
                  : bg.withOpacity(0.45),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, size: sz * 0.48, color: fg),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim profile info row
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, size: 16.w, color: AppColors.primary),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.sp,
                    color: AppColors.textMutedLight,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 14.sp,
                    color:
                        valueColor ??
                        (isDark ? Colors.white : AppColors.textDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Area map marker (suggestions = primary/blue, meetpoints = red)
// ─────────────────────────────────────────────────────────────────────────────

class _AreaMapMarker extends StatelessWidget {
  final SuggestedArea area;
  const _AreaMapMarker({required this.area});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            color: isDark ? AppColors.surfaceDark : Colors.white,
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
        CustomPaint(
          size: Size(10.w, 6.h),
          painter: _MarkerTailPainter(color: color),
        ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Area Picker Screen (map pick + place search + name/desc input)
// ─────────────────────────────────────────────────────────────────────────────

class _AreaPickerScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String areaType;
  final LatLng? initialCenter;
  const _AreaPickerScreen({
    required this.groupId,
    required this.areaType,
    this.initialCenter,
  });

  @override
  ConsumerState<_AreaPickerScreen> createState() => _AreaPickerScreenState();
}

class _AreaPickerScreenState extends ConsumerState<_AreaPickerScreen> {
  final _mapController = MapController();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _searchController = TextEditingController();

  LatLng? _pickedPoint;
  bool _submitting = false;

  // Place search
  List<Map<String, dynamic>> _searchResults = [];
  bool _searching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _mapController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ── Place search via Nominatim ────────────────────────────────────────────
  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _searchResults = []);
      return;
    }
    _debounce = Timer(
      const Duration(milliseconds: 500),
      () => _searchPlaces(query.trim()),
    );
  }

  Future<void> _searchPlaces(String query) async {
    setState(() => _searching = true);
    try {
      final dio = Dio();
      final resp = await dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'json',
          'limit': '6',
          'viewbox':
              '39.7,21.5,39.95,21.3', // Makkah bounding box (approximate)
          'bounded': '0',
        },
        options: Options(headers: {'User-Agent': 'FlutterMunawwara/1.0'}),
      );
      if (!mounted) return;
      final list = (resp.data as List)
          .map<Map<String, dynamic>>(
            (e) => {
              'display_name': e['display_name'] as String,
              'lat': double.parse(e['lat'] as String),
              'lon': double.parse(e['lon'] as String),
            },
          )
          .toList();
      setState(() => _searchResults = list);
    } catch (_) {
      // ignore errors
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectSearchResult(Map<String, dynamic> result) {
    final point = LatLng(result['lat'] as double, result['lon'] as double);
    setState(() {
      _pickedPoint = point;
      _searchResults = [];
      _searchController.clear();
    });
    _mapController.move(point, 17);
    // Auto-fill name if empty
    if (_nameController.text.isEmpty) {
      final parts = (result['display_name'] as String).split(',');
      _nameController.text = parts.first.trim();
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _pickedPoint == null) return;
    setState(() => _submitting = true);
    final (success, errorMsg) = await ref
        .read(suggestedAreaProvider.notifier)
        .addArea(
          groupId: widget.groupId,
          name: name,
          description: _descController.text.trim(),
          latitude: _pickedPoint!.latitude,
          longitude: _pickedPoint!.longitude,
          areaType: widget.areaType,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (success) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMsg ??
                (widget.areaType == 'meetpoint'
                    ? 'area_meetpoint_exists'.tr()
                    : 'error_generic'.tr()),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMeetpoint = widget.areaType == 'meetpoint';
    final accentColor = isMeetpoint
        ? const Color(0xFFDC2626)
        : AppColors.primary;
    final center =
        _pickedPoint ?? widget.initialCenter ?? const LatLng(21.4225, 39.8262);

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Symbols.arrow_back,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isMeetpoint ? 'area_meetpoint'.tr() : 'area_suggest'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 17.sp,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ── Search bar ─────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
              decoration: InputDecoration(
                hintText: 'area_search_hint'.tr(),
                hintStyle: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13.sp,
                  color: AppColors.textMutedLight,
                ),
                prefixIcon: Icon(
                  Symbols.search,
                  size: 20.w,
                  color: AppColors.textMutedLight,
                ),
                suffixIcon: _searching
                    ? Padding(
                        padding: EdgeInsets.all(12.w),
                        child: SizedBox(
                          width: 16.w,
                          height: 16.w,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: accentColor,
                          ),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: isDark
                    ? AppColors.backgroundDark
                    : const Color(0xFFF0F0F8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14.r),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 12.h),
              ),
            ),
          ),

          // ── Search results dropdown ────────────────────────────────────
          if (_searchResults.isNotEmpty)
            Container(
              constraints: BoxConstraints(maxHeight: 200.h),
              margin: EdgeInsets.symmetric(horizontal: 16.w),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: isDark ? Colors.white12 : Colors.grey.shade200,
                ),
                itemBuilder: (_, i) {
                  final r = _searchResults[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Symbols.location_on,
                      size: 18.w,
                      color: accentColor,
                    ),
                    title: Text(
                      r['display_name'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12.sp,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    onTap: () => _selectSearchResult(r),
                  );
                },
              ),
            ),

          // ── Map ────────────────────────────────────────────────────────
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16.r),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16.r),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 15,
                      onTap: (_, point) {
                        setState(() => _pickedPoint = point);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      ),
                      if (_pickedPoint != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _pickedPoint!,
                              width: 48.w,
                              height: 48.w,
                              child: Icon(
                                Symbols.location_on,
                                size: 42.w,
                                color: accentColor,
                                fill: 1,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Name & Description inputs ──────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
            child: Column(
              children: [
                TextField(
                  controller: _nameController,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'area_name_hint'.tr(),
                    hintStyle: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13.sp,
                      color: AppColors.textMutedLight,
                    ),
                    prefixIcon: Icon(
                      isMeetpoint ? Symbols.crisis_alert : Symbols.pin_drop,
                      size: 18.w,
                      color: accentColor,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.backgroundDark
                        : const Color(0xFFF0F0F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                  ),
                ),
                SizedBox(height: 8.h),
                TextField(
                  controller: _descController,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                  maxLines: 1,
                  decoration: InputDecoration(
                    hintText: 'area_desc_hint'.tr(),
                    hintStyle: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13.sp,
                      color: AppColors.textMutedLight,
                    ),
                    prefixIcon: Icon(
                      Symbols.description,
                      size: 18.w,
                      color: AppColors.textMutedLight,
                    ),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.backgroundDark
                        : const Color(0xFFF0F0F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14.r),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                  ),
                ),
              ],
            ),
          ),

          // ── Submit button ──────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(
              16.w,
              4.h,
              16.w,
              MediaQuery.of(context).padding.bottom + 16.h,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 50.h,
              child: ElevatedButton(
                onPressed: (_pickedPoint == null || _submitting)
                    ? null
                    : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  disabledBackgroundColor: accentColor.withOpacity(0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                  ),
                  elevation: 0,
                ),
                child: _submitting
                    ? SizedBox(
                        width: 22.w,
                        height: 22.w,
                        child: const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        isMeetpoint
                            ? 'area_set_meetpoint'.tr()
                            : 'area_add_suggestion'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 15.sp,
                          color: Colors.white,
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
