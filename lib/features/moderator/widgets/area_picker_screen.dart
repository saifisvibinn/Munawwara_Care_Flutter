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

import '../../../core/map/app_map_tiles.dart';
import '../../../core/services/location_permission_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../shared/providers/suggested_area_provider.dart';
import 'moderator_map_widgets.dart';
import 'active_meetpoint_card.dart';
import '../../shared/models/suggested_area_model.dart';

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

class _AreaPickerScreenState extends ConsumerState<AreaPickerScreen> {
  final _mapController = MapController();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _sheetController = DraggableScrollableController();
  final _mapSearchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  LatLng? _pickedPoint;
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
    if (widget.existingArea != null) {
      _nameController.text = widget.existingArea!.name;
      _descController.text = widget.existingArea!.description;
      _pickedPoint = LatLng(widget.existingArea!.latitude, widget.existingArea!.longitude);
      _meetpointTime = widget.existingArea!.meetpointTime;
      _reminderMinutes = widget.existingArea!.reminderMinutes ?? 15;
    } else {
      // Default to current time for new meetpoints
      _meetpointTime = DateTime.now();
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
    _nominatimDebounce?.cancel();
    _mapController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _mapSearchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
      if (mounted) _searchFocusNode.requestFocus();
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
          StandardSnackBar.showError(context, 'Could not get current location');
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
          if (_pickedPoint == null) {
            setState(() => _pickedPoint = quick);
          }
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
        setState(() => _pickedPoint = point);
      } on TimeoutException {
        if (!mounted) return;
        if (lastKnown == null) {
          StandardSnackBar.showError(context, 'Could not get current location');
        } else {
          StandardSnackBar.showWarning(
            context,
            'area_location_refine_timeout'.tr(),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        StandardSnackBar.showError(context, 'Could not get current location');
      }
    } finally {
      if (mounted) setState(() => _recenteringGps = false);
    }
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
      setState(() => _meetpointTime = DateTime(
            picked.year,
            picked.month,
            picked.day,
            current.hour,
            current.minute,
          ));
    }
  }

  void _onSelectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_meetpointTime ?? DateTime.now()),
    );
    if (picked != null) {
      final current = _meetpointTime ?? DateTime.now();
      setState(() => _meetpointTime = DateTime(
            current.year,
            current.month,
            current.day,
            picked.hour,
            picked.minute,
          ));
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _pickedPoint == null) return;
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
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
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
    final accentColor = isMeetpoint ? const Color(0xFFDC2626) : AppColors.primary;
    
    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : Colors.white,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // 1. Map Layer
          _buildMapLayer(isDark, accentColor),

          // 2. Full Screen Map Overlays
          if (_isFullScreenMap) _buildFullScreenMapOverlays(isDark, accentColor),

          // 3. Search & Top Bar
          if (!_isFullScreenMap) _buildTopSearchLayer(isDark, accentColor),

          // 4. Bottom Sheet (Details)
          _buildBottomSheet(isDark, accentColor, isMeetpoint),
        ],
      ),
    );
  }

  Widget _buildMapLayer(bool isDark, Color accentColor) {
    final center = _pickedPoint ?? widget.initialCenter ?? const LatLng(21.4225, 39.8262);
    return Positioned.fill(
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: AppMapTiles.clampMapZoom(15),
          minZoom: AppMapTiles.mapMinZoom,
          maxZoom: AppMapTiles.mapMaxZoom,
          onTap: _isFullScreenMap ? null : (_, point) => setState(() => _pickedPoint = point),
          onPositionChanged: (pos, hasGesture) {
            if (hasGesture) {
              _mapCenter = pos.center;
            }
          },
        ),
        children: [
          ...AppMapTiles.baseLayers(isDark: isDark),
          MarkerLayer(
            markers: [
              ...ref.watch(suggestedAreaProvider).areas.map((a) => Marker(
                    point: LatLng(a.latitude, a.longitude),
                    width: 48.w,
                    height: 48.w,
                    child: Opacity(
                      opacity: 0.6,
                      child: AreaMapMarker(area: a),
                    ),
                  )),
              if (_pickedPoint != null && !_isFullScreenMap)
                Marker(
                  point: _pickedPoint!,
                  width: 60.w,
                  height: 60.w,
                  alignment: Alignment.topCenter,
                  child: Icon(
                    Symbols.location_on,
                    size: 48.w,
                    color: accentColor,
                    fill: 1,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFullScreenMapOverlays(bool isDark, Color accentColor) {
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 200.h,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: isDark ? 0.5 : 0.32),
                  ],
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
    final point = _mapCenter ?? _mapController.camera.center;
    final address = await _reverseGeocode(point);

    if (!mounted) return;

    final isMeetpoint = widget.areaType == 'meetpoint';
    final accentColor =
        isMeetpoint ? const Color(0xFFDC2626) : AppColors.primary;

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final sheetDark = Theme.of(ctx).brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: sheetDark ? AppColors.surfaceDark : Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 16.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                      color: sheetDark
                          ? Colors.white.withValues(alpha: 0.2)
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  Icon(Symbols.location_on, size: 40.w, color: accentColor, fill: 1),
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
                      color: sheetDark ? Colors.white : AppColors.textDark,
                    ),
                  ),
                  SizedBox(height: 28.h),
                  SizedBox(
                    width: double.infinity,
                    height: 52.h,
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _pickedPoint = point;
                          _isFullScreenMap = false;
                          if (address != null) {
                            _nameController.text =
                                address.split(',').first.trim();
                          }
                        });
                        Navigator.pop(ctx);
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14.r),
                        ),
                      ),
                      child: Text(
                        'area_use_this_location'.tr(),
                        style: const TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'area_keep_searching'.tr(),
                      style: TextStyle(
                        color: AppColors.textMutedLight,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Lexend',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopSearchLayer(bool isDark, Color accentColor) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 10.h,
      left: 16.w,
      right: 16.w,
      child: Column(
        children: [
          Row(
            children: [
              _buildOverlayButton(icon: Symbols.arrow_back, isDark: isDark, onTap: () => Navigator.pop(context)),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: BorderRadius.circular(20.r),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)],
                ),
                child: Text(
                  widget.areaType == 'meetpoint' ? 'area_meetpoint'.tr() : 'area_suggest'.tr(),
                  style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w700, fontSize: 14.sp, color: isDark ? Colors.white : AppColors.textDark),
                ),
              ),
              const Spacer(),
              _buildOverlayButton(
                icon: Symbols.my_location,
                isDark: isDark,
                isLoading: _recenteringGps,
                onTap: _recenterOnMe,
              ),
            ],
          ),
          SizedBox(height: 10.h),
          _buildMapSearchToolbar(isDark, accentColor),
        ],
      ),
    );
  }

  void _openFullscreenMapPicker() {
    setState(() => _isFullScreenMap = true);
  }

  /// Inline expanding search (Google Maps–style) + move-pin action.
  Widget _buildMapSearchToolbar(bool isDark, Color accentColor) {
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.grey.shade300;
    final bg = isDark
        ? AppColors.surfaceDark.withValues(alpha: 0.94)
        : Colors.white.withValues(alpha: 0.96);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 280),
          sizeCurve: Curves.easeOutCubic,
          firstCurve: Curves.easeOutCubic,
          secondCurve: Curves.easeOutCubic,
          crossFadeState: _mapSearchExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: Row(
            key: const ValueKey('map_tools_collapsed'),
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _expandMapSearch,
                  icon: Icon(Symbols.search, size: 20.w, color: accentColor),
                  label: Text(
                    'area_search_area'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 13.sp,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : AppColors.textDark,
                    backgroundColor: bg,
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    side: BorderSide(color: borderColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openFullscreenMapPicker,
                  icon: Icon(
                    Symbols.add_location_alt,
                    size: 20.w,
                    color: accentColor,
                  ),
                  label: Text(
                    'area_move_pin'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 13.sp,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : AppColors.textDark,
                    backgroundColor: bg,
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    side: BorderSide(
                      color: accentColor.withValues(alpha: 0.45),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.r),
                    ),
                  ),
                ),
              ),
            ],
          ),
          secondChild: Material(
            key: const ValueKey('map_tools_search_expanded'),
            color: bg,
            elevation: 3,
            shadowColor: Colors.black.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14.r),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Symbols.arrow_back,
                    color: isDark ? Colors.white : AppColors.textDark,
                    size: 22.w,
                  ),
                  onPressed: _collapseMapSearch,
                ),
                Expanded(
                  child: TextField(
                    controller: _mapSearchController,
                    focusNode: _searchFocusNode,
                    onChanged: _scheduleNominatimSearch,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                    decoration: InputDecoration(
                      hintText: 'area_search_hint'.tr(),
                      hintStyle: TextStyle(
                        color: AppColors.textMutedLight,
                        fontSize: 13.sp,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                    ),
                  ),
                ),
                if (_mapSearchController.text.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Symbols.close,
                      color: AppColors.textMutedLight,
                      size: 20.w,
                    ),
                    onPressed: () {
                      _mapSearchController.clear();
                      setState(() {
                        _nominatimResults = [];
                        _nominatimLoading = false;
                      });
                    },
                  ),
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _mapSearchExpanded
              ? _buildSearchSuggestionsPanel(isDark, accentColor)
              : const SizedBox.shrink(key: ValueKey('no_suggestions')),
        ),
      ],
    );
  }

  Widget _buildSearchSuggestionsPanel(bool isDark, Color accentColor) {
    final q = _mapSearchController.text.trim();
    if (!_mapSearchExpanded || q.length < 3) {
      return const SizedBox.shrink(key: ValueKey('sug_hidden'));
    }

    if (_nominatimLoading && _nominatimResults.isEmpty) {
      return Padding(
        key: const ValueKey('sug_loading'),
        padding: EdgeInsets.only(top: 8.h),
        child: Material(
          color: isDark ? const Color(0xFF2A2A3C) : Colors.white,
          elevation: 6,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(14.r),
          child: Padding(
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
        ),
      );
    }

    if (!_nominatimLoading && _nominatimResults.isEmpty) {
      return Padding(
        key: const ValueKey('sug_empty'),
        padding: EdgeInsets.only(top: 8.h),
        child: Material(
          color: isDark ? const Color(0xFF2A2A3C) : Colors.white,
          elevation: 6,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(14.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Text(
              'area_no_places_found'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                color: AppColors.textMutedLight,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      key: ValueKey('sug_list_${_nominatimResults.length}'),
      padding: EdgeInsets.only(top: 8.h),
      child: Material(
        color: isDark ? const Color(0xFF2A2A3C) : Colors.white,
        elevation: 8,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(14.r),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: 240.h),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.symmetric(vertical: 6.h),
            physics: const ClampingScrollPhysics(),
            itemCount: _nominatimResults.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              indent: 16.w,
              endIndent: 16.w,
              color: isDark ? Colors.white10 : Colors.grey.shade200,
            ),
            itemBuilder: (context, i) {
              final r = _nominatimResults[i];
              final name = r['display_name'] as String;
              return InkWell(
                onTap: () {
                  final p = LatLng(r['lat'] as double, r['lon'] as double);
                  final label = name.split(',').first.trim();
                  _applyNominatimPick(p, label);
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: 12.h,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Symbols.location_on,
                        size: 20.w,
                        color: accentColor,
                        fill: 1,
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 13.sp,
                            height: 1.35,
                            color: isDark ? Colors.white : AppColors.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSheet(bool isDark, Color accentColor, bool isMeetpoint) {
    if (_isFullScreenMap) return const SizedBox.shrink();

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.44,
      minChildSize: 0.08,
      maxChildSize: 0.92,
      snap: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16.w,
                8.h,
                16.w,
                MediaQuery.of(context).padding.bottom + 16.h,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 32.w,
                      height: 3.h,
                      margin: EdgeInsets.only(bottom: 16.h),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2.r),
                      ),
                    ),
                  ),
                  if (isMeetpoint && ref.watch(suggestedAreaProvider).activeMeetpoint != null) ...[
                    ActiveMeetpointCard(
                      activeMp: ref.watch(suggestedAreaProvider).activeMeetpoint!,
                      isDark: isDark,
                      onDelete: () => _deleteActiveMeetpoint(ref.read(suggestedAreaProvider).activeMeetpoint!.id),
                    ),
                  ],
                  _buildSectionHeader('area_name_desc_header'.tr()),
                  SizedBox(height: 6.h),
                  _buildTextField(_nameController, isMeetpoint ? Symbols.crisis_alert : Symbols.pin_drop, 'area_name_hint'.tr(), accentColor, isDark),
                  SizedBox(height: 12.h),
                  _buildTextField(_descController, Symbols.description, 'area_desc_hint'.tr(), AppColors.textMutedLight, isDark),
                  if (isMeetpoint) ...[
                    SizedBox(height: 20.h),
                    _buildSectionHeader('area_schedule_title'.tr()),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        Expanded(child: _buildDateTimeTile(label: 'area_date_label'.tr(), value: _meetpointTime == null ? 'area_select_date'.tr() : DateFormat('MMM dd, yyyy').format(_meetpointTime!), icon: Symbols.calendar_today, isDark: isDark, accentColor: accentColor, onTap: _onSelectDate)),
                        SizedBox(width: 12.w),
                        Expanded(child: _buildDateTimeTile(label: 'area_time_label'.tr(), value: _meetpointTime == null ? 'area_select_time'.tr() : DateFormat('hh:mm a').format(_meetpointTime!), icon: Symbols.schedule, isDark: isDark, accentColor: accentColor, onTap: _onSelectTime)),
                      ],
                    ),
                    SizedBox(height: 20.h),
                    _buildSectionHeader('area_reminder_label'.tr()),
                    SizedBox(height: 8.h),
                    _buildReminderOptions(isDark, accentColor),
                  ],
                  SizedBox(height: 22.h),
                  _buildSubmitButton(isMeetpoint, accentColor),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverlayButton({
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return Container(
      decoration: BoxDecoration(color: isDark ? AppColors.surfaceDark : Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)]),
      child: IconButton(
        icon: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              )
            : Icon(icon, color: isDark ? Colors.white : AppColors.textDark),
        onPressed: isLoading ? null : onTap,
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: 'Lexend',
        fontWeight: FontWeight.w600,
        fontSize: 13.sp,
        color: AppColors.textMutedLight,
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, IconData icon, String hint, Color iconColor, bool isDark) {
    return TextField(
      controller: controller,
      style: TextStyle(
        fontFamily: 'Lexend',
        fontSize: 14.sp,
        color: isDark ? Colors.white : AppColors.textDark,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textMutedLight, fontSize: 13.sp),
        prefixIcon: Icon(icon, size: 20.w, color: iconColor),
        filled: true,
        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
        contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: iconColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildDateTimeTile({required String label, required String value, required IconData icon, required bool isDark, required Color accentColor, required VoidCallback onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w500,
            fontSize: 12.sp,
            color: AppColors.textMutedLight,
          ),
        ),
        SizedBox(height: 8.h),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12.r),
          child: Container(
            height: 52.h,
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A3C) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18.w, color: accentColor),
                SizedBox(width: 8.w),
                Expanded(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'Lexend', fontSize: 13.sp, fontWeight: FontWeight.w500, color: isDark ? Colors.white : AppColors.textDark))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReminderOptions(bool isDark, Color accentColor) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [0, 5, 15, 30, 60].map((mins) {
          final isSelected = _reminderMinutes == mins;
          return Padding(
            padding: EdgeInsets.only(right: 8.w),
            child: ChoiceChip(
              label: Text(
                mins == 0 ? 'area_reminder_none'.tr() : '${mins}m',
                style: TextStyle(fontFamily: 'Lexend', fontSize: 12.sp, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: isSelected ? Colors.white : (isDark ? Colors.white70 : AppColors.textDark)),
              ),
              selected: isSelected,
              onSelected: (val) {
                if (val) setState(() => _reminderMinutes = mins);
              },
              selectedColor: accentColor,
              backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
              side: BorderSide.none,
              showCheckmark: false,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSubmitButton(bool isMeetpoint, Color accentColor) {
    final canSubmit = _pickedPoint != null && _nameController.text.trim().isNotEmpty && !_submitting;
    return SizedBox(
      width: double.infinity,
      height: 56.h,
      child: ElevatedButton(
        onPressed: canSubmit ? _submit : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: _submitting
            ? SizedBox(
                width: 24.w,
                height: 24.w,
                child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Text(
                widget.existingArea != null
                    ? (isMeetpoint
                        ? 'area_update_meetpoint'.tr()
                        : 'area_update_suggestion'.tr())
                    : (isMeetpoint
                        ? 'area_set_meetpoint'.tr()
                        : 'area_add_suggestion'.tr()),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 16.sp,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
