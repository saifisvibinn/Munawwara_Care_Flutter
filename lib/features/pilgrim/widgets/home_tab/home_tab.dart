import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/safety_disclaimer_banner.dart';
import '../../helpers/moderator_navigation.dart';
import '../../providers/pilgrim_provider.dart';
import '../moderator_navigate_button.dart';
import '../sos/sos_button.dart';
import '../sos/sos_help_session_panel.dart';
import 'home_cards.dart';
import 'reassure_family_sheet.dart';
import '../../screens/live_translate_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Home Tab — fixed app bar; greeting + dashboard scroll below
// ─────────────────────────────────────────────────────────────────────────────

class PilgrimHomeTab extends StatelessWidget {
  final PilgrimState pilgrimState;
  final bool isDark;
  final WeatherAlert weatherAlert;
  final AnimationController sosPulseController;
  final AnimationController sosHoldController;
  final bool isSosHolding;
  final VoidCallback onSosHoldStart;
  final VoidCallback onSosHoldEnd;
  final Future<void> Function() onRefresh;
  final int sosCountdown;
  final Future<void> Function() onCancelSos;
  final Future<void> Function()? onCallBackSos;
  final bool showResolvedSosCard;
  final String sosHelpStatusKey;
  final String sosModeratorName;
  final Map<String, ModeratorBeacon> navBeacons;
  final LatLng? myLocation;
  final void Function(ModeratorBeacon) onNavigateToModerator;
  final int missedCallUnreadCount;
  final VoidCallback onMissedCallsTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onGroupCardTap;
  final VoidCallback onHotspotsTap;

  /// Opens weather tips / detail sheet (card remains tappable when not loading).
  final VoidCallback onWeatherTap;
  final bool isGpsEnabled;
  final bool hasLocPermission;
  final VoidCallback onLocationInactiveTap;
  final int callCooldownSeconds;

  /// From [authProvider] / prefs when pilgrim profile is not hydrated yet.
  final String? authFullName;

  const PilgrimHomeTab({
    super.key,
    required this.pilgrimState,
    required this.authFullName,
    required this.isDark,
    required this.weatherAlert,
    required this.sosPulseController,
    required this.sosHoldController,
    required this.isSosHolding,
    required this.onSosHoldStart,
    required this.onSosHoldEnd,
    required this.onRefresh,
    required this.sosCountdown,
    required this.onCancelSos,
    this.onCallBackSos,
    this.showResolvedSosCard = false,
    required this.sosHelpStatusKey,
    required this.sosModeratorName,
    required this.navBeacons,
    this.myLocation,
    required this.onNavigateToModerator,
    required this.missedCallUnreadCount,
    required this.onMissedCallsTap,
    required this.onSettingsTap,
    required this.onGroupCardTap,
    required this.onHotspotsTap,
    required this.onWeatherTap,
    required this.isGpsEnabled,
    required this.hasLocPermission,
    required this.onLocationInactiveTap,
    this.callCooldownSeconds = 0,
  });

  Widget _homeBody(GroupInfo? group) {
    return _HomeBody(
      isDark: isDark,
      pilgrimState: pilgrimState,
      group: group,
      weatherAlert: weatherAlert,
      sosPulseController: sosPulseController,
      sosHoldController: sosHoldController,
      isSosHolding: isSosHolding,
      sosCountdown: sosCountdown,
      onSosHoldStart: onSosHoldStart,
      onSosHoldEnd: onSosHoldEnd,
      onCancelSos: onCancelSos,
      onCallBackSos: onCallBackSos,
      showResolvedSosCard: showResolvedSosCard,
      sosHelpStatusKey: sosHelpStatusKey,
      sosModeratorName: sosModeratorName,
      onGroupCardTap: onGroupCardTap,
      onHotspotsTap: onHotspotsTap,
      onWeatherTap: onWeatherTap,
      navBeacons: navBeacons,
      myLocation: myLocation,
      onNavigateToModerator: onNavigateToModerator,
      callCooldownSeconds: callCooldownSeconds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final group = pilgrimState.groupInfo;
    final headerBg = isDark
        ? AppColors.backgroundDark
        : const Color(0xFFF7F9FB);

    return Container(
      color: headerBg,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 6.h),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10.r),
                    child: Image.asset(
                      'assets/static/inapp_icon.png',
                      width: 34.w,
                      height: 34.w,
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(width: 10.w),
                  Text(
                    'Munawwara Care',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: onMissedCallsTap,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Padding(
                          padding: EdgeInsets.all(10.w),
                          child: Icon(
                            Symbols.notifications,
                            size: 22.w,
                            color: AppColors.primary,
                          ),
                        ),
                        if (missedCallUnreadCount > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 5.w,
                                vertical: 2.h,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade600,
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              constraints: BoxConstraints(minWidth: 16.w),
                              child: Text(
                                // Show dynamic count
                                missedCallUnreadCount > 9
                                    ? '9+'
                                    : '$missedCallUnreadCount',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.sp,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'Lexend',
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  GestureDetector(
                    onTap: onSettingsTap,
                    child: Padding(
                      padding: EdgeInsets.all(10.w),
                      child: Icon(
                        Symbols.settings,
                        size: 22.w,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: onRefresh,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isGpsEnabled || !hasLocPermission)
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: Container(
                                  margin: EdgeInsets.only(top: 8.h, bottom: 8.h),
                                  child: Material(
                                    color: Colors.red.shade100,
                                    borderRadius: BorderRadius.circular(12.r),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12.r),
                                      onTap: onLocationInactiveTap,
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 16.w,
                                          vertical: 8.h,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Symbols.location_off,
                                              size: 16.w,
                                              color: Colors.red.shade700,
                                              fill: 1,
                                            ),
                                            SizedBox(width: 8.w),
                                            Text(
                                              'Inactive',
                                              style: TextStyle(
                                                fontFamily: 'Lexend',
                                                fontSize: 13.sp,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.red.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (navBeacons.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _homeBody(group),
                      )
                    else
                      SliverToBoxAdapter(child: _homeBody(group)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _HomeBody — rounded panel: cards, SOS, moderator navigation
// ─────────────────────────────────────────────────────────────────────────────

class _HomeBody extends StatelessWidget {
  final bool isDark;
  final PilgrimState pilgrimState;
  final GroupInfo? group;
  final WeatherAlert weatherAlert;
  final AnimationController sosPulseController;
  final AnimationController sosHoldController;
  final bool isSosHolding;
  final int sosCountdown;
  final VoidCallback onSosHoldStart;
  final VoidCallback onSosHoldEnd;
  final Future<void> Function() onCancelSos;
  final Future<void> Function()? onCallBackSos;
  final bool showResolvedSosCard;
  final String sosHelpStatusKey;
  final String sosModeratorName;
  final VoidCallback onGroupCardTap;
  final VoidCallback onHotspotsTap;
  final VoidCallback onWeatherTap;
  final Map<String, ModeratorBeacon> navBeacons;
  final LatLng? myLocation;
  final void Function(ModeratorBeacon) onNavigateToModerator;
  final int callCooldownSeconds;

  const _HomeBody({
    required this.isDark,
    required this.pilgrimState,
    required this.group,
    required this.weatherAlert,
    required this.sosPulseController,
    required this.sosHoldController,
    required this.isSosHolding,
    required this.sosCountdown,
    required this.onSosHoldStart,
    required this.onSosHoldEnd,
    required this.onCancelSos,
    this.onCallBackSos,
    this.showResolvedSosCard = false,
    required this.sosHelpStatusKey,
    required this.sosModeratorName,
    required this.onGroupCardTap,
    required this.onHotspotsTap,
    required this.onWeatherTap,
    required this.navBeacons,
    this.myLocation,
    required this.onNavigateToModerator,
    this.callCooldownSeconds = 0,
  });

  Widget _cardIcon(IconData iconData) {
    return Icon(
      iconData,
      color: const Color(0xFFF97316), // Premium Orange from mockup
      size: 28.w, // Direct icon with no background container
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final showHelp = pilgrimState.sosActive || showResolvedSosCard;
    final g = group;
    final activeBeacons = activeNavBeaconsForGroup(
      beacons: navBeacons,
      moderators: g?.moderators ?? const [],
      createdBy: g?.createdBy,
    );

    return Container(
      width: double.infinity,
      color: Colors.transparent,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 6.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Group Card (Full Width) ──────────────────────────────────────
            GroupCard(
              groupName: g?.groupName ?? 'card_no_group'.tr(),
              moderators: g?.moderators ?? const [],
              createdBy: g?.createdBy,
              hotelName: g?.hotelName ?? '',
              busNumber: g?.busNumber ?? '',
              checkIn: g?.checkIn ?? '',
              onTap: onGroupCardTap,
            ),
            if (activeBeacons.isNotEmpty) ...[
              SizedBox(height: 8.h),
              ModeratorNavigateBeaconList(
                beacons: activeBeacons,
                onNavigate: onNavigateToModerator,
              ),
            ],
            SizedBox(height: 26.h), // Pushed grid down slightly from GroupCard

            // ── Animated Switcher for help mode vs normal side-by-side mode ──
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: showHelp
                  ? Column(
                      key: const ValueKey<String>('show_help_active'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Redesigned flush SOS Help Session panel
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.h),
                          child: SosHelpSessionPanel(
                            isDark: isDark,
                            statusKey: sosHelpStatusKey,
                            moderatorName: sosModeratorName,
                            onCancelRequest: onCancelSos,
                            disableCancel:
                                sosHelpStatusKey == 'sos_status_being_handled',
                            showCancel:
                                sosHelpStatusKey != 'sos_status_resolved_friendly',
                            showCallBack:
                                sosHelpStatusKey == 'sos_status_callback_available',
                            onCallBack: onCallBackSos,
                            cooldownSeconds: callCooldownSeconds,
                            pulseController: sosPulseController,
                            onWeatherTap: onWeatherTap,
                            onHotspotsTap: onHotspotsTap,
                          ),
                        ),
                      ],
                    )
                  : Column(
                      key: const ValueKey<String>('show_help_idle'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ActionHubGrid(
                          topLeft: ScoopedGridCard(
                            position: CardPosition.topLeft,
                            icon: _cardIcon(
                              weatherAlert.isLoading || weatherAlert.isError
                                  ? Icons.wb_sunny_rounded
                                  : weatherAlert.icon,
                            ),
                            title: weatherAlert.isLoading || weatherAlert.isError
                                ? 'Weather'
                                : 'Weather (${weatherAlert.temperatureC}°C)',
                            subtext: weatherAlert.isLoading
                                ? 'Loading forecast...'
                                : weatherAlert.isError
                                    ? 'Forecast unavailable'
                                    : weatherAlert.conditionKey.tr(),
                            onTap: onWeatherTap,
                          ),
                          topRight: ScoopedGridCard(
                            position: CardPosition.topRight,
                            icon: _cardIcon(Icons.explore_rounded),
                            title: 'home_explore'.tr(),
                            subtext: 'home_explore_nearby'.tr(),
                            onTap: onHotspotsTap,
                          ),
                          bottomLeft: ScoopedGridCard(
                            position: CardPosition.bottomLeft,
                            icon: _cardIcon(Icons.translate_rounded),
                            title: 'Live Translate',
                            subtext: 'Speak & translate',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const LiveTranslateScreen(),
                                ),
                              );
                            },
                          ),
                          bottomRight: ScoopedGridCard(
                            position: CardPosition.bottomRight,
                            icon: _cardIcon(Icons.people_alt_rounded),
                            title: 'Reassure Family',
                            subtext: 'Share your safety',
                            onTap: () {
                              showReassureFamilyBottomSheet(context: context);
                            },
                          ),
                          sosButton: SosButton(
                            size: 136,
                            pulseController: sosPulseController,
                            holdController: sosHoldController,
                            isHolding: isSosHolding,
                            isLoading: pilgrimState.isSosLoading,
                            sosActive: pilgrimState.sosActive,
                            countdown: sosCountdown,
                            onHoldStart: onSosHoldStart,
                            onHoldEnd: onSosHoldEnd,
                          ),
                        ),
                        SizedBox(height: 24.h), // Pushed subtext down slightly
                        Text(
                          'sos_idle_subtext'.tr(),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            color: muted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
            ),
            SizedBox(height: 20.h), // Pushed SafetyDisclaimerBanner down slightly

            SafetyDisclaimerBanner(isDark: isDark),
          ],
        ),
      ),
    );
  }
}
