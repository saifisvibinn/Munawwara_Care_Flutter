import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/open_maps_navigation.dart';
import '../../shared/widgets/pilgrim_gender_avatar.dart';

/// In-app SOS alert for moderators (single surface; complements one FCM tray
/// notification).
class SosAlertDialog extends StatelessWidget {
  final String pilgrimName;
  final String groupName;
  final String? pilgrimGender;
  final String? pilgrimProfilePicture;
  final double? navigateLat;
  final double? navigateLng;
  final Future<void> Function() onReview;
  final Future<void> Function() onDismiss;
  final Future<void> Function()? onNavigateSuccess;

  const SosAlertDialog({
    super.key,
    required this.pilgrimName,
    required this.groupName,
    required this.onReview,
    required this.onDismiss,
    this.onNavigateSuccess,
    this.pilgrimGender,
    this.pilgrimProfilePicture,
    this.navigateLat,
    this.navigateLng,
  });

  bool get _canNavigate => navigateLat != null && navigateLng != null;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : AppColors.textDark;
    final bodyColor = isDark
        ? Colors.white.withValues(alpha: 0.88)
        : AppColors.textDark;
    final muted = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : AppColors.textMutedDark;

    final screenW = MediaQuery.sizeOf(context).width;
    final dialogW = math.max(280.0, math.min(screenW - 40, 400.0));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22.r)),
      insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
      child: SizedBox(
        width: dialogW,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(22.w, 22.h, 22.w, 18.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? AppColors.dividerDark
                              : AppColors.dividerLight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(3.w),
                        child: PilgrimGenderAvatar(
                          gender: pilgrimGender,
                          imageUrl: pilgrimProfilePicture,
                          size: 52.w,
                        ),
                      ),
                    ),
                    SizedBox(width: 14.w),
                    Icon(
                      Symbols.crisis_alert,
                      color: AppColors.error,
                      size: 42.w,
                      fill: 1,
                    ),
                  ],
                ),
                SizedBox(height: 18.h),
                Text(
                  'sos_mod_dialog_title'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 19.sp,
                    height: 1.2,
                    color: titleColor,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 14.h),
                Text(
                  'sos_mod_dialog_body_line1'.tr(
                    namedArgs: {
                      'name': pilgrimName,
                      'group': groupName.isEmpty ? '—' : groupName,
                    },
                  ),
                  style: TextStyle(
                    fontSize: 15.sp,
                    height: 1.5,
                    color: bodyColor,
                  ),
                ),
                if (!_canNavigate) ...[
                  SizedBox(height: 10.h),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 8.h,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Symbols.location_searching,
                          size: 18.sp,
                          color: AppColors.primary.withValues(alpha: 0.85),
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            'sos_mod_dialog_location_unknown'.tr(),
                            style: TextStyle(
                              fontSize: 12.5.sp,
                              height: 1.35,
                              color: muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                SizedBox(height: 14.h),
                Text(
                  'sos_mod_dialog_call_hint'.tr(),
                  style: TextStyle(
                    fontSize: 12.sp,
                    height: 1.35,
                    color: muted,
                  ),
                ),
                SizedBox(height: 22.h),
                if (_canNavigate) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.55),
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: 13.h,
                        horizontal: 16.w,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r),
                      ),
                    ),
                    onPressed: () async {
                      final ok = await OpenMapsNavigation.confirmAndLaunch(
                        context,
                        navigateLat!,
                        navigateLng!,
                      );
                      if (ok) await onNavigateSuccess?.call();
                    },
                    icon: Icon(Symbols.navigation, size: 20.sp),
                    label: Text(
                      'explore_navigate'.tr(),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.sp,
                      ),
                    ),
                  ),
                  SizedBox(height: 10.h),
                ],
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            vertical: 12.h,
                            horizontal: 8.w,
                          ),
                          foregroundColor: AppColors.primary.withValues(
                            alpha: 0.9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                        onPressed: () => onDismiss(),
                        child: Text(
                          'sos_mod_dialog_dismiss'.tr(),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14.sp,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => onReview(),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14.r),
                          ),
                        ),
                        child: Text(
                          'sos_mod_dialog_review'.tr(),
                          style: TextStyle(
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
          ),
        ),
      ),
    );
  }
}
