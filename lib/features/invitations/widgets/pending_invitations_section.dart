import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/invitation_provider.dart';
import 'pending_invitation_card.dart';

/// Lists pending group invitations at the top of the moderator groups tab.
class PendingInvitationsSection extends ConsumerWidget {
  const PendingInvitationsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pendingInvitationsProvider);
    if (state.isLoading && state.invitations.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: 16.h),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }
    if (state.invitations.isEmpty) {
      if (state.error != null) {
        return Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: SelectableText.rich(
            TextSpan(
              text: state.error,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 12.sp,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...state.invitations.map(
          (inv) => PendingInvitationCard(invitation: inv),
        ),
        if (state.error != null) ...[
          SelectableText.rich(
            TextSpan(
              text: state.error,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 12.sp,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          SizedBox(height: 8.h),
        ],
      ],
    );
  }
}
