import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/custom_dialog.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/config/app_locales.dart';
import '../../../core/widgets/app_settings_expansion.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/callkit_service.dart';
import '../../../core/services/locale_prefs.dart';
import '../../../core/services/sos_alert_audio.dart';
import '../../../core/utils/phone_number_utils.dart';
import '../../../core/widgets/phone_number_text.dart';
import '../../auth/providers/auth_provider.dart';
import '../../auth/models/wakel_info.dart';
import '../../shared/widgets/moderator_avatar.dart';
import 'moderator_profile_edit_screen.dart';

class ModeratorProfileScreen extends ConsumerStatefulWidget {
  const ModeratorProfileScreen({super.key});

  @override
  ConsumerState<ModeratorProfileScreen> createState() =>
      _ModeratorProfileScreenState();
}

class _ModeratorProfileScreenState
    extends ConsumerState<ModeratorProfileScreen> {
  late String _selectedLocale;

  static List<Map<String, String>> get _languages =>
      AppLocales.profileLanguages
          .map(
            (AppLanguageOption lang) => {
              'code': lang.code,
              'name': lang.menuLabel,
              'native': lang.nativeName,
              'flag': lang.flag,
            },
          )
          .toList();

  @override
  void initState() {
    super.initState();
    // Eagerly load email + phoneNumber from the API
    Future.microtask(() async {
      final ok = await ref.read(authProvider.notifier).fetchProfile();
      if (!mounted) return;
      if (!ok) context.go('/login');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _selectedLocale = context.locale.languageCode;
  }

  Future<void> _signOut() async {
    final confirmed = await StandardDialog.show<bool>(
      context: context,
      title: 'settings_sign_out_confirm_title',
      content: 'settings_sign_out_confirm_body',
      confirmText: 'settings_sign_out',
      cancelText: 'settings_cancel',
      isDestructive: true,
    );
    if (confirmed == true && mounted) {
      await ref.read(authProvider.notifier).logout();
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final isDark = AppTheme.isDarkEffective(themeMode, context);

    final authState = ref.watch(authProvider);
    final fullName = authState.fullName ?? 'Moderator';
    final initials = _initials(fullName);

    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;
    final dividerColor = isDark
        ? const Color(0xFF383018)
        : const Color(0xFFE2E2F0);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────────
            _Header(isDark: isDark, textPrimary: textPrimary),

            // ── Scrollable body ───────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 24.h),

                    // ── Profile card ─────────────────────────────────────────
                    _ProfileCard(
                      initials: initials,
                      fullName: fullName,
                      isDark: isDark,
                      cardBg: cardBg,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                      imageUrl: authState.profilePicture,
                      onEditTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ModeratorProfileEditScreen(),
                        ),
                      ),
                    ),

                    SizedBox(height: 28.h),

                    // ── EL WAKEL SERVICE section ─────────────────────────────
                    _SectionLabel(
                      label: 'settings_wakel_service'.tr(),
                      textMuted: textMuted,
                    ),
                    SizedBox(height: 8.h),
                    _WakelCard(
                      wakelInfo: authState.wakelInfo,
                      isDark: isDark,
                    ),

                    SizedBox(height: 28.h),

                    // ── APP SETTINGS ─────────────────────────────────────────
                    AppSettingsExpansion(
                      isDark: isDark,
                      cardBg: cardBg,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                      dividerColor: dividerColor,
                    ),

                    SizedBox(height: 28.h),

                    // ── LANGUAGE section ─────────────────────────────────────
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
                              isDark ? 0.3 : 0.04,
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
                              await LocalePrefs.saveLanguageCode(code);
                              await SosAlertAudio.stopAndReset();
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

                    // ── SUPPORT & INFO section ──────────────────────────────
                    _SectionLabel(
                      label: 'settings_support_info'.tr(),
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
                              isDark ? 0.3 : 0.04,
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _SupportRow(
                            icon: Icons.shield_outlined,
                            label: 'legal_privacy_policy'.tr(),
                            textPrimary: textPrimary,
                            textMuted: textMuted,
                            onTap: () => context.push('/privacy-policy'),
                            isLast: false,
                            dividerColor: dividerColor,
                          ),
                          _SupportRow(
                            icon: Icons.info_outline_rounded,
                            label: 'about_title'.tr(),
                            textPrimary: textPrimary,
                            textMuted: textMuted,
                            onTap: () => context.push(
                              '/about',
                              extra: true, // showAccountDeletion
                            ),
                            isLast: true,
                            dividerColor: dividerColor,
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 32.h),

                    // ── Sign Out button ───────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 52.h,
                      child: TextButton.icon(
                        onPressed: _signOut,
                        icon: Icon(
                          Icons.logout_rounded,
                          size: 18.sp,
                          color: const Color(0xFFE11D48),
                        ),
                        label: Text(
                          'settings_sign_out'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 16.sp,
                            color: const Color(0xFFE11D48),
                          ),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: isDark
                              ? const Color(0xFF4C1D24)
                              : const Color(0xFFFFF1F2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16.r),
                            side: BorderSide(
                              color: isDark
                                  ? const Color(0xFF881337)
                                  : const Color(0xFFFECDD3),
                              width: 1.5,
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

class _Header extends StatelessWidget {
  const _Header({required this.isDark, required this.textPrimary});
  final bool isDark;
  final Color textPrimary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
      child: Center(
        child: Text(
          'Munawwara Care',
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 20.sp,
            color: textPrimary,
          ),
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.initials,
    required this.fullName,
    required this.isDark,
    required this.cardBg,
    required this.textPrimary,
    required this.textMuted,
    required this.onEditTap,
    this.imageUrl,
  });

  final String initials;
  final String fullName;
  final bool isDark;
  final Color cardBg;
  final Color textPrimary;
  final Color textMuted;
  final VoidCallback onEditTap;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 24.h, horizontal: 16.w),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Centered Avatar with edit icon overlay
          Stack(
            children: [
              Container(
                width: 90.w,
                height: 90.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? Colors.white12
                      : AppColors.primary.withValues(alpha: 0.08),
                  border: Border.all(
                    color: isDark
                        ? Colors.white24
                        : AppColors.primary.withValues(alpha: 0.24),
                    width: 2.w,
                  ),
                ),
                child: Center(
                  child: ModeratorAvatar(
                    size: 86.w,
                    initials: initials,
                    imageUrl: imageUrl,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: GestureDetector(
                  onTap: onEditTap,
                  child: Container(
                    padding: EdgeInsets.all(7.w),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary,
                    ),
                    child: Icon(
                      Icons.edit_rounded,
                      color: Colors.white,
                      size: 14.sp,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          // Moderator Name
          Text(
            fullName,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w800,
              fontSize: 20.sp,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 8.h),
          // Moderator Role Chip
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: 14.w,
              vertical: 4.h,
            ),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF452D15)
                  : const Color(0xFFFFF2E6),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Text(
              'settings_role_moderator'.tr().toUpperCase(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w800,
                fontSize: 11.sp,
                color: isDark ? const Color(0xFFF97316) : const Color(0xFFC2410C),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WakelCard extends StatelessWidget {
  const _WakelCard({required this.wakelInfo, required this.isDark});
  final WakelInfo? wakelInfo;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final name = wakelInfo?.name ?? "El Wakel";
    final contact = wakelInfo?.contactNumber ?? "Travel & Pilgrimage Services";
    final imageUrl = wakelInfo?.profilePicture;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
              : [const Color(0xFF051D2D), const Color(0xFF0F3A5F)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Wakel Logo / Profile picture
          Container(
            width: 50.w,
            height: 50.w,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
            ),
            clipBehavior: Clip.antiAlias,
            child: imageUrl != null && imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => _buildPlaceholderLogo(),
                  )
                : _buildPlaceholderLogo(),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w800,
                    fontSize: 16.sp,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4.h),
                looksLikePhoneNumber(contact)
                    ? PhoneNumberText(
                        contact,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.sp,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      )
                    : Text(
                        contact,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.sp,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderLogo() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(4.w),
        child: Icon(
          Icons.explore_rounded,
          color: const Color(0xFF0F3A5F),
          size: 26.w,
        ),
      ),
    );
  }
}

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
                ? Radius.circular(16.r)
                : Radius.zero,
            bottom: isLast ? Radius.circular(16.r) : Radius.zero,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            child: Row(
              children: [
                // Flag circle
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDark ? Colors.white12 : const Color(0xFFF1F5F9),
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
                  child: Text(
                    'lang_${lang['code']}'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 15.sp,
                      color: textPrimary,
                    ),
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

class _SupportRow extends StatelessWidget {
  const _SupportRow({
    required this.icon,
    required this.label,
    required this.textPrimary,
    required this.textMuted,
    required this.onTap,
    required this.isLast,
    required this.dividerColor,
  });

  final IconData icon;
  final String label;
  final Color textPrimary;
  final Color textMuted;
  final VoidCallback onTap;
  final bool isLast;
  final Color dividerColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.vertical(
            top: !isLast ? Radius.circular(16.r) : Radius.zero,
            bottom: isLast ? Radius.circular(16.r) : Radius.zero,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: textPrimary.withValues(alpha: 0.7),
                  size: 22.sp,
                ),
                SizedBox(width: 14.w),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 15.sp,
                      color: textPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: textMuted,
                  size: 22.sp,
                ),
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
