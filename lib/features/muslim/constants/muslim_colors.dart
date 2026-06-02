import 'package:flutter/material.dart';

/// Palette aligned with the Islamic Corner Stitch mockups.
class MuslimColors {
  MuslimColors._();

  static const Color primary = Color(0xFF154212);
  static const Color primaryContainer = Color(0xFF2D5A27);
  static const Color onPrimaryContainer = Color(0xFF9DD090);
  static const Color primaryFixed = Color(0xFFBCF0AE);

  static const Color secondary = Color(0xFF904D00);
  static const Color secondaryContainer = Color(0xFFFE932C);
  static const Color onSecondaryContainer = Color(0xFF663500);
  static const Color secondaryFixed = Color(0xFFFFDCC3);

  static const Color tertiary = Color(0xFF00328B);
  static const Color tertiaryContainer = Color(0xFF0046BC);
  static const Color tertiaryFixed = Color(0xFFDBE1FF);
  static const Color onTertiaryContainer = Color(0xFFAEC1FF);

  static const Color surface = Color(0xFFF7F9FB);
  static const Color surfaceContainerLow = Color(0xFFF2F4F6);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF191C1E);
  static const Color onSurfaceVariant = Color(0xFF42493E);
  static const Color outlineVariant = Color(0xFFC2C9BB);

  static const Color surfaceDark = Color(0xFF121826);
  static const Color onSurfaceDark = Color(0xFFEFF1F3);
}

extension MuslimThemeExt on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get mPrimary => isDark ? MuslimColors.primaryFixed : MuslimColors.primary;
  Color get mPrimaryContainer => isDark ? const Color(0xFF1A3B18) : MuslimColors.primaryContainer;
  Color get mOnPrimaryContainer => isDark ? MuslimColors.primaryFixed : MuslimColors.onPrimaryContainer;

  Color get mSecondary => isDark ? MuslimColors.secondaryFixed : MuslimColors.secondary;
  Color get mSecondaryContainer => isDark ? const Color(0xFF7A4000) : MuslimColors.secondaryContainer;
  Color get mOnSecondaryContainer => isDark ? MuslimColors.secondaryFixed : MuslimColors.onSecondaryContainer;

  Color get mTertiary => isDark ? MuslimColors.tertiaryFixed : MuslimColors.tertiary;
  Color get mTertiaryContainer => isDark ? const Color(0xFF002B7A) : MuslimColors.tertiaryContainer;
  Color get mOnTertiaryContainer => isDark ? MuslimColors.tertiaryFixed : MuslimColors.onTertiaryContainer;

  Color get mPrimaryFixed => MuslimColors.primaryFixed;
  Color get mSecondaryFixed => MuslimColors.secondaryFixed;
  Color get mTertiaryFixed => MuslimColors.tertiaryFixed;

  Color get mSurface => isDark ? MuslimColors.surfaceDark : MuslimColors.surface;
  Color get mSurfaceContainerLow => isDark ? const Color(0xFF1C2331) : MuslimColors.surfaceContainerLow;
  Color get mSurfaceContainerLowest => isDark ? const Color(0xFF161D29) : MuslimColors.surfaceContainerLowest;
  
  Color get mOnSurface => isDark ? MuslimColors.onSurfaceDark : MuslimColors.onSurface;
  Color get mOnSurfaceVariant => isDark ? const Color(0xFF9AA0A6) : MuslimColors.onSurfaceVariant;
  Color get mOutlineVariant => isDark ? const Color(0xFF3C444D) : MuslimColors.outlineVariant;
}
