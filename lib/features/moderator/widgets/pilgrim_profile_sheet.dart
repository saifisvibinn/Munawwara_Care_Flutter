import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/moderator_provider.dart';
import '../screens/individual_messages_screen.dart';

void showPilgrimProfileSheet(
  BuildContext context,
  PilgrimInGroup pilgrim,
  String groupId,
  String currentUserId,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      final battColor = switch (pilgrim.batteryStatus) {
        BatteryStatus.good => const Color(0xFF16A34A),
        BatteryStatus.medium => const Color(0xFFF59E0B),
        BatteryStatus.low => const Color(0xFFDC2626),
        BatteryStatus.unknown => AppColors.textMutedLight,
      };

      return Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 32.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 20.h),
            // Avatar
            Container(
              width: 72.w,
              height: 72.w,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  pilgrim.initials,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 26.sp,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              pilgrim.fullName,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                fontSize: 20.sp,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
            SizedBox(height: 4.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8.w,
                  height: 8.w,
                  decoration: BoxDecoration(
                    color: pilgrim.isOnline
                        ? const Color(0xFF16A34A)
                        : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 6.w),
                Text(
                  pilgrim.isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    color: pilgrim.isOnline
                        ? const Color(0xFF16A34A)
                        : AppColors.textMutedLight,
                  ),
                ),
                SizedBox(width: 12.w),
                Container(
                  width: 8.w,
                  height: 8.w,
                  decoration: BoxDecoration(
                    color: pilgrim.hasLocation
                        ? AppColors.primary
                        : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 6.w),
                Text(
                  pilgrim.hasLocation ? 'Location sharing ON' : 'No location',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    color: pilgrim.hasLocation
                        ? AppColors.primary
                        : AppColors.textMutedLight,
                  ),
                ),
              ],
            ),
            SizedBox(height: 20.h),
            Divider(color: Colors.grey.shade200),
            SizedBox(height: 12.h),
            // Info rows
            if (pilgrim.nationalId != null)
              _ProfileRow(
                icon: Symbols.badge,
                label: 'National ID',
                value: pilgrim.nationalId!,
                isDark: isDark,
              ),
            if (pilgrim.phoneNumber != null)
              _ProfileRow(
                icon: Symbols.phone,
                label: 'Phone',
                value: pilgrim.phoneNumber!,
                isDark: isDark,
              ),
            if (pilgrim.batteryPercent != null)
              _ProfileRow(
                icon: Symbols.battery_5_bar,
                label: 'Battery',
                value: '${pilgrim.batteryPercent}%',
                valueColor: battColor,
                isDark: isDark,
              ),
            if (pilgrim.lastSeenText.isNotEmpty)
              _ProfileRow(
                icon: Symbols.schedule,
                label: 'Last seen',
                value: pilgrim.lastSeenText,
                isDark: isDark,
              ),
            SizedBox(height: 20.h),
            // Message Button
            SizedBox(
              width: double.infinity,
              height: 48.h,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => IndividualMessagesScreen(
                        groupId: groupId,
                        groupName: 'group_name'.tr(),
                        recipientId: pilgrim.id,
                        recipientName: pilgrim.fullName,
                        currentUserId: currentUserId,
                      ),
                    ),
                  );
                },
                icon: Icon(Symbols.chat, color: Colors.white, size: 20.w),
                label: Text(
                  'Message',
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            SizedBox(height: 12.h),
          ],
        ),
      );
    },
  );
}

class _ProfileRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isDark;

  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8.w),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Icon(icon, size: 16.w, color: AppColors.primary),
          ),
          SizedBox(width: 12.w),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12.sp,
              color: AppColors.textMutedLight,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w600,
              fontSize: 13.sp,
              color: valueColor ?? (isDark ? Colors.white : AppColors.textDark),
            ),
          ),
        ],
      ),
    );
  }
}
