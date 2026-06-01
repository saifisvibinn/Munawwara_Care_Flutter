import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/muslim_colors.dart';
import '../providers/muslim_providers.dart';
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
                    hijri.gregorianFormatted,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: MuslimColors.onSurfaceVariant,
                    ),
                  ),
                  if (hijri.hijri.formatted.isNotEmpty) ...[
                    SizedBox(height: 4.h),
                    Text(
                      hijri.hijri.formatted,
                      style: TextStyle(
                        fontFamily: 'Amiri',
                        fontSize: 15.sp,
                        color: MuslimColors.primary,
                      ),
                    ),
                  ],
                  SizedBox(height: 12.h),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: MuslimColors.secondaryContainer,
                      borderRadius: BorderRadius.circular(999.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Symbols.timer,
                          size: 16.w,
                          color: MuslimColors.onSecondaryContainer,
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
                            color: MuslimColors.onSecondaryContainer,
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
                  color: MuslimColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: MuslimColors.outlineVariant.withValues(alpha: 0.35),
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
            ? MuslimColors.secondaryFixed.withValues(alpha: 0.15)
            : null,
        border: active
            ? Border(
                left: BorderSide(
                  color: MuslimColors.secondaryContainer,
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
                    padding: EdgeInsets.only(right: 10.w),
                    child: Icon(
                      Symbols.wb_twilight,
                      color: MuslimColors.secondary,
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
                          color: active ? MuslimColors.primary : MuslimColors.onSurface,
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
                      formatPrayerTime12h(time),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: active ? 17.sp : 14.sp,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active
                            ? MuslimColors.primary
                            : MuslimColors.onSurfaceVariant,
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
                          color: MuslimColors.secondary,
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
              color: MuslimColors.outlineVariant.withValues(alpha: 0.25),
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
              ? MuslimColors.secondary.withValues(alpha: 0.18)
              : MuslimColors.outlineVariant.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          isPlaying ? Symbols.stop : Symbols.play_arrow,
          size: 14.w,
          color: isPlaying ? MuslimColors.secondary : MuslimColors.onSurfaceVariant,
        ),
      ),
    );
  }
}
