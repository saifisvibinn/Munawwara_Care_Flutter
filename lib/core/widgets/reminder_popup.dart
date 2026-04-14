import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../theme/app_colors.dart';
import 'package:material_symbols_icons/symbols.dart';

class ReminderPopup {
  static OverlayEntry? _current;

  static void show(
    BuildContext context, {
    required String body,
    required String scheduledTime,
  }) {
    _dismiss();
    final overlay = Overlay.of(context);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ReminderPopupCard(
        body: body,
        scheduledTime: scheduledTime,
        onDismiss: _dismiss,
      ),
    );

    _current = entry;
    overlay.insert(entry);
  }

  static void _dismiss() {
    if (_current != null) {
      _current?.remove();
      _current = null;
    }
  }
}

class _ReminderPopupCard extends StatefulWidget {
  final String body;
  final String scheduledTime;
  final VoidCallback onDismiss;

  const _ReminderPopupCard({
    required this.body,
    required this.scheduledTime,
    required this.onDismiss,
  });

  @override
  State<_ReminderPopupCard> createState() => _ReminderPopupCardState();
}

class _ReminderPopupCardState extends State<_ReminderPopupCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _scaleAnim = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSnooze() async {
    // Basic snooze logic - closes dialog. Real implementation would fire API.
    await _controller.reverse();
    widget.onDismiss();
  }

  void _handleDismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned.fill(
      child: Stack(
        children: [
          // Blur background
          Positioned.fill(
            child: GestureDetector(
              onTap: _handleSnooze,
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                child: Container(
                  color: Colors.black.withOpacity(isDark ? 0.42 : 0.26),
                ),
              ),
            ),
          ),
          // Animated Card
          Positioned.fill(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Align(
                alignment: Alignment.center,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32.w),
                  child: ScaleTransition(
                    scale: _scaleAnim,
                    child: _buildCard(context, isDark),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, bool isDark) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(32.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(24.w, 40.h, 24.w, 32.h),
            child: Column(
              children: [
                // Inner content
                Container(
                  width: 64.w,
                  height: 64.w,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF97316), // Orange
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF97316).withOpacity(0.4),
                        blurRadius: 15,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Symbols.notifications_active,
                      color: Colors.black,
                      size: 32.w,
                    ),
                  ),
                ),
                SizedBox(height: 24.h),
                Text(
                  'Reminder', // We could use tr() but keeping it literal to match UI exactly
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                SizedBox(height: 20.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: 24.w,
                    vertical: 24.h,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppColors.backgroundDark
                        : const Color(0xFFF1F5F9), // Slate 100
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    widget.body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w500,
                      color: isDark
                          ? Colors.white70
                          : const Color(0xFF1E293B), // Slate 800
                      height: 1.4,
                    ),
                  ),
                ),
                SizedBox(height: 24.h),
                Text(
                  widget.scheduledTime.toUpperCase(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: const Color(0xFF64748B), // Slate 500
                  ),
                ),
                SizedBox(height: 32.h),
                GestureDetector(
                  onTap: _handleDismiss,
                  child: Container(
                    color: Colors.transparent,
                    padding: EdgeInsets.symmetric(
                      horizontal: 32.w,
                      vertical: 12.h,
                    ),
                    child: Text(
                      'Dismiss',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF334155), // Slate 700
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Bottom Snooze Bar
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 20.h),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E293B)
                  : const Color(0xFFF1F5F9), // Slate 100
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32.r),
                bottomRight: Radius.circular(32.r),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info, size: 16.w, color: const Color(0xFF64748B)),
                SizedBox(width: 8.w),
                Text(
                  'TAP OUTSIDE TO SNOOZE FOR 15M',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
