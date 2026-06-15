import 'package:flutter/material.dart';

import 'glass/app_glass_theme.dart';
import 'glass/app_scroll_glass_edge.dart';

/// Soft glass bands at the top and bottom of scrollable regions so content
/// blurs under the status bar and floating nav chrome instead of clipping hard.
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
    this.enableGlass = true,
    this.overPlatformView = false,
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

  /// When false, falls back to the legacy solid gradient (reduced-transparency QA).
  final bool enableGlass;

  /// When true, skips [BackdropFilter] (required over iOS MapKit / [UiKitView]).
  final bool overPlatformView;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg =
        backgroundColor ?? AppGlassTheme.dashboardBackgroundColor(isDark);
    final keyboardOpen = AppGlassTheme.isKeyboardVisible(context);

    final resolvedTop = topExtent ?? AppGlassTheme.scrollFadeTopExtent(context);
    final resolvedBottom =
        bottomExtent ??
        (useDashboardBottomExtent
            ? AppGlassTheme.scrollFadeBottomExtentDashboard(context)
            : AppGlassTheme.scrollFadeBottomExtentStandalone(context));

    Widget edgeBand({
      required double height,
      required AppScrollGlassEdgeSide edge,
    }) {
      if (enableGlass) {
        return AppScrollGlassEdge(
          height: height,
          edge: edge,
          isDark: isDark,
          tintColor: backgroundColor,
          fadeOpacity: fadeOpacity,
          useBackdropBlur: !overPlatformView,
        );
      }
      return AppScrollSolidEdge(
        height: height,
        edge: edge,
        backgroundColor: bg,
        fadeOpacity: fadeOpacity,
      );
    }

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
            child: edgeBand(height: resolvedTop, edge: AppScrollGlassEdgeSide.top),
          ),
        if (showBottom && !keyboardOpen && resolvedBottom > 0)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: resolvedBottom,
            child: edgeBand(
              height: resolvedBottom,
              edge: AppScrollGlassEdgeSide.bottom,
            ),
          ),
      ],
    );
  }
}
