import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';

/// Multi-step forgot-password screen for moderators.
/// Step 0 → Enter email  →  Step 1 → Enter 6-digit code  →  Step 2 → Set new password
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  // Current step: 0 = email, 1 = code & new password, 2 = success
  int _step = 0;
  String? _localError;

  // Controllers
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // Password visibility
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  // Resend cooldown
  int _resendCooldown = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  // ── Step 0: Request code ──────────────────────────────────────────────────

  Future<void> _requestCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _localError = 'forgot_password_email_required'.tr());
      return;
    }
    
    setState(() => _localError = null);

    final success = await ref.read(authProvider.notifier).requestPasswordReset(email);
    
    if (success && mounted) {
      setState(() {
        _step = 1;
        _startResendCooldown();
      });
    }
  }

  // ── Step 1: Submit code and new password ──────────────────────────────────

  // ── Step 2: Submit new password ───────────────────────────────────────────

  Future<void> _submitNewPassword() async {
    final code = _codeController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (code.isEmpty || code.length != 6) {
      setState(() => _localError = 'forgot_password_code_invalid'.tr());
      return;
    }
    if (password.isEmpty || password.length < 6) {
      setState(() => _localError = 'forgot_password_password_too_short'.tr());
      return;
    }
    if (password != confirm) {
      setState(() => _localError = 'forgot_password_passwords_mismatch'.tr());
      return;
    }

    setState(() => _localError = null);

    final resultMessage = await ref.read(authProvider.notifier).resetPassword(
      email: _emailController.text.trim(),
      code: code,
      newPassword: password,
    );

    if (resultMessage != null && mounted) {
      setState(() {
        _step = 2;
      });
    }
  }

  // ── Resend logic ──────────────────────────────────────────────────────────

  void _startResendCooldown() {
    _resendCooldown = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) timer.cancel();
      });
    });
  }

  Future<void> _resendCode() async {
    if (_resendCooldown > 0) return;
    await ref.read(authProvider.notifier).requestPasswordReset(_emailController.text.trim());
    if (mounted && ref.read(authProvider).error == null) {
      _startResendCooldown();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authProvider);
    final error = _localError ?? authState.error;

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Stack(
        children: [
          // Background blurs
          Positioned(
            top: -96.h,
            right: -96.w,
            width: 384.w,
            height: 384.w,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: isDark ? 0.05 : 0.1),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: isDark ? 0.05 : 0.1),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).size.height / 2,
            left: -96.w,
            width: 288.w,
            height: 288.w,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accentGold.withValues(alpha: isDark ? 0.05 : 0.1),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentGold.withValues(alpha: isDark ? 0.05 : 0.1),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Header with back button
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          if (_step == 0 || _step == 2) {
                            context.pop();
                          } else {
                            setState(() {
                              _step = 0;
                              _localError = null;
                              ref.read(authProvider.notifier).clearError();
                            });
                          }
                        },
                        icon: Icon(
                          Symbols.arrow_back,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight - 32.h,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                        SizedBox(height: 16.h),

                        // Icon
                        if (_step < 2)
                          Align(
                            alignment: Alignment.center,
                            child: Container(
                              width: 72.w,
                              height: 72.w,
                              margin: EdgeInsets.only(bottom: 24.h),
                              decoration: BoxDecoration(
                                color: isDark ? AppColors.surfaceDark : Colors.white,
                                borderRadius: BorderRadius.circular(16.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    blurRadius: 20,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Symbols.lock_reset,
                                size: 36.w,
                                color: AppColors.primary,
                              ),
                            ),
                          ),

                        // Title
                        if (_step < 2)
                          Text(
                            'forgot_password_title'.tr(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 28.sp,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                          ),
                        if (_step < 2)
                          SizedBox(height: 8.h),

                        // Subtitle
                        if (_step < 2)
                          Text(
                            _getSubtitle(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14.sp,
                              color: isDark ? AppColors.textMutedLight : const Color(0xff64748b),
                            ),
                          ),

                        SizedBox(height: 32.h),

                        // Form card
                        Container(
                          padding: EdgeInsets.all(24.w),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.surfaceDark : Colors.white,
                            borderRadius: BorderRadius.circular(20.r),
                            boxShadow: [
                              BoxShadow(
                                color: isDark
                                    ? Colors.black.withValues(alpha: 0.2)
                                    : const Color(0xffe2e8f0).withValues(alpha: 0.5),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: _buildStepContent(isDark, authState.isLoading, error),
                        ),

                        SizedBox(height: 32.h),
                      ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getSubtitle() {
    switch (_step) {
      case 0: return 'forgot_password_email_subtitle'.tr();
      case 1: return 'forgot_password_code_sent'.tr(args: [_emailController.text.trim()]);
      default: return '';
    }
  }

  Widget _buildStepContent(bool isDark, bool isLoading, String? error) {
    switch (_step) {
      case 0: return _buildEmailStep(isDark, isLoading, error);
      case 1: return _buildCodeAndPasswordStep(isDark, isLoading, error);
      case 2: return _buildSuccessStep(isDark);
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildEmailStep(bool isDark, bool isLoading, String? error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel('forgot_password_email_label'.tr(), isDark),
        SizedBox(height: 6.h),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14.sp,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          decoration: InputDecoration(
            hintText: 'forgot_password_email_hint'.tr(),
            prefixIcon: Icon(Symbols.mail, size: 20.w),
          ),
        ),
        _buildErrorUI(error, isDark),
        SizedBox(height: 24.h),
        ElevatedButton(
          onPressed: isLoading ? null : _requestCode,
          child: isLoading ? _loadingIndicator() : Text('forgot_password_send_code'.tr()),
        ),
      ],
    );
  }

  Widget _buildCodeAndPasswordStep(bool isDark, bool isLoading, String? error) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel('forgot_password_code_label'.tr(), isDark),
        SizedBox(height: 12.h),
        
        DigitCodeInput(
          length: 6,
          isDark: isDark,
          isLoading: isLoading,
          onCompleted: (code) {
            _codeController.text = code;
          },
        ),
        
        SizedBox(height: 24.h),
        _buildFieldLabel('forgot_password_new_password'.tr(), isDark),
        SizedBox(height: 6.h),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14.sp,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          decoration: InputDecoration(
            hintText: '••••••••',
            prefixIcon: Icon(Symbols.lock, size: 20.w),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Symbols.visibility_off : Symbols.visibility, size: 20.w),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        SizedBox(height: 20.h),
        _buildFieldLabel('forgot_password_confirm_password'.tr(), isDark),
        SizedBox(height: 6.h),
        TextField(
          controller: _confirmPasswordController,
          obscureText: _obscureConfirm,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14.sp,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
          decoration: InputDecoration(
            hintText: '••••••••',
            prefixIcon: Icon(Symbols.lock_outline, size: 20.w),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm ? Symbols.visibility_off : Symbols.visibility, size: 20.w),
              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
        ),

        _buildErrorUI(error, isDark),
        SizedBox(height: 32.h),
        ElevatedButton(
          onPressed: isLoading ? null : _submitNewPassword,
          child: isLoading ? _loadingIndicator() : Text('forgot_password_reset'.tr()),
        ),
        SizedBox(height: 20.h),
        Center(
          child: GestureDetector(
            onTap: _resendCooldown > 0 || isLoading ? null : _resendCode,
            child: Text(
              _resendCooldown > 0
                  ? 'forgot_password_resend_countdown'.tr(args: ['$_resendCooldown'])
                  : 'forgot_password_resend_code'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: _resendCooldown > 0 ? AppColors.textMutedLight : const Color(0xff3b82f6),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessStep(bool isDark) {
    return Column(
      children: [
        SizedBox(height: 16.h),
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 600),
          curve: Curves.elasticOut,
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: child,
            );
          },
          child: Icon(Symbols.check_circle, size: 80.w, color: const Color(0xFF16A34A)),
        ),
        SizedBox(height: 24.h),
        Text(
          'forgot_password_success'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 16.sp,
            fontWeight: FontWeight.w500,
            height: 1.5,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        SizedBox(height: 32.h),
        ElevatedButton(
          onPressed: () => context.go('/login'),
          child: Text('forgot_password_back_to_login'.tr()),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String text, bool isDark) {
    return Padding(
      padding: EdgeInsets.only(left: 4.w),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 13.sp,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : AppColors.textDark,
        ),
      ),
    );
  }

  Widget _buildErrorUI(String? error, bool isDark) {
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3A1010) : Colors.red.shade50,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: isDark ? const Color(0xFF5C1515) : Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16.w, color: Colors.red.shade500),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                error,
                style: TextStyle(fontFamily: 'Lexend', fontSize: 12.sp, color: Colors.red.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingIndicator() {
    return SizedBox(
      width: 22.w,
      height: 22.w,
      child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
    );
  }
}

class DigitCodeInput extends StatefulWidget {
  final int length;
  final ValueChanged<String> onCompleted;
  final bool isDark;
  final bool isLoading;

  const DigitCodeInput({
    super.key,
    this.length = 6,
    required this.onCompleted,
    required this.isDark,
    required this.isLoading,
  });

  @override
  State<DigitCodeInput> createState() => _DigitCodeInputState();
}

class _DigitCodeInputState extends State<DigitCodeInput> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onChanged(int index, String value) {
    if (value.length > 1) {
      final cleanValue = value.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanValue.isEmpty) {
        _controllers[index].text = '';
        return;
      }

      if (cleanValue.length > 2) {
        // Handle Paste of 3+ digits
        for (var i = 0; i < widget.length && i < cleanValue.length; i++) {
          _controllers[i].text = cleanValue[i];
        }
        
        // Move focus to next appropriate box
        final nextFocusIdx = cleanValue.length < widget.length ? cleanValue.length : widget.length - 1;
        _focusNodes[nextFocusIdx].requestFocus();
        
        _checkCompletion();
        return;
      } else if (cleanValue.length == 2) {
        // User typed a second digit in an already filled box
        // We keep the newest digit (the second one)
        _controllers[index].text = cleanValue.substring(1);
        _controllers[index].selection = TextSelection.collapsed(offset: 1);
        
        if (index < widget.length - 1) {
          _focusNodes[index + 1].requestFocus();
        }
        _checkCompletion();
        return;
      }
    }

    if (value.isNotEmpty) {
      if (index < widget.length - 1) {
        _focusNodes[index + 1].requestFocus();
      }
      _checkCompletion();
    }
  }

  void _checkCompletion() {
    final code = _controllers.map((c) => c.text).join();
    if (code.length == widget.length) {
      widget.onCompleted(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(widget.length, (index) {
          return SizedBox(
            width: 44.w, // Slightly adjusted for spacing
            height: 56.h,
            child: KeyboardListener(
              focusNode: FocusNode(), // Intercept backspace
              onKeyEvent: (event) {
                if (event is KeyDownEvent && 
                    event.logicalKey == LogicalKeyboardKey.backspace && 
                    _controllers[index].text.isEmpty && 
                    index > 0) {
                  _focusNodes[index - 1].requestFocus();
                }
              },
              child: TextField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                enabled: !widget.isLoading,
                textAlign: TextAlign.center,
                textDirection: ui.TextDirection.ltr,
                keyboardType: TextInputType.number,
                onTap: () {
                  // Force focus to the first empty box to enforce LTR typing
                  int targetIndex = widget.length - 1;
                  for (int i = 0; i < widget.length; i++) {
                    if (_controllers[i].text.isEmpty) {
                      targetIndex = i;
                      break;
                    }
                  }
                  if (_focusNodes[targetIndex].hasFocus == false) {
                    _focusNodes[targetIndex].requestFocus();
                  }
                },
                style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 20.sp,
                fontWeight: FontWeight.w600,
                color: widget.isDark ? Colors.white : AppColors.textDark,
              ),
              inputFormatters: [
                // We don't limit length here because paste needs it
                FilteringTextInputFormatter.digitsOnly,
              ],
              decoration: InputDecoration(
                counterText: '',
                contentPadding: EdgeInsets.zero,
                filled: true,
                fillColor: widget.isDark 
                    ? AppColors.surfaceDark.withValues(alpha: 0.5) 
                    : const Color(0xfff8fafc),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(
                    color: widget.isDark ? Colors.white24 : const Color(0xffe2e8f0),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(color: AppColors.primary, width: 2),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide(
                    color: widget.isDark ? Colors.white12 : const Color(0xfff1f5f9),
                  ),
                ),
              ),
              onChanged: (value) => _onChanged(index, value),
            ),
          ),
        );
      }),
    ));
  }
}
