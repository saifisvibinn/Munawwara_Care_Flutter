import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_colors.dart';

/// Privacy policy and About entry for profile settings.
class LegalSupportSection extends ConsumerWidget {
  const LegalSupportSection({
    super.key,
    required this.isDark,
    required this.cardBg,
    required this.textPrimary,
    required this.textMuted,
    required this.dividerColor,
    this.showAccountDeletion = false,
  });

  final bool isDark;
  final Color cardBg;
  final Color textPrimary;
  final Color textMuted;
  final Color dividerColor;
  final bool showAccountDeletion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: 'legal_section_title'.tr(), textMuted: textMuted),
        SizedBox(height: 8.h),
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              _LegalRow(
                icon: Icons.privacy_tip_outlined,
                label: 'legal_privacy_policy'.tr(),
                textPrimary: textPrimary,
                textMuted: textMuted,
                onTap: () => context.push('/privacy-policy'),
              ),
              _DividerLine(color: dividerColor),
              _LegalRow(
                icon: Icons.info_outline_rounded,
                label: 'about_title'.tr(),
                textPrimary: textPrimary,
                textMuted: textMuted,
                onTap: () => context.push(
                  '/about',
                  extra: showAccountDeletion,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.textMuted});

  final String label;
  final Color textMuted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 4.w),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontWeight: FontWeight.w600,
          fontSize: 11.sp,
          letterSpacing: 1.2,
          color: textMuted,
        ),
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  const _LegalRow({
    required this.icon,
    required this.label,
    required this.textPrimary,
    required this.textMuted,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color textPrimary;
  final Color textMuted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.r),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Row(
          children: [
            Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(icon, color: color, size: 18.sp),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w600,
                  fontSize: 14.sp,
                  color: textPrimary,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: textMuted,
              size: 22.sp,
            ),
          ],
        ),
      ),
    );
  }
}

class _DividerLine extends StatelessWidget {
  const _DividerLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: color,
      indent: 16.w,
      endIndent: 16.w,
    );
  }
}
