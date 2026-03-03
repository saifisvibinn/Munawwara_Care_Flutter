import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';

/// Dialog for adding and verifying email address
class EmailVerificationDialog extends ConsumerStatefulWidget {
  final bool hasExistingEmail;

  const EmailVerificationDialog({super.key, required this.hasExistingEmail});

  @override
  ConsumerState<EmailVerificationDialog> createState() =>
      _EmailVerificationDialogState();
}

class _EmailVerificationDialogState
    extends ConsumerState<EmailVerificationDialog> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _codeFocusNode = FocusNode();

  bool _isVerificationStep = false;
  bool _isLoading = false;
  Timer? _countdownTimer;
  int _resendCountdown = 0;

  @override
  void initState() {
    super.initState();
    // If user already has email, resume at verification step.
    // Do NOT auto-send here; reopening the app/dialog should not trigger
    // background errors/snackbars due to resend throttling.
    if (widget.hasExistingEmail) {
      _isVerificationStep = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusCodeInput());
    }

    // Listen to focus changes to update UI
    _codeFocusNode.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _codeFocusNode.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startResendCountdown() {
    _resendCountdown = 60;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _addEmail() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);

    try {
      final success = await ref
          .read(authProvider.notifier)
          .addEmail(_emailCtrl.text.trim());

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (success) {
        setState(() => _isVerificationStep = true);
        _sendVerificationCode();
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusCodeInput());
      } else {
        final error = ref.read(authProvider).error ?? 'email_add_error'.tr();
        _showSnackBar(error, isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('email_verification_generic_error'.tr(), isError: true);
    }
  }

  Future<void> _sendVerificationCode() async {
    setState(() => _isLoading = true);

    try {
      final success = await ref
          .read(authProvider.notifier)
          .sendEmailVerification();

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (success) {
        _startResendCountdown();
        _showSnackBar('email_verification_sent'.tr());
      } else {
        final error =
            ref.read(authProvider).error ??
            'email_verification_send_error'.tr();
        _showSnackBar(error, isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('An error occurred. Please try again.', isError: true);
    }
  }

  Future<void> _verifyCode() async {
    if (_codeCtrl.text.trim().isEmpty) {
      _showSnackBar('email_verification_code_required'.tr(), isError: true);
      return;
    }

    if (_codeCtrl.text.trim().length != 6) {
      _showSnackBar('email_verification_code_length'.tr(), isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final success = await ref
          .read(authProvider.notifier)
          .verifyEmail(_codeCtrl.text.trim());

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (success) {
        _showSnackBar('email_verified_success'.tr());
        Navigator.of(context).pop(true); // Return true to indicate success
      } else {
        final error =
            ref.read(authProvider).error ?? 'email_verification_error'.tr();
        _showSnackBar(error, isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('email_verification_generic_error'.tr(), isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
      ),
    );
  }

  Future<void> _focusCodeInput() async {
    if (!mounted) return;

    // If already focused but keyboard was dismissed manually, force show again.
    if (_codeFocusNode.hasFocus) {
      await SystemChannels.textInput.invokeMethod('TextInput.show');
      return;
    }

    // Reset focus first, then request focus to guarantee keyboard opens.
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 30));
    if (!mounted) return;

    FocusScope.of(context).requestFocus(_codeFocusNode);
    await Future.delayed(const Duration(milliseconds: 30));
    if (!mounted) return;

    await SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 20.h),
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: screenHeight - viewInsets.bottom - 40.h,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isVerificationStep
                        ? 'email_verify_title'.tr()
                        : 'email_add_title'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 20.sp,
                      color: textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: textMuted),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Text(
                _isVerificationStep
                    ? 'email_verify_description'.tr()
                    : 'email_add_description'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 13.sp,
                  color: textMuted,
                ),
              ),
              SizedBox(height: 24.h),

              // Content
              if (!_isVerificationStep) ...[
                // Email input step
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: textPrimary,
                    ),
                    decoration: InputDecoration(
                      labelText: 'email_address'.tr(),
                      hintText: 'example@email.com',
                      prefixIcon: Icon(
                        Icons.email_rounded,
                        color: AppColors.primary,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(
                          color: textMuted.withOpacity(0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 2,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'email_required'.tr();
                      }
                      if (!RegExp(
                        r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                      ).hasMatch(v)) {
                        return 'email_invalid'.tr();
                      }
                      return null;
                    },
                  ),
                ),
                SizedBox(height: 20.h),
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _addEmail,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.primary.withOpacity(
                        0.6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 20.w,
                            height: 20.w,
                            child: const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'continue'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w600,
                              fontSize: 15.sp,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ] else ...[
                // Verification code input step
                Center(
                  child: Text(
                    'Enter the 6-digit code',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      color: textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(height: 16.h),

                // OTP Input Boxes - Tap to focus
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _focusCodeInput,
                  child: Container(
                    color: Colors.transparent,
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(6, (index) {
                            final hasValue = _codeCtrl.text.length > index;
                            final isFocused =
                                _codeFocusNode.hasFocus &&
                                _codeCtrl.text.length == index;

                            return Container(
                              margin: EdgeInsets.symmetric(horizontal: 3.w),
                              width: 38.w,
                              height: 52.h,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.surfaceDark.withOpacity(0.5)
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(
                                  color: isFocused
                                      ? AppColors.primary
                                      : hasValue
                                      ? AppColors.primary.withOpacity(0.5)
                                      : textMuted.withOpacity(0.3),
                                  width: isFocused ? 2 : 1.5,
                                ),
                                boxShadow: isFocused
                                    ? [
                                        BoxShadow(
                                          color: AppColors.primary.withOpacity(
                                            0.2,
                                          ),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Center(
                                child: Text(
                                  hasValue ? _codeCtrl.text[index] : '',
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 20.sp,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                        SizedBox(height: 12.h),

                        // Tap to focus hint
                        Text(
                          'Tap boxes to enter code',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 11.sp,
                            color: textMuted.withOpacity(0.6),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Hidden TextField for input (kept at 1x1 to ensure keyboard can re-open)
                SizedBox(
                  height: 1,
                  width: 1,
                  child: Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: _codeCtrl,
                      focusNode: _codeFocusNode,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      maxLength: 6,
                      autofocus: false,
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (value) {
                        setState(() {}); // Rebuild to update boxes
                      },
                    ),
                  ),
                ),

                SizedBox(height: 8.h),

                // Resend button
                Center(
                  child: TextButton(
                    onPressed: _resendCountdown > 0 || _isLoading
                        ? null
                        : _sendVerificationCode,
                    child: Text(
                      _resendCountdown > 0
                          ? 'resend_code_countdown'.tr(
                              args: ['$_resendCountdown'],
                            )
                          : 'resend_code'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13.sp,
                        color: _resendCountdown > 0
                            ? textMuted
                            : AppColors.primary,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 12.h),

                // Verify button
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.primary.withOpacity(
                        0.6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 20.w,
                            height: 20.w,
                            child: const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'verify'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w600,
                              fontSize: 15.sp,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
