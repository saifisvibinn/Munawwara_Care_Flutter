import 'package:cupertino_liquid_glass/cupertino_liquid_glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';

/// iOS 26–style floating liquid glass bottom tab bar (see cupertino_liquid_glass docs).
///
/// Requires [Scaffold.extendBody] = true on the parent so content scrolls behind
/// the frosted bar.
class AppLiquidGlassBottomBar extends StatelessWidget {
  const AppLiquidGlassBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    required this.isDark,
    this.badges = const [],
    this.horizontalMargin,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<LiquidGlassBottomBarItem> items;
  final bool isDark;
  final List<int> badges;
  final double? horizontalMargin;

  @override
  Widget build(BuildContext context) {
    final margin = horizontalMargin ?? 12.w;
    final inactiveColor =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final glassTheme =
        isDark ? LiquidGlassThemeData.dark() : LiquidGlassThemeData.light();
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        CupertinoLiquidGlassBottomBar(
          currentIndex: currentIndex,
          onTap: onTap,
          items: items,
          activeColor: AppColors.primary,
          inactiveColor: inactiveColor,
          theme: glassTheme,
          horizontalMargin: margin,
          useSafeArea: true,
          enableGlass: true,
        ),
        if (badges.any((count) => count > 0))
          Padding(
            padding: EdgeInsets.only(
              left: margin,
              right: margin,
              bottom: bottomInset + 30.h,
            ),
            child: SizedBox(
              height: 52.h,
              child: Row(
                children: List.generate(items.length, (index) {
                  final count =
                      index < badges.length ? badges[index] : 0;
                  return Expanded(
                    child: count > 0
                        ? Align(
                            alignment: const Alignment(0.35, -0.55),
                            child: _TabBadge(count: count),
                          )
                        : const SizedBox.shrink(),
                  );
                }),
              ),
            ),
          ),
      ],
    );
  }
}

class _TabBadge extends StatelessWidget {
  const _TabBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      decoration: const BoxDecoration(
        color: Colors.orange,
        shape: BoxShape.circle,
      ),
      constraints: BoxConstraints(minWidth: 16.w, minHeight: 16.w),
      child: Text(
        count > 9 ? '9+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 9.sp,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}
