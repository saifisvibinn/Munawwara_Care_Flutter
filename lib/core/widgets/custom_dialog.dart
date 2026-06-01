import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../theme/app_colors.dart';

class StandardDialog {
  StandardDialog._();

  /// Shows a premium, standardized confirmation/alert dialog.
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? content,
    List<String>? contentArgs,
    Map<String, String>? contentNamedArgs,
    Widget? contentWidget,
    String? confirmText,
    String? cancelText,
    bool isDestructive = false,
    Widget? icon,
    bool barrierDismissible = true,
    bool showActions = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        icon: icon ?? (isDestructive 
          ? Icon(Symbols.warning, color: Colors.red.shade600, size: 32.w)
          : null),
        iconPadding: EdgeInsets.only(top: 24.h, bottom: 8.h),
        title: Text(
          title.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        content: contentWidget ?? (content != null ? Text(
          contentNamedArgs != null
              ? content.tr(namedArgs: contentNamedArgs)
              : (contentArgs != null
                  ? content.tr(args: contentArgs)
                  : content.tr()),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14.sp,
            color: isDark ? Colors.white70 : AppColors.textMutedLight,
            height: 1.5,
          ),
        ) : null),
        contentPadding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 24.h),
        actionsPadding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
        actions: !showActions ? null : [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(ctx, false as T),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    foregroundColor: isDark ? Colors.white60 : AppColors.textMutedLight,
                    side: BorderSide(
                      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Text(
                    (cancelText?.tr() ?? 'dialog_cancel'.tr()),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true as T),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDestructive
                        ? Colors.red.shade600
                        : AppColors.primary,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                  ),
                  child: Text(
                    (confirmText?.tr() ?? 'dialog_confirm'.tr()),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Shows a standardized loading dialog with a premium feel.
  static void showLoading(BuildContext context, {String? message}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24.r),
          ),
          content: Padding(
            padding: EdgeInsets.symmetric(vertical: 24.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 3,
                  ),
                ),
                if (message != null) ...[
                  SizedBox(height: 24.h),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Hides the current dialog.
  static void hide(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }
}
