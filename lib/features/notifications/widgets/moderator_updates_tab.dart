import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../models/notification_model.dart';
import '../providers/notification_provider.dart';

/// Invitation outcomes and related updates for moderators who sent invites.
class ModeratorUpdatesTab extends ConsumerWidget {
  const ModeratorUpdatesTab({super.key});

  static const _updateTypes = {
    'invitation_accepted',
    'invitation_declined',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final all = ref.watch(notificationProvider).notifications;
    final updates = all
        .where((n) => _updateTypes.contains(n.type))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (updates.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w),
          child: Text(
            'alerts_updates_empty'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14.sp,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : AppColors.textMutedDark,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 24.h),
      itemCount: updates.length,
      separatorBuilder: (_, _) => SizedBox(height: 10.h),
      itemBuilder: (context, index) {
        return _UpdateNotificationTile(
          notification: updates[index],
          isDark: isDark,
        );
      },
    );
  }
}

class _UpdateNotificationTile extends StatelessWidget {
  final AppNotification notification;
  final bool isDark;

  const _UpdateNotificationTile({
    required this.notification,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final groupName =
        notification.data?['group_name']?.toString() ?? '';
    final time = DateFormat.jm().format(notification.createdAt);

    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: notification.iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(
              notification.icon,
              color: notification.iconColor,
              size: 22.sp,
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        notification.typeLabel,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 13.sp,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 11.sp,
                        color: AppColors.textMutedLight,
                      ),
                    ),
                  ],
                ),
                if (groupName.isNotEmpty) ...[
                  SizedBox(height: 4.h),
                  Text(
                    groupName,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ],
                SizedBox(height: 6.h),
                Text(
                  notification.message,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    height: 1.35,
                    color: isDark
                        ? AppColors.textMutedLight
                        : AppColors.textMutedDark,
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
