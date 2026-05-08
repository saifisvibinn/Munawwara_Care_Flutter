import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../notifications/screens/alerts_tab.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim Notifications Screen — wraps AlertsTab in a Scaffold with back nav
// ─────────────────────────────────────────────────────────────────────────────

class PilgrimNotificationsScreen extends StatelessWidget {
  const PilgrimNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : const Color(0xfff1f5f3),
      body: SafeArea(
        child: AlertsTab(onBack: () => Navigator.of(context).pop()),
      ),
    );
  }
}
