import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_colors.dart';

/// App-wide [DropdownButtonFormField] / [DropdownButton] styling.
/// Tweak radius, fills, and borders here to refresh every dropdown at once.
/// Pairs visually with [AppPopupMenu] (same menu corner radius and surfaces).
class AppDropdownTheme {
  AppDropdownTheme._();

  static const String fontFamily = 'Lexend';

  // --- Global tokens (edit these to restyle all dropdowns) ---
  static double fieldCornerRadius() => 16.r;
  static double menuCornerRadius() => 16.r;
  static int menuElevation() => 8;
  static double menuMaxHeight() => 320.h;

  static Color menuBackground(bool isDark) =>
      isDark ? AppColors.surfaceDark : Colors.white;

  /// Field background when not inside another tinted surface.
  static Color fieldFill(bool isDark) =>
      isDark ? AppColors.surfaceDark : Colors.white;

  /// Slightly recessed fill for dropdowns inside cards / panels.
  static Color fieldFillNested(bool isDark) =>
      isDark ? const Color(0xFF1A2230) : const Color(0xFFF3F4F6);

  static Color fieldBorder(bool isDark) =>
      isDark ? AppColors.dividerDark : AppColors.dividerLight;

  static TextStyle valueStyle(bool isDark, {double fontSize = 15}) => TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize.sp,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : AppColors.textDark,
      );

  static TextStyle labelStyle(bool isDark) => TextStyle(
        fontFamily: fontFamily,
        fontSize: 14.sp,
        color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
      );

  static TextStyle menuItemStyle(bool isDark, {double fontSize = 14}) =>
      TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize.sp,
        color: isDark ? Colors.white : AppColors.textDark,
      );

  static BorderRadius menuBorderRadius() =>
      BorderRadius.circular(menuCornerRadius());

  /// Trailing icon for form and inline dropdowns.
  static Widget menuTrailingIcon({
    IconData icon = Symbols.expand_more,
    double? size,
  }) {
    return Icon(
      icon,
      color: AppColors.primary,
      size: size ?? 22.sp,
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
    final radius = minimal ? 14.r : fieldCornerRadius();
    final pad = contentPadding ??
        (minimal
            ? EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 14.h)
            : EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h));

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

  /// Wrapper decoration for inline [DropdownButton] (no label), e.g. group picker.
  static BoxDecoration inlineContainerDecoration(bool isDark) {
    return BoxDecoration(
      color: fieldFill(isDark),
      borderRadius: BorderRadius.circular(fieldCornerRadius()),
      border: Border.all(color: fieldBorder(isDark)),
    );
  }
}
