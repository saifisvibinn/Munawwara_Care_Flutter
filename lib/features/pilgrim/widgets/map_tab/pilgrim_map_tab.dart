import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/map/app_map_controller.dart';
import '../../../../core/map/app_map_marker_data.dart';
import '../../../../core/map/app_map_marker_cluster.dart';
import '../../../../core/map/app_map_tiles.dart';
import '../../../../core/map/widgets/app_platform_map.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/map_circle_fab.dart';
import '../../../shared/models/suggested_area_model.dart';
import '../../../shared/widgets/moderator_avatar.dart';
import '../../../shared/widgets/pilgrim_gender_avatar.dart';
import '../../providers/pilgrim_provider.dart';
import 'pilgrim_area_marker.dart';
import 'hospitals_cycle_button.dart';
import '../../models/insurance_company.dart';
import 'suggestions_cycle_button.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim Map Tab
// ─────────────────────────────────────────────────────────────────────────────

class PilgrimMapTab extends StatelessWidget {
  final LatLng? myLocation;
  final LatLng? Function()? resolveMyLocation;
  final AppMapController mapController;
  final PilgrimState pilgrimState;
  final String? profileGender;
  final List<SuggestedArea> areas;

  const PilgrimMapTab({
    super.key,
    required this.myLocation,
    this.resolveMyLocation,
    required this.mapController,
    required this.pilgrimState,
    required this.profileGender,
    required this.areas,
  });

  LatLng _offsetIfTooCloseToMe(LatLng p) {
    final me = myLocation;
    if (me == null) return p;
    final dM = Geolocator.distanceBetween(
      me.latitude, me.longitude, p.latitude, p.longitude,
    );
    if (dM > 8) return p;
    const meters = 10.0;
    final latRad = me.latitude * math.pi / 180.0;
    final dLat = meters / 111320.0;
    final dLng = meters / (111320.0 * math.cos(latRad).abs().clamp(0.2, 1.0));
    return LatLng(p.latitude + dLat, p.longitude + dLng);
  }

  List<AppMapMarkerData> _markerData(
    List<HospitalLocation> hospitals,
    List<dynamic> beacons,
    bool isDark,
  ) {
    final markers = <AppMapMarkerData>[];
    for (final hospital in hospitals) {
      markers.add(
        AppMapMarkerData(
          id: 'hospital_${hospital.id}',
          point: LatLng(hospital.latitude, hospital.longitude),
          kind: AppMapMarkerKind.hospital,
          title: hospital.name,
          tintArgb: 0xFFE53935,
          glyphName: 'cross.fill',
          payload: hospital,
        ),
      );
    }
    for (final area in areas) {
      markers.add(
        AppMapMarkerData(
          id: 'area_${area.id}',
          point: LatLng(area.latitude, area.longitude),
          kind: AppMapMarkerKind.area,
          title: area.name,
          subtitle: area.isMeetpoint ? 'Meetpoint' : null,
          tintArgb: area.isMeetpoint ? 0xFFDC2626 : AppColors.primary.toARGB32(),
          glyphName: area.isMeetpoint ? 'exclamationmark.triangle.fill' : 'mappin',
          payload: area,
        ),
      );
    }
    for (final b in beacons) {
      markers.add(
        AppMapMarkerData(
          id: 'beacon_${b.moderatorId}',
          point: _offsetIfTooCloseToMe(LatLng(b.lat, b.lng)),
          kind: AppMapMarkerKind.beacon,
          title: b.name,
          tintArgb: AppColors.primary.toARGB32(),
          glyphName: 'person.fill',
          payload: b,
        ),
      );
    }
    return markers;
  }

  void _onMarkerTap(BuildContext context, AppMapMarkerData marker) {
    final payload = marker.payload;
    if (payload is SuggestedArea) {
      showAreaInfo(context, payload);
    } else if (payload is HospitalLocation) {
      showHospitalInfo(context, payload);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final group = pilgrimState.groupInfo;
    final beacons = pilgrimState.navBeacons.values.toList();
    final fabBottom = 14.h;
    final fabStride = 44.w + 10.h;

    final insuranceCompany = pilgrimState.profile?.insuranceCompany;
    final hospitals = insuranceCompany?.hospitals ?? const [];
    final markerData = _markerData(hospitals, beacons, isDark);

    void centerOnMe() {
      final target =
          resolveMyLocation?.call() ?? myLocation ?? AppMapTiles.fallbackMapCenter;
      mapController.move(target, AppMapTiles.clampMapZoom(15), preserveZoom: true);
    }

    return Stack(
      children: [
        AppPlatformMap(
          controller: mapController,
          initialCenter: myLocation ?? AppMapTiles.fallbackMapCenter,
          initialZoom: AppMapTiles.clampMapZoom(15),
          isDark: isDark,
          markers: markerData,
          showsUserLocation: true,
          onMarkerTap: (AppMapMarkerData m) => _onMarkerTap(context, m),
          flutterLayers: (ctx) => [
            AppMapMarkerCluster.layer(
              markers: [
                for (var hospital in hospitals)
                  Marker(
                    point: LatLng(hospital.latitude, hospital.longitude),
                    width: 44.w,
                    height: 44.w,
                    child: GestureDetector(
                      onTap: () => showHospitalInfo(context, hospital),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.red.shade600, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.local_hospital_rounded,
                          color: Colors.red.shade600,
                          size: 22.w,
                        ),
                      ),
                    ),
                  ),
                for (var area in areas)
                  Marker(
                    point: LatLng(area.latitude, area.longitude),
                    width: 120.w,
                    height: 82.h,
                    child: GestureDetector(
                      onTap: () => showAreaInfo(context, area),
                      child: PilgrimAreaMarker(area: area),
                    ),
                  ),
                for (final b in beacons)
                  Marker(
                    point: _offsetIfTooCloseToMe(LatLng(b.lat, b.lng)),
                    width: 92.w,
                    height: 90.h,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 46.w,
                          height: 46.w,
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceDark
                                : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.primary, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.14),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(3.w),
                            child: ModeratorAvatar(
                              size: 40.w,
                              initials:
                                  b.name.isNotEmpty ? b.name[0] : '?',
                            ),
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 6.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceDark
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(
                                color:
                                    Colors.black.withValues(alpha: 0.06)),
                          ),
                          child: Text(
                            b.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w700,
                              fontSize: 10.sp,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
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
                            border:
                                Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary
                                    .withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: PilgrimGenderAvatar(
                              gender: profileGender, size: 38.w),
                        ),
                        Container(
                          margin: EdgeInsets.only(top: 2.h),
                          padding: EdgeInsets.symmetric(
                              horizontal: 5.w, vertical: 2.h),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(
                            'you'.tr(),
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

        if (group != null)
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(14.w),
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 14.w, vertical: 10.h),
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
                      child: Icon(Symbols.group,
                          color: AppColors.primary, size: 16.w),
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

        Positioned(
          right: 14.w,
          bottom: fabBottom,
          child: MapCircleFab(
            icon: Symbols.my_location,
            onTap: centerOnMe,
          ),
        ),

        if (areas.any((a) => a.isMeetpoint))
          Positioned(
            right: 14.w,
            bottom: fabBottom + fabStride,
            child: GestureDetector(
              onTap: () {
                final mp = areas.firstWhere((a) => a.isMeetpoint);
                mapController.move(
                  LatLng(mp.latitude, mp.longitude),
                  AppMapTiles.clampMapZoom(17),
                );
                showAreaInfo(context, mp);
              },
              child: Container(
                width: 48.w,
                height: 48.w,
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(0xFFDC2626).withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(Symbols.crisis_alert,
                    color: Colors.white, size: 22.w),
              ),
            ),
          ),

        if (areas.any((a) => !a.isMeetpoint))
          Positioned(
            right: 14.w,
            bottom: fabBottom +
                fabStride * (areas.any((a) => a.isMeetpoint) ? 2 : 1),
            child: SuggestionsCycleButton(
              areas: areas.where((a) => !a.isMeetpoint).toList(),
              mapController: mapController,
              onAreaSelected: (area) => showAreaInfo(context, area),
            ),
          ),

        if (hospitals.isNotEmpty)
          Positioned(
            right: 14.w,
            bottom: fabBottom +
                fabStride *
                    ((areas.any((a) => a.isMeetpoint) ? 1 : 0) +
                        (areas.any((a) => !a.isMeetpoint) ? 1 : 0) +
                        1),
            child: HospitalsCycleButton(
              hospitals: hospitals,
              mapController: mapController,
              onHospitalSelected: (h) => showHospitalInfo(context, h),
            ),
          ),

        if (myLocation == null)
          Center(
            child: Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 8),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Symbols.location_off,
                      size: 40.w, color: AppColors.textMutedLight),
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
