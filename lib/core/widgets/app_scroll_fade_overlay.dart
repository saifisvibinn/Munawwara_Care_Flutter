import 'package:flutter/material.dart';

import 'glass/app_glass_theme.dart';

/// Soft gradient bands at the top and bottom of scrollable regions so content
/// fades under the status bar and floating nav chrome instead of clipping hard.
///
/// Place above scroll content and below interactive chrome (nav bars, FABs,
/// floating back buttons) in a [Stack].
class AppScrollFadeOverlay extends StatelessWidget {
  const AppScrollFadeOverlay({
    super.key,
    required this.child,
    this.showTop = true,
    this.showBottom = true,
    this.topExtent,
    this.bottomExtent,
    this.backgroundColor,
    this.useDashboardBottomExtent = false,
    this.fadeOpacity = 1,
  });

  final Widget child;
  final bool showTop;
  final bool showBottom;
  final double? topExtent;
  final double? bottomExtent;
  final Color? backgroundColor;
  final double fadeOpacity;

  /// When true, bottom fade uses [AppGlassTheme.bottomNavScrollPadding] (dashboard
  /// tabs with floating nav). When false, uses safe-area bottom only.
  final bool useDashboardBottomExtent;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ?? AppGlassTheme.dashboardBackgroundColor(isDark);
    final keyboardOpen = AppGlassTheme.isKeyboardVisible(context);

    final resolvedTop = topExtent ?? AppGlassTheme.scrollFadeTopExtent(context);
    final resolvedBottom = bottomExtent ??
        (useDashboardBottomExtent
            ? AppGlassTheme.scrollFadeBottomExtentDashboard(context)
            : AppGlassTheme.scrollFadeBottomExtentStandalone(context));
    final solidFade = bg.withValues(alpha: fadeOpacity.clamp(0.0, 1.0));

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        child,
        if (showTop && resolvedTop > 0)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: resolvedTop,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [solidFade, bg.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        if (showBottom && !keyboardOpen && resolvedBottom > 0)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: resolvedBottom,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [solidFade, bg.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
