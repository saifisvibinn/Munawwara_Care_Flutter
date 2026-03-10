import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/services/notification_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    AppLogger.d('SplashScreen initState');
    _navigate();
  }

  Future<void> _navigate() async {
    // Wait for _restoreSession to finish (isRestoringSession → false) with a
    // minimum splash display time of 1.5 s for a polished UX. Add a hard
    // timeout so we don't stay stuck if prefs/restore hangs.
    AppLogger.d('SplashScreen waiting for auth restore');
    try {
      await Future.any([
        Future.wait([
          Future.doWhile(() async {
            await Future.delayed(const Duration(milliseconds: 50));
            return ref.read(authProvider).isRestoringSession;
          }),
          Future.delayed(const Duration(milliseconds: 1500)),
        ]),
        Future.delayed(const Duration(seconds: 5)),
      ]);
    } catch (_) {
      // ignore
    }
    if (!mounted) return;
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      final route = auth.role == 'moderator'
          ? '/moderator-dashboard'
          : '/pilgrim-dashboard';
      AppLogger.i('SplashScreen nav to authenticated $route');
      context.go(route);

      // Check for pending notification deep-link (cold-start scenario)
      final pending = NotificationService.consumePendingNotificationData();
      if (pending != null && pending.isNotEmpty) {
        AppLogger.i('SplashScreen: processing pending notification deep-link');
        // Small delay so the dashboard is mounted before we push the chat
        Future.delayed(const Duration(milliseconds: 600), () {
          NotificationService.navigateFromNotificationData(pending);
        });
      }
    } else {
      AppLogger.i('SplashScreen nav to login');
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLogger.d('SplashScreen build');
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: Stack(
        children: [
          // Background Pattern Overlay
          Positioned.fill(
            child: Opacity(
              opacity: 0.4,
              child: CustomPaint(painter: _IslamicPatternPainter()),
            ),
          ),

          // Decorative Gradient Glows (Top Left)
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

          // Decorative Gradient Glows (Bottom Right)
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

          // Main Content
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 3),

                // Logo Container (uses static image if available)
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
                          color: AppColors.primary.withValues(alpha: 
                            isDark ? 0.05 : 0.1,
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
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 32.h),

                // App Name & Tagline
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.lexend(
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
                    style: GoogleFonts.lexend(
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

                // Footer
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'splash_version'.tr().toUpperCase(),
                      style: GoogleFonts.lexend(
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

// Painter to explicitly recreate the "Islamic-pattern" background from the CSS
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
        // Draw the cross (M20 0L20 40M40 20L0 20)
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

        // Draw the circle (circle cx=20 cy=20 r=8)
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
