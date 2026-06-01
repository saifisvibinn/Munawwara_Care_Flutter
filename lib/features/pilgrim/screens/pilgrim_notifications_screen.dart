import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../notifications/screens/alerts_tab_v2.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim Notifications Screen — wraps AlertsTab in a Scaffold with back nav
// ─────────────────────────────────────────────────────────────────────────────

class PilgrimNotificationsScreen extends StatelessWidget {
  /// When true (e.g. home missed-calls chip), list is filtered to missed only.
  /// Unread missed calls are marked read when the list is shown.
  final bool missedCallsOnly;

  const PilgrimNotificationsScreen({
    super.key,
    this.missedCallsOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : const Color(0xfff1f5f3),
      body: SafeArea(
        child: AlertsTab(
          onBack: () => Navigator.of(context).pop(),
          pilgrimMissedCallsOnly: missedCallsOnly,
        ),
      ),
    );
  }
}
