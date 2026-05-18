import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/legal_support_section.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/locale_prefs.dart';
import '../../../core/services/callkit_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../shared/widgets/pilgrim_gender_avatar.dart';
class PilgrimProfileScreen extends ConsumerStatefulWidget {
  const PilgrimProfileScreen({super.key});

  @override
  ConsumerState<PilgrimProfileScreen> createState() =>
      _PilgrimProfileScreenState();
}

class _PilgrimProfileScreenState extends ConsumerState<PilgrimProfileScreen> {
  late String _selectedLocale;

  static const _languages = [
    {'code': 'en', 'name': 'English', 'native': 'English', 'flag': '🇬🇧'},
    {'code': 'ar', 'name': 'Arabic', 'native': 'العربية', 'flag': '🇸🇦'},
    {'code': 'ur', 'name': 'Urdu', 'native': 'اردو', 'flag': '🇵🇰'},
    {'code': 'fr', 'name': 'French', 'native': 'Français', 'flag': '🇫🇷'},
    {
      'code': 'id',
      'name': 'Indonesian',
      'native': 'Bahasa Indonesia',
      'flag': '🇮🇩',
    },
    {'code': 'tr', 'name': 'Turkish', 'native': 'Türkçe', 'flag': '🇹🇷'},
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final ok = await ref.read(authProvider.notifier).fetchProfile();
      if (!mounted) return;
      if (!ok) context.go('/login');
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedLocale = context.locale.languageCode;
  }


  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final isDark = themeMode == ThemeMode.dark;

    final authState = ref.watch(authProvider);
    final fullName = authState.fullName ?? 'Pilgrim';

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
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'settings_title'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 24.sp,
                    color: textPrimary,
                  ),
                ),
              ),
            ),

            // ── Scrollable body ─────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 16.h),

                    // ── Profile card ─────────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        vertical: 20.h,
                        horizontal: 16.w,
                      ),
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
                      child: Row(
                        children: [
                          Container(
                            width: 56.w,
                            height: 56.w,
                            padding: EdgeInsets.all(2.5.w),
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
                            child: PilgrimGenderAvatar(
                              gender: authState.gender,
                              size: 51.w,
                            ),
                          ),
                          SizedBox(width: 16.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fullName,
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16.sp,
                                    color: textPrimary,
                                  ),
                                ),
                                SizedBox(height: 4.h),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 10.w,
                                    vertical: 3.h,
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
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 28.h),

                    // ── APPEARANCE section ───────────────────────────────
                    _SectionLabel(
                      label: 'settings_appearance'.tr(),
                      textMuted: textMuted,
                    ),
                    SizedBox(height: 8.h),
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
                        padding: EdgeInsets.symmetric(
                          horizontal: 16.w,
                          vertical: 14.h,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40.w,
                              height: 40.w,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.surfaceDark
                                    : AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Icon(
                                Icons.dark_mode_rounded,
                                color: AppColors.primary,
                                size: 20.sp,
                              ),
                            ),
                            SizedBox(width: 14.w),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'settings_dark_mode'.tr(),
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15.sp,
                                      color: textPrimary,
                                    ),
                                  ),
                                  SizedBox(height: 2.h),
                                  Text(
                                    'settings_dark_mode_sub'.tr(),
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 12.sp,
                                      color: textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: isDark,
                              activeThumbColor: AppColors.primary,
                              activeTrackColor: AppColors.primary.withValues(
                                alpha: 0.3,
                              ),
                              inactiveThumbColor: isDark
                                  ? AppColors.textLight
                                  : Colors.grey,
                              inactiveTrackColor: isDark
                                  ? AppColors.surfaceDark
                                  : Colors.grey.shade300,
                              onChanged: (_) => themeNotifier.toggle(),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: 28.h),

                    // ── LANGUAGE section ─────────────────────────────────
                    _SectionLabel(
                      label: 'settings_language'.tr(),
                      textMuted: textMuted,
                    ),
                    SizedBox(height: 8.h),
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
                        children: List.generate(_languages.length, (i) {
                          final lang = _languages[i];
                          final isSelected = _selectedLocale == lang['code'];
                          final isLast = i == _languages.length - 1;
                          return _LanguageRow(
                            lang: lang,
                            isSelected: isSelected,
                            isLast: isLast,
                            isDark: isDark,
                            dividerColor: dividerColor,
                            textPrimary: textPrimary,
                            textMuted: textMuted,
                            onTap: () async {
                              final code = lang['code']!;
                              setState(() => _selectedLocale = code);
                              context.setLocale(Locale(code));
                              unawaited(LocalePrefs.saveLanguageCode(code));
                              unawaited(
                                CallKitService.refreshCachedSupportDisplayName(
                                  languageCode: code,
                                ),
                              );
                              try {
                                await ApiService.dio.put(
                                  '/auth/update-language',
                                  data: {'language': code},
                                );
                              } catch (_) {
                                // Non-fatal — local language is already applied
                              }
                            },
                          );
                        }),
                      ),
                    ),

                    SizedBox(height: 28.h),

                    LegalSupportSection(
                      isDark: isDark,
                      cardBg: cardBg,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                      dividerColor: dividerColor,
                      showPilgrimDeletion: true,
                    ),

                    SizedBox(height: 28.h),

                    // ── Travel & Accommodation (Retractable) ────────────────
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.3 : 0.06,
                              ),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ExpansionTile(
                          shape: const RoundedRectangleBorder(side: BorderSide.none),
                          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                          tilePadding: EdgeInsets.symmetric(horizontal: 16.w),
                          title: Text(
                            'profile_travel_accommodation'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w600,
                              fontSize: 14.sp,
                              color: textPrimary,
                            ),
                          ),
                          leading: Icon(Icons.travel_explore_rounded, color: AppColors.primary, size: 22.sp),
                          children: [
                            _InfoTile(
                              icon: Icons.hotel_rounded,
                              label: 'group_hotel_name'.tr(),
                              value: authState.hotelName ?? 'profile_not_assigned'.tr(),
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                            _divider(dividerColor),
                            _InfoTile(
                              icon: Icons.meeting_room_rounded,
                              label: 'group_room_number'.tr(),
                              value: authState.roomNumber ?? 'profile_not_assigned'.tr(),
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                            _divider(dividerColor),
                            _InfoTile(
                              icon: Icons.directions_bus_rounded,
                              label: 'group_bus_number'.tr(),
                              value: authState.busInfo ?? 'profile_not_assigned'.tr(),
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                            _divider(dividerColor),
                            _InfoTile(
                              icon: Icons.assignment_ind_rounded,
                              label: 'profile_national_id'.tr(), // Visa status section
                              value: authState.visaStatus != null
                                  ? authState.visaStatus!.toUpperCase()
                                  : 'status_unknown'.tr(),
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                              valueColor: _getVisaColor(authState.visaStatus),
                            ),
                            SizedBox(height: 12.h),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: 16.h),

                    // ── Personal Details (Retractable) ──────────────────────
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: Container(
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16.r),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.3 : 0.06,
                              ),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ExpansionTile(
                          shape: const RoundedRectangleBorder(side: BorderSide.none),
                          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
                          tilePadding: EdgeInsets.symmetric(horizontal: 16.w),
                          title: Text(
                            'profile_personal_details'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w600,
                              fontSize: 14.sp,
                              color: textPrimary,
                            ),
                          ),
                          leading: Icon(Icons.person_outline_rounded, color: AppColors.primary, size: 22.sp),
                          children: [
                            _InfoTile(
                              icon: Icons.badge_rounded,
                              label: 'profile_national_id'.tr(),
                              value: authState.nationalId ?? 'profile_not_provided'.tr(),
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                            _divider(dividerColor),
                            _InfoTile(
                              icon: Icons.cake_rounded,
                              label: 'reg_age'.tr(),
                              value: authState.age != null ? '${authState.age} ${'reg_age_hint'.tr()}' : 'profile_not_provided'.tr(),
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                            _divider(dividerColor),
                            _InfoTile(
                              icon: Icons.wc_rounded,
                              label: 'reg_gender'.tr(),
                              value: authState.gender != null ? 'reg_${authState.gender}'.tr() : 'profile_not_provided'.tr(),
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                            _divider(dividerColor),
                            _InfoTile(
                              icon: Icons.medical_services_rounded,
                              label: 'reg_medical'.tr(),
                              value: authState.medicalHistory?.isNotEmpty == true ? authState.medicalHistory! : 'profile_none'.tr(),
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                            _divider(dividerColor),
                            _InfoTile(
                              icon: Icons.public_rounded,
                              label: 'ethnic_other'.tr(), // Ethnicity
                              value: authState.ethnicity ?? 'profile_not_provided'.tr(),
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                            SizedBox(height: 12.h),
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
    );
  }

  Color _getVisaColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'issued':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
      case 'expired':
        return Colors.red;
      default:
        return AppColors.primary;
    }
  }

  Widget _divider(Color color) => Divider(
        height: 1,
        thickness: 1,
        color: color,
        indent: 16.w,
        endIndent: 16.w,
      );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final Color textPrimary;
  final Color textMuted;
  final Color? valueColor;

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.sp,
                    color: textMuted,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 14.sp,
                    color: valueColor ?? textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.lang,
    required this.isSelected,
    required this.isLast,
    required this.isDark,
    required this.dividerColor,
    required this.textPrimary,
    required this.textMuted,
    required this.onTap,
  });

  final Map<String, String> lang;
  final bool isSelected;
  final bool isLast;
  final bool isDark;
  final Color dividerColor;
  final Color textPrimary;
  final Color textMuted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.vertical(
            top: isLast == false && lang['code'] == 'en'
                ? const Radius.circular(16)
                : Radius.zero,
            bottom: isLast ? const Radius.circular(16) : Radius.zero,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark
                        ? AppColors.surfaceDark
                        : AppColors.backgroundLight,
                  ),
                  child: Center(
                    child: Text(
                      lang['flag']!,
                      style: TextStyle(fontSize: 20.sp),
                    ),
                  ),
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lang['name']!,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 14.sp,
                          color: textPrimary,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        lang['native']!,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.sp,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.primary,
                    size: 22.sp,
                  )
                else
                  SizedBox(width: 22.sp),
              ],
            ),
          ),
        ),
        if (!isLast)
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
