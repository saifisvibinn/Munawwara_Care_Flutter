import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// Shared panel + row styling for contextual menus (UIMenu-style).
/// Selection pickers use [AppSelectionField] / [showAppSelectionSheet].
abstract final class AppPopupMenu {
  AppPopupMenu._();

  /// Apple HIG: compact menu corner radius ~10–14pt.
  static ShapeBorder panelShape() => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
      );

  static Color? panelColor(bool isDark) =>
      isDark ? AppColors.surfaceDark : Colors.white;

  static BoxConstraints panelConstraints({double? minWidth, double? maxWidth}) =>
      BoxConstraints(
        minWidth: (minWidth ?? 220).w,
        maxWidth: (maxWidth ?? 300).w,
      );

  static const Offset offsetBelowCircular40 = Offset(0, 48);
  static const Offset offsetBelowChip = Offset(0, 44);
  static const Offset offsetRowTrailingMore = Offset(-12, 40);

  /// Minimum 44pt row height per Apple HIG.
  static double get rowMinHeight => 44.h;

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
      resolvedIcon = const Color(0xFFFF3B30);
      resolvedText = const Color(0xFFFF3B30);
    } else {
      resolvedIcon = iconColor ??
          (isDark ? Colors.white : AppColors.textDark);
      resolvedText = textColor ?? (isDark ? Colors.white : AppColors.textDark);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: rowMinHeight),
      child: Row(
        children: [
          SizedBox(
            width: 28.w,
            child: Icon(icon, size: 20.sp, color: resolvedIcon),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 16.sp,
                fontWeight: FontWeight.w400,
                letterSpacing: -0.2,
                color: resolvedText,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  static Widget selectionRow({
    required String label,
    required bool isSelected,
    required bool isDark,
  }) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: rowMinHeight),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 16.sp,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: -0.2,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isSelected) ...[
            SizedBox(width: 8.w),
            Icon(Symbols.check, size: 20.sp, color: AppColors.primary),
          ],
        ],
      ),
    );
  }

  /// Wraps [PopupMenuItem] child with standard padding + min height.
  static Widget menuItemChild(Widget child) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      child: child,
    );
  }
}
