import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../router/app_router.dart';
import '../theme/app_colors.dart';

enum SnackBarType { success, error, warning, info }

/// iOS-style transient banners — frosted capsule, semantic icon tint, no solid fills.
class StandardSnackBar {
  StandardSnackBar._();

  static OverlayEntry? _entry;
  static Timer? _dismissTimer;
  static Duration _currentDuration = const Duration(seconds: 3);

  /// Shared controller on [StandardSnackBarHost] — never create per toast.
  static AnimationController? bannerController;

  static void show(
    BuildContext context, {
    required String message,
    SnackBarType type = SnackBarType.info,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    _hapticFor(type);
    _present(
      context,
      message: message,
      type: type,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  static void showSuccess(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(context, message: message, type: SnackBarType.success, duration: duration);
  }

  static void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(context, message: message, type: SnackBarType.error, duration: duration);
  }

  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(context, message: message, type: SnackBarType.warning, duration: duration);
  }

  static void showInfo(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(context, message: message, type: SnackBarType.info, duration: duration);
  }

  static void _hapticFor(SnackBarType type) {
    switch (type) {
      case SnackBarType.success:
      case SnackBarType.info:
        HapticFeedback.lightImpact();
      case SnackBarType.warning:
        HapticFeedback.selectionClick();
      case SnackBarType.error:
        HapticFeedback.mediumImpact();
    }
  }

  static void _present(
    BuildContext context, {
    required String message,
    required SnackBarType type,
    required Duration duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final overlay = _overlayFor(context);
    if (overlay == null) {
      _presentMaterialFallback(
        context,
        message: message,
        type: type,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
      );
      return;
    }

    final ticker = StandardSnackBarHost.ticker;
    if (ticker == null || bannerController == null) {
      _presentMaterialFallback(
        context,
        message: message,
        type: type,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
      );
      return;
    }

    _dismiss(immediate: true);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final icon = _iconFor(type);
    final iconColor = _iconColorFor(type);

    final controller = bannerController!;

    controller.duration = const Duration(milliseconds: 260);
    controller.reverseDuration = const Duration(milliseconds: 200);
    unawaited(controller.forward(from: 0));

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) {
        final animation = controller;

        final media = MediaQuery.of(ctx);
        final bottomInset = media.padding.bottom + 72.h;

        return _SwipeDismissBanner(
          bottomInset: bottomInset,
          animation: animation,
          onDismiss: dismiss,
          onDragStart: _pauseAutoDismiss,
          onDragCancel: _resumeAutoDismiss,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 420.w),
              child: _BannerShell(
                isDark: isDark,
                child: Row(
                  children: [
                    Icon(icon, size: 20.sp, color: iconColor),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: Text(
                        message,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                          height: 1.35,
                          decoration: TextDecoration.none,
                          decorationThickness: 0,
                          color: isDark
                              ? AppColors.textLight
                              : AppColors.textDark,
                        ),
                      ),
                    ),
                    if (actionLabel != null && onAction != null) ...[
                      SizedBox(width: 8.w),
                      TextButton(
                        onPressed: () {
                          dismiss();
                          onAction();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 4.h,
                          ),
                          minimumSize: Size(44.w, 36.h),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          actionLabel,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 15.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    _entry = entry;
    overlay.insert(entry);
    _currentDuration = duration;
    _dismissTimer = Timer(duration, _dismiss);
  }

  static void _pauseAutoDismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
  }

  static void _resumeAutoDismiss() {
    if (_entry == null || _dismissTimer != null) return;
    _dismissTimer = Timer(_currentDuration, _dismiss);
  }

  static void dismiss() => _dismiss();

  static void _dismiss({bool immediate = false}) {
    _dismissTimer?.cancel();
    _dismissTimer = null;

    final entry = _entry;
    final controller = bannerController;
    if (entry == null) return;

    void cleanup() {
      entry.remove();
      _entry = null;
    }

    if (immediate || controller == null) {
      controller?.value = 0;
      cleanup();
      return;
    }

    controller.reverse().whenComplete(cleanup);
  }

  static OverlayState? _overlayFor(BuildContext context) {
    final fromContext = Overlay.maybeOf(context, rootOverlay: true);
    if (fromContext != null) return fromContext;
    final rootContext = AppRouter.navigatorKey.currentContext;
    if (rootContext == null) return null;
    return Overlay.maybeOf(rootContext, rootOverlay: true);
  }

  static IconData _iconFor(SnackBarType type) {
    return switch (type) {
      SnackBarType.success => Symbols.check_circle,
      SnackBarType.error => Symbols.error,
      SnackBarType.warning => Symbols.warning,
      SnackBarType.info => Symbols.info,
    };
  }

  static Color _iconColorFor(SnackBarType type) {
    return switch (type) {
      SnackBarType.success => const Color(0xFF34C759),
      SnackBarType.error => const Color(0xFFFF3B30),
      SnackBarType.warning => const Color(0xFFFF9500),
      SnackBarType.info => const Color(0xFF007AFF),
    };
  }

  static void _presentMaterialFallback(
    BuildContext context, {
    required String message,
    required SnackBarType type,
    required Duration duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(_iconFor(type), color: _iconColorFor(type), size: 20.sp),
            SizedBox(width: 10.w),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.none,
                  color: isDark ? AppColors.textLight : AppColors.textDark,
                ),
              ),
            ),
          ],
        ),
        backgroundColor:
            isDark ? const Color(0xFF2C2C2E) : Colors.white.withValues(alpha: 0.96),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14.r),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0x1A3C3C43),
          ),
        ),
        margin: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
        duration: duration,
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: AppColors.primary,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }
}

class _BannerShell extends StatelessWidget {
  const _BannerShell({required this.isDark, required this.child});

  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fill = isDark ? AppColors.surfaceDark : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0x293C3C43);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.1),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: child,
      ),
    );
  }
}

class _SwipeDismissBanner extends StatefulWidget {
  const _SwipeDismissBanner({
    required this.bottomInset,
    required this.animation,
    required this.child,
    required this.onDismiss,
    required this.onDragStart,
    required this.onDragCancel,
  });

  final double bottomInset;
  final Animation<double> animation;
  final Widget child;
  final VoidCallback onDismiss;
  final VoidCallback onDragStart;
  final VoidCallback onDragCancel;

  @override
  State<_SwipeDismissBanner> createState() => _SwipeDismissBannerState();
}

class _SwipeDismissBannerState extends State<_SwipeDismissBanner>
    with SingleTickerProviderStateMixin {
  static const double _dismissDragThreshold = 44;
  static const double _dismissVelocityThreshold = 450;

  double _dragOffset = 0;
  AnimationController? _snapBackController;

  @override
  void dispose() {
    _snapBackController?.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    _snapBackController?.stop();
    widget.onDragStart();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(0, 160);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset >= _dismissDragThreshold ||
        velocity > _dismissVelocityThreshold) {
      HapticFeedback.lightImpact();
      widget.onDismiss();
      return;
    }

    widget.onDragCancel();
    _animateSnapBack();
  }

  void _onDragCancel() {
    widget.onDragCancel();
    _animateSnapBack();
  }

  void _animateSnapBack() {
    final start = _dragOffset;
    if (start <= 0) return;

    _snapBackController?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _snapBackController = controller;

    final animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeOutCubic,
    );

    void listener() {
      setState(() {
        _dragOffset = lerpDouble(start, 0, animation.value) ?? 0;
      });
    }

    animation.addListener(listener);
    controller.forward().whenComplete(() {
      animation.removeListener(listener);
      controller.dispose();
      if (_snapBackController == controller) {
        _snapBackController = null;
      }
      if (mounted) {
        setState(() => _dragOffset = 0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dragOpacity = (1 - (_dragOffset / 120).clamp(0.0, 1.0)).toDouble();

    return Positioned(
      left: 16.w,
      right: 16.w,
      bottom: widget.bottomInset,
      child: GestureDetector(
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        onVerticalDragCancel: _onDragCancel,
        behavior: HitTestBehavior.opaque,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: widget.animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
          ),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: widget.animation,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeIn,
            ),
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: Opacity(
                opacity: dragOpacity,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wrap the app root so [StandardSnackBar] can animate overlays.
class StandardSnackBarHost extends StatefulWidget {
  const StandardSnackBarHost({super.key, required this.child});

  final Widget child;

  static TickerProvider? ticker;

  @override
  State<StandardSnackBarHost> createState() => _StandardSnackBarHostState();
}

class _StandardSnackBarHostState extends State<StandardSnackBarHost>
    with SingleTickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    StandardSnackBarHost.ticker = this;
    StandardSnackBar.bannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    StandardSnackBar.bannerController?.dispose();
    StandardSnackBar.bannerController = null;
    if (StandardSnackBarHost.ticker == this) {
      StandardSnackBarHost.ticker = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
