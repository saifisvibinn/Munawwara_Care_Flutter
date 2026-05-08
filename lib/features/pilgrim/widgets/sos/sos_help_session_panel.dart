import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Post-SOS help session panel (calm surface; status text + cancel button)
// ─────────────────────────────────────────────────────────────────────────────

class SosHelpSessionPanel extends StatelessWidget {
  final bool isDark;
  final String statusKey;

  /// Name of the moderator who confirmed they're handling this (empty if none).
  final String moderatorName;

  final Future<void> Function() onCancelRequest;
  final Future<void> Function()? onCallBack;
  final bool showCancel;
  final bool showCallBack;

  const SosHelpSessionPanel({
    super.key,
    required this.isDark,
    required this.statusKey,
    required this.onCancelRequest,
    this.onCallBack,
    this.showCancel = true,
    this.showCallBack = false,
    this.moderatorName = '',
  });

  @override
  Widget build(BuildContext context) {
    final brand = 'call_support_display_name'.tr();
    final surface = isDark ? AppColors.surfaceDark : Colors.white;
    final border = AppColors.primary.withValues(alpha: 0.22);
    final titleColor = isDark ? Colors.white : AppColors.textDark;
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    final isResponding = statusKey == 'sos_status_responding';

    final String statusText;
    if (isResponding) {
      statusText = 'sos_status_responding'.tr();
    } else {
      statusText = statusKey.tr();
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 400.w),
      child: Container(
        padding: EdgeInsets.fromLTRB(22.w, 24.h, 22.w, 20.h),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(22.r),
          border: Border.all(
            color: isResponding
                ? Colors.green.withValues(alpha: 0.35)
                : border,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: isDark ? 0.25 : 0.06,
              ),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── State icon ────────────────────────────────────────────────────
            Icon(
              isResponding
                  ? Icons.directions_run_rounded
                  : Icons.mark_email_read_outlined,
              color: isResponding ? Colors.green : AppColors.primary,
              size: 40.w,
            ),
            SizedBox(height: 14.h),
            Text(
              'sos_help_title'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 18.sp,
                fontWeight: FontWeight.w800,
                color: titleColor,
                height: 1.25,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'sos_help_subtitle'.tr(namedArgs: {'name': brand}),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: muted,
                height: 1.45,
              ),
            ),
            SizedBox(height: 16.h),

            // ── Visual indicator (no loading animation) ───────────────────────
            Container(
              width: 64.w,
              height: 64.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (isResponding ? Colors.green : AppColors.primary)
                    .withValues(alpha: 0.12),
              ),
              child: Icon(
                isResponding ? Icons.check_rounded : Icons.support_agent_rounded,
                color: isResponding ? Colors.green : AppColors.primary,
                size: 36.w,
              ),
            ),

            SizedBox(height: 14.h),

            // ── Status text ───────────────────────────────────────────────────
            Text(
              statusText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: isResponding ? Colors.green : AppColors.primary,
                height: 1.35,
              ),
            ),
            SizedBox(height: 22.h),

            if (showCallBack) ...[
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onCallBack == null ? null : () => onCallBack!(),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                  child: Text(
                    'sos_call_back'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ] else if (showCancel) ...[
              // ── Cancel button ───────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: isResponding ? null : () => onCancelRequest(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isResponding ? Colors.grey.shade400 : muted,
                    side: BorderSide(
                      color: isResponding
                          ? Colors.grey.shade300
                          : isDark
                              ? AppColors.dividerDark
                              : AppColors.dividerLight,
                    ),
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                  child: Text(
                    'sos_cancel_request'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
