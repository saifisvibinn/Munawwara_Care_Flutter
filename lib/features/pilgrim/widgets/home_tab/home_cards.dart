import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';
import '../../helpers/moderator_navigation.dart';
import '../../providers/pilgrim_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Weather Alert Model
// ─────────────────────────────────────────────────────────────────────────────

class WeatherAlert {
  final int temperatureC;
  /// easy_localization key, e.g. `weather_sunny`.
  final String conditionKey;
  /// Dashboard card tip key (`weather_card_*`).
  final String cardTipKey;
  /// Detail sheet body key (`weather_reminder_*`).
  final String detailTipKey;
  final IconData icon;
  final Color iconColor;
  final bool isLoading;
  final bool isError;

  const WeatherAlert({
    required this.temperatureC,
    required this.conditionKey,
    required this.cardTipKey,
    required this.detailTipKey,
    required this.icon,
    required this.iconColor,
    required this.isLoading,
    required this.isError,
  });

  const WeatherAlert.loading()
    : temperatureC = 0,
      conditionKey = '',
      cardTipKey = '',
      detailTipKey = '',
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
                              : alert.conditionKey.tr(),
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
                alert.detailTipKey.tr(),
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                            : alert.conditionKey.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? AppColors.primary
                              : AppColors.primaryDark,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Expanded(
                        child: Text(
                          alert.isLoading
                              ? 'weather_loading_hint_short'.tr()
                              : alert.isError
                              ? 'weather_card_error_short'.tr()
                              : alert.cardTipKey.tr(),
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
                if (!alert.isLoading && !alert.isError)
                  Container(
                    padding: EdgeInsets.all(5.w),
                    decoration: BoxDecoration(
                      color: alert.iconColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      alert.icon,
                      color: alert.iconColor,
                      size: 18.w,
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
      height: 126.h,
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
  final List<ModeratorInfo> moderators;
  final String? createdBy;
  final String hotelName;
  final String busNumber;
  final String checkIn;
  final VoidCallback onTap;

  const GroupCard({
    super.key,
    required this.groupName,
    required this.moderators,
    this.createdBy,
    required this.hotelName,
    required this.busNumber,
    required this.checkIn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final noRecordsText = 'no_records_available'.tr();
    final sorted = sortedGroupModerators(moderators, createdBy: createdBy);

    final cardBg = isDark ? const Color(0xFF1D2641) : Colors.white;
    final labelColor =
        isDark ? const Color(0xFF94A3B8) : AppColors.textMutedDark;
    final valueColor = isDark ? Colors.white : AppColors.textDark;
    final valueMutedColor =
        isDark ? const Color(0xFF64748B) : AppColors.textMutedDark;

    final labelStyle = TextStyle(
      fontFamily: 'Lexend',
      fontSize: 10.sp,
      fontWeight: FontWeight.w800,
      color: labelColor,
      letterSpacing: 0.5,
    );
    final valueStyle = TextStyle(
      fontFamily: 'Lexend',
      fontSize: 14.sp,
      fontWeight: FontWeight.w800,
      color: valueColor,
    );
    final valueItalicStyle = TextStyle(
      fontFamily: 'Lexend',
      fontSize: 14.sp,
      fontWeight: FontWeight.w500,
      color: valueMutedColor,
      fontStyle: FontStyle.italic,
    );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16.w, 11.h, 16.w, 9.h),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24.r),
          border: isDark
              ? null
              : Border.all(color: AppColors.dividerLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'home_my_group'.tr().toUpperCase(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 10.sp,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
                letterSpacing: 0.8,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              groupName,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 19.sp,
                fontWeight: FontWeight.w800,
                color: valueColor,
              ),
            ),
            SizedBox(height: 9.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _GroupCardModeratorSummary(
                    moderators: sorted,
                    noRecordsText: noRecordsText,
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                    valueMutedColor: valueMutedColor,
                    isDark: isDark,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _GroupCardInfoCell(
                    label: 'group_hotel_name'.tr().toUpperCase(),
                    value: hotelName.isNotEmpty ? hotelName : 'group_not_set'.tr(),
                    hasValue: hotelName.isNotEmpty,
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                    valueItalicStyle: valueItalicStyle,
                  ),
                ),
              ],
            ),
            SizedBox(height: 7.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _GroupCardInfoCell(
                    label: 'group_checkin'.tr().toUpperCase(),
                    value: checkIn.isNotEmpty ? checkIn : 'group_not_set'.tr(),
                    hasValue: checkIn.isNotEmpty,
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                    valueItalicStyle: valueItalicStyle,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: _GroupCardInfoCell(
                    label: 'group_bus_label'.tr().toUpperCase(),
                    value: busNumber.isNotEmpty ? busNumber : 'group_not_set'.tr(),
                    hasValue: busNumber.isNotEmpty,
                    labelStyle: labelStyle,
                    valueStyle: valueStyle,
                    valueItalicStyle: valueItalicStyle,
                  ),
                ),
              ],
            ),
            SizedBox(height: 9.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 8.h),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: isDark ? 0.1 : 0.12),
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Text(
                'home_view_group_details'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCardModeratorSummary extends StatelessWidget {
  const _GroupCardModeratorSummary({
    required this.moderators,
    required this.noRecordsText,
    required this.labelStyle,
    required this.valueStyle,
    required this.valueMutedColor,
    required this.isDark,
  });

  final List<ModeratorInfo> moderators;
  final String noRecordsText;
  final TextStyle labelStyle;
  final TextStyle valueStyle;
  final Color valueMutedColor;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (moderators.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('group_moderator_section'.tr().toUpperCase(), style: labelStyle),
          SizedBox(height: 6.h),
          Text(
            noRecordsText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: valueStyle.copyWith(
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: valueMutedColor,
            ),
          ),
        ],
      );
    }

    final leader = moderators.first;
    final coModCount = moderators.length - 1;
    final initial = leader.fullName.isNotEmpty
        ? leader.fullName[0].toUpperCase()
        : '?';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('group_moderator_section'.tr().toUpperCase(), style: labelStyle),
        SizedBox(height: 6.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 13.r,
              backgroundColor: AppColors.primary.withValues(
                alpha: isDark ? 0.22 : 0.12,
              ),
              child: Text(
                initial,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w800,
                  fontSize: 11.sp,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            SizedBox(width: 6.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    leader.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle,
                  ),
                  if (coModCount > 0)
                    Padding(
                      padding: EdgeInsets.only(top: 2.h),
                      child: Text(
                        'home_co_moderators_count'.tr(
                          namedArgs: {'count': coModCount.toString()},
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                          color: valueMutedColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupCardInfoCell extends StatelessWidget {
  const _GroupCardInfoCell({
    required this.label,
    required this.value,
    required this.hasValue,
    required this.labelStyle,
    required this.valueStyle,
    required this.valueItalicStyle,
  });

  final String label;
  final String value;
  final bool hasValue;
  final TextStyle labelStyle;
  final TextStyle valueStyle;
  final TextStyle valueItalicStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: labelStyle),
        SizedBox(height: 6.h),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: hasValue ? valueStyle : valueItalicStyle,
        ),
      ],
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
      height: 126.h,
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
