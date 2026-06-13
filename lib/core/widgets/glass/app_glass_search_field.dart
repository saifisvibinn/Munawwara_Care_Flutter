import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/app_colors.dart';
import 'app_glass_surface.dart';

/// Glass search field with optional trailing filter widget.
class AppGlassSearchField extends StatelessWidget {
  const AppGlassSearchField({
    super.key,
    required this.isDark,
    required this.controller,
    required this.hintText,
    this.filter,
  });

  final bool isDark;
  final TextEditingController controller;
  final String hintText;
  final Widget? filter;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? const Color(0xFFE2E8F0) : AppColors.textDark;
    final hintColor =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return Row(
      children: [
        Expanded(
          child: AppGlassSurface(
            isDark: isDark,
            borderRadius: BorderRadius.circular(14.r),
            padding: EdgeInsets.symmetric(horizontal: 4.w),
            child: SizedBox(
              height: 48.h,
              child: TextField(
                controller: controller,
                style: TextStyle(fontSize: 14.sp, color: textColor),
                decoration: InputDecoration(
                  hintText: hintText,
                  hintStyle: TextStyle(fontSize: 14.sp, color: hintColor),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    size: 22.sp,
                    color: hintColor,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                ),
              ),
            ),
          ),
        ),
        if (filter != null) ...[
          SizedBox(width: 10.w),
          filter!,
        ],
      ],
    );
  }
}

/// Square glass filter button slot.
class AppGlassFilterButton extends StatelessWidget {
  const AppGlassFilterButton({
    super.key,
    required this.isDark,
    required this.icon,
    required this.onTap,
    this.showActiveDot = false,
  });

  final bool isDark;
  final IconData icon;
  final VoidCallback onTap;
  final bool showActiveDot;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AppGlassSurface(
        isDark: isDark,
        borderRadius: BorderRadius.circular(14.r),
        width: 48.w,
        height: 48.h,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 20.sp, color: AppColors.primary),
            if (showActiveDot)
              Positioned(
                top: 12.h,
                right: 12.w,
                child: Container(
                  width: 6.w,
                  height: 6.w,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
