import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'app_glass_surface.dart';
import 'app_glass_theme.dart';

/// Dashboard card with liquid glass shell and optional watermark.
class AppGlassCard extends StatelessWidget {
  const AppGlassCard({
    super.key,
    required this.isDark,
    required this.child,
    this.onTap,
    this.padding,
    this.borderRadius,
    this.watermark,
  });

  final bool isDark;
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final Widget? watermark;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppGlassTheme.cardRadius;
    final innerPadding = padding ?? EdgeInsets.all(16.w);

    return AppGlassSurface(
      isDark: isDark,
      glassTheme: AppGlassTheme.cardOf(isDark),
      borderRadius: radius,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (watermark != null)
              Positioned.fill(
                child: watermark!,
              ),
            Padding(
              padding: innerPadding,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
