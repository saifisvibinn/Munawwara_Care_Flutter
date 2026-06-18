import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeKey = 'app_theme_mode'; // 'light' | 'dark' | 'system'

class ThemeNotifier extends Notifier<ThemeMode> {
  static ThemeMode? _bootThemeMode;

  /// Call from [main] after [SharedPreferences.getInstance] so the first frame
  /// uses the saved theme (or system) instead of a transient light default.
  static void prepareBootTheme(SharedPreferences prefs) {
    final val = prefs.getString(_kThemeKey) ?? 'system';
    _bootThemeMode = _fromString(val);
  }

  @override
  ThemeMode build() {
    final boot = _bootThemeMode;
    if (boot != null) {
      _bootThemeMode = null;
      return boot;
    }
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_kThemeKey) ?? 'system';
    if (state != _fromString(val)) {
      state = _fromString(val);
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    // Persist without blocking the frame — avoids any perceived lag on
    // toggle before MaterialApp + bottom chrome rebuild.
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString(_kThemeKey, _toString(mode)),
    );
  }

  Future<void> toggle() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setMode(next);
  }

  bool get followsSystem => state == ThemeMode.system;

  Future<void> setFollowSystem(
    bool follow, {
    required bool effectiveIsDark,
  }) async {
    if (follow) {
      await setMode(ThemeMode.system);
      return;
    }
    await setMode(effectiveIsDark ? ThemeMode.dark : ThemeMode.light);
  }

  Future<void> setDarkEnabled(bool enabled) async {
    if (followsSystem) return;
    await setMode(enabled ? ThemeMode.dark : ThemeMode.light);
  }

  bool get isDark => state == ThemeMode.dark;

  static String _toString(ThemeMode m) {
    switch (m) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      default:
        return 'system';
    }
  }

  static ThemeMode _fromString(String s) {
    switch (s) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(
  ThemeNotifier.new,
);
