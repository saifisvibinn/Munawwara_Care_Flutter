import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../constants/muslim_colors.dart';
import '../models/muslim_models.dart';
import '../providers/muslim_providers.dart';
import '../utils/muslim_localization.dart';
import 'muslim_widgets.dart';

class DuaCard extends ConsumerWidget {
  const DuaCard({super.key, required this.dua});

  final DuaItem dua;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counter = ref.watch(duaTapCounterProvider.notifier);
    final remaining = counter.remaining(dua);
    final complete = remaining <= 0;
    final lang = context.locale.languageCode;
    final hideAuxiliary = hideDuaEnglishAuxiliary(lang);
    final displayTitle = localizedDuaTitle(dua, lang);
    final displaySource = localizedDuaSource(dua, lang);

    return Material(
      color: context.mSurfaceContainerLowest,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: complete ? null : () => counter.tap(dua),
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: context.mPrimary.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (displayTitle.isNotEmpty) ...[
                Text(
                  displayTitle,
                  style: TextStyle(
                    fontFamily: lang == 'ar' ? 'Amiri' : 'Lexend',
                    fontSize: lang == 'ar' ? 14.sp : 12.sp,
                    fontWeight: FontWeight.w600,
                    color: context.mOnSurfaceVariant,
                  ),
                ),
                SizedBox(height: 8.h),
              ],
              ArabicText(
                dua.arabic,
                style: muslimArabicStyle(fontSize: 22.sp),
              ),
              if (!hideAuxiliary && dua.transliteration.isNotEmpty) ...[
                SizedBox(height: 12.h),
                Text(
                  dua.transliteration,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    fontStyle: FontStyle.italic,
                    height: 1.45,
                    color: context.mOnSurfaceVariant.withValues(alpha: 0.85),
                  ),
                ),
              ],
              if (!hideAuxiliary && dua.translation.isNotEmpty) ...[
                SizedBox(height: 10.h),
                Container(
                  padding: EdgeInsetsDirectional.only(start: 12.w),
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(
                        color: context.mPrimary.withValues(alpha: 0.2),
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
                      color: context.mOnSurface,
                    ),
                  ),
                ),
              ],
              if (displaySource.isNotEmpty) ...[
                SizedBox(height: 10.h),
                Text(
                  displaySource,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.sp,
                    color: context.mOnSurfaceVariant,
                  ),
                ),
              ],
              SizedBox(height: 16.h),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: 48.w,
                  height: 48.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: complete
                        ? context.mPrimaryContainer
                        : context.mSurface,
                    border: Border.all(
                      color: complete
                          ? context.mPrimaryContainer
                          : context.mPrimary,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: complete
                      ? Icon(
                          Symbols.check,
                          color: context.mOnPrimaryContainer,
                          size: 22.w,
                        )
                      : Text(
                          '$remaining×',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: context.mPrimary,
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
