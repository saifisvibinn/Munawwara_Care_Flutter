import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../theme/app_colors.dart';
import 'glass/app_glass.dart';

/// One tab in [AppLiquidGlassBottomBar].
class AppBottomBarItem {
  const AppBottomBarItem({
    required this.icon,
    required this.label,
    this.activeIcon,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String label;
}

/// Floating liquid-glass bottom tab bar with drag-to-slide selection.
///
/// Position at the bottom of a dashboard [Stack] overlay (offset 0) — do not
/// use [Scaffold.bottomNavigationBar] (avoids a solid cutout band).
class AppLiquidGlassBottomBar extends StatefulWidget {
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
  final List<AppBottomBarItem> items;
  final bool isDark;
  final List<int> badges;
  final double? horizontalMargin;

  @override
  State<AppLiquidGlassBottomBar> createState() =>
      _AppLiquidGlassBottomBarState();
}

class _AppLiquidGlassBottomBarState extends State<AppLiquidGlassBottomBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late final ValueNotifier<double> _position;
  late final ValueNotifier<double> _velocity;

  bool _isDragging = false;
  final List<_VelocitySample> _velocitySamples = [];

  static const _spring = SpringDescription(
    mass: 1.0,
    stiffness: 320.0,
    damping: 22.0,
  );

  int get _maxIndex => widget.items.length - 1;

  @override
  void initState() {
    super.initState();
    final initial = widget.currentIndex.toDouble();
    _position = ValueNotifier(initial);
    _velocity = ValueNotifier(0);
    _controller = AnimationController.unbounded(vsync: this, value: initial)
      ..addListener(() {
        _position.value = _controller.value;
        _velocity.value = _controller.velocity;
      });
  }

  @override
  void didUpdateWidget(AppLiquidGlassBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex && !_isDragging) {
      _animateTo(widget.currentIndex, initialVelocity: _velocity.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _position.dispose();
    _velocity.dispose();
    super.dispose();
  }

  void _animateTo(int index, {double initialVelocity = 0}) {
    _controller.animateWith(
      SpringSimulation(
        _spring,
        _position.value,
        index.toDouble(),
        initialVelocity,
      ),
    );
  }

  void _onTapUp(TapUpDetails details, double contentWidth) {
    final tabWidth = contentWidth / widget.items.length;
    final index =
        (details.localPosition.dx / tabWidth).floor().clamp(0, _maxIndex);
    widget.onTap(index);
    _animateTo(index);
  }

  void _onDragStart(DragStartDetails details) {
    _isDragging = true;
    _controller.stop();
    _velocitySamples.clear();
    _velocity.value = 0;
  }

  void _onDragUpdate(DragUpdateDetails details, double contentWidth) {
    final tabWidth = contentWidth / widget.items.length;
    final dx = details.delta.dx;
    final delta = dx / tabWidth;

    final now = details.sourceTimeStamp?.inMicroseconds ??
        DateTime.now().microsecondsSinceEpoch;
    if (dx.abs() >= 0.4) {
      _velocitySamples.add(_VelocitySample(now, delta));
      final cutoff = now - 90 * 1000;
      while (_velocitySamples.isNotEmpty &&
          _velocitySamples.first.timeUs < cutoff) {
        _velocitySamples.removeAt(0);
      }
    }

    _position.value =
        (_position.value + delta).clamp(0.0, _maxIndex.toDouble());

    if (_velocitySamples.length >= 2) {
      final spanUs =
          _velocitySamples.last.timeUs - _velocitySamples.first.timeUs;
      if (spanUs > 0) {
        final totalDelta = _velocitySamples.fold<double>(
          0,
          (sum, s) => sum + s.delta,
        );
        _velocity.value = totalDelta * 1e6 / spanUs;
      }
    } else {
      _velocity.value = 0;
    }
  }

  void _onDragEnd(DragEndDetails details, double contentWidth) {
    _isDragging = false;
    final tabWidth = contentWidth / widget.items.length;
    final flingVelocity = details.velocity.pixelsPerSecond.dx / tabWidth;

    var target = _position.value.round();
    if (flingVelocity.abs() > 3.0) {
      target = flingVelocity > 0
          ? _position.value.ceil()
          : _position.value.floor();
    }
    target = target.clamp(0, _maxIndex);

    _velocitySamples.clear();
    widget.onTap(target);
    _animateTo(target, initialVelocity: flingVelocity);
  }

  void _onDragCancel() {
    _isDragging = false;
    _velocitySamples.clear();
    final target = _position.value.round().clamp(0, _maxIndex);
    _animateTo(target);
  }

  void _onPointerRelease(PointerEvent _) {
    if (!_isDragging) return;
    scheduleMicrotask(() {
      if (_isDragging && mounted) _onDragCancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final margin = widget.horizontalMargin ?? 16.w;
    final inactiveColor = widget.isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;

    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(margin, 0, margin, bottomInset),
      child: AppGlassSurface(
        isDark: widget.isDark,
        borderRadius: AppGlassTheme.borderRadius,
        padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 6.h),
        child: SizedBox(
          height: 52.h,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final contentWidth = constraints.maxWidth;

              return Listener(
                behavior: HitTestBehavior.translucent,
                onPointerUp: _onPointerRelease,
                onPointerCancel: _onPointerRelease,
                child: GestureDetector(
                  onTapUp: (d) => _onTapUp(d, contentWidth),
                  onHorizontalDragStart: _onDragStart,
                  onHorizontalDragUpdate: (d) =>
                      _onDragUpdate(d, contentWidth),
                  onHorizontalDragEnd: (d) => _onDragEnd(d, contentWidth),
                  onHorizontalDragCancel: _onDragCancel,
                  behavior: HitTestBehavior.opaque,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _SelectorPainter(
                        position: _position,
                        velocity: _velocity,
                        tabCount: widget.items.length,
                        isDark: widget.isDark,
                      ),
                      child: Row(
                        children: List.generate(widget.items.length, (index) {
                          final item = widget.items[index];
                          final badge = index < widget.badges.length
                              ? widget.badges[index]
                              : 0;

                          return Expanded(
                            child: _TabSlot(
                              item: item,
                              index: index,
                              position: _position,
                              badge: badge,
                              isDark: widget.isDark,
                              inactiveColor: inactiveColor,
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _VelocitySample {
  const _VelocitySample(this.timeUs, this.delta);
  final int timeUs;
  final double delta;
}

class _SelectorPainter extends CustomPainter {
  _SelectorPainter({
    required this.position,
    required this.velocity,
    required this.tabCount,
    required this.isDark,
  }) : super(repaint: Listenable.merge([position, velocity]));

  final ValueListenable<double> position;
  final ValueListenable<double> velocity;
  final int tabCount;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (tabCount == 0) return;

    final pos = position.value;
    final vel = velocity.value;
    final tabWidth = size.width / tabCount;

    final absVel = vel.abs().clamp(0.0, 20.0);
    final stretch = 1.0 + absVel / 55.0;

    final baseWidth = tabWidth * 0.82;
    final selectorWidth = baseWidth * stretch;
    final x = pos * tabWidth + (tabWidth - selectorWidth) / 2;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(x, 2, selectorWidth, size.height - 4),
      Radius.circular(18.r),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..color = AppColors.primary.withValues(
          alpha: isDark ? 0.18 : 0.10,
        ),
    );
  }

  @override
  bool shouldRepaint(_SelectorPainter old) =>
      tabCount != old.tabCount || isDark != old.isDark;
}

class _TabSlot extends StatelessWidget {
  const _TabSlot({
    required this.item,
    required this.index,
    required this.position,
    required this.badge,
    required this.isDark,
    required this.inactiveColor,
  });

  final AppBottomBarItem item;
  final int index;
  final ValueListenable<double> position;
  final int badge;
  final bool isDark;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: position,
      builder: (context, _) {
        final proximity =
            (1.0 - (position.value - index).abs()).clamp(0.0, 1.0);
        final color =
            Color.lerp(inactiveColor, AppColors.primary, proximity)!;
        final iconData =
            proximity > 0.5 ? (item.activeIcon ?? item.icon) : item.icon;
        final fontWeight = FontWeight.lerp(
          FontWeight.w500,
          FontWeight.w700,
          proximity,
        )!;
        final iconScale = 1.0 + proximity * 0.12;

        return IgnorePointer(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.scale(
                scale: iconScale,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      iconData,
                      size: 24.sp,
                      color: color,
                      fill: proximity > 0.5 ? 1.0 : 0.0,
                    ),
                    if (badge > 0)
                      Positioned(
                        right: -8.w,
                        top: -4.h,
                        child: _TabBadge(count: badge),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 2.h),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 2.w),
                  child: Text(
                    item.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 10.sp,
                      fontWeight: fontWeight,
                      color: color,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
        color: AppColors.error,
        shape: BoxShape.circle,
      ),
      constraints: BoxConstraints(minWidth: 16.w, minHeight: 16.w),
      child: Text(
        count > 9 ? '9+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 9.sp,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}
