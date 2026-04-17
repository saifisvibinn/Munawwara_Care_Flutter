import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isModeratorLogin = false;
  bool _isScanningQr = false;
  bool _obscurePassword = true;
  String? _loginError;

  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();

  bool _scanHandled = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  String _extractToken(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return '';

    final uri = Uri.tryParse(raw);
    if (uri != null) {
      final qpToken = uri.queryParameters['token'];
      if (qpToken != null && qpToken.trim().isNotEmpty) {
        return qpToken.trim();
      }
    }
    return raw;
  }

  Future<void> _handleModeratorLogin() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    if (identifier.isEmpty || password.isEmpty) {
      setState(() => _loginError = 'fill_all_fields_error'.tr());
      return;
    }
    setState(() => _loginError = null);
    final success = await ref
        .read(authProvider.notifier)
        .login(identifier: identifier, password: password);
    if (!mounted) return;
    if (success) {
      final role = ref.read(authProvider).role;
      if (role == 'moderator') {
        context.go('/moderator-dashboard');
      } else {
        context.go('/pilgrim-dashboard');
      }
    } else {
      setState(
        () => _loginError = ref.read(authProvider).error ?? 'Login failed',
      );
    }
  }

  Future<void> _handlePilgrimLoginCode(String rawToken) async {
    if (rawToken.trim().isEmpty) {
      setState(() => _loginError = 'Please enter your login code');
      return;
    }
    final token = _extractToken(rawToken);
    if (token.isEmpty) {
      setState(() => _loginError = 'Invalid login code');
      return;
    }

    setState(() => _loginError = null);
    final success = await ref
        .read(authProvider.notifier)
        .loginWithOneTimeToken(token: token);

    if (!mounted) return;

    if (success) {
      final role = ref.read(authProvider).role;
      if (role == 'moderator') {
        context.go('/moderator-dashboard');
      } else {
        context.go('/pilgrim-dashboard');
      }
    } else {
      setState(() {
        _loginError = ref.read(authProvider).error ?? 'Invalid login code';
      });
      _scanHandled = false;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanHandled || ref.read(authProvider).isLoading) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.trim().isEmpty) return;

    _scanHandled = true;
    _scannerController.stop();
    void _ = _handlePilgrimLoginCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLoading = ref.watch(authProvider).isLoading;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: Stack(
        children: [
          // Background Blurs
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
                    color: AppColors.primary.withValues(
                      alpha: isDark ? 0.05 : 0.1,
                    ),
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
                color: AppColors.accentGold.withValues(
                  alpha: isDark ? 0.05 : 0.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentGold.withValues(
                      alpha: isDark ? 0.05 : 0.1,
                    ),
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
                // Header (Language dropdown)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 24.w,
                    vertical: 8.h,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [_buildLanguageDropdown(isDark)],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: 24.w,
                      vertical: 16.h,
                    ),
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: 24.h),
                        // Logo Box
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: 72.w,
                            height: 72.w,
                            margin: EdgeInsets.only(bottom: 24.h),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16.r),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.1,
                                  ),
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
                        ),

                        // Title Text
                        Text(
                          _isModeratorLogin ? 'Moderator Login' : 'Pilgrim Login',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lexend(
                            fontSize: 28.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: 32.h),

                        // Form Container
                        Container(
                          padding: EdgeInsets.all(24.w),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceDark
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20.r),
                            boxShadow: [
                              BoxShadow(
                                color: isDark
                                    ? Colors.black.withValues(alpha: 0.2)
                                    : const Color(0xffe2e8f0).withValues(
                                        alpha: 0.5,
                                      ),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: _isModeratorLogin
                               ? _buildModeratorForm(isDark, isLoading)
                               : _buildPilgrimForm(isDark, isLoading),
                        ),

                        SizedBox(height: 32.h),

                        // Toggle Login Mode
                        if (!_isScanningQr)
                          Center(
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isModeratorLogin = !_isModeratorLogin;
                                  _loginError = null;
                                  _isScanningQr = false;
                                });
                              },
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 8.h),
                                child: Text.rich(
                                  TextSpan(
                                    text: _isModeratorLogin
                                        ? 'Not a moderator? '
                                        : 'Not a pilgrim? ',
                                    style: GoogleFonts.lexend(
                                      color: isDark ? AppColors.textMutedLight : const Color(0xff64748b),
                                      fontSize: 14.sp,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: _isModeratorLogin
                                            ? 'Log in as a pilgrim'
                                            : 'Log in as a moderator',
                                        style: GoogleFonts.lexend(
                                          color: isDark ? Colors.white : AppColors.textDark,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          
                         SizedBox(height: 32.h),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPilgrimForm(bool isDark, bool isLoading) {
    if (_isScanningQr) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 300.h,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16.r),
              child: MobileScanner(
                controller: _scannerController,
                onDetect: _onDetect,
              ),
            ),
          ),
          SizedBox(height: 16.h),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _isScanningQr = false;
                _scanHandled = false;
              });
            },
            icon: const Icon(Symbols.keyboard_return, color: AppColors.primary),
            label: Text(
              'Back to Code Entry',
              style: GoogleFonts.lexend(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel('Enter your login code', isDark),
        SizedBox(height: 6.h),
        Container(
          decoration: _fieldDecoration(isDark),
          child: TextField(
            controller: _codeController,
            style: GoogleFonts.lexend(
              fontSize: 14.sp,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
            decoration: InputDecoration(
              hintText: '',
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            ),
          ),
        ),
        _buildErrorUI(isDark),
        SizedBox(height: 24.h),
        ElevatedButton(
          onPressed: isLoading ? null : () => _handlePilgrimLoginCode(_codeController.text),
          style: _primaryButtonStyle(),
          child: isLoading
              ? _loadingIndicator()
              : Text('Continue', style: _buttonTextStyle()),
        ),
        SizedBox(height: 16.h),
        OutlinedButton.icon(
          onPressed: () {
             setState(() {
               _isScanningQr = true;
               _loginError = null;
               _scanHandled = false;
             });
          },
          icon: Icon(Symbols.qr_code_scanner, size: 20.w, color: AppColors.primary),
          label: Text('Scan QR Code', style: GoogleFonts.lexend(fontSize: 16.sp, fontWeight: FontWeight.w600, color: AppColors.primary)),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.primary, width: 1.5),
            padding: EdgeInsets.symmetric(vertical: 16.h),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        ),
      ],
    );
  }

  Widget _buildModeratorForm(bool isDark, bool isLoading) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFieldLabel('Email or Phone', isDark),
        SizedBox(height: 6.h),
        Container(
          decoration: _fieldDecoration(isDark),
          child: Row(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Icon(Symbols.person, size: 20.w, color: AppColors.textMutedLight),
              ),
              Expanded(
                child: TextField(
                  controller: _identifierController,
                  style: GoogleFonts.lexend(fontSize: 14.sp, color: isDark ? Colors.white : AppColors.textDark),
                  decoration: InputDecoration(
                    hintText: 'Email or Phone',
                    hintStyle: GoogleFonts.lexend(color: AppColors.textMutedLight),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 16.h),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 20.h),
        _buildFieldLabel('Password', isDark),
        SizedBox(height: 6.h),
        Container(
          decoration: _fieldDecoration(isDark),
          child: Row(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Icon(Symbols.lock, size: 20.w, color: AppColors.textMutedLight),
              ),
              Expanded(
                child: TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: GoogleFonts.lexend(fontSize: 14.sp, color: isDark ? Colors.white : AppColors.textDark),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    hintStyle: GoogleFonts.lexend(color: AppColors.textMutedLight),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 16.h),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _obscurePassword ? Symbols.visibility_off : Symbols.visibility,
                  size: 20.w,
                  color: AppColors.textMutedLight,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ],
          ),
        ),
        SizedBox(height: 8.h),
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onTap: () {},
            child: Text(
              'Forgot Password?',
              style: GoogleFonts.lexend(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xff3b82f6),
              ),
            ),
          ),
        ),
        _buildErrorUI(isDark),
        SizedBox(height: 24.h),
        ElevatedButton(
          onPressed: isLoading ? null : _handleModeratorLogin,
          style: _primaryButtonStyle(),
          child: isLoading
              ? _loadingIndicator()
              : Text('Log In', style: _buttonTextStyle()),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String text, bool isDark) {
    return Padding(
      padding: EdgeInsets.only(left: 4.w),
      child: Text(
        text,
        style: GoogleFonts.lexend(
          fontSize: 13.sp,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : AppColors.textDark,
        ),
      ),
    );
  }

  BoxDecoration _fieldDecoration(bool isDark) {
    return BoxDecoration(
      color: isDark ? Colors.black.withValues(alpha: 0.2) : const Color(0xfff8fafc),
      borderRadius: BorderRadius.circular(12.r),
      border: Border.all(
        color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
      ),
    );
  }

  Widget _buildErrorUI(bool isDark) {
    if (_loginError == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF3A1010) : Colors.red.shade50,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: isDark ? const Color(0xFF5C1515) : Colors.red.shade200,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 16.w, color: Colors.red.shade500),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                _loginError!,
                style: GoogleFonts.lexend(
                  fontSize: 12.sp,
                  color: Colors.red.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle _primaryButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      shadowColor: AppColors.primary.withValues(alpha: 0.3),
      padding: EdgeInsets.symmetric(vertical: 16.h),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
    );
  }

  TextStyle _buttonTextStyle() {
    return GoogleFonts.lexend(
      fontSize: 16.sp,
      fontWeight: FontWeight.w700,
    );
  }

  Widget _loadingIndicator() {
    return SizedBox(
      width: 22.w,
      height: 22.w,
      child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
    );
  }

  Widget _buildLanguageDropdown(bool isDark) {
    final Map<String, Locale> supportedLanguages = {
      'English': const Locale('en'),
      'العربية': const Locale('ar'),
      'اردو': const Locale('ur'),
      'Français': const Locale('fr'),
      'Bahasa': const Locale('id'),
      'Türkçe': const Locale('tr'),
    };

    final currentLocale = context.locale;
    String currentLangName = supportedLanguages.entries
        .firstWhere(
          (entry) => entry.value == currentLocale,
          orElse: () => const MapEntry('English', Locale('en')),
        )
        .key;

    return PopupMenuButton<String>(
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
        side: BorderSide(
          color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
        ),
      ),
      color: isDark ? AppColors.surfaceDark : Colors.white,
      onSelected: (langName) {
        final newLocale = supportedLanguages[langName];
        if (newLocale != null) {
          context.setLocale(newLocale);
        }
      },
      itemBuilder: (context) {
        return supportedLanguages.keys.map((langName) {
          final isSelected = langName == currentLangName;
          return PopupMenuItem<String>(
            value: langName,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  langName,
                  style: GoogleFonts.lexend(
                    fontSize: 14.sp,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? Colors.white : AppColors.textDark),
                  ),
                ),
                if (isSelected)
                  Icon(Symbols.check, size: 16.w, color: AppColors.primary),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(100.r),
          border: Border.all(
            color: isDark ? const Color(0xff1e293b) : const Color(0xfff1f5f9),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.language, size: 18.w, color: isDark ? AppColors.textMutedLight : const Color(0xff475569)),
            SizedBox(width: 8.w),
            Text(
              currentLangName,
              style: GoogleFonts.lexend(
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.textMutedLight : const Color(0xff475569),
              ),
            ),
            SizedBox(width: 8.w),
            Icon(Symbols.expand_more, size: 16.w, color: isDark ? AppColors.textMutedLight : const Color(0xff475569)),
          ],
        ),
      ),
    );
  }
}
