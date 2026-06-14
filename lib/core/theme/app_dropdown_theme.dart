import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_colors.dart';

/// App-wide selection field styling (Apple HIG form controls).
/// Selection menus use [AppSelectionField] + [showAppSelectionSheet].
/// Contextual action menus use [AppPopupMenu].
class AppDropdownTheme {
  AppDropdownTheme._();

  static const String fontFamily = 'Lexend';

  // Apple HIG: grouped form corners ~10–12pt; menus ~10–14pt.
  static double fieldCornerRadius() => 12.r;
  static double menuCornerRadius() => 12.r;
  static int menuElevation() => 4;
  static double menuMaxHeight() => 360.h;

  static Color menuBackground(bool isDark) =>
      isDark ? AppColors.surfaceDark : Colors.white;

  static Color fieldFill(bool isDark) =>
      isDark ? AppColors.surfaceDark : Colors.white;

  static Color fieldFillNested(bool isDark) =>
      isDark ? const Color(0xFF1A2230) : const Color(0xFFF2F2F7);

  static Color fieldBorder(bool isDark) =>
      isDark ? AppColors.dividerDark : const Color(0xFFE5E5EA);

  static TextStyle valueStyle(bool isDark, {double fontSize = 16}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        color: isDark ? Colors.white : AppColors.textDark,
      );

  static TextStyle labelStyle(bool isDark) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 13.sp,
        fontWeight: FontWeight.w500,
        color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
      );

  static TextStyle menuItemStyle(bool isDark, {double fontSize = 16}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize.sp,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        color: isDark ? Colors.white : AppColors.textDark,
      );

  static BorderRadius menuBorderRadius() =>
      BorderRadius.circular(menuCornerRadius());

  /// Settings-style disclosure chevron (44×44 min touch target per HIG).
  static Widget disclosureIcon(bool isDark, {double? size}) {
    return SizedBox(
      width: 44.w,
      height: 44.h,
      child: Icon(
        Symbols.chevron_right,
        size: size ?? 20.sp,
        color: isDark ? AppColors.textMutedLight : const Color(0xFFC7C7CC),
      ),
    );
  }

  @Deprecated('Use disclosureIcon for Apple-style pickers')
  static Widget menuTrailingIcon({
    IconData icon = Symbols.unfold_more,
    double? size,
  }) {
    return Icon(
      icon,
      color: AppColors.primary,
      size: size ?? 20.sp,
    );
  }

  static InputDecoration formFieldDecoration({
    required bool isDark,
    String? labelText,
    String? hintText,
    Widget? prefixIcon,
    EdgeInsetsGeometry? contentPadding,
    bool nested = false,
    bool minimal = false,
  }) {
    final fill = nested ? fieldFillNested(isDark) : fieldFill(isDark);
    final borderClr = fieldBorder(isDark);
    final radius = minimal ? 10.r : fieldCornerRadius();
    final pad = contentPadding ??
        (minimal
            ? EdgeInsets.fromLTRB(14.w, 8.h, 8.w, 10.h)
            : EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h));

    if (minimal) {
      return InputDecoration(
        labelText: labelText,
        hintText: hintText,
        prefixIcon: prefixIcon,
        prefixIconConstraints: BoxConstraints(minWidth: 44.w, maxHeight: 28.h),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        floatingLabelAlignment: FloatingLabelAlignment.start,
        labelStyle: labelStyle(isDark).copyWith(
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: labelStyle(isDark),
        filled: true,
        fillColor: fill,
        contentPadding: pad,
        alignLabelWithHint: false,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(
            color: AppColors.primary.withValues(alpha: 0.55),
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
      );
    }

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      labelStyle: labelStyle(isDark),
      hintStyle: labelStyle(isDark),
      filled: true,
      fillColor: fill,
      contentPadding: pad,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: borderClr),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: borderClr),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: borderClr.withValues(alpha: 0.45)),
      ),
    );
  }

  static BoxDecoration inlineContainerDecoration(bool isDark) {
    return BoxDecoration(
      color: fieldFill(isDark),
      borderRadius: BorderRadius.circular(fieldCornerRadius()),
      border: Border.all(color: fieldBorder(isDark)),
    );
  }
}
