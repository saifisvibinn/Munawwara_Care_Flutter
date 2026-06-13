import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../navigation/navigation_app.dart';
import '../navigation/navigation_app_detector.dart';
import '../providers/navigation_preference_provider.dart';
import '../theme/app_colors.dart';

/// Settings sheet for choosing the preferred navigation app.
Future<void> showNavigationAppSettingsSheet({
  required BuildContext context,
  required WidgetRef ref,
  required bool isDark,
}) async {
  final current = ref.read(navigationPreferenceProvider);
  final googleInstalled = await NavigationAppDetector.isInstalled(
    NavigationApp.googleMaps,
  );

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
    ),
    builder: (sheetContext) => _NavigationAppSettingsSheet(
      selected: current,
      showAppleMaps: !kIsWeb && Platform.isIOS,
      showGoogleMaps: !kIsWeb && (Platform.isAndroid || googleInstalled),
      isDark: isDark,
      onSelected: (app) async {
        await ref.read(navigationPreferenceProvider.notifier).setPreference(app);
        if (sheetContext.mounted) {
          Navigator.of(sheetContext).pop();
        }
      },
    ),
  );
}

class _NavigationAppSettingsSheet extends StatelessWidget {
  const _NavigationAppSettingsSheet({
    required this.selected,
    required this.showAppleMaps,
    required this.showGoogleMaps,
    required this.isDark,
    required this.onSelected,
  });

  final NavigationApp selected;
  final bool showAppleMaps;
  final bool showGoogleMaps;
  final bool isDark;
  final ValueChanged<NavigationApp> onSelected;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final dividerColor =
        isDark ? AppColors.dividerDark : const Color(0xFFE5E7EB);
    final sheetBg = isDark ? AppColors.surfaceDark : Colors.white;

    final options = <NavigationApp>[
      NavigationApp.systemSelection,
      if (showAppleMaps) NavigationApp.appleMaps,
      if (showGoogleMaps) NavigationApp.googleMaps,
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.42,
      minChildSize: 0.32,
      maxChildSize: 0.6,
      builder: (context, scrollController) {
        return Column(
          children: [
            SizedBox(height: 10.h),
            Container(
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 8.h),
              child: Text(
                'settings_nav_app_title'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 17.sp,
                  color: textPrimary,
                ),
              ),
            ),
            Expanded(
              child: Material(
                color: sheetBg,
                child: ListView.separated(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                  itemCount: options.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    thickness: 0.5,
                    color: dividerColor,
                  ),
                  itemBuilder: (context, index) {
                    final app = options[index];
                    final isSelected = app == selected;

                    return Material(
                      color: sheetBg,
                      child: InkWell(
                        onTap: () => onSelected(app),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 4.w,
                            vertical: 12.h,
                          ),
                          child: Row(
                            children: [
                              _SettingsIcon(app: app),
                              SizedBox(width: 14.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      app.displayName,
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15.sp,
                                        color: textPrimary,
                                      ),
                                    ),
                                    if (app.displaySubtitle != null) ...[
                                      SizedBox(height: 2.h),
                                      Text(
                                        app.displaySubtitle!,
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 12.sp,
                                          color: isDark
                                              ? AppColors.textMutedLight
                                              : AppColors.textMutedDark,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check,
                                  color: AppColors.primary,
                                  size: 22.sp,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.app});

  final NavigationApp app;

  @override
  Widget build(BuildContext context) {
    final (icon, color, bg) = switch (app) {
      NavigationApp.appleMaps => (
          Symbols.nest_found_savings,
          const Color(0xFF007AFF),
          const Color(0xFFE8F2FF),
        ),
      NavigationApp.googleMaps => (
          Symbols.map,
          const Color(0xFF34A853),
          const Color(0xFFE8F5E9),
        ),
      NavigationApp.systemSelection => (
          Symbols.tune,
          AppColors.primary,
          AppColors.primary.withValues(alpha: 0.1),
        ),
    };

    return Container(
      width: 36.w,
      height: 36.w,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 20.sp),
    );
  }
}
