import 'package:cupertino_liquid_glass/cupertino_liquid_glass.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'app_glass_theme.dart';

/// Thin wrapper over [CupertinoLiquidGlass] with app defaults.
class AppGlassSurface extends StatelessWidget {
  const AppGlassSurface({
    super.key,
    required this.child,
    required this.isDark,
    this.borderRadius,
    this.padding,
    this.width,
    this.height,
    this.onTap,
    this.enableGlass = true,
    this.glassTheme,
  });

  final Widget child;
  final bool isDark;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final bool enableGlass;
  /// Override material (e.g. [AppGlassTheme.popoverOf] for compact menus).
  final LiquidGlassThemeData? glassTheme;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppGlassTheme.borderRadius;

    final resolvedTheme = glassTheme ?? AppGlassTheme.of(isDark);

    Widget surface = CupertinoTheme(
      data: CupertinoThemeData(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primaryColor: AppColors.primary,
      ),
      child: CupertinoLiquidGlass(
        theme: resolvedTheme,
        blurSigma: glassTheme == null ? AppGlassTheme.blurSigma : null,
        borderRadius: radius,
        padding: padding,
        width: width,
        height: height,
        enabled: enableGlass,
        child: child,
      ),
    );

    if (onTap != null) {
      surface = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: surface,
        ),
      );
    }

    return surface;
  }
}
