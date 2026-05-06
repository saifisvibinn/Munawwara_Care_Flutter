import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';

import '../theme/app_colors.dart';

/// Prevents stacking the same sheet twice in a row (e.g. init + resume).
DateTime? _locationAlwaysSheetLastOpen;

/// Shows every time the dashboard opens or the app resumes until
/// [Permission.locationAlways] is granted. No snooze: pilgrims (and moderators)
/// must enable **Always** for the app to work as designed.
Future<void> showLocationAlwaysOnboardingIfNeeded(
  BuildContext context,
) async {
  if (kIsWeb) return;

  final always = await Permission.locationAlways.status;
  if (always.isGranted) return;

  final now = DateTime.now();
  if (_locationAlwaysSheetLastOpen != null &&
      now.difference(_locationAlwaysSheetLastOpen!) <
          const Duration(seconds: 4)) {
    return;
  }

  if (!context.mounted) return;
  await Future<void>.delayed(const Duration(milliseconds: 650));
  if (!context.mounted) return;

  final recheck = await Permission.locationAlways.status;
  if (recheck.isGranted) return;

  if (!context.mounted) return;

  _locationAlwaysSheetLastOpen = DateTime.now();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (ctx) => const _LocationAlwaysOnboardingSheet(),
  );
}

class _LocationAlwaysOnboardingSheet extends StatelessWidget {
  const _LocationAlwaysOnboardingSheet();

  Future<void> _showLimitedWarningThenMaybeClose(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final understood = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: Text(
          'location_always_limited_dialog_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w800,
            fontSize: 17.sp,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            'location_always_limited_dialog_body'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14.sp,
              height: 1.45,
              color: isDark ? Colors.white70 : AppColors.textMutedLight,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(
              'location_always_limited_dialog_back'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'location_always_limited_dialog_accept'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (understood == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(22.w, 12.h, 22.w, 20.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: textMuted.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
                SizedBox(height: 20.h),
                Container(
                  width: 72.w,
                  height: 72.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: 0.12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Symbols.my_location,
                    size: 36.w,
                    color: AppColors.primary,
                    fill: 1,
                  ),
                ),
                SizedBox(height: 18.h),
                Text(
                  'location_always_sheet_title'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w800,
                    fontSize: 20.sp,
                    height: 1.25,
                    color: textPrimary,
                  ),
                ),
                SizedBox(height: 10.h),
                Text(
                  'location_always_sheet_subtitle'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13.sp,
                    height: 1.45,
                    color: textMuted,
                  ),
                ),
                SizedBox(height: 20.h),
                _Bullet(
                  icon: Symbols.shield_lock,
                  text: 'location_always_sheet_bullet_1'.tr(),
                  isDark: isDark,
                ),
                SizedBox(height: 12.h),
                _Bullet(
                  icon: Symbols.map,
                  text: 'location_always_sheet_bullet_2'.tr(),
                  isDark: isDark,
                ),
                SizedBox(height: 12.h),
                _Bullet(
                  icon: Symbols.sos,
                  text: 'location_always_sheet_bullet_3'.tr(),
                  isDark: isDark,
                ),
                SizedBox(height: 24.h),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      await openAppSettings();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Symbols.settings, size: 20.w),
                        SizedBox(width: 8.w),
                        Text(
                          'location_always_open_settings'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 15.sp,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: 10.h),
                TextButton(
                  onPressed: () =>
                      _showLimitedWarningThenMaybeClose(context),
                  child: Text(
                    'location_always_continue_limited'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                      color: textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool isDark;

  const _Bullet({
    required this.icon,
    required this.text,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? AppColors.textLight : AppColors.textDark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36.w,
          height: 36.w,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(
            icon,
            size: 20.w,
            color: AppColors.primary,
            fill: 1,
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: 6.h),
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                height: 1.4,
                color: textColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
