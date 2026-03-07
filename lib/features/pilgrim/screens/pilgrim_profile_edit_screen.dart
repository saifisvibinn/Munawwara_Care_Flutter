import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../shared/widgets/email_verification_dialog.dart';

class PilgrimProfileEditScreen extends ConsumerStatefulWidget {
  const PilgrimProfileEditScreen({super.key});

  @override
  ConsumerState<PilgrimProfileEditScreen> createState() =>
      _PilgrimProfileEditScreenState();
}

class _PilgrimProfileEditScreenState
    extends ConsumerState<PilgrimProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _ageCtrl;
  late final TextEditingController _medicalCtrl;
  String? _selectedGender;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    _nameCtrl = TextEditingController(text: auth.fullName ?? '');
    _phoneCtrl = TextEditingController(text: auth.phoneNumber ?? '');
    _ageCtrl = TextEditingController(
      text: auth.age != null ? '${auth.age}' : '',
    );
    _medicalCtrl = TextEditingController(text: auth.medicalHistory ?? '');
    _selectedGender = auth.gender;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _ageCtrl.dispose();
    _medicalCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final ageText = _ageCtrl.text.trim();
    final int? age = ageText.isNotEmpty ? int.tryParse(ageText) : null;

    final success = await ref
        .read(authProvider.notifier)
        .updateProfile(
          fullName: _nameCtrl.text.trim(),
          phoneNumber: _phoneCtrl.text.trim(),
          age: age,
          gender: _selectedGender,
          medicalHistory: _medicalCtrl.text.trim(),
        );

    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('edit_profile_success'.tr()),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
      );
      Navigator.of(context).pop();
    } else {
      final error =
          ref.read(authProvider).error ?? 'edit_profile_error_generic'.tr();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
      );
    }
  }

  Future<void> _handleEmailAction() async {
    // Refresh first so reopened app uses latest server state.
    await ref.read(authProvider.notifier).fetchProfile();
    final authState = ref.read(authProvider);
    final hasEmail = authState.email != null && authState.email!.isNotEmpty;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => EmailVerificationDialog(hasExistingEmail: hasEmail),
    );

    if (result == true && mounted) {
      // Refresh profile to get updated email verification status
      await ref.read(authProvider.notifier).fetchProfile();
      setState(() {});
    }
  }

  Future<void> _requestModerator() async {
    final authState = ref.read(authProvider);

    // Check if email exists and is verified
    if (authState.email == null || authState.email!.isEmpty) {
      _showError('moderator_request_email_required'.tr());
      return;
    }

    if (!authState.emailVerified) {
      _showError('moderator_request_email_not_verified'.tr());
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('moderator_request_confirm_title'.tr()),
        content: Text('moderator_request_confirm_message'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text('confirm'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    final success = await ref.read(authProvider.notifier).requestModerator();
    if (!mounted) return;
    setState(() => _saving = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('moderator_request_success'.tr()),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
        ),
      );
      Navigator.of(context).pop();
    } else {
      final error =
          ref.read(authProvider).error ?? 'moderator_request_error'.tr();
      _showError(error);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
      ),
    );
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

    final fullName = authState.fullName ?? 'Pilgrim';
    final initials = _initials(fullName);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
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

            // ── Body ────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 28.h),

                      // ── Avatar ─────────────────────────────────────────
                      Center(
                        child: Container(
                          width: 88.w,
                          height: 88.w,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primaryDark,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontWeight: FontWeight.w700,
                                fontSize: 30.sp,
                                color: Colors.white,
                              ),
                            ),
                          ),
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
                            'settings_role_pilgrim'.tr(),
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

                      // ── PERSONAL INFO section ─────────────────────────
                      _SectionLabel(
                        label: 'edit_profile_section'.tr(),
                        textMuted: textMuted,
                      ),
                      SizedBox(height: 10.h),

                      Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 
                                isDark ? 0.3 : 0.06,
                              ),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _EditField(
                              controller: _nameCtrl,
                              label: 'edit_profile_full_name'.tr(),
                              icon: Icons.person_rounded,
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                              isFirst: true,
                              hasDivider: true,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'edit_profile_error_name'.tr();
                                }
                                return null;
                              },
                            ),
                            _EditField(
                              controller: _phoneCtrl,
                              label: 'edit_profile_phone'.tr(),
                              icon: Icons.phone_rounded,
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                              keyboardType: TextInputType.phone,
                              hasDivider: authState.email != null,
                            ),
                            if (authState.email != null)
                              _ReadOnlyField(
                                value: authState.email!,
                                label: 'edit_profile_email'.tr(),
                                icon: Icons.email_rounded,
                                isDark: isDark,
                                textPrimary: textPrimary,
                                textMuted: textMuted,
                                isVerified: authState.emailVerified,
                              ),
                          ],
                        ),
                      ),

                      SizedBox(height: 24.h),

                      // ── HEALTH INFO section ───────────────────────────
                      _SectionLabel(
                        label: 'edit_profile_health_section'.tr(),
                        textMuted: textMuted,
                      ),
                      SizedBox(height: 10.h),
                      Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 
                                isDark ? 0.3 : 0.06,
                              ),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Age field
                            _EditField(
                              controller: _ageCtrl,
                              label: 'reg_age'.tr(),
                              icon: Icons.cake_rounded,
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                              isFirst: true,
                              hasDivider: true,
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (v != null && v.trim().isNotEmpty) {
                                  final n = int.tryParse(v.trim());
                                  if (n == null || n < 1 || n > 120) {
                                    return 'Enter a valid age (1–120)';
                                  }
                                }
                                return null;
                              },
                            ),
                            // Gender selector
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                16.w,
                                12.h,
                                16.w,
                                12.h,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38.w,
                                    height: 38.w,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(alpha: 
                                        0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(10.r),
                                    ),
                                    child: Icon(
                                      Icons.wc_rounded,
                                      color: AppColors.primary,
                                      size: 18.sp,
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'reg_gender'.tr(),
                                          style: TextStyle(
                                            fontFamily: 'Lexend',
                                            fontSize: 12.sp,
                                            color: textMuted,
                                          ),
                                        ),
                                        SizedBox(height: 8.h),
                                        Row(
                                          children: [
                                            _GenderChip(
                                              label: 'reg_male'.tr(),
                                              value: 'male',
                                              selected:
                                                  _selectedGender == 'male',
                                              isDark: isDark,
                                              onTap: () => setState(
                                                () => _selectedGender =
                                                    _selectedGender == 'male'
                                                    ? null
                                                    : 'male',
                                              ),
                                            ),
                                            SizedBox(width: 8.w),
                                            _GenderChip(
                                              label: 'reg_female'.tr(),
                                              value: 'female',
                                              selected:
                                                  _selectedGender == 'female',
                                              isDark: isDark,
                                              onTap: () => setState(
                                                () => _selectedGender =
                                                    _selectedGender == 'female'
                                                    ? null
                                                    : 'female',
                                              ),
                                            ),
                                            SizedBox(width: 8.w),
                                            _GenderChip(
                                              label: 'profile_gender_other'
                                                  .tr(),
                                              value: 'other',
                                              selected:
                                                  _selectedGender == 'other',
                                              isDark: isDark,
                                              onTap: () => setState(
                                                () => _selectedGender =
                                                    _selectedGender == 'other'
                                                    ? null
                                                    : 'other',
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: isDark
                                  ? const Color(0xFF2D4A3A)
                                  : const Color(0xFFE2E8F0),
                              indent: 16.w,
                              endIndent: 16.w,
                            ),
                            // Medical history field (multiline)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                16.w,
                                8.h,
                                16.w,
                                8.h,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(top: 14.h),
                                    child: Container(
                                      width: 38.w,
                                      height: 38.w,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(alpha: 
                                          0.12,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          10.r,
                                        ),
                                      ),
                                      child: Icon(
                                        Icons.medical_information_rounded,
                                        color: AppColors.primary,
                                        size: 18.sp,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _medicalCtrl,
                                      maxLines: 3,
                                      minLines: 2,
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 14.sp,
                                        color: textPrimary,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'reg_medical'.tr(),
                                        hintText: 'reg_medical_hint'.tr(),
                                        labelStyle: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 12.sp,
                                          color: textMuted,
                                        ),
                                        hintStyle: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 13.sp,
                                          color: textMuted.withValues(alpha: 0.6),
                                        ),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(
                                          vertical: 14.h,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: 24.h),
                      if (authState.email == null ||
                          !authState.emailVerified) ...[
                        _SectionLabel(
                          label: 'edit_profile_email_section'.tr(),
                          textMuted: textMuted,
                        ),
                        SizedBox(height: 10.h),
                        Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16.r),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 
                                  isDark ? 0.3 : 0.06,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16.w),
                            child: Row(
                              children: [
                                Container(
                                  width: 38.w,
                                  height: 38.w,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10.r),
                                  ),
                                  child: Icon(
                                    authState.email == null
                                        ? Icons.add_rounded
                                        : Icons.verified_outlined,
                                    color: AppColors.primary,
                                    size: 18.sp,
                                  ),
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        authState.email == null
                                            ? 'edit_profile_add_email'.tr()
                                            : 'edit_profile_verify_email'.tr(),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14.sp,
                                          color: textPrimary,
                                        ),
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        authState.email == null
                                            ? 'edit_profile_add_email_desc'.tr()
                                            : 'edit_profile_verify_email_desc'
                                                  .tr(),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 11.sp,
                                          color: textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                ElevatedButton(
                                  onPressed: _handleEmailAction,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10.r),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 16.w,
                                      vertical: 10.h,
                                    ),
                                  ),
                                  child: Text(
                                    authState.email == null
                                        ? 'add'.tr()
                                        : 'verify'.tr(),
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.sp,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 24.h),
                      ],

                      // ── MODERATOR REQUEST section ──────────────────────
                      if (authState.moderatorRequestStatus == null) ...[
                        _SectionLabel(
                          label: 'edit_profile_moderator_section'.tr(),
                          textMuted: textMuted,
                        ),
                        SizedBox(height: 10.h),
                        Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16.r),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 
                                  isDark ? 0.3 : 0.06,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16.w),
                            child: Row(
                              children: [
                                Container(
                                  width: 38.w,
                                  height: 38.w,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10.r),
                                  ),
                                  child: Icon(
                                    Icons.upgrade_rounded,
                                    color: AppColors.primary,
                                    size: 18.sp,
                                  ),
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'edit_profile_request_moderator'.tr(),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14.sp,
                                          color: textPrimary,
                                        ),
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        'edit_profile_request_moderator_desc'
                                            .tr(),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 11.sp,
                                          color: textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                ElevatedButton(
                                  onPressed: _saving ? null : _requestModerator,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    disabledBackgroundColor: AppColors.primary
                                        .withValues(alpha: 0.6),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10.r),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 16.w,
                                      vertical: 10.h,
                                    ),
                                  ),
                                  child: Text(
                                    'request'.tr(),
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13.sp,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 24.h),
                      ] else ...[
                        // Show moderator request status
                        _SectionLabel(
                          label: 'edit_profile_moderator_section'.tr(),
                          textMuted: textMuted,
                        ),
                        SizedBox(height: 10.h),
                        Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(16.r),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 
                                  isDark ? 0.3 : 0.06,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(16.w),
                            child: Row(
                              children: [
                                Container(
                                  width: 38.w,
                                  height: 38.w,
                                  decoration: BoxDecoration(
                                    color: _getStatusColor(
                                      authState.moderatorRequestStatus!,
                                    ).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10.r),
                                  ),
                                  child: Icon(
                                    _getStatusIcon(
                                      authState.moderatorRequestStatus!,
                                    ),
                                    color: _getStatusColor(
                                      authState.moderatorRequestStatus!,
                                    ),
                                    size: 18.sp,
                                  ),
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        authState.moderatorRequestStatus ==
                                                'pending'
                                            ? 'moderator_status_pending'.tr()
                                            : authState
                                                      .moderatorRequestStatus ==
                                                  'approved'
                                            ? 'moderator_status_approved'.tr()
                                            : 'moderator_status_rejected'.tr(),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14.sp,
                                          color: textPrimary,
                                        ),
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        authState.moderatorRequestStatus ==
                                                'pending'
                                            ? 'moderator_status_pending_desc'
                                                  .tr()
                                            : authState
                                                      .moderatorRequestStatus ==
                                                  'approved'
                                            ? 'moderator_status_approved_desc'
                                                  .tr()
                                            : 'moderator_status_rejected_desc'
                                                  .tr(),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 11.sp,
                                          color: textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 24.h),
                      ],

                      // ── Save Changes button ──────────────────────────
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
    if (parts.isEmpty) return 'P';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return AppColors.primary;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_empty_rounded;
      case 'approved':
        return Icons.check_circle_rounded;
      case 'rejected':
        return Icons.cancel_rounded;
      default:
        return Icons.help_outline_rounded;
    }
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

class _EditField extends StatelessWidget {
  const _EditField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
    this.isFirst = false,
    this.hasDivider = false,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool isDark;
  final Color textPrimary;
  final Color textMuted;
  final bool isFirst;
  final bool hasDivider;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final dividerColor = isDark
        ? const Color(0xFF2D4A3A)
        : const Color(0xFFE2E8F0);
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, isFirst ? 6.h : 0, 16.w, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38.w,
                height: 38.w,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(icon, color: AppColors.primary, size: 18.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: TextFormField(
                  controller: controller,
                  keyboardType: keyboardType,
                  validator: validator,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    color: textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: label,
                    labelStyle: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      color: textMuted,
                    ),
                    border: InputBorder.none,
                    errorStyle: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 11.sp,
                    ),
                    contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: dividerColor,
            indent: 16.w,
            endIndent: 16.w,
          ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.value,
    required this.label,
    required this.icon,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
    this.isVerified = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final bool isDark;
  final Color textPrimary;
  final Color textMuted;
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 6.h),
      child: Row(
        children: [
          Container(
            width: 38.w,
            height: 38.w,
            decoration: BoxDecoration(
              color: textMuted.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, color: textMuted, size: 18.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: 14.h),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.sp,
                    color: textMuted,
                  ),
                ),
                SizedBox(height: 2.h),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 14.sp,
                          color: textMuted,
                        ),
                      ),
                    ),
                    if (isVerified)
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 7.w,
                          vertical: 3.h,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.verified_rounded,
                              size: 12.sp,
                              color: AppColors.primary,
                            ),
                            SizedBox(width: 3.w),
                            Text(
                              'edit_profile_email_verified'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 10.sp,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 14.h),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  const _GenderChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : (isDark ? AppColors.backgroundDark : const Color(0xFFF0F0F8)),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? const Color(0xFF2D4A3A) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 13.sp,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected
                ? Colors.white
                : (isDark ? Colors.white70 : AppColors.textDark),
          ),
        ),
      ),
    );
  }
}
