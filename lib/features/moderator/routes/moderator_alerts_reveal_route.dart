import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../notifications/screens/alerts_tab_v2.dart';

/// Full-screen alerts — same [MaterialPageRoute] push as [ResourcesScreen].
Route<void> buildModeratorAlertsRoute() {
  return MaterialPageRoute<void>(
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return Scaffold(
        backgroundColor:
            isDark ? AppColors.backgroundDark : const Color(0xFFF7F9FB),
        body: AlertsTab(
          onBack: () => Navigator.of(ctx).pop(),
        ),
      );
    },
  );
}

void openModeratorAlertsWithReveal(BuildContext context) {
  Navigator.of(context).push(buildModeratorAlertsRoute());
}
