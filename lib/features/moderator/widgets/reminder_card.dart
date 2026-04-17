import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../models/reminder_model.dart';

class ReminderCard extends StatelessWidget {
  final ReminderModel reminder;
  final VoidCallback onCancel;

  const ReminderCard({super.key, required this.reminder, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = _statusColor(reminder.status);
    final timeStr = DateFormat('dd MMM yyyy  HH:mm').format(reminder.scheduledAt.toLocal());

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status badge + time
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  'reminder_status_'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
              const Spacer(),
              Icon(Symbols.schedule, size: 14.sp, color: Colors.grey),
              SizedBox(width: 4.w),
              Text(
                timeStr,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 11.sp,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),

          // Reminder text
          Text(
            reminder.text,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textLight : AppColors.textDark,
            ),
          ),
          SizedBox(height: 8.h),

          // Target + repeat info
          Row(
            children: [
              Icon(
                reminder.targetType == 'pilgrim' ? Symbols.person : Symbols.group,
                size: 14.sp,
                color: AppColors.primary,
              ),
              SizedBox(width: 4.w),
              Text(
                reminder.targetType == 'pilgrim'
                    ? (reminder.pilgrimName ?? 'reminder_target_pilgrim'.tr())
                    : 'reminder_target_group'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.sp,
                  color: AppColors.primary,
                ),
              ),
              if (reminder.repeatCount > 1) ...[
                SizedBox(width: 16.w),
                Icon(Symbols.repeat, size: 14.sp, color: Colors.grey),
                SizedBox(width: 4.w),
                Text(
                  '${'reminder_fires_sent'.tr(
                    namedArgs: {
                      'sent': '',
                      'total': '',
                    },
                  )}    ${'reminder_interval_every'.tr(namedArgs: {'interval': _formatInterval(reminder.repeatIntervalMin)})}',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    color: Colors.grey,
                  ),
                ),
              ],
            ],
          ),

          // Cancel button (only for active reminders)
          if (reminder.isActive) ...[
            SizedBox(height: 10.h),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onCancel,
                icon: Icon(Symbols.cancel, size: 16.sp, color: Colors.redAccent),
                label: Text(
                  'area_cancel'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    color: Colors.redAccent,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return Colors.blueAccent;
      case 'active': return AppColors.primary;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.grey;
      default: return Colors.grey;
    }
  }

  String _formatInterval(int minutes) {
    if (minutes < 60) return 'm';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? 'h' : 'h m';
  }
}
