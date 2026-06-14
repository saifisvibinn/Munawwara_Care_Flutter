import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../config/app_locales.dart';
import '../services/app_language_service.dart';
import '../theme/app_colors.dart';

/// iOS Settings–style language picker: endonyms, single checkmark, sheet presentation.
Future<void> showAppLanguagePickerSheet({
  required BuildContext context,
  required String selectedCode,
  required bool isDark,
}) {
  final hostContext = context;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
    ),
    builder: (sheetContext) {
      final textPrimary =
          isDark ? AppColors.textLight : AppColors.textDark;
      final dividerColor =
          isDark ? AppColors.dividerDark : const Color(0xFFE5E7EB);
      final sheetBg = isDark ? AppColors.surfaceDark : Colors.white;

      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.38,
        maxChildSize: 0.88,
        builder: (context, scrollController) {
          return Column(
            children: [
              SizedBox(height: 10.h),
              Container(
                width: 36.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 8.h),
                child: Text(
                  'settings_language_title'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 17.sp,
                    color: textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: Material(
                  color: sheetBg,
                  child: ListView.separated(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                    itemCount: AppLocales.profileLanguages.length,
                    separatorBuilder: (_, _) => Divider(
                      height: 1,
                      thickness: 0.5,
                      color: dividerColor,
                    ),
                    itemBuilder: (context, index) {
                      final lang = AppLocales.profileLanguages[index];
                      final isSelected = lang.code == selectedCode;

                      return Material(
                        color: sheetBg,
                        child: InkWell(
                          onTap: () async {
                            if (isSelected) {
                              Navigator.pop(sheetContext);
                              return;
                            }
                            HapticFeedback.selectionClick();
                            Navigator.pop(sheetContext);
                            if (hostContext.mounted) {
                              await AppLanguageService.apply(
                                hostContext,
                                lang.code,
                              );
                            }
                          },
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 4.w,
                              vertical: 12.h,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    lang.nativeName,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      fontSize: 16.sp,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check,
                                    size: 20.sp,
                                    color: AppColors.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}
