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
import 'navigation_app_settings_sheet.dart';

/// Expandable app settings (appearance + language) for pilgrim and moderator profiles.
class AppSettingsExpansion extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    final themeNotifier = ref.read(themeProvider.notifier);
    final followsSystem = themeMode == ThemeMode.system;
    final darkEnabled = AppTheme.isDarkEffective(themeMode, context);
    final currentLanguageCode = context.locale.languageCode;
    final currentLanguageName =
        AppLanguageService.nativeNameForCode(currentLanguageCode);
    final navPreference = ref.watch(navigationPreferenceProvider);
    final navPreferenceLabel = navPreference.displayName;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
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
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(side: BorderSide.none),
          collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
          tilePadding: EdgeInsets.symmetric(horizontal: 16.w),
          childrenPadding: EdgeInsets.only(bottom: 8.h),
          title: Text(
            'settings_app_settings'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w600,
              fontSize: 14.sp,
              color: textPrimary,
            ),
          ),
          leading: Icon(
            Icons.settings_outlined,
            color: AppColors.primary,
            size: 22.sp,
          ),
          children: [
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
            Divider(height: 1, color: dividerColor),
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
            Divider(height: 1, color: dividerColor),
            _LanguageSettingsRow(
              currentLanguageName: currentLanguageName,
              isDark: isDark,
              textPrimary: textPrimary,
              textMuted: textMuted,
              onTap: () => showAppLanguagePickerSheet(
                context: context,
                selectedCode: currentLanguageCode,
                isDark: isDark,
              ),
            ),
            Divider(height: 1, color: dividerColor),
            _NavigationSettingsRow(
              currentLabel: navPreferenceLabel,
              isDark: isDark,
              textPrimary: textPrimary,
              textMuted: textMuted,
              onTap: () => showNavigationAppSettingsSheet(
                context: context,
                ref: ref,
                isDark: isDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Disclosure-style row for preferred navigation app.
class _NavigationSettingsRow extends StatelessWidget {
  const _NavigationSettingsRow({
    required this.currentLabel,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
    required this.onTap,
  });

  final String currentLabel;
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
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
          child: Row(
            children: [
              Icon(
                Icons.navigation_rounded,
                size: 22.sp,
                color: AppColors.primary,
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Text(
                  'settings_nav_app_title'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 15.sp,
                    color: textPrimary,
                  ),
                ),
              ),
              Text(
                currentLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 15.sp,
                  color: textMuted,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20.sp,
                color: textMuted.withValues(alpha: 0.65),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Disclosure-style row (label + current value + chevron), per iOS Settings patterns.
class _LanguageSettingsRow extends StatelessWidget {
  const _LanguageSettingsRow({
    required this.currentLanguageName,
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
    required this.onTap,
  });

  final String currentLanguageName;
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
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
          child: Row(
            children: [
              Icon(
                Icons.language_rounded,
                size: 22.sp,
                color: AppColors.primary,
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Text(
                  'settings_language_title'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 15.sp,
                    color: textPrimary,
                  ),
                ),
              ),
              Text(
                currentLanguageName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 15.sp,
                  color: textMuted,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20.sp,
                color: textMuted.withValues(alpha: 0.65),
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
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22.sp,
            color: enabled
                ? AppColors.primary
                : textMuted.withValues(alpha: 0.55),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 15.sp,
                    color: enabled
                        ? textPrimary
                        : textPrimary.withValues(alpha: 0.45),
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    color: enabled
                        ? textMuted
                        : textMuted.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
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
