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

import '../../../core/map/app_map_marker_cluster.dart';
import '../../../core/map/app_map_tiles.dart';
import '../../../core/services/location_permission_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/standard_snackbar.dart';
import '../../shared/providers/suggested_area_provider.dart';
import 'moderator_map_widgets.dart';
import 'active_meetpoint_card.dart';
import '../../shared/models/suggested_area_model.dart';

/// Visual tokens for area / meetpoint picker (UI only).
abstract final class _AreaPickerTheme {
  static const lightTopBar = Color.fromRGBO(245, 247, 252, 0.88);
  static const darkTopBar = Color.fromRGBO(18, 22, 30, 0.85);
  static const lightSheet = Color(0xFFF7F8FC);
  static const darkSheet = Color(0xFF12151E);
  static const lightField = Color(0xFFEDEDF4);
  static const darkField = Color(0xFF1C1F2E);
  static const lightHandle = Color(0xFFD8D8E0);
  static const darkHandle = Color(0xFF2E3040);
  static const sectionLabel = Color(0xFFB0B8C8);
  static const lightHint = Color(0xFFAAAAAA);
  static const darkHint = Color(0xFF555555);
  static const lightChipBg = Color(0xFFE8E8F0);
  static const lightChipInactiveText = Color(0xFFAAAAAA);
  static const meetpointRed = Color(0xFFC0392B);
  static const meetpointRedDark = Color(0xFFE05050);

  static Color accent(bool isDark, bool isMeetpoint) => isMeetpoint
      ? (isDark ? meetpointRedDark : meetpointRed)
      : AppColors.primary;

  static Color sheetBg(bool isDark) => isDark ? darkSheet : lightSheet;

  static Color fieldBg(bool isDark) => isDark ? darkField : lightField;

  static Color topBarBg(bool isDark) => isDark ? darkTopBar : lightTopBar;

  static Color topBarBorder(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.black.withValues(alpha: 0.06);

  static Color overlayBtnFill(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.white.withValues(alpha: 0.9);

  static Color overlayBtnBorder(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.1)
      : Colors.black.withValues(alpha: 0.08);

  static Color searchPillBg(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.07)
      : Colors.white.withValues(alpha: 0.88);

  static Color searchPillBorder(bool isDark) => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.07);
}

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
              foregroundColor: _AreaPickerTheme.meetpointRed,
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
    final accentColor = _AreaPickerTheme.accent(isDark, isMeetpoint);

    return Scaffold(
      backgroundColor: _AreaPickerTheme.sheetBg(isDark),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          _buildMapLayer(isDark, accentColor),
          if (_isFullScreenMap) _buildFullScreenMapOverlays(isDark, accentColor),
          if (!_isFullScreenMap) _buildFloatingTopBar(isDark, isMeetpoint),
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
    return Positioned.fill(
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: center,
          initialZoom: AppMapTiles.clampMapZoom(15),
          minZoom: AppMapTiles.mapMinZoom,
          maxZoom: AppMapTiles.mapMaxZoom,
          onPositionChanged: (pos, hasGesture) {
            if (_isFullScreenMap) {
              if (hasGesture) {
                _mapCenter = pos.center;
              }
              return;
            }
            final target = pos.center;
            if (hasGesture) {
              setState(() => _selectedLocation = target);
            } else {
              setState(() {
                _selectedLocation = target;
                _pickedPoint = target;
              });
            }
          },
        ),
        children: [
          ...AppMapTiles.baseLayers(isDark: isDark),
          AppMapMarkerCluster.layer(
            markerChildBehavior: false,
            markers: [
              ...ref.watch(suggestedAreaProvider).areas.map(
                    (a) => Marker(
                      point: LatLng(a.latitude, a.longitude),
                      width: 48.w,
                      height: 48.w,
                      child: Opacity(
                        opacity: 0.6,
                        child: AreaMapMarker(area: a),
                      ),
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
    final accentColor = _AreaPickerTheme.accent(
      Theme.of(context).brightness == Brightness.dark,
      isMeetpoint,
    );

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
              color: _AreaPickerTheme.sheetBg(sheetDark),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
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
                          _selectedLocation = point;
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

  Widget _buildFloatingTopBar(bool isDark, bool isMeetpoint) {
    final topPad = MediaQuery.of(context).padding.top;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _AreaPickerTheme.topBarBg(isDark),
          border: Border(
            bottom: BorderSide(
              width: 0.5,
              color: _AreaPickerTheme.topBarBorder(isDark),
            ),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, topPad + 8.h, 16.w, 10.h),
          child: Row(
            children: [
              _buildOverlayButton(
                icon: Symbols.arrow_back,
                isDark: isDark,
                onTap: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  isMeetpoint ? 'area_meetpoint'.tr() : 'area_suggest'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    fontSize: 14.sp,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              _buildOverlayButton(
                icon: Symbols.my_location,
                isDark: isDark,
                isLoading: _recenteringGps,
                onTap: _recenterOnMe,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetMapTools(bool isDark, Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_mapSearchExpanded) ...[
          _buildMapSearchExpanded(isDark, accentColor),
          SizedBox(height: 8.h),
        ],
        _buildMapSearchSuggestionsPanel(isDark, accentColor),
        if (_mapSearchExpanded &&
            _mapSearchController.text.trim().length >= 3)
          SizedBox(height: 8.h),
        _buildMapActionPillsRow(isDark, accentColor),
        SizedBox(height: 12.h),
      ],
    );
  }

  Widget _buildMapActionPillsRow(bool isDark, Color accentColor) {
    return Row(
      children: [
        Expanded(
          child: Material(
            color: _AreaPickerTheme.searchPillBg(isDark),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: _expandMapSearch,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _AreaPickerTheme.searchPillBorder(isDark),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Symbols.search,
                      size: 18.w,
                      color: isDark ? Colors.white70 : AppColors.textDark,
                    ),
                    SizedBox(width: 6.w),
                    Flexible(
                      child: Text(
                        'area_search_area'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w500,
                          fontSize: 12.sp,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Material(
            color: accentColor,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: _openFullscreenMapPicker,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Symbols.add_location_alt,
                      size: 18.w,
                      color: Colors.white,
                    ),
                    SizedBox(width: 6.w),
                    Flexible(
                      child: Text(
                        'area_move_pin'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w500,
                          fontSize: 12.sp,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapSearchExpanded(bool isDark, Color accentColor) {
    return Material(
      color: _AreaPickerTheme.searchPillBg(isDark),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _AreaPickerTheme.searchPillBorder(isDark),
            width: 0.5,
          ),
        ),
        child: Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                Symbols.arrow_back,
                color: isDark ? Colors.white : AppColors.textDark,
                size: 20.w,
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
                  fontSize: 12.sp,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
                decoration: InputDecoration(
                  hintText: 'area_search_hint'.tr(),
                  hintStyle: TextStyle(
                    color: isDark
                        ? _AreaPickerTheme.darkHint
                        : _AreaPickerTheme.lightHint,
                    fontSize: 12.sp,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10.h),
                ),
              ),
            ),
            if (_mapSearchController.text.isNotEmpty)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Symbols.close,
                  color: isDark
                      ? _AreaPickerTheme.darkHint
                      : _AreaPickerTheme.lightHint,
                  size: 18.w,
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
    );
  }

  Widget _buildMapSearchSuggestionsPanel(bool isDark, Color accentColor) {
    if (!_mapSearchExpanded) {
      return const SizedBox.shrink();
    }
    final panel = _buildSearchSuggestionsPanel(isDark, accentColor);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: panel,
    );
  }

  /// Keeps the suggestions list above the keyboard and below the top bar.
  double _suggestionsListMaxHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    const searchBarHeight = 52.0;
    final topBarHeight = mq.padding.top + 58;
    const mapPillsRowHeight = 48.0;
    final fromViewport = mq.size.height -
        mq.viewInsets.bottom -
        searchBarHeight -
        topBarHeight -
        mapPillsRowHeight;
    const sheetInitialFraction = 0.44;
    final sheetTopY = mq.size.height * (1 - sheetInitialFraction);
    final fromSheetTop = sheetTopY -
        topBarHeight -
        searchBarHeight -
        mq.viewInsets.bottom -
        8;
    final maxH = fromViewport < fromSheetTop ? fromViewport : fromSheetTop;
    return maxH.clamp(72.0, 240.h);
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

    if (_nominatimLoading && _nominatimResults.isEmpty) {
      return Material(
        key: const ValueKey('sug_loading'),
        color: _AreaPickerTheme.sheetBg(isDark),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _AreaPickerTheme.searchPillBorder(isDark),
              width: 0.5,
            ),
          ),
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
      return Material(
        key: const ValueKey('sug_empty'),
        color: _AreaPickerTheme.sheetBg(isDark),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _AreaPickerTheme.searchPillBorder(isDark),
              width: 0.5,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Text(
              'area_no_places_found'.tr(),
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 12.sp,
                color: isDark
                    ? _AreaPickerTheme.darkHint
                    : _AreaPickerTheme.lightHint,
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      key: ValueKey('sug_list_${_nominatimResults.length}'),
      color: _AreaPickerTheme.sheetBg(isDark),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: _AreaPickerTheme.searchPillBorder(isDark),
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxListHeight),
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
            color: _AreaPickerTheme.sheetBg(isDark),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
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
                  _buildSheetMapTools(isDark, accentColor),
                  Center(
                    child: Container(
                      width: 34,
                      height: 3,
                      margin: EdgeInsets.only(bottom: 16.h),
                      decoration: BoxDecoration(
                        color: isDark
                            ? _AreaPickerTheme.darkHandle
                            : _AreaPickerTheme.lightHandle,
                        borderRadius: BorderRadius.circular(2),
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
                  _buildTextField(
                    _nameController,
                    isMeetpoint ? Symbols.location_on : Symbols.pin_drop,
                    'area_name_hint'.tr(),
                    accentColor,
                    isDark,
                    accentIcon: true,
                  ),
                  SizedBox(height: 12.h),
                  _buildTextField(
                    _descController,
                    Symbols.description,
                    'area_desc_hint'.tr(),
                    isDark
                        ? _AreaPickerTheme.darkHint
                        : _AreaPickerTheme.lightHint,
                    isDark,
                    accentIcon: false,
                  ),
                  if (isMeetpoint) ...[
                    SizedBox(height: 20.h),
                    _buildSectionHeader('area_schedule_title'.tr()),
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: _buildDateTimeTile(
                            value: _meetpointTime == null
                                ? 'area_select_date'.tr()
                                : DateFormat('MMM dd, yyyy')
                                    .format(_meetpointTime!),
                            icon: Symbols.calendar_today,
                            isDark: isDark,
                            accentColor: accentColor,
                            onTap: _onSelectDate,
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          flex: 2,
                          child: _buildDateTimeTile(
                            value: _meetpointTime == null
                                ? 'area_select_time'.tr()
                                : DateFormat('hh:mm a')
                                    .format(_meetpointTime!),
                            icon: Symbols.schedule,
                            isDark: isDark,
                            accentColor: accentColor,
                            onTap: _onSelectTime,
                          ),
                        ),
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
      width: 40.w,
      height: 40.w,
      decoration: BoxDecoration(
        color: _AreaPickerTheme.overlayBtnFill(isDark),
        shape: BoxShape.circle,
        border: Border.all(
          color: _AreaPickerTheme.overlayBtnBorder(isDark),
          width: 0.5,
        ),
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              )
            : Icon(
                icon,
                size: 20.w,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
        onPressed: isLoading ? null : onTap,
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Lexend',
        fontWeight: FontWeight.w600,
        fontSize: 10.sp,
        letterSpacing: 1.2,
        color: _AreaPickerTheme.sectionLabel,
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    IconData icon,
    String hint,
    Color iconColor,
    bool isDark, {
    required bool accentIcon,
  }) {
    final fieldBorder = isDark
        ? BorderSide(
            color: Colors.white.withValues(alpha: 0.05),
            width: 0.5,
          )
        : BorderSide.none;
    return TextField(
      controller: controller,
      style: TextStyle(
        fontFamily: 'Lexend',
        fontSize: 14.sp,
        color: isDark ? Colors.white : AppColors.textDark,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? _AreaPickerTheme.darkHint : _AreaPickerTheme.lightHint,
          fontSize: 13.sp,
        ),
        prefixIcon: Icon(icon, size: 20.w, color: iconColor),
        filled: true,
        fillColor: _AreaPickerTheme.fieldBg(isDark),
        contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: fieldBorder,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: fieldBorder,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: accentIcon
              ? BorderSide(color: iconColor, width: 1)
              : fieldBorder,
        ),
      ),
    );
  }

  Widget _buildDateTimeTile({
    required String value,
    required IconData icon,
    required bool isDark,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: _AreaPickerTheme.fieldBg(isDark),
          borderRadius: BorderRadius.circular(10.r),
          border: isDark
              ? Border.all(
                  color: Colors.white.withValues(alpha: 0.05),
                  width: 0.5,
                )
              : null,
        ),
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
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderChip({
    required String label,
    required bool isSelected,
    required bool isDisabled,
    required bool isDark,
    required Color accentColor,
    required VoidCallback? onTap,
  }) {
    return Opacity(
      opacity: isDisabled ? 0.38 : 1.0,
      child: Material(
        color: isSelected
            ? accentColor
            : (isDark ? _AreaPickerTheme.darkField : _AreaPickerTheme.lightChipBg),
        borderRadius: BorderRadius.circular(20.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20.r),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20.r),
              border: isSelected
                  ? null
                  : Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.transparent,
                      width: 0.5,
                    ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : (isDark
                        ? _AreaPickerTheme.darkHint
                        : _AreaPickerTheme.lightChipInactiveText),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReminderOptions(bool isDark, Color accentColor) {
    final minutesUntil = _meetpointTime?.difference(DateTime.now()).inMinutes;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [0, 5, 15, 30, 60].map((mins) {
          final isSelected = _reminderMinutes == mins;
          final isDisabled =
              mins > 0 && minutesUntil != null && minutesUntil <= mins;
          return Padding(
            padding: EdgeInsets.only(right: 8.w),
            child: _buildReminderChip(
              label: mins == 0 ? 'area_reminder_none'.tr() : '${mins}m',
              isSelected: isSelected,
              isDisabled: isDisabled,
              isDark: isDark,
              accentColor: accentColor,
              onTap: isDisabled
                  ? null
                  : () => setState(() => _reminderMinutes = mins),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSubmitButton(bool isMeetpoint, Color accentColor) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _submitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: accentColor,
          disabledBackgroundColor: accentColor,
          disabledForegroundColor: Colors.white,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(vertical: 13.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.r),
          ),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: _submitting
            ? SizedBox(
                width: 22.w,
                height: 22.w,
                child: const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
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
                  fontWeight: FontWeight.w600,
                  fontSize: 13.sp,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                ),
              ),
      ),
    );
  }
}
