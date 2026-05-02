import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dropdown_theme.dart';
import '../../models/provisioning_models.dart';

class CreatePilgrimCard extends StatefulWidget {
  final bool isDark;
  final bool isProvisioning;
  final List<HotelOption> hotels;
  final List<BusOption> buses;
  final bool isLoadingResources;
  final Function(Map<String, dynamic> data) onCreate;

  const CreatePilgrimCard({
    super.key,
    required this.isDark,
    required this.isProvisioning,
    required this.hotels,
    required this.buses,
    required this.isLoadingResources,
    required this.onCreate,
  });

  @override
  State<CreatePilgrimCard> createState() => _CreatePilgrimCardState();
}

class _CreatePilgrimCardState extends State<CreatePilgrimCard> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _nationalIdCtrl = TextEditingController();
  final _medicalHistoryCtrl = TextEditingController();

  String _selectedLanguage = 'en';
  String _selectedVisaStatus = 'unknown';
  String _selectedEthnicity = 'Other';
  String? _selectedHotelId;
  String? _selectedRoomId;
  String? _selectedBusId;
  static const List<Map<String, String>> _ethnicityOptions = [
    {'value': 'Arab', 'labelKey': 'ethnic_arab'},
    {'value': 'South Asian', 'labelKey': 'ethnic_south_asian'},
    {'value': 'Turkic', 'labelKey': 'ethnic_turkic'},
    {'value': 'Persian', 'labelKey': 'ethnic_persian'},
    {'value': 'Malay/Indonesian', 'labelKey': 'ethnic_malay_indo'},
    {'value': 'African', 'labelKey': 'ethnic_african'},
    {'value': 'Kurdish', 'labelKey': 'ethnic_kurdish'},
    {'value': 'Berber', 'labelKey': 'ethnic_berber'},
    {'value': 'European Muslim', 'labelKey': 'ethnic_european_muslim'},
    {'value': 'Other', 'labelKey': 'ethnic_other'},
  ];

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _ageCtrl.dispose();
    _nationalIdCtrl.dispose();
    _medicalHistoryCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CreatePilgrimCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hotels == widget.hotels && oldWidget.buses == widget.buses) {
      return;
    }
    final hotelOk = _selectedHotelId == null ||
        widget.hotels.any((h) => h.id == _selectedHotelId);
    final busOk = _selectedBusId == null ||
        widget.buses.any((b) => b.id == _selectedBusId);
    var roomOk = true;
    if (_selectedRoomId != null) {
      final h =
          widget.hotels.where((x) => x.id == _selectedHotelId).firstOrNull;
      final rooms = (h?.rooms ?? const <RoomOption>[])
          .where((r) => r.active)
          .toList();
      roomOk = rooms.any((r) => r.id == _selectedRoomId);
    }
    if (hotelOk && roomOk && busOk) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (!hotelOk) {
          _selectedHotelId = null;
          _selectedRoomId = null;
        } else if (!roomOk) {
          _selectedRoomId = null;
        }
        if (!busOk) _selectedBusId = null;
      });
    });
  }

  void _handleSubmit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final selectedHotel = widget.hotels.where((h) => h.id == _selectedHotelId).firstOrNull;
    final selectedRoom = selectedHotel?.rooms.where((r) => r.id == _selectedRoomId).firstOrNull;
    final selectedBus = widget.buses.where((b) => b.id == _selectedBusId).firstOrNull;

    final data = {
      'full_name': _fullNameCtrl.text.trim(),
      'phone_number': _phoneCtrl.text.trim(),
      'national_id': _nationalIdCtrl.text.trim(),
      'medical_history': _medicalHistoryCtrl.text.trim(),
      'age': int.tryParse(_ageCtrl.text.trim()),
      'language': _selectedLanguage,
      'ethnicity': _selectedEthnicity,
      'hotel_id': _selectedHotelId,
      'hotel_name': selectedHotel?.name,
      'room_id': _selectedRoomId,
      'room_number': selectedRoom?.roomNumber,
      'bus_id': _selectedBusId,
      'bus_info': selectedBus == null
          ? null
          : '${selectedBus.busNumber} - ${selectedBus.destination}',
      'visa': {'status': _selectedVisaStatus},
    };

    widget.onCreate(data);
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = widget.isDark ? AppColors.textLight : AppColors.textDark;
    
    final selectedHotel = widget.hotels.where((h) => h.id == _selectedHotelId).firstOrNull;
    final rooms = (selectedHotel?.rooms ?? const <RoomOption>[])
        .where((r) => r.active)
        .toList();

    return Container(
      decoration: BoxDecoration(
        color: widget.isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(
          color: widget.isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: EdgeInsets.all(20.w),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8.w),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Symbols.person_add, color: AppColors.primary, size: 22.w),
                ),
                SizedBox(width: 12.w),
                Text(
                  'provisioning_create_account_title'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    fontSize: 18.sp,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
            SizedBox(height: 20.h),
            
            _buildSectionTitle('provisioning_basic_information'.tr()),
            SizedBox(height: 12.h),
            
            TextFormField(
              controller: _fullNameCtrl,
              decoration: InputDecoration(
                labelText: 'reg_full_name'.tr(),
                prefixIcon: Icon(Symbols.person),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'provisioning_required'.tr() : null,
            ),
            SizedBox(height: 12.h),
            
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'reg_phone'.tr(),
                prefixIcon: Icon(Symbols.phone),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'provisioning_required'.tr() : null,
            ),
            SizedBox(height: 12.h),
            
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: _ageCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(labelText: 'reg_age'.tr()),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'provisioning_required'.tr();
                      final num = int.tryParse(v.trim());
                      if (num == null || num < 1 || num > 120) return 'provisioning_invalid'.tr();
                      return null;
                    },
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _selectedLanguage,
                    decoration: AppDropdownTheme.formFieldDecoration(
                      isDark: widget.isDark,
                      labelText: 'settings_language'.tr(),
                      nested: true,
                    ),
                    icon: AppDropdownTheme.menuTrailingIcon(),
                    dropdownColor: AppDropdownTheme.menuBackground(widget.isDark),
                    borderRadius: AppDropdownTheme.menuBorderRadius(),
                    elevation: AppDropdownTheme.menuElevation(),
                    style: AppDropdownTheme.valueStyle(widget.isDark),
                    items: [
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(
                          'lang_english'.tr(),
                          style: AppDropdownTheme.menuItemStyle(widget.isDark),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'ar',
                        child: Text(
                          'lang_arabic'.tr(),
                          style: AppDropdownTheme.menuItemStyle(widget.isDark),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'ur',
                        child: Text(
                          'lang_urdu'.tr(),
                          style: AppDropdownTheme.menuItemStyle(widget.isDark),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'fr',
                        child: Text(
                          'lang_french'.tr(),
                          style: AppDropdownTheme.menuItemStyle(widget.isDark),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'id',
                        child: Text(
                          'lang_indonesian'.tr(),
                          style: AppDropdownTheme.menuItemStyle(widget.isDark),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'tr',
                        child: Text(
                          'lang_turkish'.tr(),
                          style: AppDropdownTheme.menuItemStyle(widget.isDark),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedLanguage = v!),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _selectedEthnicity,
                    decoration: AppDropdownTheme.formFieldDecoration(
                      isDark: widget.isDark,
                      labelText: 'ethnicity'.tr(),
                      nested: true,
                    ),
                    icon: AppDropdownTheme.menuTrailingIcon(),
                    dropdownColor: AppDropdownTheme.menuBackground(widget.isDark),
                    borderRadius: AppDropdownTheme.menuBorderRadius(),
                    elevation: AppDropdownTheme.menuElevation(),
                    style: AppDropdownTheme.valueStyle(widget.isDark),
                    items: _ethnicityOptions
                        .map(
                          (e) => DropdownMenuItem(
                            value: e['value'],
                            child: Text(
                              (e['labelKey'] ?? '').tr(),
                              style: AppDropdownTheme.menuItemStyle(widget.isDark),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedEthnicity = v!),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _selectedVisaStatus,
                    decoration: AppDropdownTheme.formFieldDecoration(
                      isDark: widget.isDark,
                      labelText: 'profile_visa_status'.tr(),
                      nested: true,
                    ),
                    icon: AppDropdownTheme.menuTrailingIcon(),
                    dropdownColor: AppDropdownTheme.menuBackground(widget.isDark),
                    borderRadius: AppDropdownTheme.menuBorderRadius(),
                    elevation: AppDropdownTheme.menuElevation(),
                    style: AppDropdownTheme.valueStyle(widget.isDark),
                    items: ['unknown', 'pending', 'issued', 'rejected', 'expired']
                        .map(
                          (s) => DropdownMenuItem(
                            value: s,
                            child: Text(
                              'status_$s'.tr(),
                              style: AppDropdownTheme.menuItemStyle(widget.isDark),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedVisaStatus = v!),
                  ),
                ),
              ],
            ),
            
            SizedBox(height: 24.h),
            
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                iconColor: AppColors.primary,
                collapsedIconColor: textPrimary,
                title: _buildSectionTitle('provisioning_optional_logistics'.tr()),
                children: [
                  SizedBox(height: 8.h),
                  DropdownButtonFormField<String?>(
                    value: _selectedHotelId,
                    isExpanded: true,
                    decoration: AppDropdownTheme.formFieldDecoration(
                      isDark: widget.isDark,
                      labelText: 'group_hotel_name'.tr(),
                      prefixIcon: Icon(Symbols.apartment),
                      nested: true,
                    ),
                    icon: AppDropdownTheme.menuTrailingIcon(),
                    dropdownColor: AppDropdownTheme.menuBackground(widget.isDark),
                    borderRadius: AppDropdownTheme.menuBorderRadius(),
                    elevation: AppDropdownTheme.menuElevation(),
                    style: AppDropdownTheme.valueStyle(widget.isDark),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(
                          'group_no_hotel'.tr(),
                          style: AppDropdownTheme.menuItemStyle(widget.isDark),
                        ),
                      ),
                      ...widget.hotels.map(
                        (h) => DropdownMenuItem<String?>(
                          value: h.id,
                          child: Text(
                            h.name,
                            style: AppDropdownTheme.menuItemStyle(widget.isDark),
                          ),
                        ),
                      ),
                    ],
                    onChanged: widget.isLoadingResources
                        ? null
                        : (v) {
                            setState(() {
                              _selectedHotelId = v;
                              _selectedRoomId = null;
                            });
                          },
                  ),
                  SizedBox(height: 12.h),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _selectedRoomId,
                          isExpanded: true,
                          decoration: AppDropdownTheme.formFieldDecoration(
                            isDark: widget.isDark,
                            labelText: 'group_room_number'.tr(),
                            prefixIcon: Icon(Symbols.meeting_room),
                            nested: true,
                          ),
                          icon: AppDropdownTheme.menuTrailingIcon(),
                          dropdownColor:
                              AppDropdownTheme.menuBackground(widget.isDark),
                          borderRadius: AppDropdownTheme.menuBorderRadius(),
                          elevation: AppDropdownTheme.menuElevation(),
                          style: AppDropdownTheme.valueStyle(widget.isDark),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'group_no_room'.tr(),
                                style:
                                    AppDropdownTheme.menuItemStyle(widget.isDark),
                              ),
                            ),
                            ...rooms.map(
                              (r) {
                                final full =
                                    r.currentOccupancy >= r.capacity;
                                final base = AppDropdownTheme.menuItemStyle(
                                  widget.isDark,
                                  fontSize: 13,
                                );
                                return DropdownMenuItem<String?>(
                                  value: r.id,
                                  child: Text(
                                    '${r.roomNumber}${r.floor != null ? ' (F${r.floor})' : ''} - ${r.currentOccupancy}/${r.capacity}',
                                    style: full
                                        ? base.copyWith(
                                            color: Colors.green.shade400,
                                          )
                                        : base,
                                  ),
                                );
                              },
                            ),
                          ],
                          onChanged: selectedHotel == null
                              ? null
                              : (v) => setState(() => _selectedRoomId = v),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _selectedBusId,
                          isExpanded: true,
                          decoration: AppDropdownTheme.formFieldDecoration(
                            isDark: widget.isDark,
                            labelText: 'group_bus_number'.tr(),
                            prefixIcon: Icon(Symbols.directions_bus),
                            nested: true,
                          ),
                          icon: AppDropdownTheme.menuTrailingIcon(),
                          dropdownColor:
                              AppDropdownTheme.menuBackground(widget.isDark),
                          borderRadius: AppDropdownTheme.menuBorderRadius(),
                          elevation: AppDropdownTheme.menuElevation(),
                          style: AppDropdownTheme.valueStyle(widget.isDark),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(
                                'group_no_bus'.tr(),
                                style:
                                    AppDropdownTheme.menuItemStyle(widget.isDark),
                              ),
                            ),
                            ...widget.buses.map(
                              (b) => DropdownMenuItem<String?>(
                                value: b.id,
                                child: Text(
                                  b.destination.isEmpty
                                      ? b.busNumber
                                      : '${b.busNumber} - ${b.destination}',
                                  style: AppDropdownTheme.menuItemStyle(
                                    widget.isDark,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _selectedBusId = v),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  TextFormField(
                    controller: _nationalIdCtrl,
                    decoration: InputDecoration(
                      labelText: 'reg_passport'.tr(),
                      prefixIcon: Icon(Symbols.badge),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  TextFormField(
                    controller: _medicalHistoryCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'reg_medical'.tr(),
                      prefixIcon: Icon(Symbols.medical_services),
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 24.h),
            
            SizedBox(
              width: double.infinity,
              height: 56.h,
              child: ElevatedButton(
                onPressed: widget.isProvisioning ? null : _handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
                ),
                child: widget.isProvisioning
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Symbols.add_circle, color: Colors.white),
                          SizedBox(width: 8.w),
                          Text(
                            'reg_create_account'.tr(),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w700,
                            ),
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

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontFamily: 'Lexend',
        fontWeight: FontWeight.w600,
        fontSize: 14.sp,
        color: widget.isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
        letterSpacing: 0.5,
      ),
    );
  }
}
