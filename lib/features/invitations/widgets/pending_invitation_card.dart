import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../models/group_invitation.dart';
import '../providers/invitation_provider.dart';
import 'decline_invitation_dialog.dart';

class PendingInvitationCard extends ConsumerWidget {
  final GroupInvitation invitation;

  const PendingInvitationCard({super.key, required this.invitation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inviteState = ref.watch(pendingInvitationsProvider);
    final isBusy = inviteState.actionInvitationId == invitation.id;
    final inviter = invitation.inviterName.trim().isEmpty
        ? invitation.inviteeEmail
        : invitation.inviterName;
    final groupName = invitation.groupName.trim().isEmpty
        ? '—'
        : invitation.groupName;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Symbols.mail,
                color: const Color(0xFF3B82F6),
                size: 28.sp,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'invite_pending_title'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w800,
                        fontSize: 15.sp,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      'invite_pending_body'.tr(
                        namedArgs: {
                          'inviter': inviter,
                          'group': groupName,
                        },
                      ),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13.sp,
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
          SizedBox(height: 14.h),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isBusy
                      ? null
                      : () => _handleDecline(context, ref),
                  child: isBusy
                      ? SizedBox(
                          width: 18.w,
                          height: 18.w,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : Text('invite_decline'.tr()),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: ElevatedButton(
                  onPressed: isBusy
                      ? null
                      : () => _handleAccept(context, ref),
                  child: Text('invite_accept'.tr()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleAccept(BuildContext context, WidgetRef ref) async {
    final ok = await ref
        .read(pendingInvitationsProvider.notifier)
        .accept(invitation.id);
    if (!context.mounted) return;
    if (ok) {
      StandardSnackBar.showSuccess(context, 'invite_accept_success'.tr());
    }
  }

  Future<void> _handleDecline(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDeclineInvitationDialog(context);
    if (!confirmed || !context.mounted) return;
    final ok = await ref
        .read(pendingInvitationsProvider.notifier)
        .decline(invitation.id);
    if (!context.mounted) return;
    if (ok) {
      StandardSnackBar.showSuccess(context, 'invite_decline_success'.tr());
    }
  }
}
