import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/map/app_map_controller.dart';
import '../../../../core/map/app_map_tiles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/open_maps_navigation.dart';
import '../../../shared/models/suggested_area_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Area info bottom sheet (free function, used by both map tab and cycle button)
// ─────────────────────────────────────────────────────────────────────────────

void showAreaInfo(BuildContext context, SuggestedArea area) {
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
                    child:
                        Icon(Symbols.schedule, color: color, size: 20.w),
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
                                ? 'area_reminder_mins'
                                    .tr(args: [area.reminderMinutes.toString()])
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
                final lat = area.latitude;
                final lng = area.longitude;
                Navigator.pop(ctx);
                await OpenMapsNavigation.launch(context, lat, lng);
              },
              icon: Icon(Symbols.navigation,
                  size: 20.w, color: Colors.white, fill: 1),
              label: Text(
                'area_navigate'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 15.sp,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(backgroundColor: color),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Suggestions Cycle Button — FAB that opens area list sheet
// ─────────────────────────────────────────────────────────────────────────────

class SuggestionsCycleButton extends StatefulWidget {
  final List<SuggestedArea> areas;
  final AppMapController mapController;
  final void Function(SuggestedArea) onAreaSelected;

  const SuggestionsCycleButton({
    super.key,
    required this.areas,
    required this.mapController,
    required this.onAreaSelected,
  });

  @override
  State<SuggestionsCycleButton> createState() =>
      _SuggestionsCycleButtonState();
}

class _SuggestionsCycleButtonState extends State<SuggestionsCycleButton> {
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
                              AppMapTiles.clampMapZoom(16.5),
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
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Symbols.pin_drop,
                                      color: Colors.white, size: 18.w),
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
                                    await OpenMapsNavigation.launch(
                                      context,
                                      area.latitude,
                                      area.longitude,
                                    );
                                  },
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8.w),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Symbols.navigation,
                                            size: 20.w,
                                            color: AppColors.primary,
                                            fill: 1),
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
            child: Icon(Symbols.pin_drop,
                color: Colors.white, size: 22.w, fill: 1),
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
