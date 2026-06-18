import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show BuildContext;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'location_permission_service.dart';
import 'tameny_location_service.dart';

/// OEM families that need extra autostart / background guidance on Android.
enum DeviceOemProfile {
  xiaomi,
  huawei,
  oppo,
  vivo,
  samsung,
  standard,
}

enum DeviceCareActionKind {
  location,
  battery,
  autostart,
  notifications,
  lockScreenCalls,
  backgroundAppRefresh,
}

class DeviceCareStep {
  const DeviceCareStep({
    required this.kind,
    required this.titleKey,
    required this.descriptionKey,
    required this.actionLabelKey,
    this.footnoteKey,
  });

  final DeviceCareActionKind kind;
  final String titleKey;
  final String descriptionKey;
  final String actionLabelKey;

  /// Optional extra line (e.g. location "Allow all the time").
  final String? footnoteKey;
}

class DeviceCareContent {
  const DeviceCareContent({
    required this.steps,
    required this.profile,
  });

  final List<DeviceCareStep> steps;
  final DeviceOemProfile profile;
}

/// Copy shown on the in-app mock settings row before opening system UI.
class DeviceCareSettingsGuide {
  const DeviceCareSettingsGuide({
    required this.titleKey,
    required this.instructionKey,
    required this.highlightLabelKey,
    required this.decoyLabelKeys,
  });

  final String titleKey;
  final String instructionKey;
  final String highlightLabelKey;
  final List<String> decoyLabelKeys;
}

/// Required permissions + Android OEM settings helpers.
class OemSettingsService {
  OemSettingsService._();

  static const _prefAutostartAck = 'device_care_autostart_ack_v1';
  static const _prefBatteryManualAck = 'device_care_battery_manual_ack_v1';
  static const _prefLockScreenCallAck = 'device_care_lock_screen_call_ack_v1';
  static const _prefBackgroundRefreshAck = 'device_care_ios_bg_refresh_ack_v1';
  static const _channel = MethodChannel('com.munawwaracare.android/oem_settings');

  static DeviceCareActionKind? _pendingReturnKind;

  static const _prefOnboardingSkipped = 'device_care_onboarding_skipped_v1';

  /// In-memory mirror of [_prefOnboardingSkipped] for sync reads.
  static bool _skippedForSession = false;

  /// Bumped when skip is set; dashboards ignore stale permission checks.
  static int _onboardingGate = 0;

  /// Whether the user chose "Skip for now" this session (sync, no I/O).
  static bool get isOnboardingSkippedForSession => _skippedForSession;

  /// Snapshot for canceling in-flight [shouldShowOnboardingOnResume] checks.
  static int get onboardingGate => _onboardingGate;

  /// Call when the user skips the permissions onboarding screen.
  static Future<void> markOnboardingSkippedForSession() async {
    _skippedForSession = true;
    _onboardingGate++;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefOnboardingSkipped, true);
  }

  static Future<bool> _hasSkippedOnboarding() async {
    if (_skippedForSession) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefOnboardingSkipped) ?? false;
  }

  static Future<void> _clearOnboardingSkip() async {
    _skippedForSession = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefOnboardingSkipped);
  }

  /// Cold start / splash: re-prompt when steps are pending (clears skip only then).
  static Future<bool> shouldShowOnboardingAtLaunch({String? role}) async {
    if (kIsWeb) return false;
    final pending = await loadPendingSteps(role: role);
    if (pending.isEmpty) return false;
    await _clearOnboardingSkip();
    return true;
  }

  /// Dashboard resume: honor skip until the next cold start via splash.
  static Future<bool> shouldShowOnboardingOnResume({
    int? gate,
    String? role,
  }) async {
    if (kIsWeb) return false;
    if (_skippedForSession) return false;
    if (gate != null && gate != _onboardingGate) return false;
    if (await _hasSkippedOnboarding()) return false;
    if (gate != null && gate != _onboardingGate) return false;
    final pending = await loadPendingSteps(role: role);
    return pending.isNotEmpty;
  }

  /// Location-dependent action: prompt again even after skip.
  static Future<bool> shouldShowOnboardingForLocationUse({String? role}) async {
    if (kIsWeb) return false;
    return !(await isLocationStepSatisfied(role));
  }

  static Future<bool> areAllStepsSatisfied({String? role}) async {
    final pending = await loadPendingSteps(role: role);
    return pending.isEmpty;
  }

  static Future<List<DeviceCareStep>> loadPendingSteps({String? role}) async {
    final profile = await detectOemProfile();
    return _pendingStepsForProfile(profile, role: role);
  }

  static Future<DeviceCareContent> loadContent({String? role}) async {
    final profile = await detectOemProfile();
    final pending = await _pendingStepsForProfile(profile, role: role);
    return DeviceCareContent(steps: pending, profile: profile);
  }

  static DeviceCareContent defaultContent() {
    if (!kIsWeb && Platform.isIOS) {
      return DeviceCareContent(
        steps: _buildIosStepsList(),
        profile: DeviceOemProfile.standard,
      );
    }
    const profile = DeviceOemProfile.standard;
    return DeviceCareContent(
      steps: _buildStepsList(profile, includeLockScreen: false),
      profile: profile,
    );
  }

  /// Call before opening system settings (tracks return for OEM steps).
  static void noteOpenedSettings(DeviceCareActionKind kind) {
    _pendingReturnKind = kind;
  }

  /// Re-check when user returns from system settings.
  static Future<void> onAppResumed() async {
    final kind = _pendingReturnKind;
    _pendingReturnKind = null;
    if (kind == null) return;
    switch (kind) {
      case DeviceCareActionKind.location:
      case DeviceCareActionKind.notifications:
        break;
      case DeviceCareActionKind.battery:
        await _reconcileBatteryAfterSettingsReturn();
        break;
      case DeviceCareActionKind.autostart:
        await _markAutostartAcknowledged();
        break;
      case DeviceCareActionKind.lockScreenCalls:
        await _reconcileLockScreenCallAfterSettingsReturn();
        break;
      case DeviceCareActionKind.backgroundAppRefresh:
        await markBackgroundRefreshManuallyAcknowledged();
        break;
    }
  }

  /// Xiaomi / Huawei / Oppo / Vivo: extra lock-screen call permissions.
  static bool profileNeedsOemLockScreenGuidance(DeviceOemProfile profile) {
    return profile == DeviceOemProfile.xiaomi ||
        profile == DeviceOemProfile.huawei ||
        profile == DeviceOemProfile.oppo ||
        profile == DeviceOemProfile.vivo;
  }

  /// Whether onboarding should include the lock-screen incoming-call step.
  static Future<bool> shouldOfferLockScreenCallStep(
    DeviceOemProfile profile,
  ) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    if (profileNeedsOemLockScreenGuidance(profile)) return true;
    try {
      final can = await FlutterCallkitIncoming.canUseFullScreenIntent();
      return can != true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _canUseFullScreenForCalls() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final can = await FlutterCallkitIncoming.canUseFullScreenIntent();
      return can == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isBatteryUnrestricted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final native = await _channel.invokeMethod<bool>('isBatteryUnrestricted');
      if (native != null) return native;
    } catch (_) {}
    return Permission.ignoreBatteryOptimizations.isGranted;
  }

  static Future<bool> openTtsSettings() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      try {
        final opened = await _channel.invokeMethod<bool>('openTtsSettings');
        return opened ?? false;
      } on PlatformException {
        return false;
      }
    }
    return false;
  }

  static Future<bool> isLocationStepSatisfied(String? role) =>
      isLocationSatisfiedForOnboarding(role);

  static Future<bool> isStepSatisfied(
    DeviceCareActionKind kind, {
    String? role,
  }) async {
    if (kIsWeb) return true;
    final prefs = await SharedPreferences.getInstance();
    switch (kind) {
      case DeviceCareActionKind.location:
        return isLocationStepSatisfied(role);
      case DeviceCareActionKind.battery:
        if (!Platform.isAndroid) return true;
        return await isBatteryUnrestricted() ||
            (prefs.getBool(_prefBatteryManualAck) ?? false);
      case DeviceCareActionKind.notifications:
        return Permission.notification.isGranted;
      case DeviceCareActionKind.autostart:
        if (!Platform.isAndroid) return true;
        return prefs.getBool(_prefAutostartAck) ?? false;
      case DeviceCareActionKind.lockScreenCalls:
        if (!Platform.isAndroid) return true;
        final profile = await detectOemProfile();
        if (profileNeedsOemLockScreenGuidance(profile)) {
          return prefs.getBool(_prefLockScreenCallAck) ?? false;
        }
        return await _canUseFullScreenForCalls();
      case DeviceCareActionKind.backgroundAppRefresh:
        if (!Platform.isIOS) return true;
        return prefs.getBool(_prefBackgroundRefreshAck) ?? false;
    }
  }

  static Future<void> _markAutostartAcknowledged() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutostartAck, true);
  }

  /// Escape hatch when native battery check is unreliable (Samsung, MIUI, etc.).
  static Future<void> markBatteryStepManuallyAcknowledged() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBatteryManualAck, true);
  }

  static Future<void> markLockScreenCallStepManuallyAcknowledged() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefLockScreenCallAck, true);
  }

  static Future<void> markBackgroundRefreshManuallyAcknowledged() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBackgroundRefreshAck, true);
  }

  static Future<void> _reconcileLockScreenCallAfterSettingsReturn() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (await _canUseFullScreenForCalls()) return;
    final profile = await detectOemProfile();
    if (profileNeedsOemLockScreenGuidance(profile)) {
      await markLockScreenCallStepManuallyAcknowledged();
    }
  }

  /// After the user returns from battery settings we opened.
  ///
  /// Stock Doze whitelist is enough on standard Android; OEM "no restrictions"
  /// screens (MIUI, etc.) are not visible to [isBatteryUnrestricted].
  static Future<void> _reconcileBatteryAfterSettingsReturn() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (await isBatteryUnrestricted()) return;
    final profile = await detectOemProfile();
    if (profile != DeviceOemProfile.standard) {
      await markBatteryStepManuallyAcknowledged();
    }
  }

  static DeviceCareSettingsGuide settingsGuideFor({
    required DeviceCareActionKind kind,
    required DeviceOemProfile profile,
  }) {
    return switch (kind) {
      DeviceCareActionKind.location => throw UnsupportedError(
        'Location uses the system permission dialog, not a guide sheet.',
      ),
      DeviceCareActionKind.battery => _batteryGuide(profile),
      DeviceCareActionKind.autostart => _autostartGuide(profile),
      DeviceCareActionKind.notifications => _notificationsGuide(profile),
      DeviceCareActionKind.lockScreenCalls => _lockScreenCallGuide(profile),
      DeviceCareActionKind.backgroundAppRefresh => _iosBackgroundRefreshGuide(),
    };
  }

  static Future<DeviceOemProfile> detectOemProfile() async {
    if (kIsWeb || !Platform.isAndroid) return DeviceOemProfile.standard;

    final nativeHaystack = await _readNativeHaystack();
    if (nativeHaystack != null && nativeHaystack.isNotEmpty) {
      return _profileFromHaystack(nativeHaystack);
    }

    try {
      final info = await DeviceInfoPlugin()
          .androidInfo
          .timeout(const Duration(seconds: 2));
      final haystack =
          '${info.brand} ${info.manufacturer} ${info.model}'.toLowerCase();
      return _profileFromHaystack(haystack);
    } on TimeoutException {
      return DeviceOemProfile.standard;
    } catch (_) {
      return DeviceOemProfile.standard;
    }
  }

  static Future<String?> _readNativeHaystack() async {
    try {
      final value = await _channel
          .invokeMethod<String>('getDeviceOemHaystack')
          .timeout(const Duration(milliseconds: 500));
      return value?.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  static DeviceOemProfile _profileFromHaystack(String haystack) {
    if (_containsAny(haystack, ['xiaomi', 'redmi', 'poco'])) {
      return DeviceOemProfile.xiaomi;
    }
    if (_containsAny(haystack, ['huawei', 'honor'])) {
      return DeviceOemProfile.huawei;
    }
    if (_containsAny(haystack, ['oppo', 'realme', 'oneplus'])) {
      return DeviceOemProfile.oppo;
    }
    if (_containsAny(haystack, ['vivo', 'iqoo'])) {
      return DeviceOemProfile.vivo;
    }
    if (_containsAny(haystack, ['samsung'])) {
      return DeviceOemProfile.samsung;
    }
    return DeviceOemProfile.standard;
  }

  static Future<List<DeviceCareStep>> _pendingStepsForProfile(
    DeviceOemProfile profile, {
    String? role,
  }) async {
    final all = await _stepsForProfile(profile);
    final pending = <DeviceCareStep>[];
    for (final step in all) {
      if (!await isStepSatisfied(step.kind, role: role)) {
        pending.add(step);
      }
    }
    return pending;
  }

  static Future<List<DeviceCareStep>> _stepsForProfile(
    DeviceOemProfile profile,
  ) async {
    if (!kIsWeb && Platform.isIOS) {
      return _buildIosStepsList();
    }
    final includeLock = await shouldOfferLockScreenCallStep(profile);
    return _buildStepsList(profile, includeLockScreen: includeLock);
  }

  /// iOS: location Always, notifications, Background App Refresh guidance.
  static List<DeviceCareStep> _buildIosStepsList() {
    return const [
      DeviceCareStep(
        kind: DeviceCareActionKind.location,
        titleKey: 'ios_setup_location_title',
        descriptionKey: 'ios_setup_location_desc',
        actionLabelKey: 'ios_setup_location_btn',
        footnoteKey: 'ios_setup_location_footnote',
      ),
      DeviceCareStep(
        kind: DeviceCareActionKind.notifications,
        titleKey: 'ios_setup_notifications_title',
        descriptionKey: 'ios_setup_notifications_desc',
        actionLabelKey: 'ios_setup_notifications_btn',
        footnoteKey: 'ios_setup_notifications_footnote',
      ),
      DeviceCareStep(
        kind: DeviceCareActionKind.backgroundAppRefresh,
        titleKey: 'ios_setup_bg_refresh_title',
        descriptionKey: 'ios_setup_bg_refresh_desc',
        actionLabelKey: 'ios_setup_bg_refresh_btn',
        footnoteKey: 'ios_setup_bg_refresh_footnote',
      ),
    ];
  }

  static List<DeviceCareStep> _buildStepsList(
    DeviceOemProfile profile, {
    required bool includeLockScreen,
  }) {
    final showAutostart = profile != DeviceOemProfile.standard &&
        profile != DeviceOemProfile.samsung;

    final steps = <DeviceCareStep>[
      const DeviceCareStep(
        kind: DeviceCareActionKind.location,
        titleKey: 'location_onboarding_title',
        descriptionKey: 'location_onboarding_desc',
        actionLabelKey: 'location_onboarding_btn',
        footnoteKey: 'location_onboarding_important',
      ),
    ];

    if (!kIsWeb && Platform.isAndroid) {
      steps.add(
        const DeviceCareStep(
          kind: DeviceCareActionKind.battery,
          titleKey: 'device_care_step_battery_title',
          descriptionKey: 'device_care_step_battery_desc',
          actionLabelKey: 'device_care_open_battery',
        ),
      );
      if (showAutostart) {
        steps.add(
          const DeviceCareStep(
            kind: DeviceCareActionKind.autostart,
            titleKey: 'device_care_step_autostart_title',
            descriptionKey: 'device_care_step_autostart_desc',
            actionLabelKey: 'device_care_open_autostart',
          ),
        );
      }
    }

    steps.add(
      const DeviceCareStep(
        kind: DeviceCareActionKind.notifications,
        titleKey: 'device_care_step_notifications_title',
        descriptionKey: 'device_care_step_notifications_desc',
        actionLabelKey: 'device_care_open_notifications',
      ),
    );

    if (includeLockScreen) {
      steps.add(
        DeviceCareStep(
          kind: DeviceCareActionKind.lockScreenCalls,
          titleKey: 'device_care_step_lock_screen_title',
          descriptionKey: 'device_care_step_lock_screen_desc',
          actionLabelKey: 'device_care_open_lock_screen',
          footnoteKey: _lockScreenFootnoteKey(profile),
        ),
      );
    }

    return steps;
  }

  static String? _lockScreenFootnoteKey(DeviceOemProfile profile) {
    return switch (profile) {
      DeviceOemProfile.xiaomi => 'device_care_step_lock_screen_footnote_xiaomi',
      DeviceOemProfile.huawei => 'device_care_step_lock_screen_footnote_huawei',
      DeviceOemProfile.oppo => 'device_care_step_lock_screen_footnote_oppo',
      DeviceOemProfile.vivo => 'device_care_step_lock_screen_footnote_vivo',
      DeviceOemProfile.samsung => 'device_care_step_lock_screen_footnote_samsung',
      DeviceOemProfile.standard =>
        'device_care_step_lock_screen_footnote_standard',
    };
  }

  static Future<bool> openStepAction(
    DeviceCareActionKind kind, {
    required BuildContext context,
    String? role,
  }) async {
    if (kIsWeb) return false;
    switch (kind) {
      case DeviceCareActionKind.location:
        final granted = await requestLocationPermissionsForOnboarding(
          context,
          role: role,
          onOpenAppSettings: () => noteOpenedSettings(kind),
        );
        if (granted &&
            context.mounted &&
            onboardingRequiresAlwaysLocation(role)) {
          await TamenyLocationService.enableTracking(
            context,
            forceSkipDisclosure: true,
            requestBatteryOptimization: false,
          );
        }
        return granted;
      case DeviceCareActionKind.notifications:
        noteOpenedSettings(kind);
        if (Platform.isAndroid) {
          try {
            final opened = await _channel.invokeMethod<bool>(
              'openNotificationSettings',
            );
            return opened ?? false;
          } on PlatformException {
            return false;
          }
        }
        final status = await Permission.notification.request();
        if (!status.isGranted) {
          await openAppSettings();
          return false;
        }
        return true;
      case DeviceCareActionKind.battery:
      case DeviceCareActionKind.autostart:
        if (!Platform.isAndroid) return false;
        noteOpenedSettings(kind);
        try {
          final method = kind == DeviceCareActionKind.battery
              ? 'openBatterySettings'
              : 'openAutostartSettings';
          final opened = await _channel.invokeMethod<bool>(method);
          if (opened == true) return true;
        } on PlatformException {
          // Fall through to native app details.
        }
        try {
          final watchKind = kind == DeviceCareActionKind.battery
              ? 'battery'
              : null;
          final opened = await _channel.invokeMethod<bool>(
            'openAppSettings',
            watchKind != null ? <String, dynamic>{'watchKind': watchKind} : null,
          );
          return opened ?? false;
        } on PlatformException {
          return false;
        }
      case DeviceCareActionKind.lockScreenCalls:
        noteOpenedSettings(kind);
        if (Platform.isAndroid) {
          try {
            final opened = await _channel.invokeMethod<bool>(
              'openLockScreenCallSettings',
            );
            return opened ?? false;
          } on PlatformException {
            return false;
          }
        }
        return false;
      case DeviceCareActionKind.backgroundAppRefresh:
        noteOpenedSettings(kind);
        await openAppSettings();
        return false;
    }
  }

  static DeviceCareSettingsGuide _batteryGuide(DeviceOemProfile profile) {
    final targetKey = switch (profile) {
      DeviceOemProfile.samsung => 'device_care_target_battery_samsung',
      DeviceOemProfile.xiaomi => 'device_care_target_battery_xiaomi',
      DeviceOemProfile.huawei => 'device_care_target_battery_huawei',
      DeviceOemProfile.oppo => 'device_care_target_battery_oppo',
      DeviceOemProfile.vivo => 'device_care_target_battery_vivo',
      DeviceOemProfile.standard => 'device_care_target_battery_standard',
    };
    return DeviceCareSettingsGuide(
      titleKey: 'device_care_guide_battery_title',
      instructionKey: 'device_care_guide_battery_instruction',
      highlightLabelKey: targetKey,
      decoyLabelKeys: const [
        'device_care_decoy_battery_saver',
        'device_care_decoy_adaptive_battery',
      ],
    );
  }

  static DeviceCareSettingsGuide _autostartGuide(DeviceOemProfile profile) {
    final targetKey = switch (profile) {
      DeviceOemProfile.xiaomi => 'device_care_target_autostart_xiaomi',
      DeviceOemProfile.huawei => 'device_care_target_autostart_huawei',
      DeviceOemProfile.oppo => 'device_care_target_autostart_oppo',
      DeviceOemProfile.vivo => 'device_care_target_autostart_vivo',
      _ => 'device_care_target_autostart_standard',
    };
    return DeviceCareSettingsGuide(
      titleKey: 'device_care_guide_autostart_title',
      instructionKey: 'device_care_guide_autostart_instruction',
      highlightLabelKey: targetKey,
      decoyLabelKeys: const [
        'device_care_decoy_other_app_a',
        'device_care_decoy_other_app_b',
      ],
    );
  }

  static DeviceCareSettingsGuide _notificationsGuide(DeviceOemProfile _) {
    return const DeviceCareSettingsGuide(
      titleKey: 'device_care_guide_notifications_title',
      instructionKey: 'device_care_guide_notifications_instruction',
      highlightLabelKey: 'device_care_target_notifications',
      decoyLabelKeys: [
        'device_care_decoy_silent_notifications',
        'device_care_decoy_lock_screen',
      ],
    );
  }

  static DeviceCareSettingsGuide _lockScreenCallGuide(DeviceOemProfile profile) {
    final targetKey = switch (profile) {
      DeviceOemProfile.xiaomi => 'device_care_target_lock_screen_xiaomi',
      DeviceOemProfile.huawei => 'device_care_target_lock_screen_huawei',
      DeviceOemProfile.oppo => 'device_care_target_lock_screen_oppo',
      DeviceOemProfile.vivo => 'device_care_target_lock_screen_vivo',
      DeviceOemProfile.samsung => 'device_care_target_lock_screen_samsung',
      DeviceOemProfile.standard => 'device_care_target_lock_screen_standard',
    };
    final instructionKey = switch (profile) {
      DeviceOemProfile.xiaomi => 'device_care_guide_lock_screen_instruction_xiaomi',
      DeviceOemProfile.standard =>
        'device_care_guide_lock_screen_instruction_standard',
      _ => 'device_care_guide_lock_screen_instruction',
    };
    return DeviceCareSettingsGuide(
      titleKey: 'device_care_guide_lock_screen_title',
      instructionKey: instructionKey,
      highlightLabelKey: targetKey,
      decoyLabelKeys: const [
        'device_care_decoy_lock_screen',
        'device_care_decoy_silent_notifications',
      ],
    );
  }

  static DeviceCareSettingsGuide _iosBackgroundRefreshGuide() {
    return const DeviceCareSettingsGuide(
      titleKey: 'ios_setup_bg_refresh_title',
      instructionKey: 'ios_setup_bg_refresh_desc',
      highlightLabelKey: 'ios_setup_bg_refresh_footnote',
      decoyLabelKeys: [],
    );
  }

  static bool _containsAny(String haystack, List<String> needles) {
    for (final needle in needles) {
      if (haystack.contains(needle)) return true;
    }
    return false;
  }
}
