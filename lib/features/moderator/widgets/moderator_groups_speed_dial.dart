import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';

/// Create / join group entry from the moderator dashboard (glass FAB + actions).
///
/// Menu presentation follows iOS / Liquid Glass patterns: one grouped glass
/// capsule, hairline dividers, spring scale-in, and staggered row reveals.
class ModeratorGroupsSpeedDial extends StatefulWidget {
  const ModeratorGroupsSpeedDial({
    super.key,
    required this.onCreateGroup,
    required this.onJoinGroup,
  });

  final VoidCallback onCreateGroup;
  final VoidCallback onJoinGroup;

  @override
  State<ModeratorGroupsSpeedDial> createState() =>
      _ModeratorGroupsSpeedDialState();
}

class _ModeratorGroupsSpeedDialState extends State<ModeratorGroupsSpeedDial>
    with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  late AnimationController _controller;

  static const _openSpring = SpringDescription(
    mass: 0.85,
    stiffness: 380.0,
    damping: 24.0,
  );

  static const _menuGap = 12.0;
  static const _closeDuration = Duration(milliseconds: 220);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, value: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    _controller.animateWith(
      SpringSimulation(
        _openSpring,
        _controller.value.clamp(0.0, 1.0),
        1.0,
        0,
      ),
    );
  }

  void _close() {
    _controller.animateTo(
      0,
      duration: _closeDuration,
      curve: Curves.easeInCubic,
    );
  }

  void _toggle() {
    final opening = !_isOpen;
    setState(() => _isOpen = opening);
    HapticFeedback.lightImpact();
    if (opening) {
      _open();
    } else {
      _close();
    }
  }

  void _closeThen(VoidCallback action) {
    HapticFeedback.selectionClick();
    if (_isOpen) {
      setState(() => _isOpen = false);
      _close();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final menuT = _controller.value.clamp(0.0, 1.0);
        final menuVisible = menuT > 0.001;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (menuVisible)
              IgnorePointer(
                ignoring: menuT < 0.15,
                child: Transform.scale(
                  scale: 0.86 + 0.14 * menuT,
                  alignment: Alignment.bottomRight,
                  child: Transform.translate(
                    offset: Offset(0, (1 - menuT) * 10.h),
                    child: SizedBox(
                      width: 268.w,
                      child: AppGlassSurface(
                        isDark: isDark,
                        borderRadius: AppGlassTheme.borderRadius,
                        padding: EdgeInsets.zero,
                        child: ClipRRect(
                          borderRadius: AppGlassTheme.borderRadius,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _ActionRow(
                                slideT: _rowSlide(menuT, delay: 0),
                                isDark: isDark,
                                label: 'dashboard_create_group'.tr(),
                                icon: Symbols.group_add,
                                onTap: () => _closeThen(widget.onCreateGroup),
                              ),
                              Divider(
                                height: 0.5,
                                thickness: 0.5,
                                color: dividerColor,
                              ),
                              _ActionRow(
                                slideT: _rowSlide(menuT, delay: 0.08),
                                isDark: isDark,
                                label: 'join_group'.tr(),
                                icon: Symbols.qr_code_scanner,
                                onTap: () => _closeThen(widget.onJoinGroup),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            SizedBox(height: menuT * _menuGap.h),
            _GlassFab(
              isDark: isDark,
              openProgress: menuT,
              onTap: _toggle,
            ),
          ],
        );
      },
    );
  }

  /// Stagger row slide on open; rows move together on close (same [menuT]).
  double _rowSlide(double menuT, {required double delay}) {
    if (_controller.status == AnimationStatus.reverse ||
        (!_isOpen && _controller.isAnimating)) {
      return menuT;
    }
    if (menuT <= delay) return 0;
    return ((menuT - delay) / (1 - delay)).clamp(0.0, 1.0);
  }
}

/// Primary 56pt glass FAB — same role as map overlay controls (see liquid-glass-ui.md).
class _GlassFab extends StatelessWidget {
  const _GlassFab({
    required this.isDark,
    required this.openProgress,
    required this.onTap,
  });

  final bool isDark;
  final double openProgress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AppGlassSurface(
        isDark: isDark,
        borderRadius: BorderRadius.circular(28.r),
        width: 56.w,
        height: 56.w,
        child: Center(
          child: Transform.rotate(
            angle: openProgress * 0.785398, // π/4 → + to ×
            child: Icon(
              Symbols.add,
              size: 28.w,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS Settings–style action row inside a grouped glass menu.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.slideT,
    required this.isDark,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final double slideT;
  final bool isDark;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;

    return Transform.translate(
      offset: Offset(0, (1 - slideT) * 6.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 48.h),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                child: Row(
                  children: [
                    Container(
                      width: 32.w,
                      height: 32.w,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary.withValues(
                          alpha: isDark ? 0.22 : 0.12,
                        ),
                      ),
                      child: Icon(
                        icon,
                        size: 18.w,
                        color: AppColors.primary,
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 14.sp,
                          height: 1.2,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
