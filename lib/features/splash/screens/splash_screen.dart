import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/bootstrap/app_startup_coordinator.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/services/notification_service.dart';
import '../../moderator/services/sos_alert_coordinator.dart';
import '../../../core/services/oem_settings_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _showPattern = false;

  @override
  void initState() {
    super.initState();
    AppLogger.d('SplashScreen initState');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _precacheDecorativeAssets();
      setState(() => _showPattern = true);
      unawaited(_navigate());
    });
  }

  Future<void> _precacheDecorativeAssets() async {
    if (!mounted) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final logoCache = (110.w * dpr).round();
    await Future.wait([
      precacheImage(
        ResizeImage(
          const AssetImage('assets/static/logo.jpeg'),
          width: logoCache,
          height: logoCache,
        ),
        context,
      ),
      precacheImage(
        const AssetImage('assets/static/empty_groups_light.png'),
        context,
      ),
      precacheImage(
        const AssetImage('assets/static/empty_groups_dark.png'),
        context,
      ),
    ]);
  }

  Future<void> _navigate() async {
    AppLogger.d('SplashScreen waiting for startup coordinator');
    try {
      await Future.any<void>([
        AppStartupCoordinator.prepareForNavigation(ref),
        Future.delayed(const Duration(seconds: 15)),
      ]);
    } catch (e, st) {
      AppLogger.e('SplashScreen startup failed: $e\n$st');
    }
    if (!mounted) return;

    final auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      final showPermissions =
          await OemSettingsService.shouldShowOnboardingAtLaunch();
      if (!mounted) return;
      if (showPermissions) {
        AppLogger.i('SplashScreen nav to permissions onboarding');
        context.go('/device-care-onboarding');
        return;
      }

      final route = auth.role == 'moderator'
          ? '/moderator-dashboard'
          : '/pilgrim-dashboard';
      AppLogger.i('SplashScreen nav to authenticated $route');
      context.go(route);

      final pending = NotificationService.consumePendingNotificationData();
      if (pending != null && pending.isNotEmpty) {
        final type =
            pending['notification_type']?.toString() ??
            pending['type']?.toString() ??
            '';
        if (type == 'sos_alert') {
          unawaited(
            SosAlertCoordinator.queueSosAlertIfStillActive(pending),
          );
        } else {
          AppLogger.i(
            'SplashScreen: processing pending notification deep-link',
          );
          Future.delayed(const Duration(milliseconds: 600), () {
            NotificationService.navigateFromNotificationData(pending);
          });
        }
      }
    } else {
      AppLogger.i('SplashScreen nav to login');
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final logoCache = (110.w * dpr).round();

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: Stack(
        children: [
          if (_showPattern)
            Positioned.fill(
              child: RepaintBoundary(
                child: Opacity(
                  opacity: 0.4,
                  child: CustomPaint(
                    painter: _IslamicPatternPainter(),
                  ),
                ),
              ),
            ),

          Positioned(
            top: -0.2 * 852.h,
            left: -0.2 * 393.w,
            width: 0.8 * 393.w,
            height: 0.4 * 852.h,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: -0.1 * 852.h,
            right: -0.1 * 393.w,
            width: 0.6 * 393.w,
            height: 0.3 * 852.h,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 80,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),

          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),

                Center(
                  child: Container(
                    width: 140.w,
                    height: 140.w,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(32.r),
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFF1F5F9),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(
                            alpha: isDark ? 0.05 : 0.1,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/static/logo.jpeg',
                        width: 110.w,
                        height: 110.w,
                        fit: BoxFit.contain,
                        cacheWidth: logoCache,
                        cacheHeight: logoCache,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 32.h),

                RichText(
                  text: TextSpan(
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 36.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                    children: const [
                      TextSpan(text: 'Munawwara '),
                      TextSpan(
                        text: 'Care',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 8.h),

                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40.w),
                  child: Text(
                    'splash_tagline'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                      color: isDark
                          ? AppColors.textMutedLight
                          : AppColors.textMutedDark,
                    ),
                  ),
                ),

                const Spacer(flex: 4),

                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'splash_version'.tr().toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.5,
                        color: isDark
                            ? AppColors.textMutedDark
                            : AppColors.textMutedLight,
                      ),
                    ),
                    SizedBox(height: 12.h),
                    Container(
                      width: 96.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(100.r),
                      ),
                    ),
                    SizedBox(height: 16.h),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IslamicPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const double tileSize = 40.0;

    for (double y = 0; y < size.height; y += tileSize) {
      for (double x = 0; x < size.width; x += tileSize) {
        canvas.drawLine(
          Offset(x + tileSize / 2, y),
          Offset(x + tileSize / 2, y + tileSize),
          paint,
        );
        canvas.drawLine(
          Offset(x, y + tileSize / 2),
          Offset(x + tileSize, y + tileSize / 2),
          paint,
        );
        canvas.drawCircle(
          Offset(x + tileSize / 2, y + tileSize / 2),
          8.0,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
