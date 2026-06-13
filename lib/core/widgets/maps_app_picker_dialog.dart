import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// External maps app for turn-by-turn directions.
enum ExternalMapsApp {
  googleMaps,
  appleMaps,
}

/// iOS: choose Google Maps or Apple Maps. Android: Google Maps only.
Future<ExternalMapsApp?> showMapsAppPickerDialog(BuildContext context) async {
  if (kIsWeb || !Platform.isIOS) {
    return ExternalMapsApp.googleMaps;
  }
  return showDialog<ExternalMapsApp>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => const _MapsAppPickerDialog(),
  );
}

class _MapsAppPickerDialog extends StatelessWidget {
  const _MapsAppPickerDialog();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.textDark;
    final muted =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final tileBg = isDark ? AppColors.surfaceDark : const Color(0xFFF8FAFC);
    final tileBorder =
        isDark ? AppColors.dividerDark : const Color(0xFFE2E8F0);

    return Dialog(
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 28.w),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(22.w, 24.h, 22.w, 18.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'maps_app_picker_title'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 20.sp,
                fontWeight: FontWeight.w800,
                color: titleColor,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'maps_app_picker_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: muted,
                height: 1.35,
              ),
            ),
            SizedBox(height: 18.h),
            _MapsAppTile(
              backgroundColor: tileBg,
              borderColor: tileBorder,
              icon: Symbols.map,
              iconColor: const Color(0xFF34A853),
              iconBg: const Color(0xFFE8F5E9),
              title: 'maps_app_google'.tr(),
              subtitle: 'maps_app_google_sub'.tr(),
              bodyColor: titleColor,
              subtitleColor: muted,
              onTap: () =>
                  Navigator.of(context).pop(ExternalMapsApp.googleMaps),
            ),
            SizedBox(height: 10.h),
            _MapsAppTile(
              backgroundColor: tileBg,
              borderColor: tileBorder,
              icon: Symbols.nest_found_savings,
              iconColor: const Color(0xFF007AFF),
              iconBg: const Color(0xFFE8F2FF),
              title: 'maps_app_apple'.tr(),
              subtitle: 'maps_app_apple_sub'.tr(),
              bodyColor: titleColor,
              subtitleColor: muted,
              onTap: () =>
                  Navigator.of(context).pop(ExternalMapsApp.appleMaps),
            ),
            SizedBox(height: 14.h),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'dialog_cancel'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                  color: muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapsAppTile extends StatelessWidget {
  const _MapsAppTile({
    required this.backgroundColor,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.bodyColor,
    required this.subtitleColor,
    required this.onTap,
  });

  final Color backgroundColor;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Color bodyColor;
  final Color subtitleColor;
  final VoidCallback onTap;

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
                    color: iconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 24.sp),
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
