import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import 'glass/app_glass.dart';

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
    return AppGlassSurface(
      isDark: isDark,
      borderRadius: AppGlassTheme.cardRadius,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Symbols.info,
            size: 24.w,
            color: const Color(0xFFF97316),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'safety_disclaimer_title'.tr(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.sp,
                    color: isDark ? Colors.white : const Color(0xFF0F3E1F),
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'safety_disclaimer_body'.tr(),
                  style: TextStyle(
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
