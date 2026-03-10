import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Brand – orange (matches Munawwara Care logo)
  static const Color primary = Color(0xFFF97316);
  static const Color primaryDark = Color(0xFFE05E0A);
  static const Color accentGold = Color(0xFFD4AF37);

  // Backgrounds
  static const Color backgroundLight = Color(0xFFF0F0F8); // lavender-white
  // Replaced warm near-black (orangey) with a neutral deep blue-black
  static const Color backgroundDark = Color(
    0xFF0B1220,
  ); // neutral deep blue-black

  // Card / surface
  static const Color surfaceLight = Color(0xFFFFFFFF);
  // Slightly lighter slate surface for dark mode cards
  static const Color surfaceDark = Color(0xFF121826); // deep slate surface

  // Text
  static const Color textDark = Color(0xFF1A1A4E); // navy title (light mode)
  static const Color textLight = Color(0xFFF1F5F9);
  static const Color textMutedDark = Color(0xFF64748B);
  static const Color textMutedLight = Color(0xFF94A3B8);
  // Dividers
  static const Color dividerLight = Color(0xFFE2E8F0);
  static const Color dividerDark = Color(0xFF25303A);
}
