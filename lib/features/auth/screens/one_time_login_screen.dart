import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';

class OneTimeLoginScreen extends ConsumerStatefulWidget {
  final bool startWithQr;

  const OneTimeLoginScreen({super.key, this.startWithQr = false});

  @override
  ConsumerState<OneTimeLoginScreen> createState() => _OneTimeLoginScreenState();
}

class _OneTimeLoginScreenState extends ConsumerState<OneTimeLoginScreen> {
  final _codeController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();

  bool _isScanning = false;
  bool _scanHandled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _isScanning = widget.startWithQr;
  }

  @override
  void dispose() {
    _codeController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  String _extractToken(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return '';

    final uri = Uri.tryParse(raw);
    if (uri != null) {
      final qpToken = uri.queryParameters['token'];
      if (qpToken != null && qpToken.trim().isNotEmpty) {
        return qpToken.trim();
      }
    }

    return raw;
  }

  Future<void> _performOneTimeLogin(String rawToken) async {
    final token = _extractToken(rawToken);
    if (token.isEmpty) {
      setState(() => _error = 'Invalid login token');
      return;
    }

    setState(() => _error = null);
    final success = await ref
        .read(authProvider.notifier)
        .loginWithOneTimeToken(token: token);

    if (!mounted) return;

    if (success) {
      final role = ref.read(authProvider).role;
      if (role == 'moderator') {
        context.go('/moderator-dashboard');
      } else {
        context.go('/pilgrim-dashboard');
      }
    } else {
      setState(() {
        _error = ref.read(authProvider).error ?? 'One-time login failed';
      });
      _scanHandled = false;
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanHandled || ref.read(authProvider).isLoading) return;
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null || code.trim().isEmpty) return;

    _scanHandled = true;
    _scannerController.stop();
    void _ = _performOneTimeLogin(code);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLoading = ref.watch(authProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'One-Time Login',
          style: GoogleFonts.lexend(fontWeight: FontWeight.w600),
        ),
      ),
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: Padding(
        padding: EdgeInsets.all(20.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : const Color(0xffe2e8f0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Login with your moderator-issued QR or code.',
                    style: GoogleFonts.lexend(
                      fontSize: 13.sp,
                      color: isDark
                          ? AppColors.textMutedLight
                          : AppColors.textMutedDark,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isScanning = true;
                              _error = null;
                              _scanHandled = false;
                            });
                          },
                          icon: const Icon(Symbols.qr_code_scanner),
                          label: const Text('Scan QR'),
                        ),
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _isScanning = false;
                              _error = null;
                            });
                          },
                          icon: const Icon(Symbols.password),
                          label: const Text('Enter Code'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(height: 16.h),

            Expanded(
              child: _isScanning
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(16.r),
                      child: MobileScanner(
                        controller: _scannerController,
                        onDetect: _onDetect,
                      ),
                    )
                  : Container(
                      padding: EdgeInsets.all(16.w),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.surfaceDark : Colors.white,
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _codeController,
                            decoration: InputDecoration(
                              labelText: 'One-time token/code',
                              hintText: 'Paste token or mcare://... QR value',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                            ),
                          ),
                          SizedBox(height: 14.h),
                          ElevatedButton.icon(
                            onPressed: isLoading
                                ? null
                                : () => _performOneTimeLogin(
                                    _codeController.text,
                                  ),
                            icon: const Icon(Symbols.login),
                            label: Text(
                              isLoading ? 'Logging in...' : 'Login now',
                            ),
                          ),
                        ],
                      ),
                    ),
            ),

            if (_error != null) ...[
              SizedBox(height: 12.h),
              Text(
                _error!,
                style: GoogleFonts.lexend(color: Colors.red, fontSize: 12.sp),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
