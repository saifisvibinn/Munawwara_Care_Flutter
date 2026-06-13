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
              Flexible(
                fit: FlexFit.loose,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text(
                    'reminder_status_${reminder.status}'.tr(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Flexible(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.schedule, size: 14.sp, color: Colors.grey),
                    SizedBox(width: 4.w),
                    Flexible(
                      child: Text(
                        timeStr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 11.sp,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _targetIcon(reminder.targetType),
                size: 14.sp,
                color: AppColors.primary,
              ),
              SizedBox(width: 4.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _targetLabel(reminder),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    if (reminder.weeklyDays.isNotEmpty) ...[
                      SizedBox(height: 4.h),
                      Text(
                        'reminder_card_weekly_days'.tr(namedArgs: {
                          'days': reminder.weeklyDays
                              .map((d) => 'reminder_weekday_short_$d'.tr())
                              .join(', '),
                        }),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 11.sp,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                    if (reminder.repeatCount > 1 ||
                        reminder.weeklyDays.isNotEmpty) ...[
                      SizedBox(height: 4.h),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Symbols.repeat, size: 14.sp, color: Colors.grey),
                          SizedBox(width: 4.w),
                          Flexible(
                            child: Text(
                              reminder.weeklyDays.isNotEmpty
                                  ? '${reminder.firesSent}/${reminder.repeatCount}'
                                  : '${reminder.firesSent}/${reminder.repeatCount}  · every ${_formatInterval(reminder.repeatIntervalMin)}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 12.sp,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
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

  IconData _targetIcon(String targetType) {
    switch (targetType) {
      case 'pilgrim':
        return Symbols.person;
      case 'system':
        return Symbols.public;
      case 'all_groups':
        return Symbols.groups;
      default:
        return Symbols.group;
    }
  }

  String _targetLabel(ReminderModel reminder) {
    switch (reminder.targetType) {
      case 'pilgrim':
        return reminder.pilgrimName ?? 'reminder_target_pilgrim'.tr();
      case 'system':
        return 'reminder_target_system_wide'.tr();
      case 'all_groups':
        return 'reminder_target_all_groups'.tr();
      case 'group':
        final n = reminder.groupIdsCount;
        if (n <= 1) {
          return 'reminder_target_one_group'.tr();
        }
        return 'reminder_target_n_groups'.tr(namedArgs: {'n': '$n'});
      default:
        return 'reminder_target_group'.tr();
    }
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

  /// Returns a human-readable interval string, e.g. "15m", "2h", "1h 30m"
  String _formatInterval(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
}
