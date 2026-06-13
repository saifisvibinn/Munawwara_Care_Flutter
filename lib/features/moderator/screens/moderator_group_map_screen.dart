import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/map/app_map_controller.dart';
import '../../../core/map/app_map_marker_cluster.dart';
import '../../../core/map/app_map_tiles.dart';
import '../../../core/map/widgets/app_platform_map.dart';
import '../../../core/services/location_permission_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/map_circle_fab.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../shared/widgets/pilgrim_gender_avatar.dart';
import '../providers/moderator_provider.dart';
import '../widgets/moderator_map_marker_data.dart';
import '../widgets/moderator_map_widgets.dart';
import '../widgets/pilgrim_marker_layout.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Moderator Group Map Screen
// ─────────────────────────────────────────────────────────────────────────────

class ModeratorGroupMapScreen extends ConsumerStatefulWidget {
  final ModeratorGroup group;

  /// If set, the map will center on this pilgrim's location on load.
  final String? focusPilgrimId;

  const ModeratorGroupMapScreen({
    super.key,
    required this.group,
    this.focusPilgrimId,
  });

  @override
  ConsumerState<ModeratorGroupMapScreen> createState() =>
      _ModeratorGroupMapScreenState();
}

class _ModeratorGroupMapScreenState
    extends ConsumerState<ModeratorGroupMapScreen> {
  final _mapController = createAppMapController();
  final _dssController = DraggableScrollableController();
  final _searchController = TextEditingController();
  String _searchQuery = '';

  LatLng? _myLocation;
  StreamSubscription<Position>? _locationSub;
  bool _sosLoading = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _searchController.addListener(() {
      if (mounted) {
        setState(() => _searchQuery = _searchController.text.toLowerCase());
      }
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    _dssController.dispose();
    _searchController.dispose();
    _locationSub?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    // If we have a specific pilgrim to focus, center there first
    if (widget.focusPilgrimId != null) {
      final target = widget.group.pilgrims.cast<PilgrimInGroup?>().firstWhere(
        (p) => p?.id == widget.focusPilgrimId,
        orElse: () => null,
      );
      if (target != null && target.hasLocation) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _mapController.move(
              LatLng(target.lat!, target.lng!),
              AppMapTiles.clampMapZoom(17),
            );
          }
        });
      }
    }

    final ok = await hasLocationAlwaysPermission();
    if (!ok || !mounted) return;

    bool usableLast(Position p) {
      final age = DateTime.now().difference(p.timestamp);
      if (age > const Duration(hours: 8)) return false;
      final acc = p.accuracy;
      if (acc.isInfinite || acc < 0) return false;
      return acc <= 8000;
    }

    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null && usableLast(last) && mounted) {
        setState(() => _myLocation = LatLng(last.latitude, last.longitude));
        if (widget.focusPilgrimId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _myLocation != null) {
              _mapController.move(
                _myLocation!,
                AppMapTiles.clampMapZoom(15),
              );
            }
          });
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
      if (widget.focusPilgrimId == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _myLocation != null) {
            _mapController.move(
              _myLocation!,
              AppMapTiles.clampMapZoom(15),
            );
          }
        });
      }
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
          }
        });
  }

  void _centerOnPilgrim(PilgrimInGroup p) {
    if (!p.hasLocation) return;
    _mapController.move(
      LatLng(p.lat!, p.lng!),
      AppMapTiles.clampMapZoom(17),
    );
  }

  void _centerOnMe() {
    final target = _myLocation ?? AppMapTiles.fallbackMapCenter;
    _mapController.move(target, AppMapTiles.clampMapZoom(15), preserveZoom: true);
  }

  void _centerOnGroup() {
    final located = widget.group.pilgrims.where((p) => p.hasLocation).toList();
    if (located.isEmpty) {
      _centerOnMe();
      return;
    }
    final latAvg =
        located.map((p) => p.lat!).reduce((a, b) => a + b) / located.length;
    final lngAvg =
        located.map((p) => p.lng!).reduce((a, b) => a + b) / located.length;
    _mapController.move(
      LatLng(latAvg, lngAvg),
      AppMapTiles.clampMapZoom(14),
    );
  }

  Future<void> _broadcastSOS() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : null,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(
          '🚨 Broadcast Emergency SOS?',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 16.sp,
            color: Colors.red.shade700,
          ),
        ),
        content: Text(
          'This will send an urgent SOS message to all pilgrims in ${widget.group.groupName}.',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14.sp,
            color: isDark ? Colors.white70 : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontFamily: 'Lexend',
                color: AppColors.textMutedLight,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Send SOS',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _sosLoading = true);
    final ok = await ref.read(moderatorProvider.notifier).broadcastSOS();
    if (!mounted) return;
    setState(() => _sosLoading = false);
    if (ok) {
      StandardSnackBar.showSuccess(context, 'msg_sos_broadcast_sent'.tr());
    } else {
      StandardSnackBar.showError(context, 'msg_sos_broadcast_failed'.tr());
    }
  }

  List<PilgrimInGroup> get _filteredPilgrims {
    var list = widget.group.pilgrims;
    if (_searchQuery.isNotEmpty) {
      list = list
          .where((p) => p.fullName.toLowerCase().contains(_searchQuery))
          .toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pilgrims = widget.group.pilgrims;
    final locatedPilgrims = pilgrims.where((p) => p.hasLocation).toList();
    final mapMarkers = ModeratorMapMarkers.pilgrims(
      locatedPilgrims,
      focusedId: widget.focusPilgrimId,
    );

    return Scaffold(
      body: Stack(
        children: [
          AppPlatformMap(
            controller: _mapController,
            initialCenter: _myLocation ?? AppMapTiles.fallbackMapCenter,
            initialZoom: AppMapTiles.clampMapZoom(14),
            isDark: isDark,
            markers: mapMarkers,
            showsUserLocation: true,
            onMarkerTap: (marker) {
              final p = marker.payload;
              if (p is PilgrimInGroup) {
                _centerOnPilgrim(p);
              }
            },
            flutterLayers: (ctx) => [
              AppMapMarkerCluster.layer(
                markerChildBehavior: false,
                markers: PilgrimMarkerLayout.pointsForMarkers(locatedPilgrims)
                    .map((item) {
                  final selected =
                      widget.focusPilgrimId == item.pilgrim.id;
                  final sz = PilgrimMapMarker.mapMarkerSize(
                    ctx,
                    isSelected: selected,
                  );
                  return Marker(
                    point: item.point,
                    width: sz.width,
                    height: sz.height,
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: PilgrimMapMarker.mapMarkerPadding(),
                      child: PilgrimMapMarker(
                        pilgrim: item.pilgrim,
                        isSelected: selected,
                        isSOS: item.pilgrim.hasSOS,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          // ── Top AppBar overlay ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 0),
                child: Row(
                  children: [
                    // Back button
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 42.w,
                        height: 42.w,
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceDark : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Symbols.arrow_back,
                          size: 20.w,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    // Group name card
                    Flexible(
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14.w,
                          vertical: 10.h,
                        ),
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(14.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
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
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.group.groupName,
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
                                    '${widget.group.onlineCount}/${widget.group.totalPilgrims} ${'dashboard_stat_online'.tr()}',
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
                    ),
                    SizedBox(width: 10.w),
                    // Broadcast SOS
                    GestureDetector(
                      onTap: _sosLoading ? null : _broadcastSOS,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 10.h,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.shade600,
                          borderRadius: BorderRadius.circular(14.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.red.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: _sosLoading
                            ? SizedBox(
                                width: 18.w,
                                height: 18.w,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Symbols.cell_tower,
                                    size: 18.w,
                                    color: Colors.white,
                                  ),
                                  SizedBox(width: 5.w),
                                  Text(
                                    'SOS',
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.sp,
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
          ),

          // ── Right-side FABs ──
          Positioned(
            right: 14.w,
            bottom: 220.h,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MapCircleFab(icon: Symbols.my_location, onTap: _centerOnMe),
                SizedBox(height: 10.h),
                MapCircleFab(icon: Symbols.group, onTap: _centerOnGroup),
              ],
            ),
          ),

          // ── Pilgrim list sheet ──
          DraggableScrollableSheet(
            controller: _dssController,
            initialChildSize: 0.28,
            minChildSize: 0.1,
            maxChildSize: 0.7,
            snap: true,
            snapSizes: const [0.1, 0.28, 0.7],
            builder: (ctx, scrollController) => Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Drag handle
                  Padding(
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
                  // Sheet header
                  Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 10.h),
                    child: Row(
                      children: [
                        Text(
                          'group_pilgrims_count'.tr(args: [widget.group.totalPilgrims.toString()]),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 15.sp,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        const Spacer(),
                        if (widget.group.sosCount > 0)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8.w,
                              vertical: 4.h,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF3A1010)
                                  : const Color(0xFFFFF1F2),
                              borderRadius: BorderRadius.circular(100.r),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0xFF5C1515)
                                    : const Color(0xFFFFE4E6),
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
                                  '${widget.group.sosCount} SOS',
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
                  // Search bar
                  Padding(
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
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 11.h),
                        ),
                      ),
                    ),
                  ),
                  // Pilgrim list
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
                      itemCount: _filteredPilgrims.length,
                      itemBuilder: (ctx, i) =>
                          _PilgrimListTile(pilgrim: _filteredPilgrims[i]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim List Tile
// ─────────────────────────────────────────────────────────────────────────────

class _PilgrimListTile extends StatelessWidget {
  final PilgrimInGroup pilgrim;
  const _PilgrimListTile({required this.pilgrim});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final battColor = switch (pilgrim.batteryStatus) {
      BatteryStatus.good => const Color(0xFF16A34A),
      BatteryStatus.medium => const Color(0xFFF59E0B),
      BatteryStatus.low => const Color(0xFFDC2626),
      BatteryStatus.unknown => AppColors.textMutedLight,
    };

    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: pilgrim.hasSOS
              ? (isDark ? const Color(0xFF3A1010) : const Color(0xFFFFF1F2))
              : isDark
              ? AppColors.backgroundDark
              : const Color(0xFFF0F0F8),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: pilgrim.hasSOS
                ? (isDark ? const Color(0xFF5C1515) : const Color(0xFFFFE4E6))
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            // Avatar
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
                      imageUrl: pilgrim.profilePicture,
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
                  if (pilgrim.lastSeenText.isNotEmpty) ...[
                    SizedBox(height: 2.h),
                    Text(
                      pilgrim.lastSeenText,
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
            // Battery
            if (pilgrim.batteryPercent != null) ...[
              SizedBox(width: 8.w),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.battery_5_bar, size: 14.w, color: battColor),
                  SizedBox(width: 2.w),
                  Text(
                    '${pilgrim.batteryPercent}%',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 11.sp,
                      color: battColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            // Call button
            if (pilgrim.phoneNumber != null) ...[
              SizedBox(width: 8.w),
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse('tel:${pilgrim.phoneNumber}');
                  if (await canLaunchUrl(uri)) launchUrl(uri);
                },
                child: Container(
                  padding: EdgeInsets.all(7.w),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppColors.surfaceDark
                        : const Color(0xFFEEEEFB),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Symbols.call,
                    size: 16.w,
                    color: AppColors.primaryDark,
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
