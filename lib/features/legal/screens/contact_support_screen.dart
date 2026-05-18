import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/legal_config.dart';
import '../../../core/theme/app_colors.dart';

/// In-app support contact with copyable email and optional mail app launch.
class ContactSupportScreen extends StatefulWidget {
  const ContactSupportScreen({
    super.key,
    this.mailSubject,
    this.mailBody,
  });

  final String? mailSubject;
  final String? mailBody;

  @override
  State<ContactSupportScreen> createState() => _ContactSupportScreenState();
}

class _ContactSupportScreenState extends State<ContactSupportScreen> {
  bool _didCopy = false;

  Uri get _mailtoUri {
    final subject = widget.mailSubject ?? LegalConfig.appName;
    final query = <String, String>{'subject': subject};
    if (widget.mailBody != null && widget.mailBody!.isNotEmpty) {
      query['body'] = widget.mailBody!;
    }
    return Uri(
      scheme: 'mailto',
      path: LegalConfig.supportEmail,
      queryParameters: query,
    );
  }

  Future<void> _copyEmail() async {
    await Clipboard.setData(
      const ClipboardData(text: LegalConfig.supportEmail),
    );
    if (!mounted) return;
    setState(() => _didCopy = true);
  }

  Future<void> _openEmailApp() async {
    try {
      await launchUrl(_mailtoUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      await _copyEmail();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('legal_email_copied_title'.tr()),
          content: SelectableText.rich(
            TextSpan(
              text: 'legal_email_copied_body'.tr(),
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
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'legal_contact_support'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
            color: textPrimary,
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'legal_contact_support_intro'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 14.sp,
                color: textMuted,
                height: 1.45,
              ),
            ),
            SizedBox(height: 24.h),
            Container(
              padding: EdgeInsets.all(20.w),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'legal_contact_support_email_label'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      color: textMuted,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  SelectableText(
                    LegalConfig.supportEmail,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 16.sp,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20.h),
            SizedBox(
              height: 52.h,
              child: OutlinedButton.icon(
                onPressed: _copyEmail,
                icon: Icon(Icons.copy_rounded, size: 20.sp),
                label: Text(
                  _didCopy
                      ? 'legal_contact_support_copied'.tr()
                      : 'legal_contact_support_copy'.tr(),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            SizedBox(
              height: 52.h,
              child: FilledButton.icon(
                onPressed: _openEmailApp,
                icon: Icon(Icons.mail_outline_rounded, size: 20.sp),
                label: Text('legal_contact_support_open_email'.tr()),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
