import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/muslim_colors.dart';
import '../models/muslim_models.dart';
import '../providers/muslim_providers.dart';
import '../../../core/widgets/glass/app_glass.dart';
import '../../../core/widgets/scroll_adaptive_foreground.dart';
import 'azkar_screen.dart';
import 'asma_ul_husna_screen.dart';
import 'duaa_screen.dart';
import 'prayer_times_screen.dart';
import '../widgets/muslim_widgets.dart';

double _islamicCornerHeaderOverlayHeight(BuildContext context) =>
    MediaQuery.viewPaddingOf(context).top + 8.h + 22.h + 8.h;

(double top, double bottom) _islamicCornerTitleBand(BuildContext context) {
  final bandTop = MediaQuery.viewPaddingOf(context).top + 8.h;
  return (bandTop, bandTop + 22.h);
}

class IslamicCornerHubScreen extends ConsumerStatefulWidget {
  const IslamicCornerHubScreen({super.key});

  @override
  ConsumerState<IslamicCornerHubScreen> createState() =>
      _IslamicCornerHubScreenState();
}

class _IslamicCornerHubScreenState extends ConsumerState<IslamicCornerHubScreen> {
  final _scrollController = ScrollController();
  double _prayerCardHeight = 180;

  @override
  void initState() {
    super.initState();
    _prayerCardHeight = 180.h;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onPrayerCardSizeChanged(Size size) {
    if ((size.height - _prayerCardHeight).abs() < 0.5) return;
    setState(() => _prayerCardHeight = size.height);
  }

  Color _resolveTitleBackground(double scrollOffset) {
    final isDark = context.isDark;
    final headerExtent = _islamicCornerHeaderOverlayHeight(context);
    final (bandTop, bandBottom) = _islamicCornerTitleBand(context);
    final fallbackBg = AppGlassTheme.dashboardBackgroundColor(isDark);

    return estimateBackdropColor(
      scrollOffset: scrollOffset,
      listPaddingTop: headerExtent + 8.h,
      bandTop: bandTop,
      bandBottom: bandBottom,
      fallbackColor: fallbackBg,
      segments: [
        ScrollBackdropSegment(
          height: _prayerCardHeight,
          color: context.mPrayerHeroFill,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bundleAsync = ref.watch(prayerBundleProvider);
    final namesAsync = ref.watch(asmaUlHusnaProvider);
    final isDark = context.isDark;
    final headerExtent = _islamicCornerHeaderOverlayHeight(context);
    final fadeBg = AppGlassTheme.dashboardBackgroundColor(isDark);

    return AppDashboardBackground(
      isDark: isDark,
      child: Stack(
        children: [
          Positioned.fill(
            child: RefreshIndicator(
              color: context.mPrimary,
              onRefresh: () async {
                ref.invalidate(prayerBundleProvider);
                ref.invalidate(asmaUlHusnaProvider);
                await ref.read(prayerBundleProvider.future);
              },
              child: ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  20.w,
                  headerExtent + 8.h,
                  20.w,
                  AppGlassTheme.dashboardScrollBottomPadding(context),
                ),
                children: [
                  MeasureSize(
                    onChange: _onPrayerCardSizeChanged,
                    child: bundleAsync.when(
                      data: (bundle) => _PrayerFeaturedCard(
                        bundle: bundle,
                        countdownMinutes: ref.watch(prayerCountdownProvider),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const PrayerTimesScreen(),
                          ),
                        ),
                      ),
                      loading: () => _PrayerFeaturedCard.loading(),
                      error: (_, _) => _PrayerFeaturedCard.error(
                        onRetry: () => ref.invalidate(prayerBundleProvider),
                      ),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 0.95,
                          child: _HubBentoCard(
                            title: 'muslim_azkar'.tr(),
                            subtitle: 'muslim_azkar_sub'.tr(),
                            icon: Symbols.wb_twilight,
                            tint: isDark
                                ? context.mPrimaryContainer.withValues(
                                    alpha: 0.92,
                                  )
                                : context.mPrimaryFixed.withValues(alpha: 0.35),
                            iconColor: context.mPrimary,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const AzkarScreen(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 16.w),
                      Expanded(
                        child: AspectRatio(
                          aspectRatio: 0.95,
                          child: _HubBentoCard(
                            title: 'muslim_duaa'.tr(),
                            subtitle: 'muslim_duaa_sub'.tr(),
                            icon: Symbols.folded_hands,
                            tint: isDark
                                ? const Color(0xFF3D2A18)
                                : context.mSecondaryFixed.withValues(
                                    alpha: 0.35,
                                  ),
                            iconColor: context.mSecondary,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const DuaaScreen(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  _HubWideCard(
                    title: 'muslim_99_names'.tr(),
                    subtitle: 'muslim_99_names_sub'.tr(),
                    icon: Symbols.star,
                    tint: isDark
                        ? context.mTertiaryContainer.withValues(alpha: 0.55)
                        : context.mOnTertiaryContainer.withValues(alpha: 0.12),
                    iconColor: context.mTertiary,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AsmaUlHusnaScreen(),
                      ),
                    ),
                  ),
                  SizedBox(height: 24.h),
                  namesAsync.when(
                    data: (names) {
                      if (names.isEmpty) return const SizedBox.shrink();
                      final dayIndex = DateTime.now().dayOfYear % names.length;
                      return _NameOfDayCard(name: names[dayIndex]);
                    },
                    loading: () => const _NameOfDayCard.loading(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AppScrollFadeOverlay(
                showBottom: false,
                topExtent: headerExtent,
                backgroundColor: fadeBg,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
                child: ScrollAdaptiveText(
                  controller: _scrollController,
                  text: 'muslim_corner_title'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w600,
                  ),
                  preferredLight: context.mPrimary,
                  preferredDark: Theme.of(context).colorScheme.onPrimary,
                  resolveBackground: _resolveTitleBackground,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrayerFeaturedCard extends StatelessWidget {
  const _PrayerFeaturedCard({
    required this.bundle,
    required this.countdownMinutes,
    required this.onTap,
  }) : onRetry = null;

  const _PrayerFeaturedCard.loading()
    : bundle = null,
      countdownMinutes = null,
      onTap = null,
      onRetry = null;

  const _PrayerFeaturedCard.error({required this.onRetry})
    : bundle = null,
      countdownMinutes = null,
      onTap = null;

  final PrayerBundle? bundle;
  final int? countdownMinutes;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;

  static const _displayPrayers = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha'];

  @override
  Widget build(BuildContext context) {
    if (bundle == null && onRetry != null) {
      return Material(
        color: context.mPrimaryContainer,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          onTap: onRetry,
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(24.w),
            child: Center(
              child: Text(
                'muslim_retry'.tr(),
                style: TextStyle(color: Colors.white, fontSize: 14.sp),
              ),
            ),
          ),
        ),
      );
    }

    if (bundle == null) {
      return Container(
        height: 180.h,
        decoration: BoxDecoration(
          color: context.mPrimaryContainer,
          borderRadius: BorderRadius.circular(16.r),
        ),
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: Colors.white),
      );
    }

    final data = bundle!.prayerTimes;
    final next = data.currentStatus.nextPrayer;
    final nextTime = data.prayerTimes[next] ?? '';
    final minutes = countdownMinutes ?? data.currentStatus.minutesUntilNext;

    return Material(
      color: context.mPrayerHeroFill,
      borderRadius: AppGlassTheme.cardRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppGlassTheme.cardRadius,
        child: Padding(
          padding: EdgeInsets.all(20.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'muslim_next_prayer'.tr().toUpperCase(),
                          style: TextStyle(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: context.mPrayerHeroLabel,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          '${formatPrayerLabel(next)} — ${formatPrayerTime12h(nextTime, context.locale)}',
                          style: TextStyle(
                            fontSize: 22.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10.w,
                            vertical: 4.h,
                          ),
                          decoration: BoxDecoration(
                            color: context.mPrayerHeroAccent,
                            borderRadius: BorderRadius.circular(999.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Symbols.schedule,
                                size: 14.w,
                                color: context.mPrayerHeroOnAccent,
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                'muslim_starts_in'.tr(
                                  args: [formatMinutesCountdown(minutes)],
                                ),
                                style: TextStyle(
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w700,
                                  color: context.mPrayerHeroOnAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Symbols.mosque,
                      size: 32.w,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final name in _displayPrayers)
                    _MiniPrayerSlot(
                      name: name,
                      time: data.prayerTimes[name] ?? '--:--',
                      isNext: name == next,
                      isCurrent: name == data.currentStatus.currentPrayer,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniPrayerSlot extends StatelessWidget {
  const _MiniPrayerSlot({
    required this.name,
    required this.time,
    required this.isNext,
    required this.isCurrent,
  });

  final String name;
  final String time;
  final bool isNext;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final highlighted = isNext || isCurrent;
    return Opacity(
      opacity: highlighted ? 1 : 0.6,
      child: Column(
        children: [
          Text(
            formatPrayerLabel(name),
            style: TextStyle(
              fontSize: 10.sp,
              fontWeight: FontWeight.w500,
              color: highlighted
                  ? context.mPrayerHeroAccent
                  : Colors.white.withValues(alpha: 0.85),
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            time.split(':').take(2).join(':'),
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: highlighted ? FontWeight.w700 : FontWeight.w600,
              color: highlighted
                  ? context.mPrayerHeroAccent
                  : Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _HubBentoCard extends StatelessWidget {
  const _HubBentoCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16.r);

    return Material(
      color: tint,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            PositionedDirectional(
              end: -4.w,
              bottom: -4.h,
              child: Icon(
                icon,
                size: 72.w,
                color: iconColor.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: context.isDark
                          ? context.mSurfaceContainerLow
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Icon(icon, color: iconColor, size: 22.w),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: iconColor,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: context.mCardSubtitle,
                    ),
                  ),
                ],
              ),
            ),
            PositionedDirectional(
              top: 12.h,
              end: 8.w,
              child: muslimForwardChevron(
                size: 18.w,
                color: iconColor.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on DateTime {
  int get dayOfYear {
    final startOfYear = DateTime(year, 1, 1);
    return difference(startOfYear).inDays;
  }
}

class _HubWideCard extends StatelessWidget {
  const _HubWideCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tint,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      isDark: context.isDark,
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: ColoredBox(
        color: tint,
        child: Stack(
          children: [
            PositionedDirectional(
              end: -10.w,
              bottom: -10.h,
              child: Icon(
                icon,
                size: 96.w,
                color: iconColor.withValues(alpha: 0.08),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      color: context.isDark
                          ? context.mSurfaceContainerLow
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Icon(icon, color: iconColor, size: 24.w),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                            color: iconColor,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: context.mCardSubtitle,
                          ),
                        ),
                      ],
                    ),
                  ),
                  muslimForwardChevron(
                    size: 20.w,
                    color: iconColor.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NameOfDayCard extends StatelessWidget {
  const _NameOfDayCard({required this.name});
  const _NameOfDayCard.loading() : name = null;

  final AsmaName? name;

  @override
  Widget build(BuildContext context) {
    final lang = context.locale.languageCode;
    final isAr = lang == 'ar';

    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: context.mSurfaceContainerLow,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: context.mOutlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'muslim_name_of_day'.tr(),
                style: TextStyle(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                  color: context.mPrimary,
                ),
              ),
              if (name != null)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: context.mPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6.r),
                  ),
                  child: Text(
                    '#${name!.number}',
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                      color: context.mPrimary,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 16.h),
          if (name == null)
            const Center(child: CircularProgressIndicator())
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: isAr
                        ? [
                            ArabicText(
                              name!.nameArabic,
                              style: muslimArabicStyle(
                                context,
                                fontSize: 32.sp,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.right,
                            ),
                            SizedBox(height: 4.h),
                            Text(
                              name!.transliteration,
                              style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                                color: context.mPrimary,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            Text(
                              name!.localizedMeaning(lang),
                              style: TextStyle(
                                fontFamily: 'Amiri',
                                fontSize: 13.sp,
                                height: 1.4,
                                color: context.mOnSurfaceVariant,
                              ),
                            ),
                          ]
                        : [
                            Text(
                              name!.transliteration,
                              style: TextStyle(
                                fontSize: 18.sp,
                                fontWeight: FontWeight.w700,
                                color: context.mOnSurface,
                              ),
                            ),
                            SizedBox(height: 6.h),
                            Text(
                              name!.localizedMeaning(lang),
                              style: TextStyle(
                                fontSize: 13.sp,
                                height: 1.4,
                                color: context.mOnSurfaceVariant,
                              ),
                            ),
                          ],
                  ),
                ),
                if (!isAr) ...[
                  SizedBox(width: 16.w),
                  ArabicText(
                    name!.nameArabic,
                    style: muslimArabicStyle(
                      context,
                      fontSize: 36.sp,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}
