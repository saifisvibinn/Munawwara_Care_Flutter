import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/gestures.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  int _selectedTab = 2; // 0 = Email, 1 = Phone, 2 = National ID
  bool _obscurePassword = true;
  String? _loginError;

  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                color: AppColors.primary.withOpacity(isDark ? 0.05 : 0.1),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(isDark ? 0.05 : 0.1),
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
                color: AppColors.accentGold.withOpacity(isDark ? 0.05 : 0.1),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentGold.withOpacity(
                      isDark ? 0.05 : 0.1,
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
                // Header
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
                        // Mosque Icon Box
                        Align(
                          alignment: Alignment.center,
                          child: Transform.rotate(
                            angle: 0.0, // Straight
                            child: Container(
                              width: 64.w,
                              height: 64.w,
                              margin: EdgeInsets.only(bottom: 16.h),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.primary.withOpacity(0.2),
                                    AppColors.primary.withOpacity(0.1),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16.r),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.1),
                                    blurRadius: 20,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16.r),
                                child: Image.asset(
                                  'assets/static/logo.jpeg',
                                  width: 64.w,
                                  height: 64.w,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Title Text
                        Text(
                          'welcome_back'.tr(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lexend(
                            fontSize: 30.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          'login_subtitle'.tr(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lexend(
                            fontSize: 14.sp,
                            height: 1.5,
                            color: isDark
                                ? AppColors.textMutedLight
                                : AppColors.textMutedDark,
                          ),
                        ),
                        SizedBox(height: 32.h),

                        // Form Container
                        Container(
                          padding: EdgeInsets.all(4.w),
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.surfaceDark
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20.r),
                            boxShadow: [
                              BoxShadow(
                                color: isDark
                                    ? Colors.black.withOpacity(0.2)
                                    : const Color(0xffe2e8f0).withOpacity(0.5),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Segmented Tab
                              Container(
                                margin: EdgeInsets.only(bottom: 24.h),
                                padding: EdgeInsets.all(4.w),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.black.withOpacity(0.2)
                                      : const Color(0xfff8fafc),
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Row(
                                  children: [
                                    _buildTab(0, 'tab_email'.tr(), isDark),
                                    _buildTab(1, 'tab_phone'.tr(), isDark),
                                    _buildTab(
                                      2,
                                      'tab_national_id'.tr(),
                                      isDark,
                                    ),
                                  ],
                                ),
                              ),

                              // Inputs
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 20.w),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildInputField(
                                      label: _getInputLabel(),
                                      hint: _getInputHint(),
                                      icon: _getInputIcon(),
                                      isDark: isDark,
                                      controller: _identifierController,
                                    ),
                                    SizedBox(height: 20.h),
                                    _buildPasswordField(
                                      isDark,
                                      controller: _passwordController,
                                    ),
                                    if (_loginError != null) ...[
                                      SizedBox(height: 12.h),
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? const Color(0xFF3A1010)
                                              : Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(
                                            10.r,
                                          ),
                                          border: Border.all(
                                            color: isDark
                                                ? const Color(0xFF5C1515)
                                                : Colors.red.shade200,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.error_outline,
                                              size: 16.w,
                                              color: Colors.red.shade500,
                                            ),
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
                                    ],
                                    SizedBox(height: 32.h),

                                    // Login Button
                                    ElevatedButton(
                                      onPressed:
                                          ref.watch(authProvider).isLoading
                                          ? null
                                          : _handleLogin,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shadowColor: AppColors.primary
                                            .withOpacity(0.3),
                                        padding: EdgeInsets.symmetric(
                                          vertical: 16.h,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12.r,
                                          ),
                                        ),
                                      ),
                                      child: ref.watch(authProvider).isLoading
                                          ? SizedBox(
                                              width: 22.w,
                                              height: 22.w,
                                              child:
                                                  const CircularProgressIndicator(
                                                    color: Colors.white,
                                                    strokeWidth: 2.5,
                                                  ),
                                            )
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  'btn_login'.tr(),
                                                  style: GoogleFonts.lexend(
                                                    fontSize: 16.sp,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                SizedBox(width: 8.w),
                                                Icon(Symbols.login, size: 20.w),
                                              ],
                                            ),
                                    ),

                                    SizedBox(height: 24.h),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 32.h),

                        // Register Link
                        Center(
                          child: RichText(
                            text: TextSpan(
                              style: GoogleFonts.lexend(
                                fontSize: 14.sp,
                                color: isDark
                                    ? AppColors.textMutedLight
                                    : const Color(0xff475569),
                              ),
                              children: [
                                TextSpan(text: '${'no_account'.tr()} '),
                                TextSpan(
                                  text: 'register_now'.tr(),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () => context.push('/register'),
                                  style: GoogleFonts.lexend(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    decoration: TextDecoration.underline,
                                    decorationColor: AppColors.accentGold,
                                    decorationThickness: 2,
                                  ),
                                ),
                              ],
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
    // Find the string name for the current locale (fallback to English if not found)
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
            Icon(
              Symbols.language,
              size: 18.w,
              color: isDark
                  ? AppColors.textMutedLight
                  : const Color(0xff475569),
            ),
            SizedBox(width: 8.w),
            Text(
              currentLangName,
              style: GoogleFonts.lexend(
                fontSize: 12.sp,
                fontWeight: FontWeight.w500,
                color: isDark
                    ? AppColors.textMutedLight
                    : const Color(0xff475569),
              ),
            ),
            SizedBox(width: 8.w),
            Icon(
              Symbols.expand_more,
              size: 16.w,
              color: isDark
                  ? AppColors.textMutedLight
                  : const Color(0xff475569),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(int index, String label, bool isDark) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 10.h),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? AppColors.surfaceDark : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8.r),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.lexend(
              fontSize: 12.sp,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected
                  ? (isDark ? Colors.white : AppColors.textDark)
                  : (isDark
                        ? AppColors.textMutedLight
                        : AppColors.textMutedDark),
            ),
          ),
        ),
      ),
    );
  }

  String _getInputLabel() {
    switch (_selectedTab) {
      case 1:
        return 'label_phone'.tr();
      case 2:
        return 'label_national_id'.tr();
      default:
        return 'label_email'.tr();
    }
  }

  String _getInputHint() {
    switch (_selectedTab) {
      case 1:
        return 'hint_phone'.tr();
      case 2:
        return 'hint_national_id'.tr();
      default:
        return 'hint_email'.tr();
    }
  }

  IconData _getInputIcon() {
    switch (_selectedTab) {
      case 1:
        return Symbols.phone;
      case 2:
        return Symbols.book;
      default:
        return Symbols.mail;
    }
  }

  Widget _buildInputField({
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    TextEditingController? controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4.w, bottom: 6.h),
          child: Text(
            label,
            style: GoogleFonts.lexend(
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.textMutedLight
                  : const Color(0xff334155),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : const Color(0xfff8fafc),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Icon(icon, size: 20.w, color: AppColors.textMutedLight),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  style: GoogleFonts.lexend(
                    fontSize: 14.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: GoogleFonts.lexend(
                      color: AppColors.textMutedLight,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 16.h),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordField(bool isDark, {TextEditingController? controller}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4.w, bottom: 6.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'label_password'.tr(),
                style: GoogleFonts.lexend(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                  color: isDark
                      ? AppColors.textMutedLight
                      : const Color(0xff334155),
                ),
              ),
              Text(
                'forgot_password'.tr(),
                style: GoogleFonts.lexend(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentGold,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : const Color(0xfff8fafc),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: Icon(
                  Symbols.lock,
                  size: 20.w,
                  color: AppColors.textMutedLight,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: _obscurePassword,
                  style: GoogleFonts.lexend(
                    fontSize: 14.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                  decoration: InputDecoration(
                    hintText: '••••••••',
                    hintStyle: GoogleFonts.lexend(
                      color: AppColors.textMutedLight,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 16.h),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Symbols.visibility_off
                      : Symbols.visibility,
                  size: 20.w,
                  color: AppColors.textMutedLight,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
