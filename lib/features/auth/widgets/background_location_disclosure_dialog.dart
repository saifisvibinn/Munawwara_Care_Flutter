import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';

/// Prominent disclosure before the background location OS permission prompt.
/// Returns `true` if the user taps Allow, `false` for Not now.
Future<bool> showBackgroundLocationDisclosure(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _BackgroundLocationDisclosureDialog(),
  );
  return result ?? false;
}

class _BackgroundLocationDisclosureDialog extends StatelessWidget {
  const _BackgroundLocationDisclosureDialog();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final titleColor = isDark ? Colors.white : AppColors.textDark;
    final bodyColor =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return Dialog.fullscreen(
      backgroundColor: background,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 32.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 1),
              Center(
                child: Container(
                  width: 72.w,
                  height: 72.w,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Symbols.location_on,
                    size: 36.w,
                    color: AppColors.primary,
                  ),
                ),
              ),
              SizedBox(height: 28.h),
              Text(
                'location_disclosure_title'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w700,
                  color: titleColor,
                  height: 1.25,
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'location_disclosure_body'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 15.sp,
                  height: 1.5,
                  color: bodyColor,
                ),
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: Text(
                    'location_disclosure_allow'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 8.h),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    'location_disclosure_not_now'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.textMutedLight
                          : AppColors.textDark,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
