import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';

/// Shared visual tokens for area / meetpoint UI (Apple inset-grouped style).
abstract final class AreaUiTheme {
  static const meetpointRed = Color(0xFFDC2626);
  static const meetpointRedDark = Color(0xFFE05050);

  static Color accent(bool isDark, {required bool isMeetpoint}) => isMeetpoint
      ? (isDark ? meetpointRedDark : meetpointRed)
      : AppColors.primary;

  static Color sheetBg(bool isDark) =>
      isDark ? const Color(0xFF12151E) : const Color(0xFFF7F8FC);

  static Color groupedBg(bool isDark) =>
      isDark ? const Color(0xFF1C1F2E) : Colors.white;

  static Color divider(bool isDark) =>
      isDark ? const Color(0xFF2E3040) : const Color(0xFFE5E5EA);

  static Color sectionLabel(bool isDark) => isDark
      ? AppColors.textMutedLight
      : AppColors.textMutedDark;

  static Color handle(bool isDark) =>
      isDark ? const Color(0xFF2E3040) : const Color(0xFFD8D8E0);

  static Color typeTint(bool isDark, Color accent) =>
      accent.withValues(alpha: isDark ? 0.14 : 0.08);

  static Color typeBorder(bool isDark, Color accent) =>
      accent.withValues(alpha: isDark ? 0.28 : 0.22);
}

/// Borderless [InputDecoration] — overrides global orange focusedBorder and fill tint.
InputDecoration areaBorderlessInputDecoration({
  required String hint,
  required Color hintColor,
  EdgeInsetsGeometry? contentPadding,
}) {
  const none = InputBorder.none;
  return InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(
      fontFamily: 'Lexend',
      fontSize: 15.sp,
      color: hintColor,
    ),
    filled: false,
    fillColor: Colors.transparent,
    border: none,
    enabledBorder: none,
    focusedBorder: none,
    errorBorder: none,
    disabledBorder: none,
    focusedErrorBorder: none,
    isDense: true,
    contentPadding: contentPadding ?? EdgeInsets.symmetric(vertical: 10.h),
  );
}

/// Modal bottom sheet chrome: grabber + solid background + safe bottom padding.
class AreaSheetScaffold extends StatelessWidget {
  const AreaSheetScaffold({
    super.key,
    required this.isDark,
    required this.child,
    this.maxHeightFactor = 0.65,
    this.scrollControlled = false,
    this.edgeToEdge = false,
    this.showGrabber = true,
  });

  final bool isDark;
  final Widget child;
  final double maxHeightFactor;
  final bool scrollControlled;
  /// Full-width sheet flush to the bottom safe area (confirm dialogs).
  final bool edgeToEdge;
  final bool showGrabber;

  @override
  Widget build(BuildContext context) {
    final body = edgeToEdge
        ? child
        : Flexible(child: child);

    return Container(
      width: double.infinity,
      constraints: edgeToEdge
          ? null
          : BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
            ),
      decoration: BoxDecoration(
        color: AreaUiTheme.sheetBg(isDark),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26.r)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        16.w,
        10.h,
        16.w,
        MediaQuery.paddingOf(context).bottom + 16.h,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showGrabber) ...[
            AreaSheetGrabber(isDark: isDark),
            SizedBox(height: 12.h),
          ],
          body,
        ],
      ),
    );
  }
}

class AreaSheetGrabber extends StatelessWidget {
  const AreaSheetGrabber({super.key, required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36.w,
        height: 4.h,
        decoration: BoxDecoration(
          color: AreaUiTheme.handle(isDark),
          borderRadius: BorderRadius.circular(2.r),
        ),
      ),
    );
  }
}

class AreaSheetTitle extends StatelessWidget {
  const AreaSheetTitle({
    super.key,
    required this.title,
    required this.isDark,
    this.subtitle,
  });

  final String title;
  final bool isDark;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 17.sp,
            color: textPrimary,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          SizedBox(height: 4.h),
          Text(
            subtitle!,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              color: AreaUiTheme.sectionLabel(isDark),
            ),
          ),
        ],
      ],
    );
  }
}

class AreaSectionLabel extends StatelessWidget {
  const AreaSectionLabel({
    super.key,
    required this.label,
    required this.isDark,
  });

  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 4.w, bottom: 6.h),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontWeight: FontWeight.w500,
          fontSize: 13.sp,
          color: AreaUiTheme.sectionLabel(isDark),
        ),
      ),
    );
  }
}

/// iOS inset grouped container.
class AreaInsetGroup extends StatelessWidget {
  const AreaInsetGroup({
    super.key,
    required this.isDark,
    required this.children,
  });

  final bool isDark;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final visible = children.where((c) => c is! SizedBox).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AreaUiTheme.groupedBg(isDark),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AreaUiTheme.divider(isDark), width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0)
              Divider(
                height: 0.5,
                thickness: 0.5,
                color: AreaUiTheme.divider(isDark),
                indent: 14.w,
              ),
            visible[i],
          ],
        ],
      ),
    );
  }
}

class AreaInsetTextRow extends StatelessWidget {
  const AreaInsetTextRow({
    super.key,
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.minLines = 1,
    this.onChanged,
    this.focusNode,
  });

  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final int minLines;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final hintColor = AreaUiTheme.sectionLabel(isDark);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
      child: Row(
        crossAxisAlignment: minLines > 1
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: minLines > 1 ? 10.h : 0),
            child: Icon(icon, size: 20.w, color: iconColor),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                inputDecorationTheme: InputDecorationTheme(
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: maxLines,
                minLines: minLines,
                onChanged: onChanged,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 15.sp,
                  color: textPrimary,
                ),
                decoration: areaBorderlessInputDecoration(
                  hint: hint,
                  hintColor: hintColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Inset grouped search row — no theme focus ring bleed.
class AreaInsetSearchRow extends StatelessWidget {
  const AreaInsetSearchRow({
    super.key,
    required this.isDark,
    required this.controller,
    required this.hint,
    required this.focusNode,
    required this.onChanged,
    this.accentColor,
    this.onCollapse,
    this.onClear,
    this.showClear = false,
  });

  final bool isDark;
  final TextEditingController controller;
  final String hint;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final Color? accentColor;
  final VoidCallback? onCollapse;
  final VoidCallback? onClear;
  final bool showClear;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final muted = AreaUiTheme.sectionLabel(isDark);
    final iconColor = accentColor ?? muted;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
      child: Row(
        children: [
          if (onCollapse != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Symbols.arrow_back, color: iconColor, size: 20.w),
              onPressed: onCollapse,
            )
          else
            Padding(
              padding: EdgeInsets.only(left: 10.w),
              child: Icon(Symbols.search, size: 20.w, color: iconColor),
            ),
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(
                inputDecorationTheme: InputDecorationTheme(
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 15.sp,
                  color: textPrimary,
                ),
                decoration: areaBorderlessInputDecoration(
                  hint: hint,
                  hintColor: muted,
                ),
              ),
            ),
          ),
          if (showClear && onClear != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Symbols.close, color: muted, size: 18.w),
              onPressed: onClear,
            ),
        ],
      ),
    );
  }
}

/// Equal-weight Search / Move pin rows inside one inset group.
class AreaMapToolsGroup extends StatelessWidget {
  const AreaMapToolsGroup({
    super.key,
    required this.isDark,
    required this.accentColor,
    required this.searchLabel,
    required this.movePinLabel,
    required this.onSearch,
    required this.onMovePin,
  });

  final bool isDark;
  final Color accentColor;
  final String searchLabel;
  final String movePinLabel;
  final VoidCallback onSearch;
  final VoidCallback onMovePin;

  @override
  Widget build(BuildContext context) {
    return AreaInsetGroup(
      isDark: isDark,
      children: [
        AreaInsetValueRow(
          isDark: isDark,
          icon: Symbols.search,
          iconColor: accentColor,
          label: searchLabel,
          onTap: onSearch,
        ),
        AreaInsetValueRow(
          isDark: isDark,
          icon: Symbols.add_location_alt,
          iconColor: accentColor,
          label: movePinLabel,
          onTap: onMovePin,
        ),
      ],
    );
  }
}

class AreaInsetValueRow extends StatelessWidget {
  const AreaInsetValueRow({
    super.key,
    required this.isDark,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.trailing,
    this.showChevron = true,
  });

  final bool isDark;
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final muted = AreaUiTheme.sectionLabel(isDark);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          child: Row(
            children: [
              Icon(icon, size: 20.w, color: iconColor),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15.sp,
                    color: textPrimary,
                  ),
                ),
              ),
              ?trailing,
              if (showChevron)
                Icon(Symbols.chevron_right, size: 20.w, color: muted),
            ],
          ),
        ),
      ),
    );
  }
}

class AreaListRow extends StatelessWidget {
  const AreaListRow({
    super.key,
    required this.isDark,
    required this.name,
    required this.isMeetpoint,
    this.description,
    this.onTap,
    this.trailing,
  });

  final bool isDark;
  final String name;
  final bool isMeetpoint;
  final String? description;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final accent = AreaUiTheme.accent(isDark, isMeetpoint: isMeetpoint);
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
          child: Row(
            children: [
              Container(
                width: 36.w,
                height: 36.w,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isMeetpoint ? Symbols.crisis_alert : Symbols.pin_drop,
                  color: Colors.white,
                  size: 18.w,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 15.sp,
                        color: textPrimary,
                      ),
                    ),
                    if (description != null && description!.isNotEmpty)
                      Text(
                        description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.sp,
                          color: AreaUiTheme.sectionLabel(isDark),
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class AreaTypeActionCard extends StatelessWidget {
  const AreaTypeActionCard({
    super.key,
    required this.isDark,
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final bool isDark;
  final String label;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;

    return Material(
      color: AreaUiTheme.typeTint(isDark, accentColor),
      borderRadius: BorderRadius.circular(16.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 12.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: AreaUiTheme.typeBorder(isDark, accentColor)),
          ),
          child: Column(
            children: [
              Container(
                width: 52.w,
                height: 52.w,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 26.w),
              ),
              SizedBox(height: 12.h),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 13.sp,
                  color: textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AreaPrimaryButton extends StatelessWidget {
  const AreaPrimaryButton({
    super.key,
    required this.label,
    required this.accentColor,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final Color accentColor;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50.h,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          disabledBackgroundColor: accentColor.withValues(alpha: 0.6),
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
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
            : icon != null
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 20.w, color: Colors.white, fill: 1),
                      SizedBox(width: 8.w),
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          fontSize: 15.sp,
                        ),
                      ),
                    ],
                  )
                : Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 15.sp,
                    ),
                  ),
      ),
    );
  }
}

/// Floating glass nav for area picker (back + title pill + locate).
class AreaPickerFloatingNav extends StatelessWidget {
  const AreaPickerFloatingNav({
    super.key,
    required this.isDark,
    required this.title,
    required this.onBack,
    required this.onLocate,
    this.isLocating = false,
  });

  final bool isDark;
  final String title;
  final VoidCallback onBack;
  final VoidCallback onLocate;
  final bool isLocating;

  static double overlayHeight(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top + 10.h + 44.w + 6.h;

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final navHeight = overlayHeight(context);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: navHeight,
          child: AppScrollGlassEdge(
            height: navHeight,
            edge: AppScrollGlassEdgeSide.top,
            isDark: isDark,
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 6.h),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppGlassIconButton(
                    isDark: isDark,
                    icon: Symbols.arrow_back,
                    onTap: onBack,
                    size: 42.w,
                  ),
                ),
                AppGlassSurface(
                  isDark: isDark,
                  borderRadius: BorderRadius.circular(14.r),
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                  glassTheme: AppGlassTheme.groupBroadcastNavPillOf(isDark),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 13.sp,
                      color: textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: isLocating
                      ? SizedBox(
                          width: 42.w,
                          height: 42.w,
                          child: Center(
                            child: SizedBox(
                              width: 20.w,
                              height: 20.w,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        )
                      : AppGlassIconButton(
                          isDark: isDark,
                          icon: Symbols.my_location,
                          onTap: onLocate,
                          size: 42.w,
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
