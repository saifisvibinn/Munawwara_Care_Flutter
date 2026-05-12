import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'app_colors.dart';

// Lexend is declared in pubspec.yaml fonts section.
// Do NOT use GoogleFonts.lexend() at runtime — it makes network requests that
// cause ANR on emulators. Use TextStyle(fontFamily: 'Lexend') directly.

class AppTheme {
  AppTheme._();

  /// Kept in sync with [MaterialApp.themeAnimationDuration] so custom chrome
  /// (e.g. bottom bars) lerps at the same rate as the rest of the app.
  static const Duration themeSwitchDuration = Duration(milliseconds: 180);

  static const Curve themeSwitchCurve = Curves.easeOutCubic;

  /// Same rule as [MaterialApp] theme mode — use this for chrome that must
  /// flip with the toggle immediately (do not use [Theme.of] brightness
  /// during [AnimatedTheme], it can lag behind the rest of the UI).
  static bool isDarkEffective(ThemeMode mode, BuildContext context) {
    return switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
  }

  static const _textTheme = TextTheme(
    displayLarge: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w700),
    displayMedium: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w700),
    displaySmall: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600),
    headlineLarge: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600),
    headlineMedium: TextStyle(
      fontFamily: 'Lexend',
      fontWeight: FontWeight.w600,
    ),
    headlineSmall: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w500),
    titleLarge: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600),
    titleMedium: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w500),
    titleSmall: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w500),
    bodyLarge: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w400),
    bodyMedium: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w400),
    bodySmall: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w400),
    labelLarge: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w500),
    labelMedium: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w400),
  );

  static ThemeData get lightTheme {
    return _buildTheme(Brightness.light);
  }

  static ThemeData get darkTheme {
    return _buildTheme(Brightness.dark);
  }

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primaryColor = AppColors.primary;
    final backgroundColor = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final surfaceColor = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: brightness,
        surface: backgroundColor,
      ),
      textTheme: _textTheme.apply(
        bodyColor: textPrimary,
        displayColor: textPrimary,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: primaryColor,
        unselectedItemColor: textMuted,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.r),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 18.sp,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 14.sp,
          color: textMuted,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
          textStyle: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 16.sp,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
          ),
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
          textStyle: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 16.sp,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          textStyle: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w600,
            fontSize: 14.sp,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark 
            ? AppColors.surfaceDark 
            : AppColors.iconBgLight.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        labelStyle: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 12.sp,
          color: textMuted,
        ),
        hintStyle: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 14.sp,
          color: textMuted,
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      ),
    );
  }
}
