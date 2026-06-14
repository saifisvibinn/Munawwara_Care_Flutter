import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';

/// Wrapper so sheet dismiss (null) is distinct from selecting a null [T].
class AppSelectionResult<T> {
  const AppSelectionResult(this.value);
  final T? value;
}

/// One row in [showAppSelectionSheet] — Apple Settings list style.
class AppSelectionOption<T> {
  const AppSelectionOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.enabled = true,
    this.textColor,
  });

  final T value;
  final String label;
  final String? subtitle;
  final bool enabled;
  final Color? textColor;
}

/// iOS Settings–style picker sheet: drag handle, title, checkmarked rows.
Future<AppSelectionResult<T>?> showAppSelectionSheet<T>({
  required BuildContext context,
  required String title,
  required List<AppSelectionOption<T>> options,
  T? selectedValue,
  bool isDark = false,
}) {
  final sheetBg = isDark ? AppColors.surfaceDark : Colors.white;
  final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
  final textMuted =
      isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
  final dividerColor =
      isDark ? AppColors.dividerDark : const Color(0xFFE5E7EB);

  return showModalBottomSheet<AppSelectionResult<T>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: sheetBg,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
    ),
    builder: (sheetContext) {
      final maxHeight = MediaQuery.sizeOf(sheetContext).height * 0.88;
      final targetHeight = (options.length * 52.h + 120.h).clamp(220.h, maxHeight);

      return SizedBox(
        height: targetHeight,
        child: Column(
          children: [
            SizedBox(height: 8.h),
            Container(
              width: 36.w,
              height: 5.h,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2.5.r),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 8.h),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 17.sp,
                  letterSpacing: -0.2,
                  color: textPrimary,
                ),
              ),
            ),
            Expanded(
              child: Material(
                color: sheetBg,
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                  itemCount: options.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    thickness: 0.5,
                    color: dividerColor,
                  ),
                  itemBuilder: (context, index) {
                    final option = options[index];
                    final isSelected = option.value == selectedValue;
                    final rowColor = option.textColor ??
                        (isSelected ? AppColors.primary : textPrimary);

                    return Material(
                      color: sheetBg,
                      child: InkWell(
                        onTap: option.enabled
                            ? () {
                                HapticFeedback.selectionClick();
                                Navigator.pop(
                                  sheetContext,
                                  AppSelectionResult<T>(option.value),
                                );
                              }
                            : null,
                        child: Opacity(
                          opacity: option.enabled ? 1 : 0.45,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: 44.h),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 4.w,
                                vertical: 10.h,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          option.label,
                                          style: TextStyle(
                                            fontFamily: 'Lexend',
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            fontSize: 16.sp,
                                            color: rowColor,
                                          ),
                                        ),
                                        if (option.subtitle != null) ...[
                                          SizedBox(height: 2.h),
                                          Text(
                                            option.subtitle!,
                                            style: TextStyle(
                                              fontFamily: 'Lexend',
                                              fontSize: 13.sp,
                                              color: textMuted,
                                            ),
                                          ),
                                        ],
                                      ],
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
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
