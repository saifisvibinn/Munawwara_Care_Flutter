import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../providers/app_version_provider.dart';

/// Shows the current app version from [appVersionProvider].
class AppVersionLabel extends ConsumerWidget {
  const AppVersionLabel({
    super.key,
    required this.textColor,
    this.fontSize,
    this.textAlign = TextAlign.center,
  });

  final Color textColor;
  final double? fontSize;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionAsync = ref.watch(appVersionProvider);
    return versionAsync.when(
      data: (info) => Text(
        'about_version_value'.tr(
          namedArgs: {
            'version': info.version,
            'build': info.buildNumber,
          },
        ),
        textAlign: textAlign,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: (fontSize ?? 12).sp,
          color: textColor,
        ),
      ),
      loading: () => SizedBox(
        height: (fontSize ?? 12).sp,
        width: 16.w,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: textColor.withValues(alpha: 0.5),
        ),
      ),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
