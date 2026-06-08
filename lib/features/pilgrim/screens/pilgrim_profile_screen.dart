import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/providers/theme_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/legal_support_section.dart';
import '../../../core/config/app_locales.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/locale_prefs.dart';
import '../../../core/services/sos_alert_audio.dart';
import '../../../core/services/callkit_service.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../auth/providers/auth_provider.dart';
import '../../shared/widgets/pilgrim_gender_avatar.dart';
import '../../../core/widgets/tameny_tracking_toggle.dart';
class PilgrimProfileScreen extends ConsumerStatefulWidget {
  const PilgrimProfileScreen({super.key});

  @override
  ConsumerState<PilgrimProfileScreen> createState() =>
      _PilgrimProfileScreenState();
}

class _PilgrimProfileScreenState extends ConsumerState<PilgrimProfileScreen> {
  late String _selectedLocale;
  File? _localProfilePictureFile;
  bool _uploadingPfp = false;

  /// Matches [PilgrimDashboardScreen] scaffold background in light mode.
  static const Color _lightBg = Color(0xfff1f5f3);

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

  Future<void> _onAvatarTap() async {
    if (_uploadingPfp) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (BuildContext sheetContext) {
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
                'profile_picture_title'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 16.sp,
                  color: textPrimary,
                ),
              ),
              SizedBox(height: 16.h),
              ListTile(
                leading: const Icon(
                  Icons.camera_alt_rounded,
                  color: AppColors.primary,
                ),
                title: Text(
                  'profile_picture_camera'.tr(),
                  style: TextStyle(fontFamily: 'Lexend', color: textPrimary),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUploadProfilePicture(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: AppColors.primary,
                ),
                title: Text(
                  'profile_picture_gallery'.tr(),
                  style: TextStyle(fontFamily: 'Lexend', color: textPrimary),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUploadProfilePicture(ImageSource.gallery);
                },
              ),
              SizedBox(height: 8.h),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUploadProfilePicture(ImageSource source) async {
    final picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1000,
        maxHeight: 1000,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;

      setState(() {
        _localProfilePictureFile = File(image.path);
        _uploadingPfp = true;
      });

      final success = await ref
          .read(authProvider.notifier)
          .updateProfilePicture(_localProfilePictureFile!);

      if (!mounted) return;

      if (success) {
        setState(() {
          _localProfilePictureFile = null;
          _uploadingPfp = false;
        });
        StandardSnackBar.showSuccess(context, 'edit_profile_success'.tr());
        return;
      }

      setState(() {
        _localProfilePictureFile = null;
        _uploadingPfp = false;
      });
      final error =
          ref.read(authProvider).error ?? 'edit_profile_error_generic'.tr();
      StandardSnackBar.showError(context, error);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _localProfilePictureFile = null;
        _uploadingPfp = false;
      });
      StandardSnackBar.showError(context, 'Error selecting image: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final isDark = AppTheme.isDarkEffective(themeMode, context);

    final authState = ref.watch(authProvider);
    final fullName = authState.fullName ?? 'Pilgrim';

    final bg = isDark ? AppColors.backgroundDark : _lightBg;
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
            if (Navigator.canPop(context))
              _SettingsHeader(isDark: isDark, textPrimary: textPrimary)
            else
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
                          GestureDetector(
                            onTap: _uploadingPfp ? null : _onAvatarTap,
                            child: Stack(
                              clipBehavior: Clip.none,
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
                                  child: _localProfilePictureFile != null
                                      ? ClipOval(
                                          child: Image.file(
                                            _localProfilePictureFile!,
                                            width: 51.w,
                                            height: 51.w,
                                            fit: BoxFit.cover,
                                          ),
                                        )
                                      : PilgrimGenderAvatar(
                                          gender: authState.gender,
                                          size: 51.w,
                                          imageUrl: authState.profilePicture,
                                        ),
                                ),
                                if (_uploadingPfp)
                                  Positioned.fill(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black.withValues(
                                          alpha: 0.45,
                                        ),
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: 20.w,
                                          height: 20.w,
                                          child: const CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  Positioned(
                                    bottom: -2.h,
                                    right: -2.w,
                                    child: Container(
                                      padding: EdgeInsets.all(4.w),
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.primary,
                                      ),
                                      child: Icon(
                                        Icons.camera_alt_rounded,
                                        color: Colors.white,
                                        size: 12.sp,
                                      ),
                                    ),
                                  ),
                              ],
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

                    // ── LOCATION SHARING section ─────────────────────────
                    _SectionLabel(
                      label: 'settings_location_sharing'.tr(),
                      textMuted: textMuted,
                    ),
                    SizedBox(height: 8.h),
                    const TamenyTrackingToggle(),
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

                    LegalSupportSection(
                      isDark: isDark,
                      cardBg: cardBg,
                      textPrimary: textPrimary,
                      textMuted: textMuted,
                      dividerColor: dividerColor,
                      showAccountDeletion: true,
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
                              icon: Symbols.hotel,
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
                              icon: Icons.assignment_turned_in_rounded,
                              label: 'Tashera Number',
                              value: authState.tasheraNumber ?? 'profile_not_provided'.tr(),
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
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
                            _divider(dividerColor),
                            _InfoTile(
                              icon: Icons.assignment_ind_rounded,
                              label: 'morafeq_name'.tr(),
                              value: authState.morafeqName ?? 'profile_not_provided'.tr(),
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                            _divider(dividerColor),
                            _InfoTile(
                              icon: Icons.phone_callback_rounded,
                              label: 'morafeq_phone'.tr(),
                              value: authState.morafeqPhone ?? 'profile_not_provided'.tr(),
                              isDark: isDark,
                              textPrimary: textPrimary,
                              textMuted: textMuted,
                            ),
                            _divider(dividerColor),
                            _InfoTile(
                              icon: Icons.mail_outline_rounded,
                              label: 'morafeq_email'.tr(),
                              value: authState.morafeqEmail ?? 'profile_not_provided'.tr(),
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

  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
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
                    color: textPrimary,
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

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({
    required this.isDark,
    required this.textPrimary,
  });

  final bool isDark;
  final Color textPrimary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 8.h, 20.w, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 42.w,
              height: 42.w,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? AppColors.backgroundDark
                      : const Color(0xFFE2E2F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: textPrimary,
                size: 20.sp,
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'settings_title'.tr(),
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
    );
  }
}
