import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../core/theme/app_colors.dart';
import '../../shared/models/suggested_area_model.dart';

class ActiveMeetpointCard extends StatelessWidget {
  final SuggestedArea activeMp;
  final bool isDark;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  const ActiveMeetpointCard({
    super.key,
    required this.activeMp,
    required this.isDark,
    required this.onDelete,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isExpired =
        activeMp.meetpointTime != null &&
        DateTime.now().isAfter(
          activeMp.meetpointTime!.add(SuggestedArea.meetpointExpiryWindow),
        );
    final accent = isDark
        ? const Color(0xFFE05050)
        : const Color(0xFFC0392B);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 16.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              child: Icon(Symbols.crisis_alert, color: Colors.white, size: 20.w, fill: 1),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        (isExpired ? 'status_expired' : 'area_meetpoint').tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w800,
                          fontSize: 10.sp,
                          letterSpacing: 0.5,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    activeMp.name,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 14.sp,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (activeMp.meetpointTime != null)
                    Text(
                      '${DateFormat('MMM dd').format(activeMp.meetpointTime!)} @ ${DateFormat('hh:mm a').format(activeMp.meetpointTime!)}',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 11.sp,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: Icon(Symbols.delete, color: accent, size: 22.w),
              tooltip: 'area_delete_meetpoint_confirm_title'.tr(),
            ),
          ],
        ),
      ),
    );
  }
}
