import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/map/app_map_tiles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/open_maps_navigation.dart';
import '../../models/insurance_company.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Hospital Info Bottom Sheet (Free function, accessible by map tab and button)
// ─────────────────────────────────────────────────────────────────────────────

void showHospitalInfo(BuildContext context, HospitalLocation hospital) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (dialogCtx) => Container(
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
              color: Colors.red.shade50.withValues(alpha: 0.8),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_hospital_rounded,
              color: Colors.red.shade600,
              size: 28.w,
            ),
          ),
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              'group_covered_hospital'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 10.sp,
                color: Colors.red.shade700,
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            hospital.name,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 17.sp,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
            textAlign: TextAlign.center,
          ),
          if (hospital.address != null && hospital.address!.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              hospital.address!,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                color: AppColors.textMutedLight,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          SizedBox(height: 24.h),
          SizedBox(
            width: double.infinity,
            height: 50.h,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(dialogCtx);
                OpenMapsNavigation.confirmAndLaunch(
                  context,
                  hospital.latitude,
                  hospital.longitude,
                );
              },
              icon: Icon(Symbols.navigation, size: 20.w, color: Colors.white, fill: 1),
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
                backgroundColor: Colors.red.shade600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hospitals Cycle Button — FAB that opens hospital list sheet
// ─────────────────────────────────────────────────────────────────────────────

class HospitalsCycleButton extends StatefulWidget {
  final List<HospitalLocation> hospitals;
  final MapController mapController;
  final void Function(HospitalLocation) onHospitalSelected;

  const HospitalsCycleButton({
    super.key,
    required this.hospitals,
    required this.mapController,
    required this.onHospitalSelected,
  });

  @override
  State<HospitalsCycleButton> createState() => _HospitalsCycleButtonState();
}

class _HospitalsCycleButtonState extends State<HospitalsCycleButton> {
  void _showHospitalList() {
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
              'group_covered_hospitals'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 17.sp,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
            SizedBox(height: 16.h),
            Flexible(
              child: widget.hospitals.isEmpty
                  ? Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.w),
                        child: Text(
                          'group_no_covered_hospitals'.tr(),
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
                      itemCount: widget.hospitals.length,
                      itemBuilder: (_, i) {
                        final hospital = widget.hospitals[i];
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            widget.mapController.move(
                              LatLng(hospital.latitude, hospital.longitude),
                              AppMapTiles.clampMapZoom(
                                widget.mapController.camera.zoom > 16.0
                                    ? widget.mapController.camera.zoom
                                    : 16.5,
                              ),
                            );
                            widget.onHospitalSelected(hospital);
                          },
                          child: Container(
                            margin: EdgeInsets.only(bottom: 10.h),
                            padding: EdgeInsets.all(12.w),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? AppColors.backgroundDark
                                  : const Color(0xFFFFF1F2),
                              borderRadius: BorderRadius.circular(14.r),
                              border: Border.all(
                                color: Colors.red.shade100,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36.w,
                                  height: 36.w,
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade600,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.local_hospital_rounded,
                                      color: Colors.white, size: 18),
                                ),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        hospital.name,
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
                                      if (hospital.address != null && hospital.address!.isNotEmpty) ...[
                                        SizedBox(height: 3.h),
                                        Text(
                                          hospital.address!,
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
                                  onTap: () {
                                    OpenMapsNavigation.confirmAndLaunch(
                                      context,
                                      hospital.latitude,
                                      hospital.longitude,
                                    );
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 8.w),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Symbols.navigation,
                                            size: 20.w,
                                            color: Colors.red.shade600,
                                            fill: 1),
                                        SizedBox(height: 2.h),
                                        Text(
                                          'area_navigate'.tr(),
                                          style: TextStyle(
                                            fontFamily: 'Lexend',
                                            fontSize: 9.sp,
                                            color: Colors.red.shade600,
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
    final count = widget.hospitals.length;
    return GestureDetector(
      onTap: () {
        if (widget.hospitals.isEmpty) return;
        _showHospitalList();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              color: Colors.red.shade600,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.red.shade600.withValues(alpha: 0.45),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(Icons.local_hospital_rounded,
                color: Colors.white, size: 22.w),
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
                      color: Colors.red.shade600,
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
