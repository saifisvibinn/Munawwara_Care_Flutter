import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'dart:math' as math;

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
                    child: Icon(
                      alert.icon,
                      color: alert.iconColor,
                      size: 36.sp,
                    ),
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
                              color: isDark ? Colors.white : AppColors.textDark,
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
                            color: isDark
                                ? AppColors.primary
                                : AppColors.primaryDark,
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
                      : (isDark
                            ? AppColors.textMutedLight
                            : AppColors.textMutedDark),
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
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
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
      color: isDark
          ? (isInteractive ? AppColors.primary.withValues(alpha: 0.35) : AppColors.dividerDark)
          : const Color(0xFFFFEDD5), // Exact Tailwind border-orange-100 from code.html
      width: isInteractive ? 1.2 : 1,
    ),
    boxShadow: [
      BoxShadow(
        color: AppColors.primary.withValues(alpha: isInteractive ? 0.14 : 0.05),
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

  const WeatherCard({super.key, required this.alert, this.onTapOpenDetail});

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
                    child: Icon(alert.icon, color: alert.iconColor, size: 18.w),
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
      height: 146.h,
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
// Scoop Card Painters and Grid Cards
// ─────────────────────────────────────────────────────────────────────────────

enum CardPosition { topLeft, topRight, bottomLeft, bottomRight }

/// Home action hub: 2×2 flush white tiles + centered SOS (design mock).
class ActionHubGrid extends StatelessWidget {
  final Widget topLeft;
  final Widget topRight;
  final Widget bottomLeft;
  final Widget bottomRight;
  final Widget sosButton;

  const ActionHubGrid({
    super.key,
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    required this.sosButton,
  });

  static const Color _hubBorder = Color(0xFFFFEDD5);
  static const Color _hubDivider = Color(0xFFF0E4D4);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outerRadius = BorderRadius.circular(28.r);
    const divider = VerticalDivider(
      width: 1,
      thickness: 1,
      color: _hubDivider,
    );
    const rowDivider = Divider(
      height: 1,
      thickness: 1,
      color: _hubDivider,
    );

    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: outerRadius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: outerRadius,
                border: isDark
                    ? null
                    : Border.all(color: _hubBorder, width: 1),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: topLeft),
                        if (!isDark) divider,
                        Expanded(child: topRight),
                      ],
                    ),
                  ),
                  if (!isDark) rowDivider,
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: bottomLeft),
                        if (!isDark) divider,
                        Expanded(child: bottomRight),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          sosButton,
        ],
      ),
    );
  }
}

class ScoopedGridCard extends StatelessWidget {
  final CardPosition position;
  final Widget icon;
  final String title;
  final String subtext;
  final VoidCallback onTap;

  const ScoopedGridCard({
    super.key,
    required this.position,
    required this.icon,
    required this.title,
    required this.subtext,
    required this.onTap,
  });

  Alignment _arrowAlignment(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final pos = isRtl
        ? switch (position) {
            CardPosition.topLeft => CardPosition.topRight,
            CardPosition.topRight => CardPosition.topLeft,
            CardPosition.bottomLeft => CardPosition.bottomRight,
            CardPosition.bottomRight => CardPosition.bottomLeft,
          }
        : position;
    return switch (pos) {
      CardPosition.topLeft => Alignment.topLeft,
      CardPosition.topRight => Alignment.topRight,
      CardPosition.bottomLeft => Alignment.bottomLeft,
      CardPosition.bottomRight => Alignment.bottomRight,
    };
  }

  double _arrowRotation(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final pos = isRtl
        ? switch (position) {
            CardPosition.topLeft => CardPosition.topRight,
            CardPosition.topRight => CardPosition.topLeft,
            CardPosition.bottomLeft => CardPosition.bottomRight,
            CardPosition.bottomRight => CardPosition.bottomLeft,
          }
        : position;

    if (isRtl) {
      return switch (pos) {
        CardPosition.topLeft => math.pi / 4,
        CardPosition.topRight => 3 * math.pi / 4,
        CardPosition.bottomLeft => -math.pi / 4,
        CardPosition.bottomRight => -3 * math.pi / 4,
      };
    } else {
      return switch (pos) {
        CardPosition.topLeft => -3 * math.pi / 4,
        CardPosition.topRight => -math.pi / 4,
        CardPosition.bottomLeft => 3 * math.pi / 4,
        CardPosition.bottomRight => math.pi / 4,
      };
    }
  }

  /// Slight nudge of label block toward each quadrant's outer corner.
  Alignment _contentAlignment(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final pos = isRtl
        ? switch (position) {
            CardPosition.topLeft => CardPosition.topRight,
            CardPosition.topRight => CardPosition.topLeft,
            CardPosition.bottomLeft => CardPosition.bottomRight,
            CardPosition.bottomRight => CardPosition.bottomLeft,
          }
        : position;
    const nudge = 0.16;
    return switch (pos) {
      CardPosition.topLeft => Alignment(-nudge, -nudge),
      CardPosition.topRight => Alignment(nudge, -nudge),
      CardPosition.bottomLeft => Alignment(-nudge, nudge),
      CardPosition.bottomRight => Alignment(nudge, nudge),
    };
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor =
        isDark ? Colors.white : const Color(0xFF154212);
    final subColor = isDark ? AppColors.textMutedLight : const Color(0xFF6B7280);
    final arrowColor = isDark
        ? AppColors.textMutedLight.withValues(alpha: 0.7)
        : const Color(0xFFF97316).withValues(alpha: 0.5);

    return Material(
      color: isDark ? AppColors.surfaceDark : Colors.white,
      child: InkWell(
        onTap: onTap,
        splashColor: AppColors.primary.withValues(alpha: 0.08),
        highlightColor: AppColors.primary.withValues(alpha: 0.04),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Align(
              alignment: _contentAlignment(context),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    icon,
                    SizedBox(height: 6.h),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: titleColor,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      subtext,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                        color: subColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.fromLTRB(10.w, 10.h, 10.w, 10.h),
                child: Align(
                  alignment: _arrowAlignment(context),
                  child: Transform.rotate(
                    angle: _arrowRotation(context),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11.sp,
                      color: arrowColor,
                    ),
                  ),
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
// Group Card (Revamped with watermark and premium style)
// ─────────────────────────────────────────────────────────────────────────────

class GroupCard extends StatelessWidget {
  final String groupName;
  final List<ModeratorInfo> moderators;
  final String? createdBy;
  final String hotelName;
  final String checkIn;
  final VoidCallback onTap;

  const GroupCard({
    super.key,
    required this.groupName,
    required this.moderators,
    this.createdBy,
    required this.hotelName,
    required this.checkIn,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final noRecordsText = 'no_records_available'.tr();
    final sorted = sortedGroupModerators(moderators, createdBy: createdBy);

    final cardBg = isDark ? const Color(0xFF1D2641) : Colors.white;
    final labelColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    final valueColor = isDark
        ? Colors.white
        : const Color(0xFF0F3E1F); // Dark Green
    final bodyValueColor = isDark ? Colors.white : Colors.black87;
    final valueMutedColor = isDark
        ? const Color(0xFF64748B)
        : AppColors.textMutedDark;

    final labelStyle = TextStyle(
      fontFamily: 'Lexend',
      fontSize: 10.sp,
      fontWeight: FontWeight.w800,
      color: labelColor,
      letterSpacing: 0.5,
    );

    final leaderName = sorted.isNotEmpty
        ? sorted.first.fullName
        : noRecordsText;
    final coModCount = sorted.length - 1;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24.r),
          border: isDark ? null : Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.12 : 0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24.r),
          child: Stack(
            children: [
              // Background Watermark Logo
              Positioned(
                right: -90.w,
                bottom: -60.h,
                child: Opacity(
                  opacity: isDark ? 0.06 : 0.1,
                  child: Image.asset(
                    'assets/static/inapp_icon.png',
                    fit: BoxFit.contain,
                    width: 400.w,
                  ),
                ),
              ),
              // Card Content
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 18.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'home_my_group'.tr().toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFF97316), // Premium Orange
                        letterSpacing: 0.8,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      groupName,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 26.sp,
                        fontWeight: FontWeight.w800,
                        color: valueColor,
                      ),
                    ),
                    SizedBox(height: 18.h),
                    // 2x2 Info Grid
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Moderator Section
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'group_moderator_section'.tr().toUpperCase(),
                                style: labelStyle,
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                leaderName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w700,
                                  color: bodyValueColor,
                                ),
                              ),
                              if (coModCount > 0)
                                Text(
                                  'home_co_moderators_count'.tr(
                                    namedArgs: {'count': coModCount.toString()},
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 11.sp,
                                    color: valueMutedColor,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12.w),
                        // Hotel Name
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'group_hotel_name'.tr().toUpperCase(),
                                style: labelStyle,
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                hotelName.isNotEmpty
                                    ? hotelName
                                    : 'group_not_set'.tr(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w700,
                                  color: bodyValueColor,
                                  fontStyle: hotelName.isEmpty
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Check-in
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'group_checkin'.tr().toUpperCase(),
                                style: labelStyle,
                              ),
                              SizedBox(height: 4.h),
                              Text(
                                checkIn.isNotEmpty
                                    ? checkIn
                                    : 'group_not_set'.tr(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w700,
                                  color: bodyValueColor,
                                  fontStyle: checkIn.isEmpty
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20.h),
                    // "View full group details" centered orange link
                    Center(
                      child: Text(
                        'home_view_group_details'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFC2410C), // Deep Orange/Brown
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
      height: 146.h,
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

// ─────────────────────────────────────────────────────────────────────────────
// Active Attendance Card (Pilgrim-side)
// ─────────────────────────────────────────────────────────────────────────────

class ActiveAttendanceCard extends StatefulWidget {
  final ActiveBoardingSession session;
  final VoidCallback onTap;

  const ActiveAttendanceCard({
    super.key,
    required this.session,
    required this.onTap,
  });

  @override
  State<ActiveAttendanceCard> createState() => _ActiveAttendanceCardState();
}

class _ActiveAttendanceCardState extends State<ActiveAttendanceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAttended = widget.session.attended;

    final cardBg = isAttended
        ? (isDark
            ? AppColors.success.withValues(alpha: 0.08)
            : AppColors.success.withValues(alpha: 0.04))
        : (isDark ? const Color(0xFF1E1E2D) : Colors.white);

    final borderColor = isAttended
        ? AppColors.success.withValues(alpha: 0.35)
        : (isDark
            ? AppColors.primary.withValues(alpha: 0.4)
            : const Color(0xFFFFEDD5));

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(
          color: borderColor,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isAttended
                ? AppColors.success.withValues(alpha: 0.04)
                : AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.r),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isAttended ? null : widget.onTap,
            splashColor: AppColors.primary.withValues(alpha: 0.12),
            highlightColor: AppColors.primary.withValues(alpha: 0.06),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 18.h),
              child: Row(
                children: [
                  // Icon container
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: isAttended
                          ? AppColors.success.withValues(alpha: 0.12)
                          : AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isAttended ? Icons.check_circle_rounded : Icons.directions_bus_rounded,
                      color: isAttended ? AppColors.success : AppColors.primary,
                      size: 28.sp,
                    ),
                  ),
                  SizedBox(width: 16.w),
                  // Text details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              isAttended ? 'attendance_checked_in'.tr() : 'attendance_title'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w800,
                                color: isAttended
                                    ? AppColors.success
                                    : (isDark ? Colors.white : AppColors.textDark),
                              ),
                            ),
                            if (!isAttended) ...[
                              SizedBox(width: 8.w),
                              // Blinking active indicator
                              FadeTransition(
                                opacity: _pulseAnimation,
                                child: Container(
                                  width: 8.w,
                                  height: 8.w,
                                  decoration: const BoxDecoration(
                                    color: AppColors.success,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          widget.session.busIdentifier.isNotEmpty
                              ? widget.session.busIdentifier
                              : 'Bus / Trip Boarding',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13.sp,
                            color: isAttended
                                ? (isDark ? Colors.white60 : AppColors.textMutedDark)
                                : (isDark ? AppColors.textMutedLight : AppColors.textMutedDark),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Action indicator / arrow
                  if (!isAttended)
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16.sp,
                      color: AppColors.primary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
