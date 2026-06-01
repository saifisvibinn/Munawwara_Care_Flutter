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
  /// One compact line or few lines on the dashboard card (localized).
  final String cardTip;
  /// Fuller guidance for the detail sheet (localized).
  final String detailTip;
  final IconData icon;
  final Color iconColor;
  final bool isLoading;
  final bool isError;

  const WeatherAlert({
    required this.temperatureC,
    required this.condition,
    required this.cardTip,
    required this.detailTip,
    required this.icon,
    required this.iconColor,
    required this.isLoading,
    required this.isError,
  });

  const WeatherAlert.loading()
    : temperatureC = 0,
      condition = '',
      cardTip = '',
      detailTip = '',
      icon = Icons.wb_sunny,
      iconColor = AppColors.primary,
      isLoading = true,
      isError = false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

void showWeatherDetailBottomSheet(BuildContext context, WeatherAlert alert) {
  if (alert.isLoading) return;
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  final titleStyle = theme.textTheme.titleLarge?.copyWith(
    fontFamily: 'Lexend',
    fontWeight: FontWeight.w800,
    color: isDark ? Colors.white : AppColors.textDark,
  );
  final bodyStyle = theme.textTheme.bodyLarge?.copyWith(
    fontFamily: 'Lexend',
    height: 1.45,
    color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
  );
  final headingStyle = theme.textTheme.titleSmall?.copyWith(
    fontFamily: 'Lexend',
    fontWeight: FontWeight.w700,
    color: isDark ? AppColors.primary : AppColors.primaryDark,
  );

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.fromLTRB(22.w, 8.h, 22.w, 20.h),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('weather_detail_sheet_title'.tr(), style: titleStyle),
              SizedBox(height: 18.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: alert.iconColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                    child: Icon(alert.icon, color: alert.iconColor, size: 36.sp),
                  ),
                  SizedBox(width: 14.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!alert.isError)
                          Text(
                            '${alert.temperatureC}\u00b0C',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 32.sp,
                              fontWeight: FontWeight.w900,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.textDark,
                            ),
                          )
                        else
                          Icon(
                            Icons.cloud_off,
                            size: 32.sp,
                            color: AppColors.textMutedDark,
                          ),
                        SizedBox(height: 6.h),
                        Text(
                          alert.isLoading
                              ? 'weather_loading'.tr()
                              : alert.condition,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.primary : AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 22.h),
              Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : AppColors.dividerLight,
              ),
              SizedBox(height: 16.h),
              Text(
                alert.isError
                    ? 'weather_detail_issue_heading'.tr()
                    : 'weather_detail_tips_heading'.tr(),
                style: headingStyle,
              ),
              SizedBox(height: 10.h),
              SelectableText(
                alert.detailTip.trim(),
                style: (bodyStyle ?? const TextStyle()).copyWith(
                  fontFamily: 'Lexend',
                  height: 1.45,
                  color: alert.isError
                      ? theme.colorScheme.error
                      : (isDark ? AppColors.textMutedLight : AppColors.textMutedDark),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'weather_detail_footer_note'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'Lexend',
                  height: 1.35,
                  color: isDark
                      ? AppColors.textMutedLight
                      : AppColors.textMutedDark,
                ),
              ),
              SizedBox(height: MediaQuery.paddingOf(ctx).bottom + 8.h),
            ],
          ),
        ),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Weather Card
// ─────────────────────────────────────────────────────────────────────────────

class WeatherCard extends StatelessWidget {
  final WeatherAlert alert;
  final VoidCallback? onTapOpenDetail;

  const WeatherCard({
    super.key,
    required this.alert,
    this.onTapOpenDetail,
  });

  static const _corner = Radius.circular(20);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    final canOpen =
        !alert.isLoading && onTapOpenDetail != null;

    Widget content = Padding(
      padding: EdgeInsets.fromLTRB(12.w, 12.h, 12.w, 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(alert.icon, color: alert.iconColor, size: 22.sp),
              SizedBox(width: 8.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.isLoading
                          ? '...'
                          : alert.isError
                          ? '--'
                          : '${alert.temperatureC}\u00b0C',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 21.sp,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : AppColors.textDark,
                        height: 1.05,
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        alert.isLoading
                            ? 'weather_loading'.tr()
                            : alert.isError
                            ? 'weather_unavailable'.tr()
                            : alert.condition,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.visible,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 11.5.sp,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.primary
                              : AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Expanded(
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                alert.isLoading
                    ? 'weather_loading_hint_short'.tr()
                    : alert.isError
                    ? alert.cardTip
                    : alert.cardTip,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 10.5.sp,
                  height: 1.34,
                  color: muted,
                ),
              ),
            ),
          ),
          if (canOpen) ...[
            SizedBox(height: 6.h),
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'weather_tap_more'.tr(),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 18.sp, color: muted),
              ],
            ),
          ],
        ],
      ),
    );

    content = ClipRRect(
      borderRadius: const BorderRadius.all(_corner),
      child: content,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.all(_corner),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: canOpen
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: const BorderRadius.all(_corner),
                onTap: onTapOpenDetail,
                child: content,
              ),
            )
          : content,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
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
                color:
                    isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
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
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return Material(
      color: isDark ? AppColors.surfaceDark : Colors.white,
      borderRadius: BorderRadius.circular(20.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20.r),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
              color:
                  isDark ? AppColors.dividerDark : AppColors.dividerLight,
            ),
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
              Icon(
                Symbols.explore,
                color: AppColors.accentGold,
                size: 28.w,
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'home_explore'.tr(),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: muted, size: 24.w),
            ],
          ),
        ),
      ),
    );
  }
}
