import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/config/legal_config.dart';
import '../../../core/theme/app_colors.dart';

/// In-app privacy policy loaded from the published URL.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _isLoading = true;
              _loadError = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _isLoading = false;
              _loadError = error.description;
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(LegalConfig.privacyPolicyUrl));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;

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
          'legal_privacy_policy'.tr(),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18.sp,
            color: textPrimary,
          ),
        ),
      ),
      body: Stack(
        children: [
          if (_loadError != null)
            _LoadErrorPanel(
              message: _loadError!,
              onRetry: () {
                setState(() {
                  _loadError = null;
                  _isLoading = true;
                });
                _controller.loadRequest(
                  Uri.parse(LegalConfig.privacyPolicyUrl),
                );
              },
            )
          else
            WebViewWidget(controller: _controller),
          if (_isLoading && _loadError == null)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

class _LoadErrorPanel extends StatelessWidget {
  const _LoadErrorPanel({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SelectableText.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${'legal_privacy_load_error'.tr()}\n\n',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                      color: Colors.red.shade700,
                    ),
                  ),
                  TextSpan(
                    text: message,
                    style: TextStyle(
                      fontSize: 13.sp,
                      color: Colors.red.shade600,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20.h),
            FilledButton(
              onPressed: onRetry,
              child: Text('legal_retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
