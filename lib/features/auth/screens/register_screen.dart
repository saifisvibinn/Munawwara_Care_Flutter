import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';

// ── Country code model ────────────────────────────────────────────────────────

class _CountryCode {
  final String flag;
  final String name;
  final String dial;
  const _CountryCode(this.flag, this.name, this.dial);
}

const _countryCodes = [
  _CountryCode('🇸🇦', 'Saudi Arabia', '+966'),
  _CountryCode('🇦🇪', 'UAE', '+971'),
  _CountryCode('🇪🇬', 'Egypt', '+20'),
  _CountryCode('🇵🇰', 'Pakistan', '+92'),
  _CountryCode('🇮🇳', 'India', '+91'),
  _CountryCode('🇧🇩', 'Bangladesh', '+880'),
  _CountryCode('🇮🇩', 'Indonesia', '+62'),
  _CountryCode('🇹🇷', 'Turkey', '+90'),
  _CountryCode('🇩🇿', 'Algeria', '+213'),
  _CountryCode('🇲🇦', 'Morocco', '+212'),
  _CountryCode('🇬🇧', 'United Kingdom', '+44'),
  _CountryCode('🇫🇷', 'France', '+33'),
  _CountryCode('🇩🇪', 'Germany', '+49'),
  _CountryCode('🇺🇸', 'United States', '+1'),
  _CountryCode('🇨🇦', 'Canada', '+1'),
  _CountryCode('🇲🇾', 'Malaysia', '+60'),
  _CountryCode('🇸🇳', 'Senegal', '+221'),
  _CountryCode('🇳🇬', 'Nigeria', '+234'),
  _CountryCode('🇮🇷', 'Iran', '+98'),
  _CountryCode('🇯🇴', 'Jordan', '+962'),
  _CountryCode('🇰🇼', 'Kuwait', '+965'),
  _CountryCode('🇶🇦', 'Qatar', '+974'),
  _CountryCode('🇧🇭', 'Bahrain', '+973'),
  _CountryCode('🇴🇲', 'Oman', '+968'),
  _CountryCode('🇾🇪', 'Yemen', '+967'),
  _CountryCode('🇱🇧', 'Lebanon', '+961'),
  _CountryCode('🇸🇾', 'Syria', '+963'),
  _CountryCode('🇮🇶', 'Iraq', '+964'),
  _CountryCode('🇹🇳', 'Tunisia', '+216'),
  _CountryCode('🇱🇾', 'Libya', '+218'),
  _CountryCode('🇸🇩', 'Sudan', '+249'),
  _CountryCode('🇸🇴', 'Somalia', '+252'),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _nameCtrl = TextEditingController();
  final _passportCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _medicalCtrl = TextEditingController();

  // State
  bool _obscurePassword = true;
  _CountryCode _selectedCode = _countryCodes.first; // +966 default
  String? _gender; // null | 'male' | 'female'

  // Field-level errors from backend
  String? _nameError;
  String? _passportError;
  String? _phoneError;
  String? _passwordError;
  String? _generalError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passportCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _ageCtrl.dispose();
    _medicalCtrl.dispose();
    super.dispose();
  }

  // ── Validate locally before sending ──────────────────────────────────────────
  bool _validate() {
    bool ok = true;
    setState(() {
      _nameError = null;
      _passportError = null;
      _phoneError = null;
      _passwordError = null;
      _generalError = null;

      if (_nameCtrl.text.trim().isEmpty) {
        _nameError = 'reg_error_name'.tr();
        ok = false;
      }
      if (_passportCtrl.text.trim().isEmpty) {
        _passportError = 'reg_error_passport'.tr();
        ok = false;
      }
      if (_phoneCtrl.text.trim().isEmpty) {
        _phoneError = 'reg_error_phone'.tr();
        ok = false;
      }
      if (_passwordCtrl.text.length < 6) {
        _passwordError = 'reg_error_password'.tr();
        ok = false;
      }
    });
    return ok;
  }

  // ── Map backend errors to fields ──────────────────────────────────────────────
  void _handleBackendError(String error) {
    final lower = error.toLowerCase();
    setState(() {
      _generalError = null;
      if (lower.contains('national_id') ||
          lower.contains('national id') ||
          lower.contains('passport') ||
          lower.contains('id already')) {
        _passportError = error;
      } else if (lower.contains('phone')) {
        _phoneError = error;
      } else if (lower.contains('name')) {
        _nameError = error;
      } else if (lower.contains('password')) {
        _passwordError = error;
      } else {
        _generalError = error;
      }
    });
  }

  Future<void> _submit() async {
    if (!_validate()) return;

    final fullPhone = '${_selectedCode.dial}${_phoneCtrl.text.trim()}';
    final ageText = _ageCtrl.text.trim();
    final int? age = ageText.isNotEmpty ? int.tryParse(ageText) : null;

    final success = await ref
        .read(authProvider.notifier)
        .registerPilgrim(
          fullName: _nameCtrl.text.trim(),
          nationalId: _passportCtrl.text.trim(),
          phoneNumber: fullPhone,
          password: _passwordCtrl.text,
          medicalHistory: _medicalCtrl.text.trim().isEmpty
              ? null
              : _medicalCtrl.text.trim(),
          age: age,
          gender: _gender,
        );

    if (!mounted) return;

    if (success) {
      _showSuccessAndPop();
    } else {
      final error = ref.read(authProvider).error ?? 'reg_error_generic'.tr();
      _handleBackendError(error);
    }
  }

  void _showSuccessAndPop() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
        ),
        content: Row(
          children: [
            Icon(Symbols.check_circle, color: Colors.white, size: 20.w),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                'reg_success'.tr(),
                style: GoogleFonts.lexend(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // New accounts are always pilgrims on first registration
    context.go('/pilgrim-dashboard');
  }

  // ── Country code picker ───────────────────────────────────────────────────────
  void _showCountryPicker(bool isDark) {
    final searchCtrl = TextEditingController();
    List<_CountryCode> filtered = List.from(_countryCodes);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.6,
              maxChildSize: 0.85,
              minChildSize: 0.4,
              expand: false,
              builder: (_, scrollCtrl) {
                return Padding(
                  padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
                  child: Column(
                    children: [
                      // Handle bar
                      Container(
                        width: 40.w,
                        height: 4.h,
                        margin: EdgeInsets.only(bottom: 16.h),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xff334155)
                              : const Color(0xffe2e8f0),
                          borderRadius: BorderRadius.circular(2.r),
                        ),
                      ),
                      // Search
                      Container(
                        margin: EdgeInsets.only(bottom: 12.h),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.2)
                              : const Color(0xfff8fafc),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xff334155)
                                : const Color(0xffe2e8f0),
                          ),
                        ),
                        child: TextField(
                          controller: searchCtrl,
                          style: GoogleFonts.lexend(
                            color: isDark ? Colors.white : AppColors.textDark,
                            fontSize: 14.sp,
                          ),
                          decoration: InputDecoration(
                            hintText: 'reg_search_country'.tr(),
                            hintStyle: GoogleFonts.lexend(
                              color: AppColors.textMutedLight,
                              fontSize: 14.sp,
                            ),
                            prefixIcon: Icon(
                              Symbols.search,
                              size: 20.w,
                              color: AppColors.textMutedLight,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              vertical: 14.h,
                            ),
                          ),
                          onChanged: (q) {
                            setSheetState(() {
                              filtered = _countryCodes
                                  .where(
                                    (c) =>
                                        c.name.toLowerCase().contains(
                                          q.toLowerCase(),
                                        ) ||
                                        c.dial.contains(q),
                                  )
                                  .toList();
                            });
                          },
                        ),
                      ),
                      // List
                      Expanded(
                        child: ListView.builder(
                          controller: scrollCtrl,
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final cc = filtered[i];
                            final isSelected =
                                cc.dial == _selectedCode.dial &&
                                cc.name == _selectedCode.name;
                            return ListTile(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8.w,
                                vertical: 2.h,
                              ),
                              leading: Text(
                                cc.flag,
                                style: TextStyle(fontSize: 24.sp),
                              ),
                              title: Text(
                                cc.name,
                                style: GoogleFonts.lexend(
                                  fontSize: 14.sp,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textDark,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                              trailing: Text(
                                cc.dial,
                                style: GoogleFonts.lexend(
                                  fontSize: 13.sp,
                                  color: isSelected
                                      ? AppColors.primary
                                      : AppColors.textMutedLight,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                              onTap: () {
                                setState(() => _selectedCode = cc);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

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
          // Background glow – top right
          Positioned(
            top: -80.h,
            right: -80.w,
            width: 300.w,
            height: 300.w,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: isDark ? 0.06 : 0.12),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          // Background glow – bottom left
          Positioned(
            bottom: -60.h,
            left: -60.w,
            width: 250.w,
            height: 250.w,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentGold.withValues(alpha: 
                      isDark ? 0.04 : 0.08,
                    ),
                    blurRadius: 80,
                    spreadRadius: 15,
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // ── App bar ─────────────────────────────────────────────────
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Symbols.arrow_back_ios_new,
                          size: 20.w,
                          color: isDark
                              ? AppColors.textMutedLight
                              : AppColors.textMutedDark,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          'register_title'.tr(),
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lexend(
                            fontSize: 17.sp,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                      ),
                      // Spacer to balance the back button
                      SizedBox(width: 48.w),
                    ],
                  ),
                ),

                // ── Scrollable body ─────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 120.h),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Header ────────────────────────────────────────
                          Text(
                            'reg_welcome'.tr(),
                            style: GoogleFonts.lexend(
                              fontSize: 26.sp,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: isDark ? Colors.white : AppColors.textDark,
                            ),
                          ),
                          SizedBox(height: 6.h),
                          Text(
                            'reg_subtitle'.tr(),
                            style: GoogleFonts.lexend(
                              fontSize: 13.sp,
                              height: 1.5,
                              color: isDark
                                  ? AppColors.textMutedLight
                                  : AppColors.textMutedDark,
                            ),
                          ),
                          SizedBox(height: 28.h),

                          // ── General error banner ───────────────────────────
                          if (_generalError != null) ...[
                            _ErrorBanner(
                              message: _generalError!,
                              isDark: isDark,
                            ),
                            SizedBox(height: 16.h),
                          ],

                          // ── Required fields card ───────────────────────────
                          _SectionCard(
                            isDark: isDark,
                            children: [
                              // Full Name
                              _buildField(
                                label: 'reg_full_name'.tr(),
                                hint: 'reg_full_name_hint'.tr(),
                                controller: _nameCtrl,
                                icon: Symbols.person,
                                error: _nameError,
                                isDark: isDark,
                                onChanged: (_) =>
                                    setState(() => _nameError = null),
                              ),
                              SizedBox(height: 20.h),

                              // Passport number
                              _buildField(
                                label: 'reg_passport'.tr(),
                                hint: 'reg_passport_hint'.tr(),
                                controller: _passportCtrl,
                                icon: Symbols.badge,
                                error: _passportError,
                                isDark: isDark,
                                onChanged: (_) =>
                                    setState(() => _passportError = null),
                              ),
                              SizedBox(height: 20.h),

                              // Phone
                              _buildPhoneField(isDark),
                              SizedBox(height: 20.h),

                              // Password
                              _buildPasswordField(isDark),
                            ],
                          ),

                          SizedBox(height: 24.h),

                          // ── Optional section ───────────────────────────────
                          Row(
                            children: [
                              Text(
                                'reg_profile_health'.tr(),
                                style: GoogleFonts.lexend(
                                  fontSize: 17.sp,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? Colors.white
                                      : AppColors.textDark,
                                ),
                              ),
                              SizedBox(width: 8.w),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8.w,
                                  vertical: 3.h,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.surfaceDark
                                      : AppColors.surfaceLight,
                                  borderRadius: BorderRadius.circular(20.r),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xff334155)
                                        : const Color(0xffe2e8f0),
                                  ),
                                ),
                                child: Text(
                                  'reg_optional'.tr().toUpperCase(),
                                  style: GoogleFonts.lexend(
                                    fontSize: 10.sp,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.8,
                                    color: isDark
                                        ? AppColors.textMutedLight
                                        : AppColors.textMutedDark,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 6.h),
                          Text(
                            'reg_optional_desc'.tr(),
                            style: GoogleFonts.lexend(
                              fontSize: 12.sp,
                              height: 1.4,
                              color: isDark
                                  ? AppColors.textMutedLight
                                  : AppColors.textMutedDark,
                            ),
                          ),
                          SizedBox(height: 16.h),

                          _SectionCard(
                            isDark: isDark,
                            children: [
                              // Age + Gender row
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Age
                                  SizedBox(
                                    width: 90.w,
                                    child: _buildField(
                                      label: 'reg_age'.tr(),
                                      hint: 'reg_age_hint'.tr(),
                                      controller: _ageCtrl,
                                      isDark: isDark,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                      ],
                                      maxLength: 3,
                                    ),
                                  ),
                                  SizedBox(width: 16.w),
                                  // Gender
                                  Expanded(child: _buildGenderToggle(isDark)),
                                ],
                              ),
                              SizedBox(height: 20.h),

                              // Medical history
                              _buildTextArea(
                                label: 'reg_medical'.tr(),
                                hint: 'reg_medical_hint'.tr(),
                                controller: _medicalCtrl,
                                isDark: isDark,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Floating bottom CTA ─────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                24.w,
                16.h,
                24.w,
                MediaQuery.of(context).padding.bottom + 16.h,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    (isDark
                            ? AppColors.backgroundDark
                            : AppColors.backgroundLight)
                        .withValues(alpha: 0),
                    isDark
                        ? AppColors.backgroundDark
                        : AppColors.backgroundLight,
                  ],
                  stops: const [0.0, 0.35],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.primary.withValues(alpha: 
                          0.6,
                        ),
                        elevation: 0,
                        shadowColor: AppColors.primary.withValues(alpha: 0.4),
                        padding: EdgeInsets.symmetric(vertical: 16.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                      ),
                      child: isLoading
                          ? SizedBox(
                              width: 22.w,
                              height: 22.w,
                              child: const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'reg_create_account'.tr(),
                                  style: GoogleFonts.lexend(
                                    fontSize: 16.sp,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(width: 8.w),
                                Icon(Symbols.arrow_forward, size: 20.w),
                              ],
                            ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: GoogleFonts.lexend(
                        fontSize: 13.sp,
                        color: isDark
                            ? AppColors.textMutedLight
                            : const Color(0xff475569),
                      ),
                      children: [
                        TextSpan(text: '${'reg_already_account'.tr()} '),
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Text(
                              'btn_login'.tr(),
                              style: GoogleFonts.lexend(
                                fontSize: 13.sp,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
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
          ),
        ],
      ),
    );
  }

  // ── Widget builders ────────────────────────────────────────────────────────────

  Widget _buildField({
    required String label,
    required String hint,
    TextEditingController? controller,
    IconData? icon,
    String? error,
    required bool isDark,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label, isDark: isDark),
        SizedBox(height: 6.h),
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0xfff8fafc),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: error != null
                  ? Colors.red.shade300
                  : (isDark
                        ? const Color(0xff334155)
                        : const Color(0xffe2e8f0)),
            ),
          ),
          child: Row(
            children: [
              if (icon != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  child: Icon(
                    icon,
                    size: 20.w,
                    color: error != null
                        ? Colors.red.shade300
                        : AppColors.textMutedLight,
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  inputFormatters: inputFormatters,
                  maxLength: maxLength,
                  onChanged: onChanged,
                  style: GoogleFonts.lexend(
                    fontSize: 14.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: GoogleFonts.lexend(
                      color: AppColors.textMutedLight,
                      fontSize: 14.sp,
                    ),
                    border: InputBorder.none,
                    counterText: '',
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 15.h,
                      horizontal: icon == null ? 14.w : 0,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null) ...[
          SizedBox(height: 4.h),
          _FieldError(message: error),
        ],
      ],
    );
  }

  Widget _buildPhoneField(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: 'reg_phone'.tr(), isDark: isDark),
        SizedBox(height: 6.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Country code button
            GestureDetector(
              onTap: () => _showCountryPicker(isDark),
              child: Container(
                height: 51.h,
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : const Color(0xfff8fafc),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: _phoneError != null
                        ? Colors.red.shade300
                        : (isDark
                              ? const Color(0xff334155)
                              : const Color(0xffe2e8f0)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_selectedCode.flag, style: TextStyle(fontSize: 20.sp)),
                    SizedBox(width: 4.w),
                    Text(
                      _selectedCode.dial,
                      style: GoogleFonts.lexend(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    SizedBox(width: 2.w),
                    Icon(
                      Symbols.expand_more,
                      size: 16.w,
                      color: AppColors.textMutedLight,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 8.w),
            // Phone number input
            Expanded(
              child: Container(
                height: 51.h,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : const Color(0xfff8fafc),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: _phoneError != null
                        ? Colors.red.shade300
                        : (isDark
                              ? const Color(0xff334155)
                              : const Color(0xffe2e8f0)),
                  ),
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => setState(() => _phoneError = null),
                  style: GoogleFonts.lexend(
                    fontSize: 14.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'reg_phone_hint'.tr(),
                    hintStyle: GoogleFonts.lexend(
                      color: AppColors.textMutedLight,
                      fontSize: 14.sp,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14.w),
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_phoneError != null) ...[
          SizedBox(height: 4.h),
          _FieldError(message: _phoneError!),
        ],
      ],
    );
  }

  Widget _buildPasswordField(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: 'reg_password'.tr(), isDark: isDark),
        SizedBox(height: 6.h),
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0xfff8fafc),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: _passwordError != null
                  ? Colors.red.shade300
                  : (isDark
                        ? const Color(0xff334155)
                        : const Color(0xffe2e8f0)),
            ),
          ),
          child: Row(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                child: Icon(
                  Symbols.lock,
                  size: 20.w,
                  color: _passwordError != null
                      ? Colors.red.shade300
                      : AppColors.textMutedLight,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  onChanged: (_) => setState(() => _passwordError = null),
                  style: GoogleFonts.lexend(
                    fontSize: 14.sp,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                  decoration: InputDecoration(
                    hintText: 'reg_password_hint'.tr(),
                    hintStyle: GoogleFonts.lexend(
                      color: AppColors.textMutedLight,
                      fontSize: 14.sp,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 15.h),
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
        if (_passwordError != null) ...[
          SizedBox(height: 4.h),
          _FieldError(message: _passwordError!),
        ],
      ],
    );
  }

  Widget _buildGenderToggle(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: 'reg_gender'.tr(), isDark: isDark),
        SizedBox(height: 6.h),
        Container(
          padding: EdgeInsets.all(3.w),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0xfff8fafc),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
            ),
          ),
          child: Row(
            children: [
              _GenderOption(
                label: 'reg_male'.tr(),
                isSelected: _gender == 'male',
                isDark: isDark,
                onTap: () =>
                    setState(() => _gender = _gender == 'male' ? null : 'male'),
              ),
              _GenderOption(
                label: 'reg_female'.tr(),
                isSelected: _gender == 'female',
                isDark: isDark,
                onTap: () => setState(
                  () => _gender = _gender == 'female' ? null : 'female',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextArea({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label: label, isDark: isDark),
        SizedBox(height: 6.h),
        Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0xfff8fafc),
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(
              color: isDark ? const Color(0xff334155) : const Color(0xffe2e8f0),
            ),
          ),
          child: TextField(
            controller: controller,
            maxLines: 3,
            minLines: 3,
            style: GoogleFonts.lexend(
              fontSize: 14.sp,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.lexend(
                color: AppColors.textMutedLight,
                fontSize: 13.sp,
              ),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14.w,
                vertical: 12.h,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _SectionCard({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.2)
                : const Color(0xffe2e8f0).withValues(alpha: 0.6),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool isDark;
  const _FieldLabel({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 2.w),
      child: Text(
        label,
        style: GoogleFonts.lexend(
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.textMutedLight : const Color(0xff334155),
        ),
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  final String message;
  const _FieldError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 4.w),
      child: Row(
        children: [
          Icon(Symbols.error, size: 13.w, color: Colors.red.shade400),
          SizedBox(width: 4.w),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.lexend(
                fontSize: 11.sp,
                color: Colors.red.shade400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final bool isDark;
  const _ErrorBanner({required this.message, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Symbols.error, size: 18.w, color: Colors.red.shade500),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.lexend(
                fontSize: 13.sp,
                color: Colors.red.shade700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GenderOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;
  const _GenderOption({
    required this.label,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(vertical: 10.h),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? AppColors.backgroundDark : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9.r),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
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
              fontSize: 13.sp,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected
                  ? AppColors.primary
                  : (isDark
                        ? AppColors.textMutedLight
                        : AppColors.textMutedDark),
            ),
          ),
        ),
      ),
    );
  }
}
