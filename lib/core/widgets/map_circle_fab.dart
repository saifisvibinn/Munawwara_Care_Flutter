import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';
import 'glass/app_glass.dart';

/// Circular control for map overlays (e.g. “my location”), shared by pilgrim
/// and moderator maps.
class MapCircleFab extends StatelessWidget {
  const MapCircleFab({
    super.key,
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AppGlassSurface(
        isDark: isDark,
        borderRadius: BorderRadius.circular(24.r),
        width: 48.w,
        height: 48.w,
        child: Center(
          child: Icon(
            icon,
            size: 20.w,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
      ),
    );
  }
}
