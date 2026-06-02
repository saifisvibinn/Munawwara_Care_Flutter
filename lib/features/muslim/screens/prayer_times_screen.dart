import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/muslim_colors.dart';
import '../providers/muslim_providers.dart';
import '../utils/muslim_localization.dart';
import '../widgets/muslim_widgets.dart';
import '../widgets/qibla_compass_widget.dart';

class PrayerTimesScreen extends ConsumerWidget {
  const PrayerTimesScreen({super.key});

  static const _orderedKeys = [
    'imsak',
    'fajr',
    'sunrise',
    'dhuhr',
    'asr',
    'maghrib',
    'isha',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bundleAsync = ref.watch(prayerBundleProvider);
    final countdown = ref.watch(prayerCountdownProvider);

    return MuslimScreenScaffold(
      title: 'muslim_prayer_times'.tr(),
      onRefresh: () async {
        ref.invalidate(prayerBundleProvider);
        await ref.read(prayerBundleProvider.future);
      },
      body: bundleAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(prayerBundleProvider),
            child: Text('muslim_retry'.tr()),
          ),
        ),
        data: (bundle) {
          final pt = bundle.prayerTimes;
          final hijri = bundle.hijri;
          final next = pt.currentStatus.nextPrayer;
          final current = pt.currentStatus.currentPrayer;
          final minutes = countdown ?? pt.currentStatus.minutesUntilNext;

          return ListView(
            padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 32.h),
            children: [
              Column(
                children: [
                  Text(
                    formatGregorianDateLocalized(
                      locale: context.locale,
                      isoDate: pt.date,
                      apiFallback: hijri.gregorianFormatted,
                    ),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: context.mOnSurfaceVariant,
                    ),
                  ),
                  if (hijri.hijri.day > 0) ...[
                    SizedBox(height: 4.h),
                    Text(
                      formatHijriDateLocalized(hijri.hijri),
                      style: TextStyle(
                        fontFamily: 'Amiri',
                        fontSize: 15.sp,
                        color: context.mPrimary,
                      ),
                    ),
                  ],
                  SizedBox(height: 12.h),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: context.mSecondaryContainer,
                      borderRadius: BorderRadius.circular(999.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Symbols.timer,
                          size: 16.w,
                          color: context.mOnSecondaryContainer,
                        ),
                        SizedBox(width: 6.w),
                        Text(
                          'muslim_next_in'.tr(
                            args: [
                              formatPrayerLabel(next),
                              formatMinutesCountdown(minutes),
                            ],
                          ),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: context.mOnSecondaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              Container(
                decoration: BoxDecoration(
                  color: context.mSurfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: context.mOutlineVariant.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < _orderedKeys.length; i++)
                      _PrayerRow(
                        name: _orderedKeys[i],
                        time: pt.prayerTimes[_orderedKeys[i]] ?? '--:--',
                        isCurrent: _orderedKeys[i] == current,
                        isNext: _orderedKeys[i] == next,
                        showDivider: i < _orderedKeys.length - 1,
                      ),
                  ],
                ),
              ),
              SizedBox(height: 24.h),
              QiblaCompassWidget(qibla: bundle.qibla),
            ],
          );
        },
      ),
    );
  }
}

class _PrayerRow extends ConsumerWidget {
  const _PrayerRow({
    required this.name,
    required this.time,
    required this.isCurrent,
    required this.isNext,
    required this.showDivider,
  });

  final String name;
  final String time;
  final bool isCurrent;
  final bool isNext;
  final bool showDivider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = isCurrent || isNext;
    final playable = const ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha']
        .contains(name.toLowerCase());

    return Container(
      decoration: BoxDecoration(
        color: active
            ? context.mSecondaryFixed.withValues(alpha: 0.15)
            : null,
        border: active
            ? BorderDirectional(
                start: BorderSide(
                  color: context.mSecondaryContainer,
                  width: 4.w,
                ),
              )
            : null,
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: active ? 18.h : 14.h),
            child: Row(
              children: [
                if (active)
                  Padding(
                    padding: EdgeInsetsDirectional.only(end: 10.w),
                    child: Icon(
                      Symbols.wb_twilight,
                      color: context.mSecondary,
                      size: 22.w,
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        formatPrayerLabel(name),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: active ? 17.sp : 14.sp,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                          color: active ? context.mPrimary : context.mOnSurface,
                        ),
                      ),
                      if (playable) ...[
                        SizedBox(width: 8.w),
                        _PrayerPlayButton(name: name),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatPrayerTime12h(time, context.locale),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: active ? 17.sp : 14.sp,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active
                            ? context.mPrimary
                            : context.mOnSurfaceVariant,
                      ),
                    ),
                    if (isCurrent)
                      Text(
                        'muslim_current'.tr().toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 9.sp,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: context.mSecondary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              indent: 20.w,
              endIndent: 20.w,
              color: context.mOutlineVariant.withValues(alpha: 0.25),
            ),
        ],
      ),
    );
  }
}

class _PrayerPlayButton extends ConsumerWidget {
  const _PrayerPlayButton({required this.name});

  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playingName = ref.watch(playingPrayerSoundProvider);
    final isPlaying = playingName == name;

    return GestureDetector(
      onTap: () {
        final notifier = ref.read(playingPrayerSoundProvider.notifier);
        if (isPlaying) {
          notifier.stop();
        } else {
          notifier.play(name);
        }
      },
      child: Container(
        padding: EdgeInsets.all(5.w),
        decoration: BoxDecoration(
          color: isPlaying
              ? context.mSecondary.withValues(alpha: 0.18)
              : context.mOutlineVariant.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isPlaying ? Symbols.stop : Symbols.play_arrow,
          size: 14.w,
          color: isPlaying ? context.mSecondary : context.mOnSurfaceVariant,
        ),
      ),
    );
  }
}
