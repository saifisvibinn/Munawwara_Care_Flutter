import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// Shared panel + row styling for [PopupMenuButton] (group ⋮, list row ⋮, toolbar menus, etc.).
/// Dropdown *fields* use `AppDropdownTheme` in `lib/core/theme/app_dropdown_theme.dart`.
abstract final class AppPopupMenu {
  AppPopupMenu._();

  static ShapeBorder panelShape() => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
      );

  static Color? panelColor(bool isDark) =>
      isDark ? AppColors.surfaceDark : null;

  static BoxConstraints panelConstraints({double? minWidth, double? maxWidth}) =>
      BoxConstraints(
        minWidth: (minWidth ?? 200).w,
        maxWidth: (maxWidth ?? 280).w,
      );

  /// Below the group map top-right circular control (40×40).
  static const Offset offsetBelowCircular40 = Offset(0, 48);

  /// Below compact triggers (e.g. language chip on login).
  static const Offset offsetBelowChip = Offset(0, 40);

  /// For ⋮ at the trailing edge of a dense row (pilgrim list).
  static const Offset offsetRowTrailingMore = Offset(-20, 36);

  static Widget actionRow({
    required IconData icon,
    required String label,
    required bool isDark,
    Color? iconColor,
    Color? textColor,
    bool destructive = false,
  }) {
    final Color resolvedIcon;
    final Color? resolvedText;
    if (destructive) {
      resolvedIcon = Colors.red;
      resolvedText = Colors.red;
    } else {
      resolvedIcon = iconColor ??
          (isDark ? Colors.white70 : AppColors.textDark);
      resolvedText = textColor ?? (isDark ? Colors.white : null);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18.w, color: resolvedIcon),
        SizedBox(width: 12.w),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14.sp,
              color: resolvedText,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// Single-choice list rows (e.g. language picker) with trailing check.
  static Widget selectionRow({
    required String label,
    required bool isSelected,
    required bool isDark,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? Colors.white : AppColors.textDark),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isSelected) ...[
          SizedBox(width: 8.w),
          Icon(Symbols.check, size: 18.w, color: AppColors.primary),
        ],
      ],
    );
  }
}
