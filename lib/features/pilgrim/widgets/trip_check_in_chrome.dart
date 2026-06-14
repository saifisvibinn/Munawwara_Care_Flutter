import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';

/// Horizontal inset so centered header text clears the floating back button.
double tripCheckInBackButtonInset(BuildContext context) => 14.w + 42.w + 12.w;

class TripCheckInFloatingBackButton extends StatelessWidget {
  const TripCheckInFloatingBackButton({
    super.key,
    required this.isDark,
    required this.onTap,
  });

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      start: 14.w,
      top: MediaQuery.paddingOf(context).top + 10.h,
      child: AppGlassIconButton(
        isDark: isDark,
        icon: Symbols.arrow_back,
        onTap: onTap,
        size: 42.w,
      ),
    );
  }
}

class TripCheckInPageHeader extends StatelessWidget {
  const TripCheckInPageHeader({
    super.key,
    required this.isDark,
    required this.title,
    this.subtitle,
  });

  final bool isDark;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final inset = tripCheckInBackButtonInset(context);
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;

    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 10.h, inset, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 20.sp,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                height: 1.4,
                color: textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
