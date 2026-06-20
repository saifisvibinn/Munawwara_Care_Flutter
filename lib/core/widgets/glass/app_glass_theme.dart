import 'dart:io';

import 'package:cupertino_liquid_glass/cupertino_liquid_glass.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/app_colors.dart';

/// Shared liquid glass styling aligned with [AppLiquidGlassBottomBar].
///
/// Design intent follows Apple's Liquid Glass guidance: glass belongs on the
/// **functional layer** (navigation, toolbars, key controls) so underlying
/// content stays in focus. See:
/// https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass
///
/// Rules we follow in this app:
/// - One glass layer per visual block (no nested glass-on-glass).
/// - Reserve glass for nav chrome, headers, FABs, and primary dashboard cards.
/// - Keep list rows, form fields, and chat bubbles solid for legibility.
/// - Use [bottomNavScrollPadding] so scroll content clears the floating tab bar
///   (scroll-edge separation, similar to iOS scroll edge effects).
/// - Set [enableGlass] false on [AppGlassSurface] for reduced-transparency QA.
class AppGlassTheme {
  AppGlassTheme._();

  /// Backdrop blur intensity. Reduce if profiling shows scroll jank.
  static const double blurSigma = 28;

  /// Blur for scroll-edge bands — slightly lighter than card glass for map perf.
  static const double scrollEdgeBlurSigma = 20;

  /// iOS scroll edges — tuned to approximate [UIBlurEffect] thin material.
  static const double scrollEdgeBlurSigmaIos = 26;

  /// True on native iOS (not web).
  static bool get isIos => !kIsWeb && Platform.isIOS;

  /// Blur sigma for scroll-edge bands on the current platform.
  static double scrollEdgeBlurForPlatform() =>
      isIos ? scrollEdgeBlurSigmaIos : scrollEdgeBlurSigma;

  /// Tint strength at the solid edge of a scroll glass band (Android / fallback).
  static double scrollEdgeTintOpacity(bool isDark) =>
      isDark ? 0.55 : 0.65;

  /// Map vignette tint for bottom glass edges over map tiles.
  static Color mapVignetteTintColor(bool isDark) =>
      isDark ? Colors.black : Colors.black;

  /// Concentric with floating tab bar (26pt system-style radius).
  static BorderRadius get borderRadius => BorderRadius.circular(26.r);

  static BorderRadius get cardRadius => BorderRadius.circular(24.r);

  static BorderRadius get iconButtonRadius => BorderRadius.circular(22.r);

  /// Tight gap between a toolbar control and its anchored popover (iOS inline).
  static Offset get popoverGapBelowTrigger => Offset(0, 8.h);

  /// Lighter glass for anchored popovers — map/content stays visible through
  /// the panel (Apple context-menu / dock-style material, not a solid sheet).
  static LiquidGlassThemeData popoverOf(bool isDark) {
    return of(isDark).copyWith(
      blurSigma: 18,
      tintOpacity: isDark ? 0.38 : 0.32,
      vibrancyIntensity: isDark ? 0.1 : 0.06,
      specularOpacity: isDark ? 0.16 : 0.18,
    );
  }

  /// Opaque nav context pill for group broadcast screens — no specular sheen.
  static LiquidGlassThemeData groupBroadcastNavPillOf(bool isDark) {
    return of(isDark).copyWith(
      blurSigma: 24,
      tintOpacity: isDark ? 0.88 : 0.94,
      vibrancyIntensity: 0,
      specularOpacity: 0,
      borderWidth: 0.5,
      edgeLightColor: isDark
          ? const Color(0x28FFFFFF)
          : const Color(0x35FFFFFF),
    );
  }

  /// Height of the top glass band behind group-broadcast floating nav rows.
  static double groupBroadcastNavGlassHeight(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top + 10.h + 44.w + 6.h;

  static LiquidGlassThemeData of(bool isDark) =>
      isDark ? LiquidGlassThemeData.dark() : LiquidGlassThemeData.light();

  /// Matches [AppDashboardBackground] so PageView underlays never peek through.
  static Color dashboardBackgroundColor(bool isDark) =>
      isDark ? AppColors.backgroundDark : const Color(0xFFF7F9FB);

  /// Glass pill content height (vertical padding + tab row).
  static double get bottomBarPillHeight => 6.h + 52.h + 6.h;

  /// Total height of [AppLiquidGlassBottomBar] from the physical screen bottom.
  /// Includes the home-indicator inset applied inside the bar widget.
  static double floatingBottomBarHeight(BuildContext context) {
    return MediaQuery.viewPaddingOf(context).bottom + bottomBarPillHeight;
  }

  /// [Positioned] `bottom` offset — bar is flush with the screen bottom.
  static double floatingBottomBarBottomOffset(BuildContext context) => 0;

  /// Bottom scroll padding so content clears the floating glass nav bar.
  /// Includes [bottomNavScrollPaddingExtra] so primary buttons are not clipped.
  static double get bottomNavScrollPaddingExtra => 32.h;

  /// Fade band above the nav bar — taller than scroll padding so list content
  /// scrolls under the glass edge and blur is visible.
  static double get scrollEdgeBottomFadeBand => 40.h;

  static double bottomNavScrollPadding(BuildContext context) =>
      floatingBottomBarHeight(context) + bottomNavScrollPaddingExtra;

  /// True when the software keyboard is open.
  static bool isKeyboardVisible(BuildContext context) =>
      MediaQuery.viewInsetsOf(context).bottom > 0;

  /// Bottom padding for dashboard tab scroll views.
  /// Uses keyboard inset when open; otherwise clears the floating tab bar.
  /// Slightly less than [scrollFadeBottomExtentDashboard] so content scrolls
  /// into the bottom glass band.
  static double dashboardScrollBottomPadding(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard > 0) return keyboard + 16.h;
    return floatingBottomBarHeight(context) + 16.h;
  }

  /// Bottom inset for map overlay controls (locate, suggestions, hospitals).
  static double mapControlsBottomInset(BuildContext context) =>
      floatingBottomBarHeight(context) + 40.h;

  /// Glass pill height for the Provision / Activation / Manage sub-nav.
  static double get provisionSubNavPillHeight => 6.h + 48.h + 6.h;

  /// Top inset for the floating provisioning sub-nav (below status bar).
  static double provisionSubNavTopOffset(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top + 8.h;

  /// Top scroll padding so content clears the floating provisioning sub-nav.
  static double provisionSubNavScrollPadding(BuildContext context) {
    if (isKeyboardVisible(context)) {
      return MediaQuery.viewPaddingOf(context).top + 8.h;
    }
    return provisionSubNavTopOffset(context) + provisionSubNavPillHeight + 8.h;
  }

  /// Height of the top scroll-edge fade band (status bar + soft falloff).
  static double scrollFadeTopExtent(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top + 20.h;

  /// Bottom fade for dashboard tabs that sit above the floating glass nav bar.
  static double scrollFadeBottomExtentDashboard(BuildContext context) =>
      floatingBottomBarHeight(context) + scrollEdgeBottomFadeBand;

  /// Bottom offset for dashboard glass FABs (e.g. create/join group speed dial).
  ///
  /// Must sit above [scrollFadeBottomExtentDashboard] so [AppGlassSurface]
  /// backdrop blur samples scroll content only — not the scroll-edge fade band
  /// (which would double-blur and show a horizontal seam through the circle).
  static double dashboardFabBottomOffset(BuildContext context) =>
      scrollFadeBottomExtentDashboard(context) + 16.h;

  /// Native map / visual glass band at bottom — covers tab bar, not full scroll pad.
  static double mapScrollEdgeBottomExtent(BuildContext context) =>
      floatingBottomBarHeight(context) + 28.h;

  /// Bottom fade for standalone pushed screens (no floating tab bar).
  static double scrollFadeBottomExtentStandalone(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).bottom + 20.h;

  /// Top fade for provisioning — covers status bar + floating sub-nav pill.
  static double scrollFadeProvisioningTopExtent(BuildContext context) =>
      provisionSubNavScrollPadding(context) + 12.h;
}
