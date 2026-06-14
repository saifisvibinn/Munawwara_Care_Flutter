import 'package:cupertino_liquid_glass/cupertino_liquid_glass.dart';
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

  static double bottomNavScrollPadding(BuildContext context) =>
      floatingBottomBarHeight(context) + bottomNavScrollPaddingExtra;

  /// True when the software keyboard is open.
  static bool isKeyboardVisible(BuildContext context) =>
      MediaQuery.viewInsetsOf(context).bottom > 0;

  /// Bottom padding for dashboard tab scroll views.
  /// Uses keyboard inset when open; otherwise clears the floating tab bar.
  static double dashboardScrollBottomPadding(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard > 0) return keyboard + 16.h;
    return bottomNavScrollPadding(context);
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
}
