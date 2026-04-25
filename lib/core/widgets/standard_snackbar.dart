import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../theme/app_colors.dart';

enum SnackBarType { success, error, warning, info }

class StandardSnackBar {
  StandardSnackBar._();

  static void show(
    BuildContext context, {
    required String message,
    SnackBarType type = SnackBarType.info,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {

    Color bgColor;
    Color iconColor;
    IconData icon;

    switch (type) {
      case SnackBarType.success:
        bgColor = AppColors.success;
        iconColor = Colors.white;
        icon = Symbols.check_circle;
        break;
      case SnackBarType.error:
        bgColor = AppColors.error;
        iconColor = Colors.white;
        icon = Symbols.error;
        break;
      case SnackBarType.warning:
        bgColor = AppColors.warning;
        iconColor = Colors.white;
        icon = Symbols.warning;
        break;
      case SnackBarType.info:
        bgColor = AppColors.info;
        iconColor = Colors.white;
        icon = Symbols.info;
        break;
    }

    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(
            icon,
            color: iconColor,
            size: 20.w,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              message.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: bgColor,
      behavior: SnackBarBehavior.floating,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
      ),
      margin: EdgeInsets.all(16.w),
      duration: duration,
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(
              label: actionLabel.tr(),
              textColor: Colors.white,
              onPressed: onAction,
            )
          : null,
    );

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  static void showSuccess(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    show(context, message: message, type: SnackBarType.success, duration: duration);
  }

  static void showError(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    show(context, message: message, type: SnackBarType.error, duration: duration);
  }

  static void showWarning(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    show(context, message: message, type: SnackBarType.warning, duration: duration);
  }

  static void showInfo(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    show(context, message: message, type: SnackBarType.info, duration: duration);
  }
}
