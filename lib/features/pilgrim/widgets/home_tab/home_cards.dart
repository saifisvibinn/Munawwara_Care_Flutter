import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

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
// Shared tap footer for compact home cards
// ─────────────────────────────────────────────────────────────────────────────

class _HomeCardTapFooter extends StatelessWidget {
  final String label;

  const _HomeCardTapFooter({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ),
          SizedBox(width: 4.w),
          Icon(
            Icons.arrow_forward_rounded,
            size: 16.sp,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

BoxDecoration _homeActionCardDecoration({
  required bool isDark,
  required BorderRadius borderRadius,
  required bool isInteractive,
}) {
  return BoxDecoration(
    color: isDark ? AppColors.surfaceDark : Colors.white,
    borderRadius: borderRadius,
    border: Border.all(
      color: isInteractive
          ? AppColors.primary.withValues(alpha: isDark ? 0.35 : 0.2)
          : isDark
          ? AppColors.dividerDark
          : AppColors.dividerLight,
      width: isInteractive ? 1.2 : 1,
    ),
    boxShadow: [
      BoxShadow(
        color: AppColors.primary.withValues(
          alpha: isInteractive ? 0.14 : 0.05,
        ),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: isInteractive ? 0.1 : 0.06),
        blurRadius: 14,
        offset: const Offset(0, 5),
      ),
    ],
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final canOpen = !alert.isLoading && onTapOpenDetail != null;

    final customRadius = BorderRadius.circular(24.r);

    Widget content = Padding(
      padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 10.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w900,
                    color: isDark ? Colors.white : AppColors.textDark,
                    height: 1.05,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  alert.isLoading
                      ? 'weather_loading'.tr()
                      : alert.isError
                      ? 'weather_unavailable'.tr()
                      : alert.condition,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w800,
                    color: isDark ? AppColors.primary : AppColors.primaryDark,
                  ),
                ),
                SizedBox(height: 2.h),
                Expanded(
                  child: Text(
                    alert.isLoading
                        ? 'weather_loading_hint_short'.tr()
                        : alert.cardTip,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 10.sp,
                      height: 1.25,
                      color: muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (canOpen) ...[
            SizedBox(height: 6.h),
            _HomeCardTapFooter(label: 'weather_tap_more'.tr()),
          ],
        ],
      ),
    );

    return SizedBox(
      height: 128.h,
      child: DecoratedBox(
        decoration: _homeActionCardDecoration(
          isDark: isDark,
          borderRadius: customRadius,
          isInteractive: canOpen,
        ),
        child: ClipRRect(
          borderRadius: customRadius,
          child: canOpen
              ? Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: customRadius,
                    onTap: onTapOpenDetail,
                    splashColor: AppColors.primary.withValues(alpha: 0.12),
                    highlightColor: AppColors.primary.withValues(alpha: 0.06),
                    child: content,
                  ),
                )
              : content,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Group Card
// ─────────────────────────────────────────────────────────────────────────────

class GroupCard extends StatelessWidget {
  final String groupName;
  final String moderatorName;
  final String hotelName;
  final String busNumber;
  final String checkIn;
  final List<String> moderatorInitials;
  final int pilgrimCount;
  final VoidCallback onTap;

  const GroupCard({
    super.key,
    required this.groupName,
    required this.moderatorName,
    required this.hotelName,
    required this.busNumber,
    required this.checkIn,
    required this.moderatorInitials,
    required this.pilgrimCount,
    required this.onTap,
  });

  Widget _buildAvatarCircles(List<String> initials, int totalCount) {
    final List<Widget> list = [];
    // Draw first 2 initials
    for (int i = 0; i < initials.length && i < 2; i++) {
      list.add(
        Container(
          width: 24.w,
          height: 24.w,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFF97316),
            shape: BoxShape.circle,
          ),
          child: Text(
            initials[i],
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11.sp,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    // Draw remaining member count circle (+N)
    final remaining = totalCount - initials.length;
    if (remaining > 0) {
      if (initials.isNotEmpty) {
        list.add(SizedBox(width: 2.w));
      }
      list.add(
        Container(
          width: 24.w,
          height: 24.w,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF2E3E5C), // Premium navy blue circle
            shape: BoxShape.circle,
          ),
          child: Text(
            '+$remaining',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 9.sp,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: list,
    );
  }

  @override
  Widget build(BuildContext context) {
    final noRecordsText = 'no_records_available'.tr();

    final labelStyle = TextStyle(
      fontFamily: 'Lexend',
      fontSize: 10.sp,
      fontWeight: FontWeight.w800,
      color: const Color(0xFF94A3B8), // slate label
      letterSpacing: 0.5,
    );
    final valueStyle = TextStyle(
      fontFamily: 'Lexend',
      fontSize: 14.sp,
      fontWeight: FontWeight.w800,
      color: Colors.white,
    );
    final valueItalicStyle = TextStyle(
      fontFamily: 'Lexend',
      fontSize: 14.sp,
      fontWeight: FontWeight.w500,
      color: const Color(0xFF64748B),
      fontStyle: FontStyle.italic,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 10.h), // Tighter padding for a sleeker card
        decoration: BoxDecoration(
          color: const Color(0xFF1D2641), // Premium navy blue background matching mockup
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Row 1: Orange header and avatar circles
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'home_my_group'.tr().toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFF97316),
                    letterSpacing: 0.8,
                  ),
                ),
                _buildAvatarCircles(moderatorInitials, pilgrimCount),
              ],
            ),
            SizedBox(height: 0.h),
            // Row 2: Group name
            Text(
              groupName,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 20.sp, // Slightly more compact font size
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 8.h), // Tighter spacing
            // Divider
            const Divider(color: Colors.white12, height: 1),
            SizedBox(height: 8.h), // Tighter spacing
            // Details Grid
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('group_moderator_section'.tr().toUpperCase(), style: labelStyle),
                      SizedBox(height: 1.h),
                      Text(
                        moderatorName.isNotEmpty ? moderatorName : noRecordsText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: valueStyle,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('group_hotel_name'.tr().toUpperCase(), style: labelStyle),
                      SizedBox(height: 1.h),
                      Text(
                        hotelName.isNotEmpty ? hotelName : 'Not set',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: hotelName.isNotEmpty ? valueStyle : valueItalicStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 8.h), // Tighter spacing
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BUS', style: labelStyle),
                      SizedBox(height: 1.h),
                      Text(
                        busNumber.isNotEmpty ? busNumber : 'Not set',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: busNumber.isNotEmpty ? valueStyle : valueItalicStyle,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CHECK-IN', style: labelStyle),
                      SizedBox(height: 1.h),
                      Text(
                        checkIn.isNotEmpty ? checkIn : 'Not set',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: checkIn.isNotEmpty ? valueStyle : valueItalicStyle,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h), // Tighter spacing
            // Pill button at the bottom
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 8.h), // Sleeker pill button padding
              decoration: BoxDecoration(
                color: const Color(0x1AFFF7ED), // Semi-translucent light orange background
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Text(
                'View full group details',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFFF8533),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Explore Card (mirrors weather — inner left edge scoops around SOS)
// ─────────────────────────────────────────────────────────────────────────────

class ExploreCard extends StatelessWidget {
  final VoidCallback onTap;

  const ExploreCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    final customRadius = BorderRadius.circular(24.r);

    return SizedBox(
      height: 128.h,
      child: DecoratedBox(
        decoration: _homeActionCardDecoration(
          isDark: isDark,
          borderRadius: customRadius,
          isInteractive: true,
        ),
        child: ClipRRect(
          borderRadius: customRadius,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: customRadius,
              onTap: onTap,
              splashColor: AppColors.primary.withValues(alpha: 0.12),
              highlightColor: AppColors.primary.withValues(alpha: 0.06),
              child: Padding(
                padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 10.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'home_explore'.tr(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? Colors.white
                                        : AppColors.textDark,
                                    height: 1.1,
                                  ),
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  'home_explore_nearby'.tr(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 11.sp,
                                    color: muted,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.all(5.w),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.explore_outlined,
                              color: AppColors.primary,
                              size: 18.w,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 6.h),
                    _HomeCardTapFooter(label: 'home_explore_tap'.tr()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
