import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';
import '../providers/invitation_provider.dart';
import 'pending_invitation_card.dart';

/// Lists pending group invitations at the top of the moderator groups tab.
class PendingInvitationsSection extends ConsumerWidget {
  const PendingInvitationsSection({super.key, required this.isDark});

  final bool isDark;

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
                fontSize: 12.sp,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final content = Column(
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
                fontSize: 12.sp,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),
          SizedBox(height: 8.h),
        ],
      ],
    );

    return AppGlassCard(
      isDark: isDark,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      child: content,
    );
  }
}
