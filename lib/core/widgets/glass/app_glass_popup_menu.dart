import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../theme/app_colors.dart';
import '../app_popup_menu.dart';
import 'app_glass_surface.dart';
import 'app_glass_theme.dart';

/// One row or divider inside [AppGlassPopupMenuAnchor].
class AppGlassPopupMenuItem<T> {
  const AppGlassPopupMenuItem({
    required this.value,
    required this.icon,
    required this.label,
    this.iconColor,
    this.destructive = false,
  }) : isDivider = false;

  const AppGlassPopupMenuItem.divider()
      : value = null,
        icon = null,
        label = null,
        iconColor = null,
        destructive = false,
        isDivider = true;

  final T? value;
  final IconData? icon;
  final String? label;
  final Color? iconColor;
  final bool destructive;
  final bool isDivider;
}

/// Liquid glass contextual menu anchored to its trigger.
///
/// Uses an [OverlayEntry] (not a dialog route) so [AppGlassSurface] blurs live
/// content beneath — aligned with Apple's popover guidance in
/// [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass):
/// anchor to source, single glass shell, solid rows inside for legibility.
class AppGlassPopupMenuAnchor<T> extends StatefulWidget {
  const AppGlassPopupMenuAnchor({
    super.key,
    required this.isDark,
    required this.child,
    required this.items,
    required this.onSelected,
    this.offset,
    this.constraints,
    this.semanticLabel,
  });

  final bool isDark;
  final Widget child;
  final List<AppGlassPopupMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  /// Gap below trigger; defaults to [AppGlassTheme.popoverGapBelowTrigger].
  final Offset? offset;
  final BoxConstraints? constraints;
  final String? semanticLabel;

  @override
  State<AppGlassPopupMenuAnchor<T>> createState() =>
      _AppGlassPopupMenuAnchorState<T>();
}

class _AppGlassPopupMenuAnchorState<T> extends State<AppGlassPopupMenuAnchor<T>>
    with TickerProviderStateMixin {
  final _triggerKey = GlobalKey();
  OverlayEntry? _entry;
  AnimationController? _controller;
  bool _isClosing = false;
  ModalRoute<void>? _hostRoute;

  bool get _isMenuVisible => _entry != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextRoute = ModalRoute.of(context);
    if (_hostRoute != nextRoute) {
      _hostRoute?.animation?.removeStatusListener(_onHostRouteAnimation);
      _hostRoute = nextRoute;
      _hostRoute?.animation?.addStatusListener(_onHostRouteAnimation);
    }
  }

  void _onHostRouteAnimation(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _removeMenu(immediate: true);
    }
  }

  @override
  void dispose() {
    _hostRoute?.animation?.removeStatusListener(_onHostRouteAnimation);
    _removeMenu(immediate: true);
    super.dispose();
  }

  void _removeMenu({bool immediate = false}) {
    final entry = _entry;
    final controller = _controller;
    if (entry == null) return;
    if (_isClosing && !immediate) return;

    void tearDown() {
      controller?.removeListener(entry.markNeedsBuild);
      entry.remove();
      controller?.dispose();
      _entry = null;
      _controller = null;
      _isClosing = false;
    }

    if (immediate || controller == null) {
      tearDown();
      return;
    }

    _isClosing = true;
    controller.reverse().whenComplete(tearDown);
  }

  void _toggleMenu() {
    if (_isMenuVisible) {
      _removeMenu();
      return;
    }
    _openMenu();
  }

  void _openMenu() {
    if (_isMenuVisible) return;

    final triggerBox =
        _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (triggerBox == null || !mounted) return;

    final triggerOrigin = triggerBox.localToGlobal(Offset.zero);
    final triggerSize = triggerBox.size;
    final gap = widget.offset ?? AppGlassTheme.popoverGapBelowTrigger;

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 150),
    );
    _controller = controller;
    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        final screen = MediaQuery.sizeOf(overlayContext);
        final isRtl =
            Directionality.of(overlayContext) == TextDirection.rtl;
        final menuTop = triggerOrigin.dy + triggerSize.height + gap.dy;
        final triggerEnd = triggerOrigin.dx + triggerSize.width;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Re-tapping the trigger sits above the map stack; capture it here
            // so the menu toggles closed like iOS toolbar menus.
            Positioned(
              left: triggerOrigin.dx,
              top: triggerOrigin.dy,
              width: triggerSize.width,
              height: triggerSize.height,
              child: GestureDetector(
                onTap: _removeMenu,
                behavior: HitTestBehavior.opaque,
              ),
            ),
            Positioned(
              top: menuTop,
              left: isRtl ? triggerOrigin.dx + gap.dx : null,
              right: isRtl
                  ? null
                  : screen.width - triggerEnd - gap.dx,
              child: TapRegion(
                onTapOutside: (_) => _removeMenu(),
                child: FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
                    alignment:
                        isRtl ? Alignment.topLeft : Alignment.topRight,
                    child: _GlassMenuPanel<T>(
                      isDark: widget.isDark,
                      items: widget.items,
                      constraints: widget.constraints ??
                          AppPopupMenu.panelConstraints(),
                      onSelect: (value) {
                        _removeMenu();
                        widget.onSelected(value);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    _entry = entry;
    controller.addListener(entry.markNeedsBuild);
    Overlay.of(context).insert(entry);
    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: KeyedSubtree(
        key: _triggerKey,
        child: GestureDetector(
          onTap: _toggleMenu,
          behavior: HitTestBehavior.opaque,
          child: widget.child,
        ),
      ),
    );
  }
}

class _GlassMenuPanel<T> extends StatelessWidget {
  const _GlassMenuPanel({
    required this.isDark,
    required this.items,
    required this.constraints,
    required this.onSelect,
  });

  final bool isDark;
  final List<AppGlassPopupMenuItem<T>> items;
  final BoxConstraints constraints;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    final dividerColor =
        isDark ? AppColors.dividerDark : const Color(0xFFE2E8F0);

    return IntrinsicWidth(
      child: ConstrainedBox(
        constraints: constraints,
        child: AppGlassSurface(
          isDark: isDark,
          glassTheme: AppGlassTheme.popoverOf(isDark),
          borderRadius: AppGlassTheme.cardRadius,
          padding: EdgeInsets.symmetric(vertical: 6.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
            for (final item in items)
              if (item.isDivider)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: dividerColor,
                  ),
                )
              else
                _MenuRow<T>(
                  item: item,
                  isDark: isDark,
                  onTap: () => onSelect(item.value as T),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuRow<T> extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.isDark,
    required this.onTap,
  });

  final AppGlassPopupMenuItem<T> item;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final iconColor = item.destructive
        ? Colors.red
        : (item.iconColor ??
            (isDark ? Colors.white70 : AppColors.textDark));
    final textColor = item.destructive ? Colors.red : textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 48.h),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
            child: Row(
              children: [
                Container(
                  width: 32.w,
                  height: 32.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: item.destructive
                        ? Colors.red.withValues(alpha: isDark ? 0.18 : 0.1)
                        : AppColors.primary.withValues(
                            alpha: isDark ? 0.22 : 0.12,
                          ),
                  ),
                  child: Icon(
                    item.icon ?? Symbols.circle,
                    size: 18.w,
                    color: iconColor,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    item.label ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
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
