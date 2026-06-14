import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/map/app_map_controller.dart';
import '../../../../core/map/app_map_tiles.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/glass/app_glass.dart';
import '../../../../core/utils/open_maps_navigation.dart';
import '../../../shared/models/suggested_area_model.dart';
import '../../../shared/widgets/area_ui_widgets.dart';

void showAreaInfo(BuildContext context, SuggestedArea area) {
  final isMeetpoint = area.isMeetpoint;
  final accent = AreaUiTheme.accent(
    Theme.of(context).brightness == Brightness.dark,
    isMeetpoint: isMeetpoint,
  );
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => AreaSheetScaffold(
      isDark: isDark,
      maxHeightFactor: 0.55,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: AreaUiTheme.typeTint(isDark, accent),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Text(
              isMeetpoint
                  ? 'area_meetpoint'.tr()
                  : 'area_suggestion_label'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 11.sp,
                color: accent,
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            area.name,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w700,
              fontSize: 20.sp,
              color: textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          if (area.description.isNotEmpty) ...[
            SizedBox(height: 6.h),
            Text(
              area.description,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                color: AreaUiTheme.sectionLabel(isDark),
              ),
              textAlign: TextAlign.center,
            ),
          ],
          SizedBox(height: 6.h),
          Text(
            '${'area_by'.tr()} ${area.createdByName}',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12.sp,
              color: AreaUiTheme.sectionLabel(isDark),
            ),
          ),
          if (isMeetpoint && area.meetpointTime != null) ...[
            SizedBox(height: 16.h),
            AreaInsetGroup(
              isDark: isDark,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                  child: Row(
                    children: [
                      Icon(Symbols.schedule, color: accent, size: 20.w),
                      SizedBox(width: 10.w),
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
                                color: textPrimary,
                              ),
                            ),
                            if (area.reminderMinutes != null)
                              Text(
                                area.reminderMinutes! > 0
                                    ? 'area_reminder_mins'.tr(
                                        args: [area.reminderMinutes.toString()],
                                      )
                                    : 'area_reminder_at_time'.tr(),
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 12.sp,
                                  color: AreaUiTheme.sectionLabel(isDark),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 20.h),
          AreaPrimaryButton(
            label: 'area_navigate'.tr(),
            accentColor: accent,
            icon: Symbols.navigation,
            onPressed: () async {
              final lat = area.latitude;
              final lng = area.longitude;
              Navigator.pop(ctx);
              await OpenMapsNavigation.launch(context, lat, lng);
            },
          ),
        ],
      ),
    ),
  );
}

class SuggestionsCycleButton extends StatefulWidget {
  const SuggestionsCycleButton({
    super.key,
    required this.areas,
    required this.mapController,
    required this.onAreaSelected,
  });

  final List<SuggestedArea> areas;
  final AppMapController mapController;
  final void Function(SuggestedArea) onAreaSelected;

  @override
  State<SuggestionsCycleButton> createState() => _SuggestionsCycleButtonState();
}

class _SuggestionsCycleButtonState extends State<SuggestionsCycleButton> {
  void _showAreaList() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => AreaSheetScaffold(
        isDark: isDark,
        scrollControlled: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AreaSheetTitle(
              isDark: isDark,
              title: 'area_view_all'.tr(),
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
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: widget.areas.length,
                      separatorBuilder: (_, _) => SizedBox(height: 8.h),
                      itemBuilder: (_, i) {
                        final area = widget.areas[i];
                        final accent = AreaUiTheme.accent(
                          isDark,
                          isMeetpoint: area.isMeetpoint,
                        );
                        return AreaInsetGroup(
                          isDark: isDark,
                          children: [
                            AreaListRow(
                              isDark: isDark,
                              name: area.name,
                              description: area.description.isNotEmpty
                                  ? area.description
                                  : null,
                              isMeetpoint: area.isMeetpoint,
                              onTap: () {
                                Navigator.pop(ctx);
                                widget.mapController.move(
                                  LatLng(area.latitude, area.longitude),
                                  AppMapTiles.clampMapZoom(16.5),
                                );
                                widget.onAreaSelected(area);
                              },
                              trailing: IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Symbols.navigation,
                                  size: 20.w,
                                  color: accent,
                                  fill: 1,
                                ),
                                onPressed: () async {
                                  await OpenMapsNavigation.launch(
                                    context,
                                    area.latitude,
                                    area.longitude,
                                  );
                                },
                              ),
                            ),
                          ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        if (widget.areas.isEmpty) return;
        _showAreaList();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AppGlassSurface(
            isDark: isDark,
            borderRadius: BorderRadius.circular(24.r),
            width: 48.w,
            height: 48.w,
            child: Icon(
              Symbols.pin_drop,
              color: AppColors.primary,
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
