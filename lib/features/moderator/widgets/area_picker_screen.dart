import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/map/app_map_controller.dart';
import '../../../core/map/app_map_marker_cluster.dart';
import '../../../core/map/app_map_tiles.dart';
import '../../../core/map/widgets/app_platform_map.dart';
import '../../../core/services/location_permission_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass/app_glass.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../shared/providers/suggested_area_provider.dart';
import 'moderator_map_marker_data.dart';
import 'moderator_map_widgets.dart';
import 'active_meetpoint_card.dart';
import '../../shared/models/suggested_area_model.dart';
import '../../shared/widgets/area_ui_widgets.dart';

/// Area Picker Screen for selecting locations and scheduling meetpoints.
class AreaPickerScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String areaType;
  final LatLng? initialCenter;
  final SuggestedArea? existingArea;

  const AreaPickerScreen({
    super.key,
    required this.groupId,
    required this.areaType,
    this.initialCenter,
    this.existingArea,
  });

  @override
  ConsumerState<AreaPickerScreen> createState() => _AreaPickerScreenState();
}

class _AreaPickerScreenState extends ConsumerState<AreaPickerScreen>
    with WidgetsBindingObserver {
  final _mapController = createAppMapController();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _nameFocusNode = FocusNode();
  final _descFocusNode = FocusNode();
  final _sheetController = DraggableScrollableController();
  final _mapSearchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  LatLng? _pickedPoint;
  /// Map center while panning; finalized into [_pickedPoint] on camera idle.
  LatLng? _selectedLocation;
  bool _submitting = false;
  DateTime? _meetpointTime;
  int _reminderMinutes = 15;

  // UX State
  bool _isFullScreenMap = false;
  LatLng? _mapCenter;
  bool _recenteringGps = false;
  bool _mapSearchExpanded = false;
  Timer? _nominatimDebounce;
  List<Map<String, dynamic>> _nominatimResults = [];
  bool _nominatimLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.existingArea != null) {
      _nameController.text = widget.existingArea!.name;
      _descController.text = widget.existingArea!.description;
      final existing = LatLng(
        widget.existingArea!.latitude,
        widget.existingArea!.longitude,
      );
      _pickedPoint = existing;
      _selectedLocation = existing;
      _meetpointTime = widget.existingArea!.meetpointTime;
      _reminderMinutes = widget.existingArea!.reminderMinutes ?? 15;
    } else {
      _meetpointTime = DateTime.now();
      final defaultCenter =
          widget.initialCenter ?? const LatLng(21.4225, 39.8262);
      _pickedPoint = defaultCenter;
      _selectedLocation = defaultCenter;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(suggestedAreaProvider.notifier).load(widget.groupId);
      }
    });

    _nameController.addListener(() {
      if (mounted) setState(() {});
    });
    _mapSearchController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nominatimDebounce?.cancel();
    _mapController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _nameFocusNode.dispose();
    _descFocusNode.dispose();
    _mapSearchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (mounted) _syncSheetWithKeyboard();
  }

  void _syncSheetWithKeyboard() {
    if (!mounted || !_sheetController.isAttached) return;
    final searchFocused = _searchFocusNode.hasFocus;
    final hasFocus = _nameFocusNode.hasFocus ||
        _descFocusNode.hasFocus ||
        searchFocused;
    if (!hasFocus) return;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboard <= 0) return;
    final screenH = MediaQuery.sizeOf(context).height;
    if (screenH <= 0) return;
    final target = searchFocused
        ? 0.90
        : ((keyboard + 148.h) / screenH).clamp(0.44, 0.72);
    if (_sheetController.size < target - 0.015) {
      unawaited(
        _sheetController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  void _collapseMapSearch() {
    _nominatimDebounce?.cancel();
    _searchFocusNode.unfocus();
    setState(() {
      _mapSearchExpanded = false;
      _mapSearchController.clear();
      _nominatimResults = [];
      _nominatimLoading = false;
    });
  }

  void _expandMapSearch() {
    setState(() => _mapSearchExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocusNode.requestFocus();
      if (_sheetController.isAttached && _sheetController.size < 0.85) {
        unawaited(
          _sheetController.animateTo(
            0.90,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  void _scheduleNominatimSearch(String raw) {
    setState(() {});
    _nominatimDebounce?.cancel();
    final q = raw.trim();
    if (q.length < 3) {
      setState(() {
        _nominatimResults = [];
        _nominatimLoading = false;
      });
      return;
    }
    _nominatimDebounce = Timer(
      const Duration(milliseconds: 400),
      () => _fetchNominatim(q),
    );
  }

  Future<void> _fetchNominatim(String query) async {
    setState(() => _nominatimLoading = true);
    try {
      final dio = Dio();
      final resp = await dio.get(
        'https://nominatim.openstreetmap.org/search',
        queryParameters: {
          'q': query,
          'format': 'json',
          'limit': '8',
        },
        options: Options(headers: {'User-Agent': 'FlutterMunawwara/1.0'}),
      );
      if (!mounted) return;
      final rawList = resp.data as List<dynamic>? ?? [];
      final list = <Map<String, dynamic>>[];
      for (final e in rawList) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        final lat = double.tryParse('${m['lat']}');
        final lon = double.tryParse('${m['lon']}');
        final name = m['display_name'] as String?;
        if (lat == null || lon == null || name == null) continue;
        list.add({'display_name': name, 'lat': lat, 'lon': lon});
      }
      setState(() => _nominatimResults = list);
    } catch (_) {
      if (mounted) setState(() => _nominatimResults = []);
    } finally {
      if (mounted) setState(() => _nominatimLoading = false);
    }
  }

  void _applyNominatimPick(LatLng point, String? primaryLabel) {
    _nominatimDebounce?.cancel();
    _searchFocusNode.unfocus();
    setState(() {
      _pickedPoint = point;
      _selectedLocation = point;
      _mapController.move(point, AppMapTiles.clampMapZoom(15));
      if (primaryLabel != null && _nameController.text.trim().isEmpty) {
        _nameController.text = primaryLabel;
      }
      _mapSearchExpanded = false;
      _mapSearchController.clear();
      _nominatimResults = [];
      _nominatimLoading = false;
    });
  }

  Future<String?> _reverseGeocode(LatLng point) async {
    try {
      final dio = Dio();
      final resp = await dio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'lat': point.latitude,
          'lon': point.longitude,
          'format': 'json',
        },
        options: Options(headers: {'User-Agent': 'FlutterMunawwara/1.0'}),
      );
      return resp.data['display_name'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _recenterOnMe() async {
    if (_recenteringGps) return;
    setState(() => _recenteringGps = true);

    Position? lastKnown;
    try {
      final ok = await hasLocationAlwaysPermission();
      if (!ok) {
        if (mounted) {
          StandardSnackBar.showError(context, 'error_location_unavailable'.tr());
        }
        return;
      }

      // Fast path: fused / cached location (especially indoors vs cold GPS).
      lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        final age = DateTime.now().difference(lastKnown.timestamp);
        if (age.inMinutes < 30 && lastKnown.accuracy <= 5000) {
          final quick = LatLng(lastKnown.latitude, lastKnown.longitude);
          _mapController.move(quick, AppMapTiles.clampMapZoom(17));
          setState(() {
            _pickedPoint = quick;
            _selectedLocation = quick;
          });
        }
      }

      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 18),
          ),
        );
        if (!mounted) return;
        final point = LatLng(pos.latitude, pos.longitude);
        _mapController.move(point, AppMapTiles.clampMapZoom(17));
        setState(() {
          _pickedPoint = point;
          _selectedLocation = point;
        });
      } on TimeoutException {
        if (!mounted) return;
        if (lastKnown == null) {
          StandardSnackBar.showError(context, 'error_location_unavailable'.tr());
        } else {
          StandardSnackBar.showWarning(
            context,
            'area_location_refine_timeout'.tr(),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        StandardSnackBar.showError(context, 'error_location_unavailable'.tr());
      }
    } finally {
      if (mounted) setState(() => _recenteringGps = false);
    }
  }

  /// If [scheduled] is not after now, assume the next calendar day (e.g. 2:00
  /// after 23:06 on the same date → tomorrow at 02:00).
  DateTime _normalizeMeetpointDateTime(DateTime scheduled) {
    final now = DateTime.now();
    if (scheduled.isAfter(now)) {
      return scheduled;
    }
    return scheduled.add(const Duration(days: 1));
  }

  void _applyMeetpointSchedule(DateTime scheduled) {
    final normalized = _normalizeMeetpointDateTime(scheduled);
    final now = DateTime.now();
    if (!normalized.isAfter(now)) {
      if (mounted) {
        StandardSnackBar.showError(
          context,
          'Please select a future date and time.',
        );
      }
      return;
    }
    setState(() {
      _meetpointTime = normalized;
      final minutesUntil = normalized.difference(now).inMinutes;
      if (_reminderMinutes > 0 && _reminderMinutes >= minutesUntil) {
        _reminderMinutes = 0;
      }
    });
  }

  void _onSelectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _meetpointTime ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      final current = _meetpointTime ?? DateTime.now();
      _applyMeetpointSchedule(
        DateTime(
          picked.year,
          picked.month,
          picked.day,
          current.hour,
          current.minute,
        ),
      );
    }
  }

  void _onSelectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_meetpointTime ?? DateTime.now()),
    );
    if (picked != null) {
      final current = _meetpointTime ?? DateTime.now();
      _applyMeetpointSchedule(
        DateTime(
          current.year,
          current.month,
          current.day,
          picked.hour,
          picked.minute,
        ),
      );
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _pickedPoint == null) return;

    if (widget.areaType == 'meetpoint' && _meetpointTime != null) {
      final normalized = _normalizeMeetpointDateTime(_meetpointTime!);
      if (!normalized.isAfter(DateTime.now())) {
        StandardSnackBar.showError(
          context,
          'Please select a future date and time.',
        );
        return;
      }
      _meetpointTime = normalized;
    }

    setState(() => _submitting = true);
    
    bool success;
    String? errorMsg;

    if (widget.existingArea != null) {
      // Update Mode
      final (s, e) = await ref.read(suggestedAreaProvider.notifier).updateArea(
            groupId: widget.groupId,
            areaId: widget.existingArea!.id,
            name: name,
            description: _descController.text.trim(),
            latitude: _pickedPoint!.latitude,
            longitude: _pickedPoint!.longitude,
            meetpointTime: _meetpointTime,
            reminderMinutes: _reminderMinutes,
          );
      success = s;
      errorMsg = e;
    } else {
      // Create Mode
      final (s, e) = await ref.read(suggestedAreaProvider.notifier).addArea(
            groupId: widget.groupId,
            name: name,
            description: _descController.text.trim(),
            latitude: _pickedPoint!.latitude,
            longitude: _pickedPoint!.longitude,
            areaType: widget.areaType,
            meetpointTime: _meetpointTime,
            reminderMinutes: _reminderMinutes,
          );
      success = s;
      errorMsg = e;
    }

    if (!context.mounted) return;
    setState(() => _submitting = false);
    if (success) {
      if (mounted) Navigator.pop(context);
    } else {
      String msg = errorMsg ?? 'error_generic';
      if (msg.contains('meetpoint already exists')) {
        msg = 'area_meetpoint_exists';
      }
      StandardSnackBar.showError(context, msg);
    }
  }

  Future<void> _deleteActiveMeetpoint(String areaId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('area_delete_meetpoint_confirm_title'.tr()),
        content: Text('area_delete_meetpoint_confirm_message'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('cancel'.tr())),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AreaUiTheme.meetpointRed,
            ),
            child: Text('group_delete'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref.read(suggestedAreaProvider.notifier).deleteArea(widget.groupId, areaId);
      if (!mounted) return;
      if (success) {
        StandardSnackBar.showSuccess(context, 'area_deleted'.tr());
      } else {
        StandardSnackBar.showError(context, 'error_generic'.tr());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMeetpoint = widget.areaType == 'meetpoint';
    final accentColor = AreaUiTheme.accent(isDark, isMeetpoint: isMeetpoint);

    return Scaffold(
      backgroundColor: AreaUiTheme.sheetBg(isDark),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          _buildMapLayer(isDark, accentColor),
          if (_isFullScreenMap) _buildFullScreenMapOverlays(isDark, accentColor),
          if (!_isFullScreenMap)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AreaPickerFloatingNav(
                isDark: isDark,
                title: isMeetpoint
                    ? 'area_meetpoint'.tr()
                    : 'area_suggest'.tr(),
                onBack: () => Navigator.pop(context),
                onLocate: _recenterOnMe,
                isLocating: _recenteringGps,
              ),
            ),
          if (!_isFullScreenMap) _buildCenterPinOverlay(accentColor),
          _buildBottomSheet(isDark, accentColor, isMeetpoint),
        ],
      ),
    );
  }

  Widget _buildMapLayer(bool isDark, Color accentColor) {
    final center = _pickedPoint ??
        _selectedLocation ??
        widget.initialCenter ??
        const LatLng(21.4225, 39.8262);
    final areas = ref.watch(suggestedAreaProvider).areas;
    return Positioned.fill(
      child: AppPlatformMap(
        key: _mapController.mapViewKey,
        controller: _mapController,
        initialCenter: center,
        initialZoom: AppMapTiles.clampMapZoom(15),
        isDark: isDark,
        markers: ModeratorMapMarkers.areas(areas),
        iosNativeScrollEdges: AppGlassTheme.isIos && _isFullScreenMap,
        iosScrollEdgeTopHeight: _isFullScreenMap ? 120.h : null,
        iosScrollEdgeBottomHeight: _isFullScreenMap ? 200.h : null,
        onPositionChanged: (target, hasGesture) {
          if (_isFullScreenMap) {
            if (hasGesture) {
              _mapCenter = target;
            }
            return;
          }
          if (hasGesture) {
            // Avoid setState during pan — it rebuilds UiKitView and blocks gestures.
            _selectedLocation = target;
          } else {
            setState(() {
              _selectedLocation = target;
              _pickedPoint = target;
            });
          }
        },
        flutterLayers: (ctx) => [
          AppMapMarkerCluster.layer(
            markerChildBehavior: false,
            markers: [
              for (final a in areas)
                Marker(
                  point: LatLng(a.latitude, a.longitude),
                  width: 48.w,
                  height: 48.w,
                  child: Opacity(
                    opacity: 0.6,
                    child: AreaMapMarker(area: a),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Fixed center pin — map pans underneath (not a map marker).
  Widget _buildCenterPinOverlay(Color accentColor) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Transform.translate(
            offset: Offset(0, -22.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.location_on,
                  size: 48,
                  color: accentColor,
                  fill: 1,
                ),
                SizedBox(height: 4.h),
                Container(
                  width: 14.w,
                  height: 5.h,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullScreenMapOverlays(bool isDark, Color accentColor) {
    const topBandHeight = 120.0;
    const bottomBandHeight = 200.0;

    return Stack(
      children: [
        if (!AppGlassTheme.isIos) ...[
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: topBandHeight.h,
            child: AppScrollGlassEdge(
              height: topBandHeight.h,
              edge: AppScrollGlassEdgeSide.top,
              isDark: isDark,
              useBackdropBlur: false,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: bottomBandHeight.h,
            child: AppScrollGlassEdge(
              height: bottomBandHeight.h,
              edge: AppScrollGlassEdgeSide.bottom,
              isDark: isDark,
              tintColor: AppGlassTheme.mapVignetteTintColor(isDark),
              tintOpacity: isDark ? 0.5 : 0.32,
              useBackdropBlur: false,
            ),
          ),
        ],
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 6.h),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppGlassIconButton(
                  isDark: isDark,
                  icon: Symbols.arrow_back,
                  onTap: () => setState(() => _isFullScreenMap = false),
                  size: 42.w,
                ),
              ),
            ),
          ),
        ),
        Center(
          child: Transform.translate(
            offset: Offset(0, -22.h),
            child: Icon(
              Symbols.location_on,
              size: 52.w,
              color: accentColor,
              fill: 1,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 20.w,
          right: 20.w,
          bottom: MediaQuery.of(context).padding.bottom + 20.h,
          child: SafeArea(
            top: false,
            child: FilledButton.icon(
              onPressed: _showConfirmSelectionModal,
              icon: Icon(Symbols.check_circle, size: 22.w, color: Colors.white),
              label: Text(
                'area_confirm_pin'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 15.sp,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.r),
                ),
                elevation: 3,
                shadowColor: accentColor.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showConfirmSelectionModal() async {
    final point = _mapCenter ?? _mapController.center;
    final address = await _reverseGeocode(point);

    if (!mounted) return;

    final isMeetpoint = widget.areaType == 'meetpoint';
    final accentColor = AreaUiTheme.accent(
      Theme.of(context).brightness == Brightness.dark,
      isMeetpoint: isMeetpoint,
    );

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final sheetDark = Theme.of(ctx).brightness == Brightness.dark;
        final textPrimary =
            sheetDark ? AppColors.textLight : AppColors.textDark;

        return AreaSheetScaffold(
          isDark: sheetDark,
          edgeToEdge: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.location_on,
                size: 40.w,
                color: accentColor,
                fill: 1,
              ),
              SizedBox(height: 14.h),
              Text(
                address ?? 'area_selected_location_label'.tr(),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: textPrimary,
                ),
              ),
              SizedBox(height: 24.h),
              AreaPrimaryButton(
                label: 'area_use_this_location'.tr(),
                accentColor: accentColor,
                onPressed: () {
                  setState(() {
                    _pickedPoint = point;
                    _selectedLocation = point;
                    _isFullScreenMap = false;
                    if (address != null) {
                      _nameController.text =
                          address.split(',').first.trim();
                    }
                  });
                  Navigator.pop(ctx);
                },
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'area_keep_searching'.tr(),
                  style: TextStyle(
                    color: AreaUiTheme.sectionLabel(sheetDark),
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Lexend',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomSheet(bool isDark, Color accentColor, bool isMeetpoint) {
    if (_isFullScreenMap) return const SizedBox.shrink();

    final keyboardBottom = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardOpen = keyboardBottom > 0;

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        if (notification.extent <= notification.minExtent + 0.02) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _sheetController,
        initialChildSize: 0.44,
        minChildSize: 0.08,
        maxChildSize: 0.92,
        snap: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: AreaUiTheme.sheetBg(isDark),
              borderRadius: BorderRadius.vertical(top: Radius.circular(26.r)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16.w,
                  10.h,
                  16.w,
                  keyboardBottom +
                      (keyboardOpen ? 8.h : MediaQuery.paddingOf(context).bottom + 16.h),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: AreaSheetGrabber(isDark: isDark)),
                    SizedBox(height: 12.h),
                    if (_mapSearchExpanded) ...[
                      AreaInsetGroup(
                        isDark: isDark,
                        children: [
                          AreaInsetSearchRow(
                            isDark: isDark,
                            accentColor: accentColor,
                            controller: _mapSearchController,
                            hint: 'area_search_hint'.tr(),
                            focusNode: _searchFocusNode,
                            onChanged: _scheduleNominatimSearch,
                            onCollapse: _collapseMapSearch,
                            showClear: _mapSearchController.text.isNotEmpty,
                            onClear: () {
                              _mapSearchController.clear();
                              setState(() {
                                _nominatimResults = [];
                                _nominatimLoading = false;
                              });
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                      _buildSearchSuggestionsPanel(isDark, accentColor),
                    ] else ...[
                      AreaSheetTitle(
                        isDark: isDark,
                        title: isMeetpoint
                            ? 'area_meetpoint'.tr()
                            : 'area_suggest'.tr(),
                      ),
                      SizedBox(height: 14.h),
                      AreaMapToolsGroup(
                        isDark: isDark,
                        accentColor: accentColor,
                        searchLabel: 'area_search_area'.tr(),
                        movePinLabel: 'area_move_pin'.tr(),
                        onSearch: _expandMapSearch,
                        onMovePin: _openFullscreenMapPicker,
                      ),
                      SizedBox(height: 12.h),
                      if (isMeetpoint &&
                          ref.watch(suggestedAreaProvider).activeMeetpoint !=
                              null) ...[
                        ActiveMeetpointCard(
                          activeMp: ref
                              .watch(suggestedAreaProvider)
                              .activeMeetpoint!,
                          isDark: isDark,
                          onDelete: () => _deleteActiveMeetpoint(
                            ref.read(suggestedAreaProvider).activeMeetpoint!.id,
                          ),
                        ),
                        SizedBox(height: 12.h),
                      ],
                      AreaSectionLabel(
                        isDark: isDark,
                        label: 'area_name_desc_header'.tr(),
                      ),
                      AreaInsetGroup(
                        isDark: isDark,
                        children: [
                          AreaInsetTextRow(
                            isDark: isDark,
                            icon: isMeetpoint
                                ? Symbols.location_on
                                : Symbols.pin_drop,
                            iconColor: accentColor,
                            controller: _nameController,
                            hint: 'area_name_hint'.tr(),
                            focusNode: _nameFocusNode,
                          ),
                          AreaInsetTextRow(
                            isDark: isDark,
                            icon: Symbols.description,
                            iconColor: accentColor,
                            controller: _descController,
                            hint: 'area_desc_hint'.tr(),
                            maxLines: 4,
                            minLines: 2,
                            focusNode: _descFocusNode,
                          ),
                        ],
                      ),
                      if (isMeetpoint) ...[
                        SizedBox(height: 16.h),
                        AreaSectionLabel(
                          isDark: isDark,
                          label: 'area_schedule_title'.tr(),
                        ),
                        AreaInsetGroup(
                          isDark: isDark,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _buildScheduleHalf(
                                    isDark: isDark,
                                    accentColor: accentColor,
                                    icon: Symbols.calendar_today,
                                    value: _meetpointTime == null
                                        ? 'area_select_date'.tr()
                                        : DateFormat('MMM dd, yyyy')
                                            .format(_meetpointTime!),
                                    onTap: _onSelectDate,
                                  ),
                                ),
                                Container(
                                  width: 0.5,
                                  height: 44.h,
                                  color: AreaUiTheme.divider(isDark),
                                ),
                                Expanded(
                                  child: _buildScheduleHalf(
                                    isDark: isDark,
                                    accentColor: accentColor,
                                    icon: Symbols.schedule,
                                    value: _meetpointTime == null
                                        ? 'area_select_time'.tr()
                                        : DateFormat('hh:mm a')
                                            .format(_meetpointTime!),
                                    onTap: _onSelectTime,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 16.h),
                        AreaSectionLabel(
                          isDark: isDark,
                          label: 'area_reminder_label'.tr(),
                        ),
                        _buildReminderSegmented(isDark, accentColor),
                      ],
                      SizedBox(height: 20.h),
                      AreaPrimaryButton(
                        label: widget.existingArea != null
                            ? (isMeetpoint
                                ? 'area_update_meetpoint'.tr()
                                : 'area_update_suggestion'.tr())
                            : (isMeetpoint
                                ? 'area_set_meetpoint'.tr()
                                : 'area_add_suggestion'.tr()),
                        accentColor: accentColor,
                        isLoading: _submitting,
                        onPressed: _submitting ? null : _submit,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildScheduleHalf({
    required bool isDark,
    required Color accentColor,
    required IconData icon,
    required String value,
    required VoidCallback onTap,
  }) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          child: Row(
            children: [
              Icon(icon, size: 18.w, color: accentColor),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w500,
                    color: textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReminderSegmented(bool isDark, Color accentColor) {
    final minutesUntil = _meetpointTime?.difference(DateTime.now()).inMinutes;
    final outline = AreaUiTheme.divider(isDark);
    final textMuted = AreaUiTheme.sectionLabel(isDark);

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: accentColor,
              secondary: accentColor,
            ),
      ),
      child: SegmentedButton<int>(
        segments: [0, 5, 15, 30, 60].map((mins) {
          final disabled =
              mins > 0 && minutesUntil != null && minutesUntil <= mins;
          return ButtonSegment<int>(
            value: mins,
            enabled: !disabled,
            label: Text(
              mins == 0 ? 'area_reminder_none'.tr() : '${mins}m',
              style: TextStyle(fontSize: 11.sp),
            ),
          );
        }).toList(),
        selected: {_reminderMinutes},
        onSelectionChanged: (next) {
          if (next.isNotEmpty) setState(() => _reminderMinutes = next.first);
        },
        multiSelectionEnabled: false,
        emptySelectionAllowed: false,
        showSelectedIcon: false,
        style: ButtonStyle(
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: outline)),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return textMuted;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return accentColor;
            return Colors.transparent;
          }),
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'Lexend',
              fontWeight: FontWeight.w600,
              fontSize: 11.sp,
            ),
          ),
        ),
      ),
    );
  }

  /// Keeps the suggestions list filling the expanded search sheet.
  double _suggestionsListMaxHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    const chromeHeight = 120.0;
    final sheetFraction = _mapSearchExpanded ? 0.90 : 0.44;
    final sheetHeight = mq.size.height * sheetFraction;
    final available = sheetHeight -
        chromeHeight -
        keyboard -
        mq.padding.bottom -
        24;
    return available.clamp(72.0, 420.h);
  }

  void _openFullscreenMapPicker() {
    setState(() => _isFullScreenMap = true);
  }

  Widget _buildSearchSuggestionsPanel(bool isDark, Color accentColor) {
    final q = _mapSearchController.text.trim();
    if (!_mapSearchExpanded || q.length < 3) {
      return const SizedBox.shrink(key: ValueKey('sug_hidden'));
    }
    final maxListHeight = _suggestionsListMaxHeight(context);
    final muted = AreaUiTheme.sectionLabel(isDark);
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;

    if (_nominatimLoading && _nominatimResults.isEmpty) {
      return AreaInsetGroup(
        key: const ValueKey('sug_loading'),
        isDark: isDark,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20.h),
            child: Center(
              child: SizedBox(
                width: 24.w,
                height: 24.w,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: accentColor,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (!_nominatimLoading && _nominatimResults.isEmpty) {
      return AreaInsetGroup(
        key: const ValueKey('sug_empty'),
        isDark: isDark,
        children: [
          Padding(
            padding: EdgeInsets.all(16.w),
            child: Text(
              'area_no_places_found'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                color: muted,
              ),
            ),
          ),
        ],
      );
    }

    return AreaInsetGroup(
      key: ValueKey('sug_list_${_nominatimResults.length}'),
      isDark: isDark,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            itemCount: _nominatimResults.length,
            separatorBuilder: (context, index) => Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 14.w,
              color: AreaUiTheme.divider(isDark),
            ),
            itemBuilder: (context, i) {
              final r = _nominatimResults[i];
              final name = r['display_name'] as String;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    final p = LatLng(r['lat'] as double, r['lon'] as double);
                    final label = name.split(',').first.trim();
                    _applyNominatimPick(p, label);
                  },
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.w,
                      vertical: 12.h,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Symbols.location_on,
                          size: 20.w,
                          color: muted,
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13.sp,
                              height: 1.35,
                              color: textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
