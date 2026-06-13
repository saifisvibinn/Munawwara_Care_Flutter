import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/app_colors.dart';

/// Subtle gradient mesh so liquid glass blur is visible behind cards.
class AppDashboardBackground extends StatelessWidget {
  const AppDashboardBackground({
    super.key,
    required this.isDark,
    required this.child,
  });

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = isDark ? AppColors.backgroundDark : const Color(0xFFF7F9FB);

    return SizedBox.expand(
      child: Container(
        color: base,
        child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -80.h,
            right: -60.w,
            child: _Blob(
              size: 220.w,
              color: AppColors.primary.withValues(alpha: isDark ? 0.12 : 0.08),
            ),
          ),
          Positioned(
            top: 180.h,
            left: -40.w,
            child: _Blob(
              size: 160.w,
              color: const Color(0xFFF97316)
                  .withValues(alpha: isDark ? 0.08 : 0.06),
            ),
          ),
          Positioned(
            bottom: 120.h,
            right: -20.w,
            child: _Blob(
              size: 140.w,
              color: AppColors.primary.withValues(alpha: isDark ? 0.06 : 0.05),
            ),
          ),
          child,
        ],
      ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}
