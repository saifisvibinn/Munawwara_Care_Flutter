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


  LatLng? _pickedPoint;
  bool _submitting = false;
  DateTime? _meetpointTime;
  int _reminderMinutes = 15;

  // UX State
  bool _isFullScreenMap = false;
  bool _isSearchExpanded = false;
  LatLng? _mapCenter;
  bool _recenteringGps = false;

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
  }

  @override
  void dispose() {
    _mapController.dispose();
    _nameController.dispose();
    _descController.dispose();
    super.dispose();
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
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
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
          _mapController.move(quick, 17);
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
        _mapController.move(point, 17);
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
          initialZoom: 15,
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
        // Crosshair
        Center(
          child: Container(
            margin: EdgeInsets.only(bottom: 24.h), // Offset for pin point
            child: Icon(
              Symbols.add_location_alt,
              size: 48.w,
              color: accentColor,
              shadows: const [Shadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
            ),
          ),
        ),
        // Confirm Button Pill
        Positioned(
          bottom: 40.h,
          left: 0,
          right: 0,
          child: Center(
            child: InkWell(
              onTap: _showConfirmSelectionModal,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 14.h),
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(30.r),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, offset: const Offset(0, 5))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.check_circle, color: Colors.white, size: 20.w),
                    SizedBox(width: 8.w),
                    Text(
                      'Confirm selection',
                      style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w700, fontSize: 15.sp, color: Colors.white),
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

  void _showConfirmSelectionModal() async {
    final point = _mapCenter ?? _mapController.camera.center;
    final address = await _reverseGeocode(point);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32.r)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40.w, height: 4.h, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2.r))),
            SizedBox(height: 24.h),
            Icon(Symbols.location_on, size: 40.w, color: AppColors.primary),
            SizedBox(height: 16.h),
            Text(
              address ?? 'Selected Location',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Lexend', fontSize: 14.sp, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 32.h),
            SizedBox(
              width: double.infinity,
              height: 54.h,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _pickedPoint = point;
                    _isFullScreenMap = false;
                    if (address != null) {
                      _nameController.text = address.split(',').first.trim();
                    }
                  });
                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                ),
                child: Text('area_use_this_location'.tr(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
            SizedBox(height: 12.h),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('area_keep_searching'.tr(), style: TextStyle(color: AppColors.textMutedLight, fontWeight: FontWeight.w600)),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
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
          SizedBox(height: 12.h),
          GestureDetector(
            onTap: () => setState(() => _isSearchExpanded = !_isSearchExpanded),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 15)],
              ),
              child: Row(
                children: [
                  Icon(Symbols.search, size: 20.w, color: AppColors.textMutedLight),
                  SizedBox(width: 12.w),
                  Text(
                    'area_search_hint'.tr(),
                    style: TextStyle(fontFamily: 'Lexend', fontSize: 13.sp, color: AppColors.textMutedLight),
                  ),
                ],
              ),
            ),
          ),
          if (_isSearchExpanded)
            Container(
              margin: EdgeInsets.only(top: 8.h),
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(16.r),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20)],
              ),
              child: Column(
                children: [
                  _buildHotspotRow("Central Park", "0.2 mi", isDark),
                  _buildHotspotRow("Starbucks", "0.3 mi", isDark),
                  _buildHotspotRow("City Hall", "0.5 mi", isDark),
                  Divider(height: 1, color: isDark ? Colors.white12 : Colors.grey.shade100),
                  ListTile(
                    leading: Icon(Symbols.explore, size: 18.w, color: accentColor),
                    title: Text('area_set_location_on_map'.tr(), style: TextStyle(fontFamily: 'Lexend', fontSize: 12.sp, fontWeight: FontWeight.w600, color: accentColor)),
                    trailing: Icon(Symbols.chevron_right, size: 16.w, color: accentColor),
                    onTap: () {
                      setState(() {
                        _isSearchExpanded = false;
                        _isFullScreenMap = true;
                      });
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHotspotRow(String name, String dist, bool isDark) {
    return ListTile(
      dense: true,
      leading: Icon(Symbols.pin_drop, size: 18.w, color: AppColors.textMutedLight),
      title: Text(name, style: TextStyle(fontFamily: 'Lexend', fontSize: 12.sp, color: isDark ? Colors.white : AppColors.textDark)),
      trailing: Text(dist, style: TextStyle(fontFamily: 'Lexend', fontSize: 10.sp, color: AppColors.textMutedLight)),
      onTap: () {
        // Mock selection for hotspot
        setState(() => _isSearchExpanded = false);
      },
    );
  }

  Widget _buildBottomSheet(bool isDark, Color accentColor, bool isMeetpoint) {
    if (_isFullScreenMap) return const SizedBox.shrink();

    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: 0.5,
      minChildSize: 0.08,
      maxChildSize: 0.95,
      snap: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32.r)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 25,
                offset: const Offset(0, -5),
              )
            ],
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, MediaQuery.of(context).padding.bottom + 20.h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40.w,
                      height: 4.h,
                      margin: EdgeInsets.only(bottom: 20.h),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : Colors.grey.shade300,
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
                  SizedBox(height: 8.h),
                  _buildTextField(_nameController, isMeetpoint ? Symbols.crisis_alert : Symbols.pin_drop, 'area_name_hint'.tr(), accentColor, isDark),
                  SizedBox(height: 12.h),
                  _buildTextField(_descController, Symbols.description, 'area_desc_hint'.tr(), AppColors.textMutedLight, isDark),
                  if (isMeetpoint) ...[
                    SizedBox(height: 24.h),
                    _buildSectionHeader('area_schedule_title'.tr()),
                    SizedBox(height: 12.h),
                    Row(
                      children: [
                        Expanded(child: _buildDateTimeTile(label: 'area_date_label'.tr(), value: _meetpointTime == null ? 'area_select_date'.tr() : DateFormat('MMM dd, yyyy').format(_meetpointTime!), icon: Symbols.calendar_today, isDark: isDark, accentColor: accentColor, onTap: _onSelectDate)),
                        SizedBox(width: 12.w),
                        Expanded(child: _buildDateTimeTile(label: 'area_time_label'.tr(), value: _meetpointTime == null ? 'area_select_time'.tr() : DateFormat('hh:mm a').format(_meetpointTime!), icon: Symbols.schedule, isDark: isDark, accentColor: accentColor, onTap: _onSelectTime)),
                      ],
                    ),
                    SizedBox(height: 24.h),
                    _buildSectionHeader('area_reminder_label'.tr()),
                    SizedBox(height: 12.h),
                    _buildReminderOptions(isDark, accentColor),
                  ],
                  SizedBox(height: 32.h),
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
    return Text(title.toUpperCase(), style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600, fontSize: 11.sp, color: AppColors.textMutedLight, letterSpacing: 1.1));
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
        Text(label, style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w600, fontSize: 10.sp, color: AppColors.textMutedLight, letterSpacing: 1.1)),
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
          elevation: 8,
          shadowColor: accentColor.withValues(alpha: 0.4),
        ),
        child: _submitting
            ? SizedBox(
                width: 24.w,
                height: 24.w,
                child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Text(
                widget.existingArea != null
                    ? (isMeetpoint ? 'Update Meetpoint' : 'Update Suggestion')
                    : (isMeetpoint ? 'area_set_meetpoint'.tr() : 'area_add_suggestion'.tr()),
                style: TextStyle(fontFamily: 'Lexend', fontWeight: FontWeight.w700, fontSize: 16.sp, color: Colors.white),
              ),
      ),
    );
  }
}
