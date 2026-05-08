import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Weather Alert Model
// ─────────────────────────────────────────────────────────────────────────────

class WeatherAlert {
  final int temperatureC;
  final String condition;
  final String reminder;
  final IconData icon;
  final Color iconColor;
  final bool isLoading;
  final bool isError;

  const WeatherAlert({
    required this.temperatureC,
    required this.condition,
    required this.reminder,
    required this.icon,
    required this.iconColor,
    required this.isLoading,
    required this.isError,
  });

  const WeatherAlert.loading()
    : temperatureC = 0,
      condition = 'Loading weather',
      reminder = 'Checking local weather conditions...',
      icon = Icons.wb_sunny,
      iconColor = AppColors.primary,
      isLoading = true,
      isError = false;

  const WeatherAlert.error(String message)
    : temperatureC = 0,
      condition = 'Weather unavailable',
      reminder = message,
      icon = Icons.cloud_off,
      iconColor = AppColors.textMutedLight,
      isLoading = false,
      isError = true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Weather Card
// ─────────────────────────────────────────────────────────────────────────────

class WeatherCard extends StatelessWidget {
  final WeatherAlert alert;
  const WeatherCard({super.key, required this.alert});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(alert.icon, color: AppColors.accentGold, size: 28.w),
          SizedBox(height: 8.h),
          Text(
            alert.isLoading
                ? '...'
                : alert.isError
                ? '--'
                : '${alert.temperatureC}\u00b0C',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 26.sp,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            alert.isLoading
                ? 'weather_loading'.tr()
                : alert.isError
                ? 'weather_unavailable'.tr()
                : alert.condition,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              color: isDark ? AppColors.primary : AppColors.primaryDark,
            ),
          ),
          SizedBox(height: 4.h),
          Expanded(
            child: Text(
              alert.isLoading ? 'weather_loading_hint'.tr() : alert.reminder,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 11.sp,
                color: isDark
                    ? AppColors.textMutedLight
                    : AppColors.textMutedDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Group Card
// ─────────────────────────────────────────────────────────────────────────────

class GroupCard extends StatelessWidget {
  final String groupName;
  final VoidCallback onTap;

  const GroupCard({super.key, required this.groupName, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Symbols.groups, color: AppColors.primary, size: 36.w),
            SizedBox(height: 16.h),
            Text(
              'home_my_group'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            SizedBox(height: 4.h),
            Expanded(
              child: Text(
                groupName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 24.sp,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : AppColors.textDark,
                  height: 1.1,
                ),
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'home_tap_details'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 12.sp,
                color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Explore Card
// ─────────────────────────────────────────────────────────────────────────────

class ExploreCard extends StatelessWidget {
  final VoidCallback onTap;
  const ExploreCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 16.h),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
              color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.navigation_rounded,
                color: AppColors.primary,
                size: 20.w,
              ),
            ),
            SizedBox(width: 10.w),
            Text(
              'home_explore'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
            const Spacer(),
            Icon(
              Symbols.arrow_forward_ios,
              size: 14.w,
              color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
            ),
          ],
        ),
      ),
    );
  }
}
