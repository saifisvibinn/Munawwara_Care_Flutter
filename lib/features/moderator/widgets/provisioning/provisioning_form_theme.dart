import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';

/// Shared tokens and [InputDecorationTheme] for the moderator provisioning form.
///
/// Keeps one source of truth for field styling (Material-style outlined fields).
class ProvisioningFormTheme {
  ProvisioningFormTheme._();

  static double gapMd(BuildContext context) => 16.h;

  static double gapSm(BuildContext context) => 12.h;

  static double gapLg(BuildContext context) => 20.h;

  static BorderRadius fieldRadius(BuildContext context) =>
      BorderRadius.circular(12.r);

  /// Merges with [Theme.of(context).inputDecorationTheme] for each field.
  static InputDecorationTheme inputDecorationTheme(bool isDark) {
    final outline = isDark ? AppColors.dividerDark : AppColors.dividerLight;
    final fill = isDark ? const Color(0xFF151B26) : const Color(0xFFF8FAFC);

    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.r),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    final hintColor = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return InputDecorationTheme(
      filled: true,
      fillColor: fill,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      border: border(outline),
      enabledBorder: border(outline),
      focusedBorder: border(AppColors.primary, 2),
      errorBorder: border(AppColors.error),
      focusedErrorBorder: border(AppColors.error, 2),
      disabledBorder: border(outline.withValues(alpha: 0.4)),
      hintStyle: TextStyle(
        fontFamily: 'Lexend',
        fontSize: 14.sp,
        fontWeight: FontWeight.w600,
        color: hintColor.withValues(alpha: 0.95),
        height: 1.2,
      ),
      errorStyle: TextStyle(
        fontFamily: 'Lexend',
        fontSize: 12.sp,
        color: AppColors.error,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  static InputDecoration fieldDecoration({
    required BuildContext context,
    required bool isDark,
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      prefixIconConstraints: BoxConstraints(minWidth: 48.w, maxHeight: 28.h),
    );
  }
}
