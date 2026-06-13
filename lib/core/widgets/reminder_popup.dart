import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../theme/app_colors.dart';
import 'package:material_symbols_icons/symbols.dart';

class ReminderPopup {
  static void show(
    BuildContext context, {
    required String body,
    required String scheduledTime,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'reminder_popup_dismiss'.tr(),
      barrierColor: Colors.black.withValues(alpha: 0.3),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return _ReminderPopupCard(
          body: body,
          scheduledTime: scheduledTime,
          onDismiss: () => Navigator.of(context).pop(),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.8, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _ReminderPopupCard extends StatelessWidget {
  final String body;
  final String scheduledTime;
  final VoidCallback onDismiss;

  const _ReminderPopupCard({
    required this.body,
    required this.scheduledTime,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w),
          child: _buildCard(context, isDark),
        ),
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
            color: Colors.black.withValues(alpha: 0.15),
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
                        color: const Color(0xFFF97316).withValues(alpha: 0.4),
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
                  'reminder_popup_title'.tr(),
                  style: TextStyle(
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
                    body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
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
                  scheduledTime.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    color: const Color(0xFF64748B), // Slate 500
                  ),
                ),
                SizedBox(height: 32.h),
                GestureDetector(
                  onTap: onDismiss,
                  child: Container(
                    color: Colors.transparent,
                    padding: EdgeInsets.symmetric(
                      horizontal: 32.w,
                      vertical: 12.h,
                    ),
                    child: Text(
                      'reminder_popup_dismiss'.tr(),
                      style: TextStyle(
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
          SizedBox(height: 24.h),
        ],
      ),
    );
  }
}
