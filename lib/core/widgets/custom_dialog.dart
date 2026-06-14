import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../theme/app_colors.dart';
import 'glass/app_glass.dart';

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
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;
    final accent = isDestructive ? const Color(0xFFDC2626) : AppColors.primary;
    final resolvedContent = contentWidget ??
        (content != null
            ? Text(
                contentNamedArgs != null
                    ? content.tr(namedArgs: contentNamedArgs)
                    : (contentArgs != null
                        ? content.tr(args: contentArgs)
                        : content.tr()),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13.sp,
                  color: textMuted,
                  height: 1.5,
                ),
              )
            : null);

    final resolvedIcon = icon ??
        Icon(
          isDestructive ? Symbols.warning_rounded : Symbols.info,
          size: 28.w,
          color: accent,
          fill: isDestructive ? 1 : 0,
        );

    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.58 : 0.42),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: EdgeInsets.symmetric(horizontal: 28.w),
        child: AppGlassSurface(
          isDark: isDark,
          borderRadius: BorderRadius.circular(28.r),
          padding: EdgeInsets.fromLTRB(24.w, 28.h, 24.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56.w,
                height: 56.w,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.2 : 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.28),
                  ),
                ),
                child: Center(child: resolvedIcon),
              ),
              SizedBox(height: 16.h),
              Text(
                title.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 18.sp,
                  color: textPrimary,
                ),
              ),
              if (resolvedContent != null) ...[
                SizedBox(height: 8.h),
                resolvedContent,
              ],
              if (showActions) ...[
                SizedBox(height: 24.h),
                SizedBox(
                  width: double.infinity,
                  height: 50.h,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true as T),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                    ),
                    child: Text(
                      (confirmText?.tr() ?? 'dialog_confirm'.tr()),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w700,
                        fontSize: 15.sp,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 10.h),
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false as T),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark
                          ? const Color(0xFF60A5FA)
                          : const Color(0xFF2563EB),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                    ),
                    child: Text(
                      (cancelText?.tr() ?? 'dialog_cancel'.tr()),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 15.sp,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Shows a standardized loading dialog with a premium feel.
  static void showLoading(BuildContext context, {String? message}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.58 : 0.42),
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: EdgeInsets.symmetric(horizontal: 28.w),
          child: AppGlassSurface(
            isDark: isDark,
            borderRadius: BorderRadius.circular(28.r),
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 28.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 3,
                  ),
                ),
                if (message != null) ...[
                  SizedBox(height: 20.h),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
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
