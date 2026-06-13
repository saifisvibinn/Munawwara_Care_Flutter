import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
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
  File? _localProfilePictureFile;

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

  bool _hasUnsavedChanges() {
    final auth = ref.read(authProvider);
    final nameChanged = _nameCtrl.text.trim() != (auth.fullName ?? '');
    final phoneChanged = _phoneCtrl.text.trim() != (auth.phoneNumber ?? '');
    final pfpChanged = _localProfilePictureFile != null;
    return nameChanged || phoneChanged || pfpChanged;
  }

  Future<bool> _showDiscardConfirmationDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
          ),
          title: Text(
            'profile_discard_title'.tr() == 'profile_discard_title'
                ? 'Discard Changes?'
                : 'profile_discard_title'.tr(),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: textPrimary,
              fontSize: 18.sp,
            ),
          ),
          content: Text(
            'profile_discard_msg'.tr() == 'profile_discard_msg'
                ? 'Changes will be discarded until saved.'
                : 'profile_discard_msg'.tr(),
            style: TextStyle(
              color: textPrimary.withValues(alpha: 0.8),
              fontSize: 14.sp,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'profile_discard_cancel'.tr() == 'profile_discard_cancel'
                    ? 'Keep Editing'
                    : 'profile_discard_cancel'.tr(),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'profile_discard_confirm'.tr() == 'profile_discard_confirm'
                    ? 'Discard'
                    : 'profile_discard_confirm'.tr(),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.red,
                ),
              ),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final auth = ref.read(authProvider);
    final nameChanged = _nameCtrl.text.trim() != (auth.fullName ?? '');
    final phoneChanged = _phoneCtrl.text.trim() != (auth.phoneNumber ?? '');

    bool success = true;

    if (nameChanged || phoneChanged) {
      success = await ref
          .read(authProvider.notifier)
          .updateProfile(
            fullName: _nameCtrl.text.trim(),
            phoneNumber: _phoneCtrl.text.trim(),
          );
    }

    if (!success) {
      if (!mounted) return;
      setState(() => _saving = false);
      final error =
          ref.read(authProvider).error ?? 'edit_profile_error_generic'.tr();
      StandardSnackBar.showError(context, error);
      return;
    }

    if (_localProfilePictureFile != null) {
      final pfpSuccess = await ref
          .read(authProvider.notifier)
          .updateProfilePicture(_localProfilePictureFile!);
      if (!pfpSuccess) {
        if (!mounted) return;
        setState(() => _saving = false);
        final error =
            ref.read(authProvider).error ?? 'Failed to update profile picture';
        StandardSnackBar.showError(context, error);
        return;
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    StandardSnackBar.showSuccess(context, 'edit_profile_success'.tr());
    Navigator.of(context).pop();
  }

  Future<void> _onAvatarTap() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: EdgeInsets.only(top: 8.h, bottom: 16.h),
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              Text(
                'profile_picture_title'.tr() == 'profile_picture_title'
                    ? 'Profile Picture'
                    : 'profile_picture_title'.tr(),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16.sp,
                  color: textPrimary,
                ),
              ),
              SizedBox(height: 16.h),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                title: Text(
                  'profile_picture_camera'.tr() == 'profile_picture_camera'
                      ? 'Take Photo'
                      : 'profile_picture_camera'.tr(),
                  style: TextStyle( color: textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                title: Text(
                  'profile_picture_gallery'.tr() == 'profile_picture_gallery'
                      ? 'Choose from Gallery'
                      : 'profile_picture_gallery'.tr(),
                  style: TextStyle( color: textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              SizedBox(height: 8.h),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 85,
      );
      if (image == null) return;

      setState(() {
        _localProfilePictureFile = File(image.path);
      });
    } catch (e) {
      if (!mounted) return;
      StandardSnackBar.showError(context, 'Error selecting image: $e');
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

    return PopScope(
      canPop: !_hasUnsavedChanges(),
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _showDiscardConfirmationDialog();
        if (discard && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
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
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'edit_profile_title'.tr(),
                        style: TextStyle(
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
                        child: GestureDetector(
                          onTap: _saving ? null : _onAvatarTap,
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white24
                                        : AppColors.primary.withValues(alpha: 0.24),
                                    width: 2.w,
                                  ),
                                ),
                                child: _localProfilePictureFile != null
                                    ? ClipOval(
                                        child: Image.file(
                                          _localProfilePictureFile!,
                                          width: 88.w,
                                          height: 88.w,
                                          fit: BoxFit.cover,
                                        ),
                                      )
                                    : ModeratorAvatar(
                                        size: 88.w,
                                        initials: initials,
                                        imageUrl: authState.profilePicture,
                                      ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: EdgeInsets.all(6.w),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppColors.primary,
                                  ),
                                  child: Icon(
                                    Icons.camera_alt_rounded,
                                    color: Colors.white,
                                    size: 14.sp,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      SizedBox(height: 8.h),
                      Center(
                        child: Text(
                          fullName,
                          style: TextStyle(
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
