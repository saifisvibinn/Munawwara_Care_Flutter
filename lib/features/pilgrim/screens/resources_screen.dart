
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';
import '../../auth/providers/auth_provider.dart';
import '../../moderator/widgets/moderator_map_widgets.dart';

import '../models/resource_models.dart';
import '../../moderator/screens/document_viewer_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models (Typedefs for public models)
// ─────────────────────────────────────────────────────────────────────────────

typedef _HotelRoom = HotelRoom;
typedef _Hotel = Hotel;
typedef _InsuranceHospital = InsuranceHospital;
typedef _Insurance = Insurance;

// ─────────────────────────────────────────────────────────────────────────────
// State & Notifier
// ─────────────────────────────────────────────────────────────────────────────

class _ResourcesState {
  final bool isLoading;
  final String? error;
  final List<_Hotel> hotels;
  final List<_Insurance> insurances;

  const _ResourcesState({
    this.isLoading = false,
    this.error,
    this.hotels = const [],
    this.insurances = const [],
  });

  _ResourcesState copyWith({
    bool? isLoading,
    String? error,
    List<_Hotel>? hotels,
    List<_Insurance>? insurances,
    bool clearError = false,
  }) =>
      _ResourcesState(
        isLoading: isLoading ?? this.isLoading,
        error: clearError ? null : (error ?? this.error),
        hotels: hotels ?? this.hotels,
        insurances: insurances ?? this.insurances,
      );
}

class _ResourcesNotifier extends Notifier<_ResourcesState> {
  @override
  _ResourcesState build() => const _ResourcesState();

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final results = await Future.wait([
        ApiService.dio.get('/resources/hotels'),
        ApiService.dio.get('/resources/insurances'),
      ]);

      List<_Hotel> hotels = [];
      List<_Insurance> insurances = [];

      final hotelsData = results[0].data;
      final hotelsRaw = hotelsData is Map<String, dynamic>
          ? (hotelsData['data'] as List<dynamic>? ?? [])
          : (hotelsData is List<dynamic> ? hotelsData : <dynamic>[]);
      hotels = hotelsRaw
          .map((h) => _Hotel.fromJson(Map<String, dynamic>.from(h as Map)))
          .toList();

      final insData = results[1].data;
      final insRaw = insData is Map<String, dynamic>
          ? (insData['data'] as List<dynamic>? ?? [])
          : (insData is List<dynamic> ? insData : <dynamic>[]);
      insurances = insRaw
          .map((i) => _Insurance.fromJson(Map<String, dynamic>.from(i as Map)))
          .toList();

      state = state.copyWith(
        isLoading: false,
        hotels: hotels,
        insurances: insurances,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }
}

final _resourcesProvider =
    NotifierProvider.autoDispose<_ResourcesNotifier, _ResourcesState>(
  _ResourcesNotifier.new,
);

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class ResourcesScreen extends ConsumerStatefulWidget {
  const ResourcesScreen({super.key});

  @override
  ConsumerState<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends ConsumerState<ResourcesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(_resourcesProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(_resourcesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isModerator = ref.watch(authProvider).role?.toLowerCase() == 'moderator';

    final bgColor =
        isDark ? AppColors.backgroundDark : const Color(0xFFF7F9FB);
    final headerBg = isDark ? AppColors.surfaceDark : Colors.white;
    final topInset = MediaQuery.paddingOf(context).top;
    final statusBarStyle = SystemUiOverlayStyle(
      statusBarColor: headerBg,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: statusBarStyle,
      child: Scaffold(
        backgroundColor: bgColor,
        body: Column(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: headerBg,
                border: Border(
                  bottom: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(top: topInset),
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(14.w, 6.h, 16.w, 0),
                      child: Row(
                        children: [
                          CircleButton(
                            icon: Symbols.arrow_back,
                            onTap: () => Navigator.of(context).pop(),
                            enableGlass: false,
                          ),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'resources_title'.tr(),
                                  style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? Colors.white
                                        : AppColors.textDark,
                                  ),
                                ),
                                Text(
                                  'resources_subtitle'.tr(),
                                  style: TextStyle(
                                    fontSize: 11.sp,
                                    color: isDark
                                        ? AppColors.textMutedLight
                                        : AppColors.textMutedDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (state.isLoading)
                            SizedBox(
                              width: 18.w,
                              height: 18.w,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            )
                          else
                            IconButton(
                              tooltip: 'Refresh',
                              icon: Icon(
                                Symbols.refresh,
                                color: AppColors.primary,
                                size: 22.w,
                              ),
                              onPressed: () => ref
                                  .read(_resourcesProvider.notifier)
                                  .load(),
                            ),
                        ],
                      ),
                    ),
                        SizedBox(height: 4.h),
                        TabBar(
                          controller: _tabController,
                          dividerColor: Colors.transparent,
                          dividerHeight: 0,
                          labelColor: AppColors.primary,
                          unselectedLabelColor: isDark
                              ? AppColors.textMutedLight
                              : AppColors.textMutedDark,
                          indicatorColor: AppColors.primary,
                          indicatorWeight: 2.5,
                          labelStyle: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.sp,
                          ),
                          unselectedLabelStyle: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13.sp,
                          ),
                          tabs: [
                            Tab(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Symbols.apartment, size: 16.w),
                                  SizedBox(width: 6.w),
                                  Text('resources_hotels'.tr()),
                                ],
                              ),
                            ),
                            Tab(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Symbols.health_and_safety, size: 16.w),
                                  SizedBox(width: 6.w),
                                  Text('resources_insurances'.tr()),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: AppScrollFadeOverlay(
                    showTop: false,
                    backgroundColor: bgColor,
                    child: state.isLoading && state.hotels.isEmpty
                      ? Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                      : state.error != null && state.hotels.isEmpty
                          ? _ErrorRetry(
                              isDark: isDark,
                              onRetry: () =>
                                  ref.read(_resourcesProvider.notifier).load(),
                            )
                          : TabBarView(
                              controller: _tabController,
                              children: [
                                _HotelsTab(
                                  hotels: state.hotels,
                                  isDark: isDark,
                                  isModerator: isModerator,
                                ),
                                _InsurancesTab(
                                  insurances: state.insurances,
                                  isDark: isDark,
                                  isModerator: isModerator,
                                ),
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
// Hotels Tab
// ─────────────────────────────────────────────────────────────────────────────

class _HotelsTab extends StatelessWidget {
  final List<_Hotel> hotels;
  final bool isDark;
  final bool isModerator;

  const _HotelsTab({
    required this.hotels,
    required this.isDark,
    required this.isModerator,
  });

  @override
  Widget build(BuildContext context) {
    final displayHotels =
        isModerator ? hotels : hotels.where((h) => h.active).toList();

    if (displayHotels.isEmpty) {
      return _EmptyState(
        isDark: isDark,
        icon: Symbols.apartment,
        message: 'resources_no_hotels'.tr(),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
      itemCount: displayHotels.length,
      separatorBuilder: (_, _) => SizedBox(height: 12.h),
      itemBuilder: (context, index) => _HotelCard(
        hotel: displayHotels[index],
        isDark: isDark,
        isModerator: isModerator,
      ),
    );
  }
}

class _HotelCard extends StatefulWidget {
  final _Hotel hotel;
  final bool isDark;
  final bool isModerator;

  const _HotelCard({
    required this.hotel,
    required this.isDark,
    required this.isModerator,
  });

  @override
  State<_HotelCard> createState() => _HotelCardState();
}

class _HotelCardState extends State<_HotelCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF25303A) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.hotel.rooms.isNotEmpty
                    ? () => setState(() => _expanded = !_expanded)
                    : null,
                child: Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Row(
                    children: [
                      Container(
                        width: 44.w,
                        height: 44.w,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFE0F2FE),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Icon(
                          Symbols.hotel,
                          color: isDark
                              ? const Color(0xFF38BDF8)
                              : const Color(0xFF0284C7),
                          size: 22.sp,
                          fill: 1,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.hotel.name,
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w800,
                                color: textPrimary,
                              ),
                            ),
                            if (widget.hotel.city.isNotEmpty ||
                                widget.hotel.address.isNotEmpty) ...[
                              SizedBox(height: 3.h),
                              Text(
                                [
                                  if (widget.hotel.city.isNotEmpty)
                                    widget.hotel.city,
                                  if (widget.hotel.address.isNotEmpty)
                                    widget.hotel.address,
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: textMuted,
                                ),
                              ),
                            ],
                            SizedBox(height: 6.h),
                            Row(
                              children: [
                                _InfoBadge(
                                  icon: Symbols.meeting_room,
                                  label:
                                      '${widget.hotel.rooms.length} ${'resources_rooms'.tr()}',
                                  isDark: isDark,
                                ),
                                if (widget.isModerator && !widget.hotel.active) ...[
                                  SizedBox(width: 8.w),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6.w,
                                      vertical: 2.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(4.r),
                                    ),
                                    child: Text(
                                      'Inactive',
                                      style: TextStyle(
                                        fontSize: 9.sp,
                                        color: Colors.red.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (widget.hotel.rooms.isNotEmpty)
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 250),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: textMuted,
                            size: 22.w,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: _RoomsList(
                rooms: widget.hotel.rooms,
                isDark: isDark,
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoomsList extends StatelessWidget {
  final List<_HotelRoom> rooms;
  final bool isDark;

  const _RoomsList({required this.rooms, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final dividerColor =
        isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFE2E8F0);
    final textMuted =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final textPrimary = isDark ? Colors.white : AppColors.textDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: dividerColor),
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 4.h),
          child: Text(
            'resources_rooms_list'.tr().toUpperCase(),
            style: TextStyle(
              fontSize: 9.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: textMuted,
            ),
          ),
        ),
        ...rooms.asMap().entries.map((e) {
          final i = e.key;
          final room = e.value;
          final roomNumber = room.roomNumber.trim();
          final floor = room.floor.trim();
          final roomLabel = roomNumber.isEmpty
              ? 'resources_room_unassigned'.tr()
              : 'resources_room_number'.tr(args: [roomNumber]);
          final floorLabel = floor.isEmpty
              ? 'resources_floor_unassigned'.tr()
              : 'resources_floor'.tr(args: [floor]);
          final capacityLabel = room.capacity <= 0
              ? 'resources_capacity_unassigned'.tr()
              : 'resources_capacity'.tr(args: ['${room.capacity}']);
          return Column(
            children: [
              if (i > 0) Divider(height: 1, color: dividerColor),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                child: Row(
                  children: [
                    Container(
                      width: 32.w,
                      height: 32.w,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.primary.withValues(alpha: 0.12)
                            : AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Center(
                        child: Icon(
                          Symbols.meeting_room,
                          size: 16.sp,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            roomLabel,
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          Text(
                            floorLabel,
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _InfoBadge(
                      icon: Symbols.person,
                      label: capacityLabel,
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
        SizedBox(height: 8.h),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Insurances Tab
// ─────────────────────────────────────────────────────────────────────────────

class _InsurancesTab extends StatelessWidget {
  final List<_Insurance> insurances;
  final bool isDark;
  final bool isModerator;

  const _InsurancesTab({
    required this.insurances,
    required this.isDark,
    required this.isModerator,
  });

  @override
  Widget build(BuildContext context) {
    final displayInsurances = isModerator
        ? insurances
        : insurances.where((i) => i.active).toList();

    if (displayInsurances.isEmpty) {
      return _EmptyState(
        isDark: isDark,
        icon: Symbols.health_and_safety,
        message: 'resources_no_insurances'.tr(),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
      itemCount: displayInsurances.length,
      separatorBuilder: (_, _) => SizedBox(height: 12.h),
      itemBuilder: (context, index) {
        final insurance = displayInsurances[index];
        final hasPolicy = isModerator &&
            insurance.policyDocumentUrl != null &&
            insurance.policyDocumentUrl!.isNotEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InsuranceCard(
              insurance: insurance,
              isDark: isDark,
              isModerator: isModerator,
            ),
            if (hasPolicy) ...[
              SizedBox(height: 8.h),
              _PolicyCard(insurance: insurance, isDark: isDark),
            ],
          ],
        );
      },
    );
  }
}

class _InsuranceCard extends StatefulWidget {
  final _Insurance insurance;
  final bool isDark;
  final bool isModerator;

  const _InsuranceCard({
    required this.insurance,
    required this.isDark,
    required this.isModerator,
  });

  @override
  State<_InsuranceCard> createState() => _InsuranceCardState();
}

class _InsuranceCardState extends State<_InsuranceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF25303A) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    final textMuted =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.insurance.hospitals.isNotEmpty
                    ? () => setState(() => _expanded = !_expanded)
                    : null,
                child: Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Row(
                    children: [
                      Container(
                        width: 44.w,
                        height: 44.w,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF14291F)
                              : const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Icon(
                          Symbols.health_and_safety,
                          color: isDark
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFF16A34A),
                          size: 22.sp,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.insurance.name,
                              style: TextStyle(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w800,
                                color: textPrimary,
                              ),
                            ),
                            SizedBox(height: 6.h),
                            Row(
                              children: [
                                _InfoBadge(
                                  icon: Symbols.local_hospital,
                                  label:
                                      '${widget.insurance.hospitals.length} ${'resources_hospitals'.tr()}',
                                  isDark: isDark,
                                  color: const Color(0xFF16A34A),
                                ),
                                if (widget.isModerator && !widget.insurance.active) ...[
                                  SizedBox(width: 8.w),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 6.w,
                                      vertical: 2.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(4.r),
                                    ),
                                    child: Text(
                                      'Inactive',
                                      style: TextStyle(
                                        fontSize: 9.sp,
                                        color: Colors.red.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (widget.insurance.hospitals.isNotEmpty)
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 250),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: textMuted,
                            size: 22.w,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: _HospitalsList(
                hospitals: widget.insurance.hospitals,
                isDark: isDark,
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 250),
            ),
          ],
        ),
      ),
    );
  }
}

class _PolicyCard extends StatelessWidget {
  final _Insurance insurance;
  final bool isDark;

  const _PolicyCard({
    required this.insurance,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final borderColor =
        isDark ? const Color(0xFF25303A) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    final textMuted =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20.r),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DocumentViewerScreen(
                url: insurance.policyDocumentProxyUrl!,
                title: insurance.name.isNotEmpty
                    ? '${insurance.name} · ${'view_policy'.tr()}'
                    : 'view_policy'.tr(),
              ),
            ),
          );
        },
        child: Ink(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Container(
                  width: 44.w,
                  height: 44.w,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    Symbols.picture_as_pdf,
                    color: isDark
                        ? const Color(0xFF60A5FA)
                        : const Color(0xFF2563EB),
                    size: 22.sp,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'view_policy'.tr(),
                        style: TextStyle(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w800,
                          color: textPrimary,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        'active_policy'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: textMuted,
                  size: 22.w,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HospitalsList extends StatelessWidget {
  final List<_InsuranceHospital> hospitals;
  final bool isDark;

  const _HospitalsList({required this.hospitals, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final dividerColor =
        isDark ? Colors.white.withValues(alpha: 0.07) : const Color(0xFFE2E8F0);
    final textMuted =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final textPrimary = isDark ? Colors.white : AppColors.textDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: dividerColor),
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 4.h),
          child: Text(
            'resources_hospitals_list'.tr().toUpperCase(),
            style: TextStyle(
              fontSize: 9.sp,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: textMuted,
            ),
          ),
        ),
        ...hospitals.asMap().entries.map((e) {
          final i = e.key;
          final hospital = e.value;
          return Column(
            children: [
              if (i > 0) Divider(height: 1, color: dividerColor),
              Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                child: Row(
                  children: [
                    Container(
                      width: 32.w,
                      height: 32.w,
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF14291F)
                            : const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Center(
                        child: Icon(
                          Symbols.local_hospital,
                          size: 16.sp,
                          color: isDark
                              ? const Color(0xFF4ADE80)
                              : const Color(0xFF16A34A),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hospital.name,
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                          ),
                          if (hospital.address.isNotEmpty)
                            Text(
                              hospital.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
        SizedBox(height: 8.h),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ─────────────────────────────────────────────────────────────────────────────

class _InfoBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  final Color? color;

  const _InfoBadge({
    required this.icon,
    required this.label,
    required this.isDark,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.primary;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: isDark ? 0.16 : 0.09),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11.sp, color: effectiveColor),
          SizedBox(width: 4.w),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.sp,
              fontWeight: FontWeight.w700,
              color: effectiveColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isDark;
  final IconData icon;
  final String message;

  const _EmptyState({
    required this.isDark,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 52.sp,
            color: (isDark ? AppColors.textMutedLight : AppColors.textMutedDark)
                .withValues(alpha: 0.4),
          ),
          SizedBox(height: 16.h),
          Text(
            message,
            style: TextStyle(
              fontSize: 14.sp,
              color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final bool isDark;
  final VoidCallback onRetry;

  const _ErrorRetry({required this.isDark, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.error_outline,
            size: 48.sp,
            color: Colors.red.shade400,
          ),
          SizedBox(height: 12.h),
          Text(
            'error_loading_data'.tr(),
            style: TextStyle(
              fontSize: 14.sp,
              color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
            ),
          ),
          SizedBox(height: 16.h),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: Icon(Symbols.refresh, size: 16.sp),
            label: Text(
              'retry'.tr(),
              style: const TextStyle(),
            ),
          ),
        ],
      ),
    );
  }
}
