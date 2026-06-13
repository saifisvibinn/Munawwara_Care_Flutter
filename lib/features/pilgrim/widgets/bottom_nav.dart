import 'package:cupertino_liquid_glass/cupertino_liquid_glass.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_liquid_glass_bottom_bar.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim Bottom Navigation Bar — iOS Liquid Glass (cupertino_liquid_glass)
// ─────────────────────────────────────────────────────────────────────────────

class PilgrimBottomNav extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int unreadMessages;

  const PilgrimBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.unreadMessages,
  });

  static const _tabIndices = [0, 1, 2, 3];

  int get _selectedSlot {
    final slot = _tabIndices.indexOf(currentIndex);
    return slot >= 0 ? slot : 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark =
        AppTheme.isDarkEffective(ref.watch(themeProvider), context);

    final items = [
      LiquidGlassBottomBarItem(
        icon: Symbols.home,
        label: 'tab_home'.tr(),
      ),
      LiquidGlassBottomBarItem(
        icon: Symbols.map,
        label: 'tab_map'.tr(),
      ),
      LiquidGlassBottomBarItem(
        icon: Symbols.folded_hands,
        label: 'tab_muslim'.tr(),
      ),
      LiquidGlassBottomBarItem(
        icon: Symbols.campaign,
        label: 'tab_announcements'.tr(),
      ),
    ];

    return AppLiquidGlassBottomBar(
      currentIndex: _selectedSlot,
      onTap: (slot) => onTap(_tabIndices[slot]),
      items: items,
      isDark: isDark,
      badges: [0, 0, 0, unreadMessages],
    );
  }
}
