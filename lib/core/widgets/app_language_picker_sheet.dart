import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../config/app_locales.dart';
import '../services/app_language_service.dart';
import '../widgets/app_selection_sheet.dart';

/// iOS Settings–style language picker: endonyms, single checkmark, sheet presentation.
Future<void> showAppLanguagePickerSheet({
  required BuildContext context,
  required String selectedCode,
  required bool isDark,
}) async {
  final result = await showAppSelectionSheet<String>(
    context: context,
    title: 'settings_language_title'.tr(),
    options: [
      for (final lang in AppLocales.profileLanguages)
        AppSelectionOption(value: lang.code, label: lang.nativeName),
    ],
    selectedValue: selectedCode,
    isDark: isDark,
  );

  if (result == null || !context.mounted) return;
  if (result.value == selectedCode) return;
  await AppLanguageService.apply(context, result.value!);
}
