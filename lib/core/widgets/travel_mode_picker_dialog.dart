import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// How the user wants to reach a destination in Google Maps.
enum MapsTravelMode {
  walking,
  driving,
}

/// Shows a premium travel-mode picker for hotel / map navigation.
Future<MapsTravelMode?> showTravelModePickerDialog(BuildContext context) {
  return showDialog<MapsTravelMode>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const _TravelModePickerDialog(),
  );
}

class _TravelModePickerDialog extends StatelessWidget {
  const _TravelModePickerDialog();

  static const Color _titleGreen = Color(0xFF0F3E1F);
  static const Color _walkingCircle = Color(0xFF0F3E1F);
  static const Color _carCircle = Color(0xFFF5EDE0);
  static const Color _carIcon = Color(0xFF8B6914);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : _titleGreen;
    final subtitleColor =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final optionBg =
        isDark ? AppColors.surfaceDark : const Color(0xFFF8FAFC);
    final optionBorder =
        isDark ? AppColors.dividerDark : const Color(0xFFE2E8F0);
    final bodyColor = isDark ? Colors.white : AppColors.textDark;

    return Dialog(
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 28.w),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(22.w, 24.h, 22.w, 18.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'hotel_nav_choose_mode_title'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 20.sp,
                fontWeight: FontWeight.w800,
                color: titleColor,
                height: 1.25,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'hotel_nav_choose_mode_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: subtitleColor,
                height: 1.35,
              ),
            ),
            SizedBox(height: 18.h),
            Divider(
              height: 1,
              thickness: 1,
              color: optionBorder,
            ),
            SizedBox(height: 16.h),
            _TravelModeOptionTile(
              backgroundColor: optionBg,
              borderColor: optionBorder,
              iconBackgroundColor:
                  isDark ? _walkingCircle.withValues(alpha: 0.85) : _walkingCircle,
              iconColor: Colors.white,
              icon: Symbols.directions_walk,
              title: 'hotel_nav_walking'.tr(),
              subtitle: 'hotel_nav_walking_sub'.tr(),
              bodyColor: bodyColor,
              subtitleColor: subtitleColor,
              onTap: () => Navigator.of(context).pop(MapsTravelMode.walking),
            ),
            SizedBox(height: 10.h),
            _TravelModeOptionTile(
              backgroundColor: optionBg,
              borderColor: optionBorder,
              iconBackgroundColor:
                  isDark ? _carCircle.withValues(alpha: 0.35) : _carCircle,
              iconColor: _carIcon,
              icon: Symbols.directions_car,
              title: 'hotel_nav_by_car'.tr(),
              subtitle: 'hotel_nav_by_car_sub'.tr(),
              bodyColor: bodyColor,
              subtitleColor: subtitleColor,
              onTap: () => Navigator.of(context).pop(MapsTravelMode.driving),
            ),
            SizedBox(height: 18.h),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: bodyColor,
                padding: EdgeInsets.symmetric(vertical: 10.h),
              ),
              child: Text(
                'dialog_cancel'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelModeOptionTile extends StatelessWidget {
  final Color backgroundColor;
  final Color borderColor;
  final Color iconBackgroundColor;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color bodyColor;
  final Color subtitleColor;
  final VoidCallback onTap;

  const _TravelModeOptionTile({
    required this.backgroundColor,
    required this.borderColor,
    required this.iconBackgroundColor,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bodyColor,
    required this.subtitleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
            child: Row(
              children: [
                Container(
                  width: 44.w,
                  height: 44.w,
                  decoration: BoxDecoration(
                    color: iconBackgroundColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: iconColor,
                    size: 24.sp,
                    fill: 1,
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                          color: bodyColor,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                          color: subtitleColor,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: subtitleColor,
                  size: 22.sp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
