import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_glass_theme.dart';
import 'app_native_scroll_glass_edge.dart';

/// Which screen edge the glass band sits on.
enum AppScrollGlassEdgeSide { top, bottom }

/// Blurred scroll-edge band — liquid-glass treatment over live content.
///
/// On iOS uses native [UIVisualEffectView] (same as MapKit edges). On other
/// platforms uses [BackdropFilter] with a light material tint.
class AppScrollGlassEdge extends StatelessWidget {
  const AppScrollGlassEdge({
    super.key,
    required this.height,
    required this.edge,
    required this.isDark,
    this.tintColor,
    this.blurSigma,
    this.tintOpacity,
    this.fadeOpacity = 1,
    this.useBackdropBlur = true,
  });

  final double height;
  final AppScrollGlassEdgeSide edge;
  final bool isDark;
  final Color? tintColor;
  final double? blurSigma;
  final double? tintOpacity;
  final double fadeOpacity;

  /// When false, renders a translucent tint gradient only.
  ///
  /// Required over iOS [UiKitView] / MapKit — [BackdropFilter] cannot sample
  /// platform views and can trigger `recreating_view` crashes.
  final bool useBackdropBlur;

  @override
  Widget build(BuildContext context) {
    if (height <= 0) return const SizedBox.shrink();

    if (!useBackdropBlur) {
      return _tintOnlyEdge();
    }

    if (AppGlassTheme.isIos) {
      return IgnorePointer(
        child: AppNativeScrollGlassEdge(
          height: height,
          fadesFromTop: edge == AppScrollGlassEdgeSide.top,
          isDark: isDark,
        ),
      );
    }

    return _flutterBlurEdge();
  }

  Widget _tintOnlyEdge() {
    final baseTint =
        tintColor ?? AppGlassTheme.dashboardBackgroundColor(isDark);
    final resolvedTintOpacity =
        (tintOpacity ?? AppGlassTheme.scrollEdgeTintOpacity(isDark)) *
        fadeOpacity.clamp(0.0, 1.0);

    final begin = edge == AppScrollGlassEdgeSide.top
        ? Alignment.topCenter
        : Alignment.bottomCenter;
    final end = edge == AppScrollGlassEdgeSide.top
        ? Alignment.bottomCenter
        : Alignment.topCenter;

    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: begin,
              end: end,
              stops: const [0.0, 0.4, 1.0],
              colors: [
                baseTint.withValues(alpha: resolvedTintOpacity * 0.5),
                baseTint.withValues(alpha: resolvedTintOpacity * 0.18),
                baseTint.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _flutterBlurEdge() {
    final resolvedBlur = blurSigma ?? AppGlassTheme.scrollEdgeBlurForPlatform();
    final resolvedTintOpacity =
        (tintOpacity ?? AppGlassTheme.scrollEdgeTintOpacity(isDark)) *
        fadeOpacity.clamp(0.0, 1.0);

    final begin = edge == AppScrollGlassEdgeSide.top
        ? Alignment.topCenter
        : Alignment.bottomCenter;
    final end = edge == AppScrollGlassEdgeSide.top
        ? Alignment.bottomCenter
        : Alignment.topCenter;

    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: ClipRect(
          child: ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              begin: begin,
              end: end,
              colors: const [Colors.white, Colors.transparent],
              stops: const [0.0, 1.0],
            ).createShader(bounds),
            blendMode: BlendMode.dstIn,
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: resolvedBlur,
                sigmaY: resolvedBlur,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: begin,
                    end: end,
                    colors: [
                      Colors.white.withValues(alpha: resolvedTintOpacity * 0.15),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Solid-color gradient fallback when glass blur is disabled.
class AppScrollSolidEdge extends StatelessWidget {
  const AppScrollSolidEdge({
    super.key,
    required this.height,
    required this.edge,
    required this.backgroundColor,
    this.fadeOpacity = 1,
  });

  final double height;
  final AppScrollGlassEdgeSide edge;
  final Color backgroundColor;
  final double fadeOpacity;

  @override
  Widget build(BuildContext context) {
    if (height <= 0) return const SizedBox.shrink();

    final solidFade = backgroundColor.withValues(
      alpha: fadeOpacity.clamp(0.0, 1.0),
    );
    final begin = edge == AppScrollGlassEdgeSide.top
        ? Alignment.topCenter
        : Alignment.bottomCenter;
    final end = edge == AppScrollGlassEdgeSide.top
        ? Alignment.bottomCenter
        : Alignment.topCenter;

    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: begin,
              end: end,
              colors: [solidFade, backgroundColor.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}
