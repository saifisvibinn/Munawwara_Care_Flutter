import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/legal_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';
import '../../../core/widgets/app_version_label.dart';
import '../../../core/widgets/custom_dialog.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../../core/widgets/support_dialogs.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/support_api.dart';

/// App info, version, support, and account-deletion entry points.
class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({
    super.key,
    this.showAccountDeletion = true,
  });

  final bool showAccountDeletion;

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  bool _isDeletingAccount = false;

  bool get _isModerator {
    final role = ref.watch(authProvider).role?.toLowerCase();
    return role == 'moderator' || role == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;
    final dividerColor = isDark
        ? AppColors.dividerDark
        : AppColors.dividerLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'about_title'.tr(),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
            color: textPrimary,
          ),
        ),
      ),
      body: AppScrollFadeOverlay(
        showTop: false,
        backgroundColor:
            isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
          child: Column(
            children: [
              SizedBox(height: 16.h),
              Container(
                width: 72.w,
                height: 72.w,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16.r),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16.r),
                  child: Image.asset(
                    'assets/static/logo.jpeg',
                    width: 72.w,
                    height: 72.w,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                LegalConfig.appName,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 20.sp,
                  color: textPrimary,
                ),
              ),
              SizedBox(height: 8.h),
              AppVersionLabel(
                textColor: textMuted,
                fontSize: 13,
              ),
              SizedBox(height: 32.h),
              Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16.r),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _AboutRow(
                      icon: Icons.report_problem_outlined,
                      label: 'settings_report_issue'.tr(),
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                      onTap: () => SupportDialogs.showReport(context),
                    ),
                    _DividerLine(color: dividerColor),
                    _AboutRow(
                      icon: Icons.rate_review_outlined,
                      label: 'settings_send_feedback'.tr(),
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                      onTap: () => SupportDialogs.showFeedback(context),
                    ),
                    _DividerLine(color: dividerColor),
                    _AboutRow(
                      icon: Icons.star_rate_rounded,
                      label: 'settings_rate_app'.tr(),
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                      onTap: () => SupportDialogs.showRating(context),
                    ),
                    _DividerLine(color: dividerColor),
                    _AboutRow(
                      icon: Icons.help_outline_rounded,
                      label: 'settings_faq'.tr(),
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                      onTap: () => context.push('/faq'),
                    ),
                    _DividerLine(color: dividerColor),
                    _AboutRow(
                      icon: Icons.mail_outline_rounded,
                      label: 'legal_contact_support'.tr(),
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                      onTap: () => context.push('/contact-support'),
                    ),
                    if (widget.showAccountDeletion && _isModerator) ...[
                      _DividerLine(color: dividerColor),
                      Padding(
                        padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 16.h),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: textMuted,
                              size: 18.sp,
                            ),
                            SizedBox(width: 10.w),
                            Expanded(
                              child: Text(
                                'legal_moderator_deletion_note'.tr(),
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  color: textMuted,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (widget.showAccountDeletion) ...[
                      _DividerLine(color: dividerColor),
                      _AboutRow(
                        icon: Icons.delete_outline_rounded,
                        label: 'legal_request_deletion'.tr(),
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                        isDestructive: true,
                        isLoading: _isDeletingAccount,
                        onTap: _isDeletingAccount
                            ? null
                            : () => _deleteAccount(context),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 4.w),
                child: Text(
                  'legal_agora_disclosure'.tr(),
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: textMuted,
                    height: 1.4,
                  ),
                ),
              ),
              SizedBox(height: 32.h),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirmed = await StandardDialog.show<bool>(
      context: context,
      title: 'legal_deletion_confirm_title',
      content: 'legal_deletion_confirm_body',
      confirmText: 'legal_deletion_confirm_action',
      cancelText: 'settings_cancel',
      isDestructive: true,
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      await SupportApi.deleteOwnAccount();
      await ref.read(authProvider.notifier).logout();
      if (!context.mounted) return;
      StandardSnackBar.showSuccess(
        context,
        'legal_account_deleted_success'.tr(),
      );
      context.go('/login');
    } on DioException catch (e) {
      if (!context.mounted) return;
      StandardSnackBar.showError(
        context,
        SupportApi.parseError(e),
      );
    } catch (_) {
      if (!context.mounted) return;
      StandardSnackBar.showError(context, 'error_general'.tr());
    } finally {
      if (mounted) {
        setState(() => _isDeletingAccount = false);
      }
    }
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.icon,
    required this.label,
    required this.textPrimary,
    required this.textMuted,
    required this.onTap,
    this.isDestructive = false,
    this.isLoading = false,
  });

  final IconData icon;
  final String label;
  final Color textPrimary;
  final Color textMuted;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? Colors.red.shade600 : AppColors.primary;
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
              child: isLoading
                  ? Padding(
                      padding: EdgeInsets.all(8.w),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: color,
                      ),
                    )
                  : Icon(icon, color: color, size: 18.sp),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14.sp,
                  color: isDestructive ? Colors.red.shade600 : textPrimary,
                ),
              ),
            ),
            if (!isLoading)
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
