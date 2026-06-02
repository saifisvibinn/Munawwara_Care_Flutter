import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// Short coordination / non-emergency disclaimer for pilgrim home.
class SafetyDisclaimerBanner extends StatelessWidget {
  const SafetyDisclaimerBanner({
    super.key,
    required this.isDark,
  });

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.textMutedLight : const Color(0xFF475569);
    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceDark
            : const Color(0xFFFFF7ED), // Premium peach/cream
        borderRadius: BorderRadius.circular(24.r), // Premium 24.r rounded corners
        border: Border.all(
          color: isDark
              ? AppColors.primary.withValues(alpha: 0.3)
              : const Color(0xFFFFE3C3), // Soft orange border
          width: 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Symbols.info,
            size: 24.w,
            color: const Color(0xFFF97316), // Premium orange icon
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'safety_disclaimer_title'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 14.sp,
                    color: isDark ? Colors.white : const Color(0xFF0F3E1F), // Dark green title
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'safety_disclaimer_body'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.5.sp,
                    color: muted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
