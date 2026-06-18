import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';

/// Full-width banner shown when dashboard data is served from a local snapshot.
class OfflineDataBanner extends StatelessWidget {
  const OfflineDataBanner({
    super.key,
    required this.isDark,
  });

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final background = isDark ? const Color(0xFF2A2010) : const Color(0xFFFFF7ED);
    final borderColor = isDark
        ? AppColors.warning.withValues(alpha: 0.35)
        : AppColors.warning.withValues(alpha: 0.28);
    final iconColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    final textColor = isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E);

    return ColoredBox(
      color: background,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: borderColor),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            child: Row(
              children: [
                Icon(
                  Symbols.cloud_off,
                  size: 18.w,
                  color: iconColor,
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    'offline_showing_saved_data'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                      height: 1.35,
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
