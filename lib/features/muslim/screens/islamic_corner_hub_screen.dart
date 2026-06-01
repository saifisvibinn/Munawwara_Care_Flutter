import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/muslim_colors.dart';
import '../models/muslim_models.dart';
import '../providers/muslim_providers.dart';
import '../screens/azkar_screen.dart';
import '../screens/duaa_screen.dart';
import '../screens/hadith_screen.dart';
import '../screens/prayer_times_screen.dart';
import '../screens/asma_ul_husna_screen.dart';
import '../widgets/muslim_widgets.dart';

class IslamicCornerHubScreen extends ConsumerWidget {
  const IslamicCornerHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? MuslimColors.surfaceDark : MuslimColors.surface;
    final bundleAsync = ref.watch(prayerBundleProvider);
    final hadithAsync = ref.watch(randomHadithProvider);

    return ColoredBox(
      color: bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
              child: Text(
                'muslim_corner_title'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: isDark ? MuslimColors.onSurfaceDark : MuslimColors.primary,
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: MuslimColors.primary,
                onRefresh: () async {
                  ref.invalidate(prayerBundleProvider);
                  ref.invalidate(randomHadithProvider);
                  await ref.read(prayerBundleProvider.future);
                },
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
                  children: [
                    bundleAsync.when(
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
                    SizedBox(height: 24.h),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 16.h,
                      crossAxisSpacing: 16.w,
                      childAspectRatio: 0.95,
                      children: [
                        _HubBentoCard(
                          title: 'muslim_azkar'.tr(),
                          subtitle: 'muslim_azkar_sub'.tr(),
                          icon: Symbols.schedule,
                          tint: MuslimColors.primaryFixed.withValues(alpha: 0.35),
                          iconColor: MuslimColors.primary,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AzkarScreen(),
                            ),
                          ),
                        ),
                        _HubBentoCard(
                          title: 'muslim_duaa'.tr(),
                          subtitle: 'muslim_duaa_sub'.tr(),
                          icon: Symbols.pan_tool,
                          tint: MuslimColors.secondaryFixed.withValues(alpha: 0.35),
                          iconColor: MuslimColors.secondary,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const DuaaScreen(),
                            ),
                          ),
                        ),
                        _HubBentoCard(
                          title: 'muslim_hadith'.tr(),
                          subtitle: 'muslim_hadith_sub'.tr(),
                          icon: Symbols.menu_book,
                          tint: MuslimColors.tertiaryFixed.withValues(alpha: 0.55),
                          iconColor: MuslimColors.tertiaryContainer,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const HadithScreen(),
                            ),
                          ),
                        ),
                        _HubBentoCard(
                          title: 'muslim_99_names'.tr(),
                          subtitle: 'muslim_99_names_sub'.tr(),
                          icon: Symbols.star,
                          tint: MuslimColors.onTertiaryContainer.withValues(alpha: 0.12),
                          iconColor: MuslimColors.tertiary,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const AsmaUlHusnaScreen(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 24.h),
                    hadithAsync.when(
                      data: (hadith) => _HadithOfDayCard(hadith: hadith),
                      loading: () => const _HadithOfDayCard.loading(),
                      error: (_, _) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrayerFeaturedCard extends StatelessWidget {
  const _PrayerFeaturedCard({
    required this.bundle,
    required this.countdownMinutes,
    required this.onTap,
  })  : onRetry = null;

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
        color: MuslimColors.primaryContainer,
        borderRadius: BorderRadius.circular(16.r),
        child: InkWell(
          onTap: onRetry,
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(24.w),
            child: Center(
              child: Text(
                'muslim_retry'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  color: Colors.white,
                  fontSize: 14.sp,
                ),
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
          color: MuslimColors.primaryContainer,
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
      color: MuslimColors.primary,
      borderRadius: BorderRadius.circular(16.r),
      elevation: 4,
      shadowColor: MuslimColors.primary.withValues(alpha: 0.35),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
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
                            fontFamily: 'Lexend',
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                            color: MuslimColors.secondaryFixed.withValues(alpha: 0.85),
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          '${formatPrayerLabel(next)} — ${formatPrayerTime12h(nextTime)}',
                          style: TextStyle(
                            fontFamily: 'Lexend',
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
                            color: MuslimColors.secondaryContainer,
                            borderRadius: BorderRadius.circular(999.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Symbols.schedule,
                                size: 14.w,
                                color: MuslimColors.onSecondaryContainer,
                              ),
                              SizedBox(width: 4.w),
                              Text(
                                'muslim_starts_in'.tr(
                                  args: [formatMinutesCountdown(minutes)],
                                ),
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w700,
                                  color: MuslimColors.onSecondaryContainer,
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
              fontFamily: 'Lexend',
              fontSize: 10.sp,
              fontWeight: FontWeight.w500,
              color: highlighted
                  ? MuslimColors.secondaryContainer
                  : Colors.white,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            time.split(':').take(2).join(':'),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12.sp,
              fontWeight: highlighted ? FontWeight.w700 : FontWeight.w600,
              color: highlighted
                  ? MuslimColors.secondaryContainer
                  : Colors.white,
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
    return Material(
      color: tint,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Stack(
          children: [
            Positioned(
              right: -4.w,
              bottom: -4.h,
              child: Icon(icon, size: 72.w, color: iconColor.withValues(alpha: 0.08)),
            ),
            Padding(
              padding: EdgeInsets.all(16.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                    child: Icon(icon, color: iconColor, size: 22.w),
                  ),
                  const Spacer(),
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: iconColor,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 11.sp,
                      color: MuslimColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12.h,
              right: 8.w,
              child: Icon(
                Symbols.chevron_right,
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

class _HadithOfDayCard extends StatelessWidget {
  const _HadithOfDayCard({required this.hadith});

  const _HadithOfDayCard.loading() : hadith = null;

  final HadithData? hadith;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: MuslimColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: MuslimColors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'muslim_hadith_of_day'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: MuslimColors.primary,
            ),
          ),
          SizedBox(height: 12.h),
          if (hadith == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            Text(
              '"${hadith!.english}"',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                fontStyle: FontStyle.italic,
                height: 1.5,
                color: MuslimColors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              '— ${hadith!.collectionName} · #${hadith!.hadithNumber}',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 11.sp,
                color: MuslimColors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
