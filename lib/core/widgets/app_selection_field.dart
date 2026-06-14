export 'app_selection_sheet.dart';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import '../theme/app_dropdown_theme.dart';
import 'app_selection_sheet.dart';

enum AppSelectionStyle {
  /// Labeled form field — opens a bottom sheet.
  form,

  /// Compact pill/chip for toolbar filters.
  compact,

  /// Minimal inset field (e.g. language pair rows).
  minimal,
}

/// Apple HIG selection control: tappable field opens a Settings-style sheet.
class AppSelectionField<T> extends StatelessWidget {
  const AppSelectionField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.sheetTitle,
    this.hint,
    this.label,
    this.prefixIcon,
    this.enabled = true,
    this.isDark = false,
    this.style = AppSelectionStyle.form,
    this.decoration,
    this.nested = false,
    this.minimal = false,
    this.trailingIcon,
    this.errorText,
    this.isExpanded = true,
  });

  final T? value;
  final List<AppSelectionOption<T>> options;
  final ValueChanged<T?> onChanged;
  final String sheetTitle;
  final String? hint;
  final String? label;
  final Widget? prefixIcon;
  final bool enabled;
  final bool isDark;
  final AppSelectionStyle style;
  final InputDecoration? decoration;
  final bool nested;
  final bool minimal;
  final Widget? trailingIcon;
  final String? errorText;
  final bool isExpanded;

  String? get _displayLabel {
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    return null;
  }

  Future<void> _openSheet(BuildContext context) async {
    if (!enabled || options.isEmpty) return;
    final result = await showAppSelectionSheet<T>(
      context: context,
      title: sheetTitle,
      options: options,
      selectedValue: value,
      isDark: isDark,
    );
    if (result != null) {
      onChanged(result.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final display = _displayLabel;
    final resolvedDark =
        isDark || Theme.of(context).brightness == Brightness.dark;

    switch (style) {
      case AppSelectionStyle.compact:
        return _buildCompact(context, resolvedDark, display);
      case AppSelectionStyle.minimal:
        return _buildMinimal(context, resolvedDark, display);
      case AppSelectionStyle.form:
        return _buildForm(context, resolvedDark, display);
    }
  }

  String? _placeholderForField({required bool useExternalLabel}) {
    if (hint != null) return hint;
    if (!useExternalLabel && label != null) return label;
    return null;
  }

  InputDecoration _resolveDecoration(
    bool isDark,
    String? display, {
    required bool useExternalLabel,
  }) {
    final hasValue = display != null;
    final placeholder = _placeholderForField(useExternalLabel: useExternalLabel);

    final base = decoration ??
        AppDropdownTheme.formFieldDecoration(
          isDark: isDark,
          prefixIcon: prefixIcon,
          nested: nested,
          minimal: minimal,
        );

    return base.copyWith(
      labelText: null,
      hintText: hasValue ? null : (placeholder ?? base.hintText),
      floatingLabelBehavior: FloatingLabelBehavior.never,
      prefixIcon: prefixIcon ?? base.prefixIcon,
    );
  }

  Widget _buildForm(BuildContext context, bool isDark, String? display) {
    final hasValue = display != null;
    final useExternalLabel = label != null && decoration == null;
    final radius = minimal ? 14.r : AppDropdownTheme.fieldCornerRadius();

    final field = InkWell(
      onTap: enabled ? () => _openSheet(context) : null,
      borderRadius: BorderRadius.circular(radius),
      child: InputDecorator(
        decoration: _resolveDecoration(
          isDark,
          display,
          useExternalLabel: useExternalLabel,
        ).copyWith(
          enabled: enabled,
          errorText: errorText,
          suffixIcon:
              trailingIcon ?? AppDropdownTheme.disclosureIcon(isDark),
        ),
        isEmpty: !hasValue,
        child: hasValue
            ? Text(
                display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppDropdownTheme.valueStyle(isDark),
              )
            : const SizedBox.shrink(),
      ),
    );

    if (!useExternalLabel) {
      return field;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label!,
          style: AppDropdownTheme.labelStyle(isDark).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 6.h),
        field,
      ],
    );
  }

  Widget _buildMinimal(BuildContext context, bool isDark, String? display) {
    final hasValue = display != null;

    return InkWell(
      onTap: enabled ? () => _openSheet(context) : null,
      borderRadius: BorderRadius.circular(14.r),
      child: InputDecorator(
        decoration: _resolveDecoration(
          isDark,
          display,
          useExternalLabel: false,
        ).copyWith(
          enabled: enabled,
          suffixIcon:
              trailingIcon ?? AppDropdownTheme.disclosureIcon(isDark),
        ),
        isEmpty: !hasValue,
        child: hasValue
            ? Text(
                display,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppDropdownTheme.valueStyle(isDark),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, bool isDark, String? display) {
    final bg = isDark ? const Color(0xFF1A2230) : const Color(0xFFF5F5F7);
    final text = display ?? _placeholderForField(useExternalLabel: false) ?? '';

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20.r),
      child: InkWell(
        onTap: enabled ? () => _openSheet(context) : null,
        borderRadius: BorderRadius.circular(20.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
          child: Row(
            mainAxisSize: isExpanded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (isExpanded)
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: display == null
                        ? AppDropdownTheme.labelStyle(isDark)
                            .copyWith(fontSize: 13.sp)
                        : AppDropdownTheme.valueStyle(isDark, fontSize: 13),
                  ),
                )
              else
                Text(
                  text,
                  style: display == null
                      ? AppDropdownTheme.labelStyle(isDark)
                          .copyWith(fontSize: 13.sp)
                      : AppDropdownTheme.valueStyle(isDark, fontSize: 13),
                ),
              SizedBox(width: 4.w),
              trailingIcon ??
                  Icon(
                    Symbols.unfold_more,
                    size: 18.sp,
                    color: AppColors.primary,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Form-integrated selection field with validation support.
class AppSelectionFormField<T> extends FormField<T> {
  AppSelectionFormField({
    super.key,
    super.initialValue,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
    super.enabled,
    required List<AppSelectionOption<T>> options,
    required ValueChanged<T?> onChanged,
    required String sheetTitle,
    String? hint,
    String? label,
    Widget? prefixIcon,
    bool isDark = false,
    AppSelectionStyle style = AppSelectionStyle.form,
    InputDecoration? decoration,
    bool nested = false,
    bool minimal = false,
    Widget? trailingIcon,
  }) : super(
          builder: (state) {
            return AppSelectionField<T>(
              value: state.value,
              options: options,
              onChanged: (value) {
                state.didChange(value);
                onChanged(value);
              },
              sheetTitle: sheetTitle,
              hint: hint,
              label: label,
              prefixIcon: prefixIcon,
              enabled: enabled,
              isDark: isDark,
              style: style,
              decoration: decoration,
              nested: nested,
              minimal: minimal,
              trailingIcon: trailingIcon,
              errorText: state.errorText,
            );
          },
        );
}
