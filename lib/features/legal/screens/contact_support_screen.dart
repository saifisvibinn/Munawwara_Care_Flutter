import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/config/legal_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';
import '../../../core/widgets/phone_number_text.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/support_api.dart';

/// In-app support or account-deletion request (emailed to support by the server).
class ContactSupportScreen extends ConsumerStatefulWidget {
  const ContactSupportScreen({
    super.key,
    this.requestType = SupportRequestType.support,
  });

  final SupportRequestType requestType;

  @override
  ConsumerState<ContactSupportScreen> createState() =>
      _ContactSupportScreenState();
}

class _ContactSupportScreenState extends ConsumerState<ContactSupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  final _contactController = TextEditingController();
  bool _isSubmitting = false;
  bool _didSucceed = false;
  String? _errorMessage;

  bool get _isDeletion =>
      widget.requestType == SupportRequestType.accountDeletion;

  @override
  void dispose() {
    _messageController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await SupportApi.submitRequest(
        type: widget.requestType,
        message: _messageController.text,
        contactHint: _contactController.text,
      );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _didSucceed = true;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = SupportApi.parseError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString();
      });
    }
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
    final auth = ref.watch(authProvider);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
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
            _isDeletion
                ? 'legal_request_deletion'.tr()
                : 'legal_contact_support'.tr(),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 18.sp,
              color: textPrimary,
            ),
          ),
        ),
        body: _didSucceed
            ? _SuccessBody(
                isDeletion: _isDeletion,
                textPrimary: textPrimary,
                textMuted: textMuted,
                onDone: () => Navigator.of(context).maybePop(),
              )
            : AppScrollFadeOverlay(
                showTop: false,
                backgroundColor:
                    isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
                child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isDeletion
                            ? 'legal_deletion_form_intro'.tr()
                            : 'legal_contact_support_intro'.tr(),
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: textMuted,
                          height: 1.45,
                        ),
                      ),
                      SizedBox(height: 20.h),
                      _AccountInfoCard(
                        cardBg: cardBg,
                        isDark: isDark,
                        textPrimary: textPrimary,
                        textMuted: textMuted,
                        auth: auth,
                      ),
                      SizedBox(height: 20.h),
                      TextFormField(
                        controller: _messageController,
                        maxLines: _isDeletion ? 4 : 6,
                        maxLength: 2000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _fieldDecoration(
                          label: _isDeletion
                              ? 'legal_deletion_message_label'.tr()
                              : 'legal_support_message_label'.tr(),
                          hint: _isDeletion
                              ? 'legal_deletion_message_hint'.tr()
                              : 'legal_support_message_hint'.tr(),
                          isDark: isDark,
                        ),
                        validator: (value) {
                          if (_isDeletion) return null;
                          if (value == null || value.trim().isEmpty) {
                            return 'legal_support_message_required'.tr();
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: 16.h),
                      TextFormField(
                        controller: _contactController,
                        maxLength: 320,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _fieldDecoration(
                          label: 'legal_support_contact_hint_label'.tr(),
                          hint: 'legal_support_contact_hint_hint'.tr(),
                          isDark: isDark,
                        ),
                      ),
                      if (_errorMessage != null) ...[
                        SizedBox(height: 16.h),
                        SelectableText.rich(
                          TextSpan(
                            text: _errorMessage,
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: 24.h),
                      SizedBox(
                        height: 52.h,
                        child: FilledButton(
                          onPressed: _isSubmitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: _isDeletion
                                ? Colors.red.shade700
                                : AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14.r),
                            ),
                          ),
                          child: _isSubmitting
                              ? SizedBox(
                                  width: 22.w,
                                  height: 22.w,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isDeletion
                                      ? 'legal_deletion_submit'.tr()
                                      : 'legal_support_submit'.tr(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15.sp,
                                  ),
                                ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      Text(
                        'legal_support_footer'.tr(
                          namedArgs: {
                            'email': LegalConfig.supportEmail,
                          },
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: textMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required bool isDark,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.r),
      ),
      filled: true,
      fillColor: isDark
          ? AppColors.surfaceDark
          : Colors.white,
    );
  }
}

class _AccountInfoCard extends StatelessWidget {
  const _AccountInfoCard({
    required this.cardBg,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
    required this.auth,
  });

  final Color cardBg;
  final bool isDark;
  final Color textPrimary;
  final Color textMuted;
  final AuthState auth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'legal_support_account_info'.tr(),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13.sp,
              color: textMuted,
            ),
          ),
          SizedBox(height: 12.h),
          _InfoRow(
            label: 'legal_deletion_email_role'.tr(),
            value: auth.role ?? '—',
            textPrimary: textPrimary,
            textMuted: textMuted,
          ),
          _InfoRow(
            label: 'legal_deletion_email_user_id'.tr(),
            value: auth.userId ?? '—',
            textPrimary: textPrimary,
            textMuted: textMuted,
          ),
          _InfoRow(
            label: 'legal_deletion_email_name'.tr(),
            value: auth.fullName ?? '—',
            textPrimary: textPrimary,
            textMuted: textMuted,
          ),
          if (auth.phoneNumber != null && auth.phoneNumber!.isNotEmpty)
            _InfoRow(
              label: 'legal_deletion_email_phone'.tr(),
              value: auth.phoneNumber!,
              textPrimary: textPrimary,
              textMuted: textMuted,
              forceLtr: true,
            ),
          if (auth.email != null && auth.email!.isNotEmpty)
            _InfoRow(
              label: 'legal_support_account_email'.tr(),
              value: auth.email!,
              textPrimary: textPrimary,
              textMuted: textMuted,
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.textPrimary,
    required this.textMuted,
    this.forceLtr = false,
  });

  final String label;
  final String value;
  final Color textPrimary;
  final Color textMuted;
  final bool forceLtr;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88.w,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                color: textMuted,
              ),
            ),
          ),
          Expanded(
            child: forceLtr
                ? PhoneNumberText(
                    value,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: textPrimary,
                    ),
                  )
                : Text(
                    value,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: textPrimary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SuccessBody extends StatelessWidget {
  const _SuccessBody({
    required this.isDeletion,
    required this.textPrimary,
    required this.textMuted,
    required this.onDone,
  });

  final bool isDeletion;
  final Color textPrimary;
  final Color textMuted;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 32.h),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 64.sp,
            color: AppColors.primary,
          ),
          SizedBox(height: 24.h),
          Text(
            isDeletion
                ? 'legal_deletion_success_title'.tr()
                : 'legal_support_success_title'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 20.sp,
              color: textPrimary,
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            isDeletion
                ? 'legal_deletion_success_body'.tr()
                : 'legal_support_success_body'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.sp,
              color: textMuted,
              height: 1.45,
            ),
          ),
          SizedBox(height: 32.h),
          SizedBox(
            width: double.infinity,
            height: 52.h,
            child: FilledButton(
              onPressed: onDone,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                ),
              ),
              child: Text(
                'dialog_ok'.tr(),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15.sp,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
