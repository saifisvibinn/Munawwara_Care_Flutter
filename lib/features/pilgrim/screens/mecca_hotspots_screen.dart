import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/explore_places_service.dart';
import '../../../core/theme/app_colors.dart';
import '../models/explore_place.dart';

/// Kaaba — used for distance when the pilgrim's GPS fix is unavailable.
const LatLng _kaaba = LatLng(21.422487, 39.826206);
const LatLng _medina = LatLng(24.467233, 39.611121);

class MeccaHotspotsScreen extends StatefulWidget {
  /// Pilgrim's current location when available (sorts by distance).
  final LatLng? anchorLocation;

  const MeccaHotspotsScreen({super.key, this.anchorLocation});

  @override
  State<MeccaHotspotsScreen> createState() => _MeccaHotspotsScreenState();
}

class _MeccaHotspotsScreenState extends State<MeccaHotspotsScreen> {
  static const _categoryKeys = <String?>[
    null,
    'food',
    'pharmacy',
    'hospital',
    'mosque',
    'shopping',
    'landmarks',
    'toilet',
    'drinking_water',
  ];

  LatLng? _gpsAnchor;
  StreamSubscription<Position>? _gpsSub;
  bool _reloadedAfterFirstFix = false;

  static const double _hubFallbackDistanceM = 200000; // 200km

  bool get _isOutsideHubs {
    final a = _gpsAnchor ?? widget.anchorLocation;
    if (a == null) return false;
    final dKaaba = Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      _kaaba.latitude,
      _kaaba.longitude,
    );
    final dMedina = Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      _medina.latitude,
      _medina.longitude,
    );
    return dKaaba > _hubFallbackDistanceM && dMedina > _hubFallbackDistanceM;
  }

  LatLng get _effectiveAnchor {
    final a = _gpsAnchor ?? widget.anchorLocation;
    if (a == null) return _kaaba;
    return _isOutsideHubs ? _kaaba : a;
  }

  /// Map center for “nearby” APIs.
  double get _centerLat => _effectiveAnchor.latitude;
  double get _centerLng => _effectiveAnchor.longitude;

  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  List<ExplorePlace> _loaded = [];
  List<ExplorePlace> _searchHits = [];
  bool _loading = true;
  bool _searchLoading = false;
  String? _error;
  int _selectedCategory = 0;

  bool _isUsableLastKnown(Position p) {
    final age = DateTime.now().difference(p.timestamp);
    if (age > const Duration(hours: 8)) return false;
    final acc = p.accuracy;
    if (acc.isInfinite || acc < 0) return false;
    return acc <= 8000;
  }

  void _setGpsAnchor(LatLng next) {
    final prev = _gpsAnchor;
    if (prev != null &&
        (prev.latitude - next.latitude).abs() < 0.000001 &&
        (prev.longitude - next.longitude).abs() < 0.000001) {
      return;
    }
    setState(() => _gpsAnchor = next);

    // Re-sort existing list immediately so distances update.
    if (_loaded.isNotEmpty) {
      _sortByDistance(_loaded);
      if (mounted) setState(() {});
    }

    // If we're within the hubs, reload once after the first fix to make sure
    // results are aligned to the user's real position. If outside, we keep
    // Kaaba fallback and show a coverage warning instead of per-place distance.
    if (!_reloadedAfterFirstFix && !_isOutsideHubs) {
      _reloadedAfterFirstFix = true;
      unawaited(_loadPlaces());
    }
  }

  Future<void> _initGpsAnchor() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (!mounted) return;
      if (last != null && _isUsableLastKnown(last)) {
        _setGpsAnchor(LatLng(last.latitude, last.longitude));
      }
    } catch (_) {}

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      _setGpsAnchor(LatLng(pos.latitude, pos.longitude));
    } catch (_) {}

    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 30,
      ),
    ).listen((pos) {
      if (!mounted) return;
      _setGpsAnchor(LatLng(pos.latitude, pos.longitude));
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initGpsAnchor());
    _loadPlaces();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _gpsSub?.cancel();
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final q = _searchController.text.trim();
    if (q.length < 2) {
      setState(() {
        _searchHits = [];
        _searchLoading = false;
      });
      return;
    }
    setState(() => _searchLoading = true);
    _searchDebounce = Timer(const Duration(milliseconds: 550), () async {
      try {
        final hits = await ExplorePlacesService.searchNearby(
          q,
          centerLat: _centerLat,
          centerLng: _centerLng,
        );
        if (!mounted) return;
        setState(() {
          _searchHits = hits;
          _searchLoading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _searchHits = [];
          _searchLoading = false;
        });
      }
    });
  }

  Future<void> _loadPlaces() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ExplorePlacesService.fetchNearbyPlaces(
        centerLat: _centerLat,
        centerLng: _centerLng,
      );
      if (!mounted) return;
      _sortByDistance(list);
      setState(() {
        _loaded = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'explore_error'.tr();
      });
    }
  }

  void _sortByDistance(List<ExplorePlace> list) {
    final anchor = _effectiveAnchor;
    list.sort((a, b) {
      final da = Geolocator.distanceBetween(
        anchor.latitude,
        anchor.longitude,
        a.latitude,
        a.longitude,
      );
      final db = Geolocator.distanceBetween(
        anchor.latitude,
        anchor.longitude,
        b.latitude,
        b.longitude,
      );
      return da.compareTo(db);
    });
  }

  double _distanceKm(ExplorePlace p) {
    final anchor = _effectiveAnchor;
    return ExplorePlacesService.distanceKm(
      anchor.latitude,
      anchor.longitude,
      p,
    );
  }

  List<ExplorePlace> get _activeSource {
    final q = _searchController.text.trim();
    if (q.length >= 2 && _searchHits.isNotEmpty) return _searchHits;
    return _loaded;
  }

  List<ExplorePlace> get _filtered {
    final key = _categoryKeys[_selectedCategory];
    final src = _activeSource;
    if (key == null) return src;
    return src.where((p) => p.categoryKey == key).toList();
  }

  Future<void> _openInMaps(ExplorePlace p) async {
    final ok = await _confirmOpenGoogleMaps();
    if (!ok) return;

    final uris = <Uri>[
      // Best on Android when Google Maps is installed.
      Uri.parse(
        'google.navigation:q=${p.latitude},${p.longitude}&mode=w',
      ),
      // Generic geo fallback.
      Uri.parse('geo:${p.latitude},${p.longitude}?q=${p.latitude},${p.longitude}'),
      // Web fallback.
      Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${p.latitude},${p.longitude}',
      ),
    ];

    for (final uri in uris) {
      try {
        final didLaunch = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (didLaunch) return;
      } catch (_) {}
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('explore_open_maps_failed_title'.tr()),
        content: SelectableText.rich(
          TextSpan(
            text: 'explore_open_maps_failed_body'.tr(),
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

  Future<bool> _confirmOpenGoogleMaps() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('explore_open_maps_title'.tr()),
        content: Text('explore_open_maps_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('dialog_cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('explore_open_maps_open'.tr()),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : const Color(0xFFF1F5F3),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: isDark ? Colors.white : AppColors.textDark,
        title: Text(
          'explore_nearby_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 22.sp,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 6.h, 16.w, 20.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 14.sp,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
                decoration: InputDecoration(
                  hintText: 'explore_search_hint'.tr(),
                  hintStyle: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    color: AppColors.textMutedLight,
                  ),
                  prefixIcon: Icon(
                    Symbols.search,
                    size: 24.w,
                    color: AppColors.textMutedLight,
                  ),
                  suffixIcon: _searchLoading
                      ? Padding(
                          padding: EdgeInsets.all(12.w),
                          child: SizedBox(
                            width: 20.w,
                            height: 20.w,
                            child: const CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Symbols.close, size: 22.w),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchHits = []);
                              },
                            )
                          : null,
                  filled: true,
                  fillColor: isDark ? AppColors.surfaceDark : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.r),
                    borderSide: const BorderSide(color: Color(0xFFE3E6E8)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.r),
                    borderSide: const BorderSide(color: Color(0xFFE3E6E8)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.r),
                    borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 12.h),
                ),
              ),
              SizedBox(height: 8.h),
              if (_isOutsideHubs)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    color: (isDark ? AppColors.surfaceDark : Colors.white)
                        .withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.info,
                        size: 18.w,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          'explore_outside_ksa_warning'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.textMutedLight
                                : AppColors.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_isOutsideHubs) SizedBox(height: 8.h),
              Text(
                'explore_osm_note'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 11.sp,
                  color: AppColors.textMutedLight,
                ),
              ),
              SizedBox(height: 10.h),
              SizedBox(
                height: 42.h,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categoryKeys.length,
                  separatorBuilder: (_, _) => SizedBox(width: 8.w),
                  itemBuilder: (context, index) {
                    final selectedChip = _selectedCategory == index;
                    final key = _categoryKeys[index];
                    final label = key == null
                        ? 'explore_cat_all'.tr()
                        : 'explore_cat_$key'.tr();
                    return GestureDetector(
                      onTap: () => setState(() => _selectedCategory = index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: EdgeInsets.symmetric(horizontal: 18.w),
                        decoration: BoxDecoration(
                          color: selectedChip
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : (isDark ? AppColors.surfaceDark : Colors.white),
                          borderRadius: BorderRadius.circular(22.r),
                          border: Border.all(
                            color: selectedChip
                                ? AppColors.primary
                                : const Color(0xFFD9DFE5),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF1D2244),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: 14.h),
              Expanded(
                child: _loading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            SizedBox(height: 16.h),
                            Text(
                              'explore_loading'.tr(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 14.sp,
                                color: AppColors.textMutedLight,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: EdgeInsets.all(24.w),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 14.sp,
                                      color: isDark ? Colors.white70 : AppColors.textDark,
                                    ),
                                  ),
                                  SizedBox(height: 20.h),
                                  FilledButton(
                                    onPressed: _loadPlaces,
                                    child: Text('explore_retry'.tr()),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : filtered.isEmpty
                            ? Center(
                                child: Text(
                                  'explore_empty'.tr(),
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 14.sp,
                                    color: AppColors.textMutedLight,
                                  ),
                                ),
                              )
                            : GridView.builder(
                                itemCount: filtered.length,
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12.w,
                                  mainAxisSpacing: 12.h,
                                  childAspectRatio: 0.68,
                                ),
                                itemBuilder: (context, index) {
                                  final place = filtered[index];
                                  return _ExplorePlaceCard(
                                    place: place,
                                    distanceKm: _distanceKm(place),
                                    useHaramFallback: widget.anchorLocation == null,
                                    hideDistance: _isOutsideHubs,
                                    isDark: isDark,
                                    onTap: () => _openInMaps(place),
                                    onNavigate: () => _openInMaps(place),
                                  );
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExplorePlaceCard extends StatelessWidget {
  final ExplorePlace place;
  final double distanceKm;
  final bool useHaramFallback;
  final bool hideDistance;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onNavigate;

  const _ExplorePlaceCard({
    required this.place,
    required this.distanceKm,
    required this.useHaramFallback,
    required this.hideDistance,
    required this.isDark,
    required this.onTap,
    required this.onNavigate,
  });

  Color get _color {
    switch (place.categoryKey) {
      case 'food':
        return const Color(0xFFE27D60);
      case 'pharmacy':
        return const Color(0xFF4F8A8B);
      case 'shopping':
        return const Color(0xFF8D7A66);
      case 'mosque':
        return const Color(0xFF386641);
      case 'hospital':
        return const Color(0xFFBC4749);
      case 'toilet':
      case 'drinking_water':
        return const Color(0xFF457B9D);
      default:
        return const Color(0xFF7DA0CA);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (hideDistance) {
      final distLabel = 'explore_outside_ksa_distance'.tr();
      return _buildCard(context, distLabel);
    }

    final String distValue = distanceKm < 1.0
        ? 'explore_distance_m'.tr(args: [(distanceKm * 1000).round().toString()])
        : 'explore_distance_km'.tr(args: [distanceKm.toStringAsFixed(1)]);
    final distLabel = useHaramFallback
        ? 'explore_distance_haram'.tr(args: [distValue])
        : distValue;
    return _buildCard(context, distLabel);
  }

  Widget _buildCard(BuildContext context, String distLabel) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20.r),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(20.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(12.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14.r),
                  child: SizedBox(
                    height: 88.h,
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _color.withValues(alpha: 0.85),
                            _color,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Icon(place.icon, size: 40.w, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 10.h),
                Text(
                  place.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F132B),
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'explore_cat_${place.categoryKey}'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 12.sp,
                    color: AppColors.textMutedLight,
                  ),
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(
                      Symbols.pin_drop,
                      size: 15.w,
                      color: isDark ? Colors.white70 : const Color(0xFF202545),
                    ),
                    SizedBox(width: 4.w),
                    Expanded(
                      child: Text(
                        distLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : const Color(0xFF202545),
                        ),
                      ),
                    ),
                    SizedBox(width: 6.w),
                    IconButton(
                      onPressed: onNavigate,
                      icon: Icon(
                        Symbols.directions,
                        size: 20.w,
                        color: AppColors.primary,
                      ),
                      tooltip: 'explore_navigate'.tr(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
