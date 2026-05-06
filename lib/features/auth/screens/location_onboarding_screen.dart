import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/services/location_permission_service.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/auth_provider.dart';

class LocationOnboardingScreen extends ConsumerStatefulWidget {
  const LocationOnboardingScreen({super.key});

  @override
  ConsumerState<LocationOnboardingScreen> createState() => _LocationOnboardingScreenState();
}

class _LocationOnboardingScreenState extends ConsumerState<LocationOnboardingScreen>
    with WidgetsBindingObserver {
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissionAndProceed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissionAndProceed();
    }
  }

  Future<void> _checkPermissionAndProceed() async {
    if (_isChecking) return;
    setState(() => _isChecking = true);
    
    final isGranted = await hasLocationAlwaysPermission();
    if (isGranted) {
      if (!mounted) return;
      final role = ref.read(authProvider).role;
      if (role == 'moderator') {
        context.go('/moderator-dashboard');
      } else {
        context.go('/pilgrim-dashboard');
      }
    } else {
      if (mounted) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _handleEnableLocation() async {
    final isGranted = await requestLocationPermissionsFlow();
    if (isGranted) {
      _checkPermissionAndProceed();
    } else {
      // If still not granted, open settings
      await openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false, // Prevent back navigation
      child: Scaffold(
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                
                // Icon
                Container(
                  width: 100.w,
                  height: 100.w,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Symbols.location_on,
                    size: 48.w,
                    color: AppColors.primary,
                  ),
                ),
                
                SizedBox(height: 32.h),
                
                // Title
                Text(
                  'Enable location to continue',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 24.sp,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
                
                SizedBox(height: 16.h),
                
                // Description
                Text(
                  'This app needs your location so your moderator can assist you and ensure your safety.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 15.sp,
                    height: 1.5,
                    color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
                  ),
                ),
                
                SizedBox(height: 24.h),
                
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Symbols.info, size: 24.w, color: AppColors.primary),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Text(
                          'Important: Please choose "Allow all the time" when prompted by your system settings.',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const Spacer(flex: 3),
                
                // Primary Button
                SizedBox(
                  width: double.infinity,
                  height: 56.h,
                  child: ElevatedButton(
                    onPressed: _isChecking ? null : _handleEnableLocation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                      elevation: 0,
                    ),
                    child: _isChecking
                        ? SizedBox(
                            width: 24.w,
                            height: 24.w,
                            child: const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Enable location',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                
                SizedBox(height: 32.h),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
