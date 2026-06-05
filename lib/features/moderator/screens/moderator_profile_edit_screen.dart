import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/standard_snackbar.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../shared/widgets/moderator_avatar.dart';

class ModeratorProfileEditScreen extends ConsumerStatefulWidget {
  const ModeratorProfileEditScreen({super.key});

  @override
  ConsumerState<ModeratorProfileEditScreen> createState() =>
      _ModeratorProfileEditScreenState();
}

class _ModeratorProfileEditScreenState
    extends ConsumerState<ModeratorProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    _nameCtrl = TextEditingController(text: auth.fullName ?? '');
    _phoneCtrl = TextEditingController(text: auth.phoneNumber ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final success = await ref
        .read(authProvider.notifier)
        .updateProfile(
          fullName: _nameCtrl.text.trim(),
          phoneNumber: _phoneCtrl.text.trim(),
        );

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      StandardSnackBar.showSuccess(context, 'edit_profile_success'.tr());
      Navigator.of(context).pop();
    } else {
      final error =
          ref.read(authProvider).error ?? 'edit_profile_error_generic'.tr();
      StandardSnackBar.showError(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;

    final fullName = authState.fullName ?? 'Moderator';
    final initials = _initials(fullName);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(8.w, 12.h, 20.w, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: textPrimary,
                      size: 20.sp,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'edit_profile_title'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 20.sp,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 44.w),
                ],
              ),
            ),

            // ── Body ──────────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 28.h),

                      // ── Avatar ─────────────────────────────────────────────
                      Center(
                        child: Stack(
                          children: [
                            ModeratorAvatar(size: 88.w, initials: initials),
                            // Camera badge removed per UI request
                          ],
                        ),
                      ),

                      SizedBox(height: 8.h),
                      Center(
                        child: Text(
                          fullName,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w600,
                            fontSize: 16.sp,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          margin: EdgeInsets.only(top: 4.h),
                          padding: EdgeInsets.symmetric(
                            horizontal: 12.w,
                            vertical: 4.h,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Text(
                            'settings_role_moderator'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w500,
                              fontSize: 12.sp,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: 32.h),

                      // ── PERSONAL INFO section ──────────────────────────────
                      _SectionLabel(
                        label: 'edit_profile_section'.tr().toUpperCase(),
                        textMuted: textMuted,
                      ),
                      SizedBox(height: 10.h),

                        Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16.r),
                            border: Border.all(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.25 : 0.03,
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Full Name
                              _ProfileInfoRow(
                                label: 'edit_profile_full_name'.tr(),
                                icon: Icons.person_rounded,
                                isDark: isDark,
                                textPrimary: textPrimary,
                                textMuted: textMuted,
                                hasDivider: true,
                                child: TextFormField(
                                  controller: _nameCtrl,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  validator: (v) {
                                    if (v == null || v.trim().isEmpty) {
                                      return 'edit_profile_error_name'.tr();
                                    }
                                    return null;
                                  },
                                ),
                              ),

                              // Phone Number
                              _ProfileInfoRow(
                                label: 'edit_profile_phone'.tr(),
                                icon: Icons.phone_rounded,
                                isDark: isDark,
                                textPrimary: textPrimary,
                                textMuted: textMuted,
                                hasDivider: true,
                                child: TextFormField(
                                  controller: _phoneCtrl,
                                  keyboardType: TextInputType.phone,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),

                              // Email (read-only)
                              if (authState.email != null)
                                _ProfileInfoRow(
                                  label: 'edit_profile_email'.tr(),
                                  icon: Icons.email_rounded,
                                  isDark: isDark,
                                  textPrimary: textPrimary,
                                  textMuted: textMuted,
                                  hasDivider: true,
                                  trailing: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8.w,
                                      vertical: 4.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF1E293B)
                                          : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6.r),
                                    ),
                                    child: Text(
                                      'edit_profile_email_verified'.tr().toUpperCase(),
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 9.sp,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    authState.email!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 15.sp,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary,
                                    ),
                                  ),
                                ),

                              // Reset Password (action)
                              _ProfileInfoRow(
                                label: 'forgot_password_title'.tr(),
                                icon: Icons.lock_rounded,
                                isDark: isDark,
                                textPrimary: textPrimary,
                                textMuted: textMuted,
                                hasDivider: false,
                                onTap: () => context.push('/forgot-password'),
                                trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  size: 22.sp,
                                  color: textMuted.withValues(alpha: 0.7),
                                ),
                                child: Text(
                                  '••••••••',
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 15.sp,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      SizedBox(height: 32.h),

                      // ── Save Changes button ────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 52.h,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            disabledBackgroundColor: AppColors.primary
                                .withValues(alpha: 0.6),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14.r),
                            ),
                          ),
                          child: _saving
                              ? SizedBox(
                                  width: 22.w,
                                  height: 22.w,
                                  child: const CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : Text(
                                  'edit_profile_save'.tr(),
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16.sp,
                                  ),
                                ),
                        ),
                      ),

                      SizedBox(height: 32.h),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'M';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

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

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.label,
    required this.icon,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
    required this.child,
    this.hasDivider = true,
    this.trailing,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isDark;
  final Color textPrimary;
  final Color textMuted;
  final Widget child;
  final bool hasDivider;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dividerColor = isDark ? AppColors.dividerDark : AppColors.dividerLight;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.r),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Icon Container
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    icon,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF334155),
                    size: 18.sp,
                  ),
                ),
                SizedBox(width: 16.w),

                // Label and Value
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 10.sp,
                          color: textMuted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      child,
                    ],
                  ),
                ),

                // Optional Trailing
                if (trailing != null) ...[
                  SizedBox(width: 12.w),
                  trailing!,
                ],
              ],
            ),
          ),
          if (hasDivider)
            Divider(
              height: 1,
              thickness: 1,
              color: dividerColor,
              indent: 72.w, // Align with the start of the text (16 padding + 40 container + 16 spacing)
              endIndent: 16.w,
            ),
        ],
      ),
    );
  }
}
