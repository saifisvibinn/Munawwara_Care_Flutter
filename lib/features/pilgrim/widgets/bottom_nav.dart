import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pilgrim Bottom Navigation Bar
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

  // Maps nav-bar slot → tab index in the dashboard PageView.
  static const _tabIndices = [0, 1, 2, 3];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final isDark = AppTheme.isDarkEffective(themeMode, context);
    final labels = [
      'tab_home'.tr(),
      'tab_map'.tr(),
      'tab_muslim'.tr(),
      'tab_announcements'.tr(),
    ];
    final icons = [
      Symbols.home,
      Symbols.map,
      Symbols.folded_hands,
      Symbols.campaign,
    ];
    // Badge counts per slot (announcements tab only)
    final badges = [0, 0, 0, unreadMessages];

    final bgColor = isDark ? AppColors.surfaceDark : Colors.white;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);
    final unselectedIconColor =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(
          top: BorderSide(color: dividerColor, width: 1),
        ),
      ),
      height: 66.h + MediaQuery.of(context).padding.bottom,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      child: Row(
        children: List.generate(4, (slot) {
          final tabIndex = _tabIndices[slot];
          final isSelected = tabIndex == currentIndex;
          final badge = badges[slot];

          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(tabIndex),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: AppTheme.themeSwitchDuration,
                        curve: AppTheme.themeSwitchCurve,
                        width: 44.w,
                        height: 32.h,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark
                                  ? AppColors.iconBgDark
                                  : AppColors.iconBgLight)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Icon(
                          icons[slot],
                          size: slot == 3 ? 24.w : 22.w,
                          color: isSelected
                              ? AppColors.primary
                              : unselectedIconColor,
                        ),
                      ),
                      if (badge > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            padding: EdgeInsets.all(3.w),
                            decoration: const BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                            ),
                            constraints: BoxConstraints(
                              minWidth: 14.w,
                              minHeight: 14.w,
                            ),
                            child: Text(
                              badge > 9 ? '9+' : '$badge',
                              style: TextStyle(
                                fontSize: 9.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    labels[slot],
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 10.sp,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                      color: isSelected
                          ? AppColors.primary
                          : unselectedIconColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
