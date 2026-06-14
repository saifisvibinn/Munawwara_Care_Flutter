import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Keeps status bar and navigation bar icon brightness in sync with [themeMode].
///
/// Applies both [AnnotatedRegion] and [SystemChrome.setSystemUIOverlayStyle] so
/// iOS clock/battery icons update when the in-app theme or system brightness
/// changes under edge-to-edge layout.
class AppSystemUiScope extends StatefulWidget {
  const AppSystemUiScope({
    super.key,
    required this.themeMode,
    required this.child,
  });

  final ThemeMode themeMode;
  final Widget child;

  @override
  State<AppSystemUiScope> createState() => _AppSystemUiScopeState();
}

class _AppSystemUiScopeState extends State<AppSystemUiScope>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDarkEffective(widget.themeMode, context);
    final style = AppTheme.systemUiOverlayStyle(isDark: isDark);
    SystemChrome.setSystemUIOverlayStyle(style);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: style,
      sized: false,
      child: widget.child,
    );
  }
}
