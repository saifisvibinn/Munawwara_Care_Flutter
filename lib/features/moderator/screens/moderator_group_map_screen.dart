import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/moderator_provider.dart';

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
  final _mapController = MapController();
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
            _mapController.move(LatLng(target.lat!, target.lng!), 17);
          }
        });
      }
    }

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
      // Only auto-center on me if we're not focusing a specific pilgrim
      if (widget.focusPilgrimId == null) {
        _mapController.move(_myLocation!, 15);
      }
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
          }
        });
  }

  void _centerOnMe() {
    final target = _myLocation ?? const LatLng(21.3891, 39.8579);
    _mapController.move(target, 15);
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
    _mapController.move(LatLng(latAvg, lngAvg), 14);
  }

  Future<void> _broadcastSOS() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
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
          style: TextStyle(fontFamily: 'Lexend', fontSize: 14.sp),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ok ? Colors.red.shade700 : Colors.grey.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        content: Text(
          ok ? '🚨 SOS broadcast sent!' : 'Failed to send SOS. Try again.',
          style: const TextStyle(color: Colors.white, fontFamily: 'Lexend'),
        ),
      ),
    );
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
    final pilgrims = widget.group.pilgrims;
    final locatedPilgrims = pilgrims.where((p) => p.hasLocation).toList();

    return Scaffold(
      body: Stack(
        children: [
          // ── Map ──
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
              // My location
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
              // Pilgrim markers
              MarkerLayer(
                markers: [
                  for (final p in locatedPilgrims)
                    Marker(
                      point: LatLng(p.lat!, p.lng!),
                      width: 64.w,
                      height: 72.h,
                      child: _PilgrimMapMarker(pilgrim: p),
                    ),
                ],
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
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          Symbols.arrow_back,
                          size: 20.w,
                          color: AppColors.textDark,
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
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
                                      color: AppColors.textDark,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${widget.group.onlineCount}/${widget.group.totalPilgrims} Online',
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
                              color: Colors.red.withOpacity(0.3),
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
                _MapFab(icon: Symbols.my_location, onTap: _centerOnMe),
                SizedBox(height: 10.h),
                _MapFab(icon: Symbols.group, onTap: _centerOnGroup),
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
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
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
                        color: const Color(0xFFE2E8F0),
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
                          '${widget.group.totalPilgrims} Pilgrims',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 15.sp,
                            color: AppColors.textDark,
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
                        color: const Color(0xFFF0F0F8),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: TextField(
                        controller: _searchController,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 13.sp,
                          color: AppColors.textDark,
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
// Pilgrim Map Marker
// ─────────────────────────────────────────────────────────────────────────────

class _PilgrimMapMarker extends StatelessWidget {
  final PilgrimInGroup pilgrim;
  const _PilgrimMapMarker({required this.pilgrim});

  @override
  Widget build(BuildContext context) {
    final isSOS = pilgrim.hasSOS;
    final color = isSOS ? const Color(0xFFDC2626) : AppColors.primaryDark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36.w,
          height: 36.w,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.45),
                blurRadius: 8,
                spreadRadius: 2,
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
                      fontSize: 11.sp,
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
// Map FAB
// ─────────────────────────────────────────────────────────────────────────────

class _MapFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapFab({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44.w,
        height: 44.w,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20.w, color: AppColors.textDark),
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
              ? const Color(0xFFFFF1F2)
              : const Color(0xFFF0F0F8),
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(
            color: pilgrim.hasSOS
                ? const Color(0xFFFFE4E6)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            // Avatar
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
                      color: AppColors.textDark,
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
                    color: AppColors.primary.withOpacity(0.12),
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

