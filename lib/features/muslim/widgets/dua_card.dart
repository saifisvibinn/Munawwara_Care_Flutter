import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/muslim_colors.dart';
import '../models/muslim_models.dart';
import '../providers/muslim_providers.dart';
import 'muslim_widgets.dart';

class DuaCard extends ConsumerWidget {
  const DuaCard({super.key, required this.dua});

  final DuaItem dua;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counter = ref.watch(duaTapCounterProvider.notifier);
    final remaining = counter.remaining(dua);
    final complete = remaining <= 0;

    return Material(
      color: MuslimColors.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: complete ? null : () => counter.tap(dua),
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: MuslimColors.primary.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (dua.title != null && dua.title!.isNotEmpty) ...[
                Text(
                  dua.title!,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: MuslimColors.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: 8.h),
              ],
              ArabicText(
                dua.arabic,
                style: muslimArabicStyle(fontSize: 22.sp),
              ),
              SizedBox(height: 12.h),
              Text(
                dua.transliteration,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 14.sp,
                  fontStyle: FontStyle.italic,
                  height: 1.45,
                  color: MuslimColors.onSurfaceVariant.withValues(alpha: 0.85),
                ),
              ),
              SizedBox(height: 10.h),
              Container(
                padding: EdgeInsets.only(left: 12.w),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: MuslimColors.primary.withValues(alpha: 0.2),
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  dua.translation,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    height: 1.45,
                    color: MuslimColors.onSurface,
                  ),
                ),
              ),
              if (dua.source.isNotEmpty) ...[
                SizedBox(height: 10.h),
                Text(
                  dua.source,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.sp,
                    color: MuslimColors.onSurfaceVariant,
                  ),
                ),
              ],
              SizedBox(height: 16.h),
              Align(
                alignment: Alignment.centerRight,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 48.w,
                  height: 48.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: complete
                        ? MuslimColors.primaryContainer
                        : MuslimColors.surface,
                    border: Border.all(
                      color: complete
                          ? MuslimColors.primaryContainer
                          : MuslimColors.primary,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: complete
                      ? Icon(
                          Symbols.check,
                          color: MuslimColors.onPrimaryContainer,
                          size: 22.w,
                        )
                      : Text(
                          '$remaining×',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: MuslimColors.primary,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
