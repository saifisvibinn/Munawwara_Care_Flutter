import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../navigation/navigation_app.dart';
import '../theme/app_colors.dart';

/// Result from the first-time / on-demand navigation app picker sheet.
class NavigationAppPickerResult {
  const NavigationAppPickerResult({
    required this.app,
    required this.rememberChoice,
  });

  final NavigationApp app;
  final bool rememberChoice;
}

/// Material 3 bottom sheet for choosing a navigation app.
Future<NavigationAppPickerResult?> showNavigationAppPickerSheet({
  required BuildContext context,
  required List<NavigationApp> availableApps,
  required bool isDark,
  required Future<bool> Function(NavigationApp app) onLaunch,
}) {
  if (availableApps.isEmpty) return Future.value();

  return showModalBottomSheet<NavigationAppPickerResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
    ),
    builder: (sheetContext) => _NavigationAppPickerSheet(
      availableApps: availableApps,
      isDark: isDark,
      onLaunch: onLaunch,
    ),
  );
}

class _NavigationAppPickerSheet extends StatefulWidget {
  const _NavigationAppPickerSheet({
    required this.availableApps,
    required this.isDark,
    required this.onLaunch,
  });

  final List<NavigationApp> availableApps;
  final bool isDark;
  final Future<bool> Function(NavigationApp app) onLaunch;

  @override
  State<_NavigationAppPickerSheet> createState() =>
      _NavigationAppPickerSheetState();
}

class _NavigationAppPickerSheetState extends State<_NavigationAppPickerSheet> {
  bool _rememberChoice = false;
  NavigationApp? _launchingApp;

  bool get isDark => widget.isDark;

  Color get titleColor => isDark ? Colors.white : AppColors.textDark;

  Color get muted =>
      isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

  Color get tileBg => isDark ? AppColors.surfaceDark : const Color(0xFFF8FAFC);

  Color get tileBorder =>
      isDark ? AppColors.dividerDark : const Color(0xFFE2E8F0);

  Future<void> _onAppSelected(NavigationApp app) async {
    if (_launchingApp != null) return;

    setState(() => _launchingApp = app);

    final launched = await widget.onLaunch(app);
    if (!mounted) return;

    if (launched) {
      Navigator.of(context).pop(
        NavigationAppPickerResult(app: app, rememberChoice: _rememberChoice),
      );
      return;
    }

    setState(() => _launchingApp = null);
    await _showLaunchFailed();
  }

  Future<void> _showLaunchFailed() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('explore_open_maps_failed_title'.tr()),
        content: SelectableText.rich(
          TextSpan(
            text: 'explore_open_maps_failed_body'.tr(),
            style: TextStyle(
              fontFamily: 'Lexend',
              color: Colors.red.shade700,
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('dialog_ok'.tr()),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 16.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            'maps_app_picker_title'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 17.sp,
              fontWeight: FontWeight.w700,
              color: titleColor,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'maps_app_picker_subtitle'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: muted,
              height: 1.35,
            ),
          ),
          SizedBox(height: 18.h),
          ...widget.availableApps.map((app) {
            final isLaunching = _launchingApp == app;
            return Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: _NavigationAppTile(
                backgroundColor: tileBg,
                borderColor: tileBorder,
                icon: _iconFor(app),
                iconColor: _iconColorFor(app),
                iconBg: _iconBgFor(app),
                title: app.displayName,
                subtitle: app.displaySubtitle ?? '',
                bodyColor: titleColor,
                subtitleColor: muted,
                isLoading: isLaunching,
                onTap: isLaunching ? null : () => _onAppSelected(app),
              ),
            );
          }),
          SizedBox(height: 4.h),
          CheckboxListTile(
            value: _rememberChoice,
            onChanged: _launchingApp != null
                ? null
                : (value) => setState(() => _rememberChoice = value ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: AppColors.primary,
            title: Text(
              'nav_app_remember_choice'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: titleColor,
              ),
            ),
          ),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }

  IconData _iconFor(NavigationApp app) => switch (app) {
        NavigationApp.appleMaps => Symbols.nest_found_savings,
        NavigationApp.googleMaps => Symbols.map,
        NavigationApp.systemSelection => Symbols.explore,
      };

  Color _iconColorFor(NavigationApp app) => switch (app) {
        NavigationApp.appleMaps => const Color(0xFF007AFF),
        NavigationApp.googleMaps => const Color(0xFF34A853),
        NavigationApp.systemSelection => AppColors.primary,
      };

  Color _iconBgFor(NavigationApp app) => switch (app) {
        NavigationApp.appleMaps => const Color(0xFFE8F2FF),
        NavigationApp.googleMaps => const Color(0xFFE8F5E9),
        NavigationApp.systemSelection =>
          AppColors.primary.withValues(alpha: 0.1),
      };
}

class _NavigationAppTile extends StatelessWidget {
  const _NavigationAppTile({
    required this.backgroundColor,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.bodyColor,
    required this.subtitleColor,
    this.isLoading = false,
    this.onTap,
  });

  final Color backgroundColor;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final Color bodyColor;
  final Color subtitleColor;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
            child: Row(
              children: [
                Container(
                  width: 44.w,
                  height: 44.w,
                  decoration: BoxDecoration(
                    color: iconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: iconColor, size: 24.sp),
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
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                          color: bodyColor,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        SizedBox(height: 2.h),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                            color: subtitleColor,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isLoading)
                  SizedBox(
                    width: 22.w,
                    height: 22.w,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: subtitleColor,
                    size: 22.sp,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
