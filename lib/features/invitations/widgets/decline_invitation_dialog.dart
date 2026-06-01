import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';

/// Confirms before declining a group invitation.
Future<bool> showDeclineInvitationDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16.r),
        ),
        title: Text(
          'invite_decline_confirm_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        content: Text(
          'invite_decline_confirm_body'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14.sp,
            height: 1.4,
            color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'cancel'.tr(),
              style: const TextStyle(fontFamily: 'Lexend'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'invite_decline'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w700,
                color: Theme.of(ctx).colorScheme.error,
              ),
            ),
          ),
        ],
      );
    },
  );
  return result == true;
}
