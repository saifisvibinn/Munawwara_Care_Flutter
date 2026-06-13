import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../navigation/navigation_app.dart';
import '../providers/navigation_preference_provider.dart';
import '../providers/theme_provider.dart';
import '../services/app_language_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'app_language_picker_sheet.dart';
import 'glass/app_glass.dart';
import 'navigation_app_settings_sheet.dart';

/// Expandable app settings (appearance + language) for pilgrim and moderator profiles.
class AppSettingsExpansion extends ConsumerStatefulWidget {
  const AppSettingsExpansion({
    super.key,
    required this.isDark,
    required this.cardBg,
    required this.textPrimary,
    required this.textMuted,
    required this.dividerColor,
  });

  final bool isDark;
  final Color cardBg;
  final Color textPrimary;
  final Color textMuted;
  final Color dividerColor;

  @override
  ConsumerState<AppSettingsExpansion> createState() =>
      _AppSettingsExpansionState();
}

class _AppSettingsExpansionState extends ConsumerState<AppSettingsExpansion> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final followsSystem = themeMode == ThemeMode.system;
    final darkEnabled = AppTheme.isDarkEffective(themeMode, context);
    final currentLanguageCode = context.locale.languageCode;
    final currentLanguageName =
        AppLanguageService.nativeNameForCode(currentLanguageCode);
    final navPreference = ref.watch(navigationPreferenceProvider);
    final navPreferenceLabel = navPreference.displayName;

    final isDark = widget.isDark;
    final textPrimary = widget.textPrimary;
    final textMuted = widget.textMuted;
    final dividerColor = widget.dividerColor;

    return AppGlassCard(
      isDark: isDark,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24.r),
                bottom: _expanded ? Radius.zero : Radius.circular(24.r),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(18.w, 18.h, 14.w, 18.h),
                child: Row(
                  children: [
                    _SettingsIconChip(
                      icon: Icons.settings_outlined,
                      isDark: isDark,
                      enabled: true,
                    ),
                    SizedBox(width: 14.w),
                    Expanded(
                      child: Text(
                        'settings_app_settings'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 16.sp,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 26.sp,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Column(
              children: [
                _InsetDivider(color: dividerColor),
                _ThemeToggleRow(
                  icon: Icons.brightness_auto_rounded,
                  title: 'settings_follow_system'.tr(),
                  subtitle: 'settings_follow_system_sub'.tr(),
                  value: followsSystem,
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  onChanged: (enabled) {
                    themeNotifier.setFollowSystem(
                      enabled,
                      effectiveIsDark: darkEnabled,
                    );
                  },
                ),
                _InsetDivider(color: dividerColor),
                _ThemeToggleRow(
                  icon: Icons.dark_mode_rounded,
                  title: 'settings_dark_mode'.tr(),
                  subtitle: 'settings_dark_mode_sub'.tr(),
                  value: darkEnabled,
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  enabled: !followsSystem,
                  onChanged: followsSystem
                      ? null
                      : (enabled) => themeNotifier.setDarkEnabled(enabled),
                ),
                _InsetDivider(color: dividerColor),
                _DisclosureSettingsRow(
                  icon: Icons.language_rounded,
                  title: 'settings_language_title'.tr(),
                  value: currentLanguageName,
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  onTap: () => showAppLanguagePickerSheet(
                    context: context,
                    selectedCode: currentLanguageCode,
                    isDark: isDark,
                  ),
                ),
                _InsetDivider(color: dividerColor),
                _DisclosureSettingsRow(
                  icon: Icons.navigation_rounded,
                  title: 'settings_nav_app_title'.tr(),
                  value: navPreferenceLabel,
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  onTap: () => showNavigationAppSettingsSheet(
                    context: context,
                    ref: ref,
                    isDark: isDark,
                  ),
                ),
                SizedBox(height: 8.h),
              ],
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }
}

class _SettingsIconChip extends StatelessWidget {
  const _SettingsIconChip({
    required this.icon,
    required this.isDark,
    required this.enabled,
  });

  final IconData icon;
  final bool isDark;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40.w,
      height: 40.w,
      decoration: BoxDecoration(
        color: enabled
            ? AppColors.primary.withValues(alpha: isDark ? 0.22 : 0.12)
            : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Icon(
        icon,
        size: 20.sp,
        color: enabled
            ? AppColors.primary
            : AppColors.primary.withValues(alpha: 0.45),
      ),
    );
  }
}

class _InsetDivider extends StatelessWidget {
  const _InsetDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 72.w),
      child: Divider(height: 1, thickness: 1, color: color),
    );
  }
}

class _DisclosureSettingsRow extends StatelessWidget {
  const _DisclosureSettingsRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool isDark;
  final Color textPrimary;
  final Color textMuted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18.w, 16.h, 14.w, 16.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SettingsIconChip(
                icon: icon,
                isDark: isDark,
                enabled: true,
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 15.sp,
                        height: 1.35,
                        color: textPrimary,
                      ),
                    ),
                    SizedBox(height: 6.h),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            value,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 14.sp,
                              height: 1.3,
                              color: textMuted,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 22.sp,
                          color: textMuted.withValues(alpha: 0.65),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeToggleRow extends StatelessWidget {
  const _ThemeToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
    this.enabled = true,
    this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool isDark;
  final Color textPrimary;
  final Color textMuted;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18.w, 16.h, 14.w, 16.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsIconChip(
            icon: icon,
            isDark: isDark,
            enabled: enabled,
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 15.sp,
                    height: 1.35,
                    color: enabled
                        ? textPrimary
                        : textPrimary.withValues(alpha: 0.45),
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 13.sp,
                    height: 1.35,
                    color: enabled
                        ? textMuted
                        : textMuted.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withValues(alpha: 0.3),
            inactiveThumbColor: isDark ? AppColors.textLight : Colors.grey,
            inactiveTrackColor:
                isDark ? AppColors.surfaceDark : Colors.grey.shade300,
          ),
        ],
      ),
    );
  }
}
