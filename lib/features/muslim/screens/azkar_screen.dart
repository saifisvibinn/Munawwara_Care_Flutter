import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../constants/muslim_colors.dart';
import '../providers/muslim_providers.dart';
import '../widgets/dua_card.dart';
import '../widgets/muslim_widgets.dart';

class AzkarScreen extends ConsumerWidget {
  const AzkarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(duaI18nReadyProvider);
    final period = ref.watch(azkarPeriodProvider);
    final duasAsync = ref.watch(azkarDuasProvider);

    return MuslimScreenScaffold(
      title: 'muslim_azkar'.tr(),
      onRefresh: () async {
        ref.invalidate(azkarDuasProvider);
        await ref.read(azkarDuasProvider.future);
      },
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
            child: Container(
              padding: EdgeInsets.all(4.w),
              decoration: BoxDecoration(
                color: context.mSurfaceContainerLow,
                borderRadius: BorderRadius.circular(999.r),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _PeriodTab(
                      label: 'muslim_morning'.tr(),
                      selected: period == AzkarPeriod.morning,
                      onTap: () => ref
                          .read(azkarPeriodProvider.notifier)
                          .setPeriod(AzkarPeriod.morning),
                    ),
                  ),
                  Expanded(
                    child: _PeriodTab(
                      label: 'muslim_evening'.tr(),
                      selected: period == AzkarPeriod.evening,
                      onTap: () => ref
                          .read(azkarPeriodProvider.notifier)
                          .setPeriod(AzkarPeriod.evening),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: duasAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: TextButton(
                  onPressed: () => ref.invalidate(azkarDuasProvider),
                  child: Text('muslim_retry'.tr()),
                ),
              ),
              data: (duas) => ListView.separated(
                padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 24.h),
                itemCount: duas.length,
                separatorBuilder: (_, _) => SizedBox(height: 16.h),
                itemBuilder: (_, index) => DuaCard(dua: duas[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeriodTab extends StatelessWidget {
  const _PeriodTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? context.mPrimaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(999.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999.r),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12.h),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: selected
                  ? context.mOnPrimaryContainer
                  : context.mOnSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
