import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/app_colors.dart';
import 'app_glass_surface.dart';
import 'app_glass_theme.dart';

/// Circular 44pt glass icon button for dashboard headers.
class AppGlassIconButton extends StatelessWidget {
  const AppGlassIconButton({
    super.key,
    required this.isDark,
    required this.icon,
    required this.onTap,
    this.badge,
    this.iconColor,
    this.size,
  });

  final bool isDark;
  final IconData icon;
  final VoidCallback onTap;
  final Widget? badge;
  final Color? iconColor;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final side = size ?? 44.w;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AppGlassSurface(
            isDark: isDark,
            borderRadius: AppGlassTheme.iconButtonRadius,
            width: side,
            height: side,
            child: Center(
              child: Icon(
                icon,
                size: 22.sp,
                color: iconColor ?? AppColors.primary,
              ),
            ),
          ),
          ?badge,
        ],
      ),
    );
  }
}
