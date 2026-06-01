import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';

/// Create / join group entry from the moderator dashboard (FAB + two actions).
class ModeratorGroupsSpeedDial extends StatefulWidget {
  const ModeratorGroupsSpeedDial({
    super.key,
    required this.onCreateGroup,
    required this.onJoinGroup,
  });

  final VoidCallback onCreateGroup;
  final VoidCallback onJoinGroup;

  @override
  State<ModeratorGroupsSpeedDial> createState() => _ModeratorGroupsSpeedDialState();
}

class _ModeratorGroupsSpeedDialState extends State<ModeratorGroupsSpeedDial>
    with SingleTickerProviderStateMixin {
  bool _isOpen = false;
  late AnimationController _controller;
  late Animation<double> _expandAnimation;

  static const _fabOrange = Color(0xFFF97316);
  static const _optionSpacing = 10.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      value: 0.0,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
      parent: _controller,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isOpen = !_isOpen;
      if (_isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  void _closeThen(VoidCallback action) {
    if (_isOpen) {
      setState(() => _isOpen = false);
      _controller.reverse();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        final t = _expandAnimation.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              heightFactor: t <= 0 ? 0.0 : t,
              child: IgnorePointer(
                ignoring: t < 0.02,
                child: Opacity(
                  opacity: t,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 14),
                    child: Transform.scale(
                      scale: 0.86 + 0.14 * t,
                      alignment: Alignment.bottomCenter,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: t * _optionSpacing.h),
            FloatingActionButton(
              heroTag: 'mod_dashboard_groups_fab',
              onPressed: _toggle,
              backgroundColor: _fabOrange,
              foregroundColor: Colors.white,
              shape: const CircleBorder(),
              elevation: 6,
              child: AnimatedRotation(
                turns: _isOpen ? 0.125 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Icon(Symbols.add, size: 28.w),
              ),
            ),
          ],
        );
      },
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SpeedDialChip(
              isDark: isDark,
              label: 'dashboard_create_group'.tr(),
              icon: Symbols.group_add,
              onTap: () => _closeThen(widget.onCreateGroup),
            ),
            SizedBox(height: _optionSpacing.h),
            _SpeedDialChip(
              isDark: isDark,
              label: 'join_group'.tr(),
              icon: Symbols.qr_code_scanner,
              onTap: () => _closeThen(widget.onJoinGroup),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedDialChip extends StatelessWidget {
  final bool isDark;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SpeedDialChip({
    required this.isDark,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(24.r);
    return Material(
      color: isDark ? AppColors.surfaceDark : Colors.white,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: r),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: r,
        child: SizedBox(
          height: 46.h,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18.w, color: const Color(0xFFF97316)),
                SizedBox(width: 8.w),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 13.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
