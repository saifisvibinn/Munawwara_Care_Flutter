import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../../core/theme/app_colors.dart';
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

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _ageCtrl.dispose();
    _nationalIdCtrl.dispose();
    _medicalHistoryCtrl.dispose();
    super.dispose();
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
    
    // We don't clear immediately, let the parent handle success and then call back if needed
    // or we can expose a reset method. For now, let's just clear on submit if not provisioning.
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
                  'Provision Account',
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
            
            _buildSectionTitle('Basic Information'),
            SizedBox(height: 12.h),
            
            TextFormField(
              controller: _fullNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Symbols.person),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            SizedBox(height: 12.h),
            
            TextFormField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Symbols.phone),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            SizedBox(height: 12.h),
            
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: TextFormField(
                    controller: _ageCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Age'),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      final num = int.tryParse(v.trim());
                      if (num == null || num < 1 || num > 120) return 'Invalid';
                      return null;
                    },
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedLanguage,
                    decoration: const InputDecoration(labelText: 'Language'),
                    items: [
                      DropdownMenuItem(value: 'en', child: Text('lang_english'.tr())),
                      DropdownMenuItem(value: 'ar', child: Text('lang_arabic'.tr())),
                      DropdownMenuItem(value: 'ur', child: Text('lang_urdu'.tr())),
                      DropdownMenuItem(value: 'fr', child: Text('lang_french'.tr())),
                      DropdownMenuItem(value: 'id', child: Text('lang_indonesian'.tr())),
                      DropdownMenuItem(value: 'tr', child: Text('lang_turkish'.tr())),
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
                    initialValue: _selectedEthnicity,
                    decoration: const InputDecoration(labelText: 'Ethnicity'),
                    items: [
                      'Arab', 'South Asian', 'Turkic', 'Persian', 
                      'Malay/Indonesian', 'African', 'Kurdish', 
                      'Berber', 'European Muslim', 'Other'
                    ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setState(() => _selectedEthnicity = v!),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedVisaStatus,
                    decoration: const InputDecoration(labelText: 'Visa Status'),
                    items: ['unknown', 'pending', 'issued', 'rejected', 'expired']
                        .map((s) => DropdownMenuItem(
                          value: s, 
                          child: Text(
                            s.toUpperCase(),
                            style: TextStyle(fontSize: 12.sp, fontFamily: 'Lexend'),
                          ),
                        ))
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
                title: _buildSectionTitle('Optional Logistics'),
                children: [
                  SizedBox(height: 8.h),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedHotelId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Hotel',
                      prefixIcon: Icon(Symbols.apartment),
                    ),
                    items: [
                      DropdownMenuItem<String>(value: null, child: Text('group_no_hotel'.tr())),
                      ...widget.hotels.map((h) => DropdownMenuItem(value: h.id, child: Text(h.name))),
                    ],
                    onChanged: widget.isLoadingResources ? null : (v) {
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
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedRoomId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Room',
                            prefixIcon: Icon(Symbols.meeting_room),
                          ),
                          items: [
                            DropdownMenuItem<String>(value: null, child: Text('group_no_room'.tr())),
                            ...rooms.map((r) => DropdownMenuItem(
                              value: r.id, 
                              child: Text(r.floor == null ? r.roomNumber : '${r.roomNumber} (F${r.floor})')
                            )),
                          ],
                          onChanged: selectedHotel == null ? null : (v) => setState(() => _selectedRoomId = v),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedBusId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Bus',
                            prefixIcon: Icon(Symbols.directions_bus),
                          ),
                          items: [
                            DropdownMenuItem<String>(value: null, child: Text('group_no_bus'.tr())),
                            ...widget.buses.map((b) => DropdownMenuItem(
                              value: b.id, 
                              child: Text(b.destination.isEmpty ? b.busNumber : '${b.busNumber} - ${b.destination}')
                            )),
                          ],
                          onChanged: (v) => setState(() => _selectedBusId = v),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  TextFormField(
                    controller: _nationalIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'National ID / Passport',
                      prefixIcon: Icon(Symbols.badge),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  TextFormField(
                    controller: _medicalHistoryCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Medical Conditions / Notes',
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
                            'Create Account',
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
