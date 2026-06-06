import 'dart:io';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dropdown_theme.dart';
import '../../models/provisioning_models.dart';
import '../../models/pilgrim_field_options.dart';
import 'provisioning_form_theme.dart';
import '../../../pilgrim/models/insurance_company.dart';

/// Translates a nationality string using the nat_ prefix key.
/// Falls back to the original English value if no translation exists.
String _natTr(String nat) {
  final key = 'nat_${nat.toLowerCase().replaceAll(' ', '_')}';
  final translated = key.tr();
  return translated == key ? nat : translated;
}

/// Translates a language code using the lang_ prefix key.
/// Falls back to the provided label if no translation exists.
String _langTr(String code, String fallback) {
  final key = 'lang_$code';
  final translated = key.tr();
  return translated == key ? fallback : translated;
}

class CreatePilgrimCard extends StatefulWidget {
  final bool isDark;
  final bool isProvisioning;
  final List<HotelOption> hotels;
  final List<InsuranceCompany> insurances;
  final bool isLoadingResources;
  final List<String> ethnicityOptions;
  final List<PilgrimLanguageOption> languageOptions;
  final Function(Map<String, dynamic> data) onCreate;

  const CreatePilgrimCard({
    super.key,
    required this.isDark,
    required this.isProvisioning,
    required this.hotels,
    required this.insurances,
    required this.isLoadingResources,
    required this.ethnicityOptions,
    required this.languageOptions,
    required this.onCreate,
  });

  @override
  State<CreatePilgrimCard> createState() => _CreatePilgrimCardState();
}

class _CreatePilgrimCardState extends State<CreatePilgrimCard> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _altPhoneCtrl = TextEditingController();
  final _morafeqNameCtrl = TextEditingController();
  final _morafeqPhoneCtrl = TextEditingController();
  final _morafeqEmailCtrl = TextEditingController();
  final _tasheraNumberCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _nationalIdCtrl = TextEditingController();
  final _medicalHistoryCtrl = TextEditingController();

  String _selectedLanguage = 'en';
  String? _selectedEthnicity;
  String? _selectedHotelId;
  String? _selectedRoomId;
  String? _selectedInsuranceCompanyId;
  Set<String> _genderSelection = {'male'};

  File? _tasheraDocument;
  String? _tasheraDocumentName;
  final List<File> _documents = [];
  File? _profilePicture;

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _altPhoneCtrl.dispose();
    _morafeqNameCtrl.dispose();
    _morafeqPhoneCtrl.dispose();
    _morafeqEmailCtrl.dispose();
    _tasheraNumberCtrl.dispose();
    _ageCtrl.dispose();
    _nationalIdCtrl.dispose();
    _medicalHistoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTasheraDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _tasheraDocument = File(result.files.single.path!);
          _tasheraDocumentName = result.files.single.name;
        });
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  Future<void> _pickDocument() async {
    if (_documents.length >= 3) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _documents.add(File(result.files.single.path!));
        });
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  Future<void> _pickProfilePicture() async {
    final isDark = widget.isDark;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;

    showModalBottomSheet(
      context: context,
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: EdgeInsets.only(top: 8.h, bottom: 16.h),
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              Text(
                'profile_picture_title'.tr() == 'profile_picture_title'
                    ? 'Profile Picture'
                    : 'profile_picture_title'.tr(),
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontWeight: FontWeight.w700,
                  fontSize: 16.sp,
                  color: textPrimary,
                ),
              ),
              SizedBox(height: 16.h),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded, color: AppColors.primary),
                title: Text(
                  'profile_picture_camera'.tr() == 'profile_picture_camera'
                      ? 'Take Photo'
                      : 'profile_picture_camera'.tr(),
                  style: TextStyle(fontFamily: 'Lexend', color: textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
                title: Text(
                  'profile_picture_gallery'.tr() == 'profile_picture_gallery'
                      ? 'Choose from Gallery'
                      : 'profile_picture_gallery'.tr(),
                  style: TextStyle(fontFamily: 'Lexend', color: textPrimary),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              SizedBox(height: 8.h),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    try {
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );
      if (image == null) return;
      setState(() {
        _profilePicture = File(image.path);
      });
    } catch (e) {
      debugPrint('Error picking profile picture: $e');
    }
  }

  @override
  void didUpdateWidget(covariant CreatePilgrimCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hotelsInsurancesChanged =
        oldWidget.hotels != widget.hotels || oldWidget.insurances != widget.insurances;
    final optionsChanged = oldWidget.ethnicityOptions != widget.ethnicityOptions ||
        oldWidget.languageOptions != widget.languageOptions;

    if (hotelsInsurancesChanged) {
      final hotelOk = _selectedHotelId == null ||
          widget.hotels.any((h) => h.id == _selectedHotelId);
      final insuranceOk = _selectedInsuranceCompanyId == null ||
          widget.insurances.any((i) => i.id == _selectedInsuranceCompanyId);
      var roomOk = true;
      if (_selectedRoomId != null) {
        final h =
            widget.hotels.where((x) => x.id == _selectedHotelId).firstOrNull;
        final rooms = (h?.rooms ?? const <RoomOption>[])
            .where((r) => r.active)
            .toList();
        roomOk = rooms.any((r) => r.id == _selectedRoomId);
      }
      if (!hotelOk || !roomOk || !insuranceOk) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            if (!hotelOk) {
              _selectedHotelId = null;
              _selectedRoomId = null;
            } else if (!roomOk) {
              _selectedRoomId = null;
            }
            if (!insuranceOk) _selectedInsuranceCompanyId = null;
          });
        });
      }
    }

    if (optionsChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          final langCodes =
              widget.languageOptions.map((l) => l.code).toSet();
          if (!langCodes.contains(_selectedLanguage)) {
            _selectedLanguage = widget.languageOptions.isNotEmpty
                ? widget.languageOptions.first.code
                : 'en';
          }
          final ethn = widget.ethnicityOptions.toSet();
          if (_selectedEthnicity != null &&
              !ethn.contains(_selectedEthnicity)) {
            _selectedEthnicity = null;
          }
        });
      });
    }
  }

  void _showEthnicitySearchDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return _SearchSelectionDialog(
          title: 'provisioning_field_ethnicity'.tr(),
          options: widget.ethnicityOptions,
          initialValue: _selectedEthnicity,
          isDark: widget.isDark,
          onSelected: (v) {
            setState(() => _selectedEthnicity = v);
          },
        );
      },
    );
  }

  void _handleSubmit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final selectedHotel =
        widget.hotels.where((h) => h.id == _selectedHotelId).firstOrNull;
    final selectedRoom =
        selectedHotel?.rooms.where((r) => r.id == _selectedRoomId).firstOrNull;

    final data = {
      'full_name': _fullNameCtrl.text.trim(),
      'phone_number': _phoneCtrl.text.trim(),
      'alternative_phone_number': _altPhoneCtrl.text.trim().isEmpty ? null : _altPhoneCtrl.text.trim(),
      'profile_picture': _profilePicture?.path,
      'tashera_document': _tasheraDocument?.path,
      'documents': _documents.map((f) => f.path).toList(),
      'morafeq_name': _morafeqNameCtrl.text.trim().isEmpty ? null : _morafeqNameCtrl.text.trim(),
      'morafeq_phone': _morafeqPhoneCtrl.text.trim().isEmpty ? null : _morafeqPhoneCtrl.text.trim(),
      'morafeq_email': _morafeqEmailCtrl.text.trim().isEmpty ? null : _morafeqEmailCtrl.text.trim(),
      'tashera_number': _tasheraNumberCtrl.text.trim().isEmpty ? null : _tasheraNumberCtrl.text.trim(),
      'insurance_company_id': _selectedInsuranceCompanyId,
      'national_id': _nationalIdCtrl.text.trim(),
      'medical_history': _medicalHistoryCtrl.text.trim(),
      'age': int.tryParse(_ageCtrl.text.trim()),
      'gender': _genderSelection.first,
      'language': _selectedLanguage,
      'ethnicity': _selectedEthnicity ?? 'Other',
      'hotel_id': _selectedHotelId,
      'hotel_name': selectedHotel?.name,
      'room_id': _selectedRoomId,
      'room_number': selectedRoom?.roomNumber,
    };

    widget.onCreate(data);
  }

  Icon _prefix(IconData icon, Color muted) =>
      Icon(icon, size: 20.sp, color: muted);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textMuted =
        widget.isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final textPrimary =
        widget.isDark ? AppColors.textLight : AppColors.textDark;
    final outline =
        widget.isDark ? AppColors.dividerDark : AppColors.dividerLight;

    final selectedHotel =
        widget.hotels.where((h) => h.id == _selectedHotelId).firstOrNull;
    final rooms = (selectedHotel?.rooms ?? const <RoomOption>[])
        .where((r) => r.active)
        .toList();

    final hotelInteractive =
        !widget.isLoadingResources && widget.hotels.isNotEmpty;
    final roomInteractive =
        selectedHotel != null && !widget.isLoadingResources && rooms.isNotEmpty;

    final g = ProvisioningFormTheme.gapMd(context);
    final gSm = ProvisioningFormTheme.gapSm(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: widget.isDark ? AppColors.surfaceDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
        side: BorderSide(
          color: outline.withValues(alpha: widget.isDark ? 0.9 : 0.65),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
        child: Theme(
          data: theme.copyWith(
            inputDecorationTheme:
                ProvisioningFormTheme.inputDecorationTheme(widget.isDark),
            splashColor: AppColors.primary.withValues(alpha: 0.08),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Symbols.person_add,
                      color: AppColors.primary,
                      size: 24.sp,
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        'provisioning_create_account_title'.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                 SizedBox(height: ProvisioningFormTheme.gapLg(context)),
                 Center(
                   child: Stack(
                     children: [
                       GestureDetector(
                         onTap: _pickProfilePicture,
                         child: Container(
                           width: 80.w,
                           height: 80.w,
                           decoration: BoxDecoration(
                             shape: BoxShape.circle,
                             color: widget.isDark
                                 ? Colors.white12
                                 : AppColors.primary.withValues(alpha: 0.08),
                             border: Border.all(
                               color: widget.isDark
                                   ? Colors.white24
                                   : AppColors.primary.withValues(alpha: 0.24),
                               width: 2.w,
                             ),
                           ),
                           clipBehavior: Clip.antiAlias,
                           child: _profilePicture != null
                               ? Image.file(
                                   _profilePicture!,
                                   fit: BoxFit.cover,
                                   width: 80.w,
                                   height: 80.w,
                                 )
                               : Image.asset(
                                   _genderSelection.first == 'female'
                                       ? 'assets/static/pilgrim_female.png'
                                       : 'assets/static/pilgrim_male.png',
                                   fit: BoxFit.cover,
                                   width: 80.w,
                                   height: 80.w,
                                 ),
                         ),
                       ),
                       Positioned(
                         bottom: 0,
                         right: 0,
                         child: GestureDetector(
                           onTap: _pickProfilePicture,
                           child: Container(
                             padding: EdgeInsets.all(6.w),
                             decoration: const BoxDecoration(
                               shape: BoxShape.circle,
                               color: AppColors.primary,
                             ),
                             child: Icon(
                               Symbols.camera_enhance,
                               color: Colors.white,
                               size: 14.sp,
                             ),
                           ),
                         ),
                       ),
                       if (_profilePicture != null)
                         Positioned(
                           top: 0,
                           right: 0,
                           child: GestureDetector(
                             onTap: () => setState(() => _profilePicture = null),
                             child: Container(
                               padding: EdgeInsets.all(4.w),
                               decoration: const BoxDecoration(
                                 shape: BoxShape.circle,
                                 color: Colors.red,
                               ),
                               child: Icon(
                                 Symbols.close,
                                 color: Colors.white,
                                 size: 12.sp,
                               ),
                             ),
                           ),
                         ),
                     ],
                   ),
                 ),
                 SizedBox(height: ProvisioningFormTheme.gapMd(context)),
                Text(
                  'provisioning_basic_information'.tr(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                SizedBox(height: gSm),
                AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _fullNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        textInputAction: TextInputAction.next,
                        decoration: ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: 'reg_full_name'.tr(),
                          prefixIcon: _prefix(Symbols.person, textMuted),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'provisioning_required'.tr()
                            : null,
                      ),
                      SizedBox(height: g),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        textInputAction: TextInputAction.next,
                        decoration: ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: 'reg_phone'.tr(),
                          prefixIcon: _prefix(Symbols.phone, textMuted),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'provisioning_required'.tr()
                            : null,
                      ),
                      SizedBox(height: g),
                      TextFormField(
                        controller: _altPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: 'provisioning_alt_phone'.tr(),
                          prefixIcon: _prefix(Symbols.phone, textMuted),
                        ),
                        validator: (v) {
                          if (v != null && v.trim().isNotEmpty) {
                            if (v.trim() == _phoneCtrl.text.trim()) {
                              return 'provisioning_invalid'.tr();
                            }
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: g),
                Text(
                  'reg_gender'.tr(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w600,
                    color: textMuted,
                  ),
                ),
                SizedBox(height: gSm),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment<String>(
                      value: 'male',
                      label: Text('reg_male'.tr()),
                      icon: Icon(Symbols.male, size: 18.sp),
                    ),
                    ButtonSegment<String>(
                      value: 'female',
                      label: Text('reg_female'.tr()),
                      icon: Icon(Symbols.female, size: 18.sp),
                    ),
                  ],
                  selected: _genderSelection,
                  onSelectionChanged: (next) =>
                      setState(() => _genderSelection = next),
                  multiSelectionEnabled: false,
                  emptySelectionAllowed: false,
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 12.h,
                    ),
                    side: BorderSide(color: outline),
                    foregroundColor: textMuted,
                    selectedForegroundColor: AppColors.primary,
                    selectedBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.12),
                    textStyle: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w600,
                      fontSize: 13.sp,
                    ),
                  ),
                ),
                SizedBox(height: g),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 5,
                      child: TextFormField(
                        controller: _ageCtrl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        decoration: ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: 'reg_age'.tr(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'provisioning_required'.tr();
                          }
                          final n = int.tryParse(v.trim());
                          if (n == null || n < 1 || n > 120) {
                            return 'provisioning_invalid'.tr();
                          }
                          return null;
                        },
                      ),
                    ),
                    SizedBox(width: gSm),
                    Expanded(
                      flex: 7,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _selectedLanguage,
                        decoration: ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: 'settings_language'.tr(),
                        ),
                        icon: AppDropdownTheme.menuTrailingIcon(),
                        dropdownColor:
                            AppDropdownTheme.menuBackground(widget.isDark),
                        borderRadius: AppDropdownTheme.menuBorderRadius(),
                        elevation: AppDropdownTheme.menuElevation(),
                        style: AppDropdownTheme.valueStyle(widget.isDark),
                        items: widget.languageOptions
                            .map(
                              (opt) => DropdownMenuItem<String>(
                                value: opt.code,
                                child: Text(
                                  _langTr(opt.code, opt.label),
                                  style: AppDropdownTheme.menuItemStyle(
                                    widget.isDark,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: widget.languageOptions.isEmpty
                            ? null
                            : (v) => setState(
                                  () => _selectedLanguage = v ?? 'en',
                                ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: g),
                _MorafeqInfoExpansion(
                  isDark: widget.isDark,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _morafeqNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: 'morafeq_name'.tr(),
                          prefixIcon: _prefix(Symbols.person, textMuted),
                        ),
                        validator: (v) {
                          final phone = _morafeqPhoneCtrl.text.trim();
                          if (phone.isNotEmpty && (v == null || v.trim().isEmpty)) {
                            return 'provisioning_required'.tr();
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: g),
                      TextFormField(
                        controller: _morafeqPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: 'morafeq_phone'.tr(),
                          prefixIcon: _prefix(Symbols.phone, textMuted),
                        ),
                        validator: (v) {
                          final name = _morafeqNameCtrl.text.trim();
                          if (name.isNotEmpty && (v == null || v.trim().isEmpty)) {
                            return 'provisioning_required'.tr();
                          }
                          return null;
                        },
                      ),
                      SizedBox(height: g),
                      TextFormField(
                        controller: _morafeqEmailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: '${'morafeq_email'.tr()} (Optional)',
                          prefixIcon: _prefix(Symbols.mail, textMuted),
                        ),
                        validator: (v) {
                          if (v != null && v.trim().isNotEmpty) {
                            final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
                            if (!emailRegex.hasMatch(v.trim())) {
                              return 'provisioning_invalid'.tr();
                            }
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                SizedBox(height: g),
                _AdditionalDetailsExpansion(
                  isDark: widget.isDark,
                  textPrimary: textPrimary,
                  textMuted: textMuted,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: widget.ethnicityOptions.isEmpty
                            ? null
                            : _showEthnicitySearchDialog,
                        borderRadius: BorderRadius.circular(12.r),
                        child: IgnorePointer(
                          child: TextFormField(
                            key: ValueKey('ethnicity_$_selectedEthnicity'),
                            initialValue: _selectedEthnicity == null
                                ? null
                                : _natTr(_selectedEthnicity!),
                            decoration: ProvisioningFormTheme.fieldDecoration(
                              context: context,
                              isDark: widget.isDark,
                              hintText: 'provisioning_field_ethnicity'.tr(),
                            ),
                            style: AppDropdownTheme.valueStyle(widget.isDark),
                            validator: (v) => _selectedEthnicity == null
                                ? 'provisioning_required'.tr()
                                : null,
                          ),
                        ),
                      ),
                      SizedBox(height: g),
                      DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue:
                            hotelInteractive ? _selectedHotelId : null,
                        decoration: ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: 'provisioning_field_hotel'.tr(),
                          prefixIcon: _prefix(Symbols.apartment, textMuted),
                        ),
                        icon: AppDropdownTheme.menuTrailingIcon(),
                        dropdownColor:
                            AppDropdownTheme.menuBackground(widget.isDark),
                        borderRadius: AppDropdownTheme.menuBorderRadius(),
                        elevation: AppDropdownTheme.menuElevation(),
                        style: AppDropdownTheme.valueStyle(widget.isDark),
                        items: hotelInteractive
                            ? widget.hotels
                                .map(
                                  (h) => DropdownMenuItem<String?>(
                                    value: h.id,
                                    child: Text(
                                      h.name,
                                      style: AppDropdownTheme.menuItemStyle(
                                        widget.isDark,
                                      ),
                                    ),
                                  ),
                                )
                                .toList()
                            : [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  enabled: false,
                                  child: Text(
                                    'provisioning_no_hotels'.tr(),
                                    style: AppDropdownTheme.menuItemStyle(
                                      widget.isDark,
                                    ),
                                  ),
                                ),
                              ],
                        onChanged: hotelInteractive
                            ? (v) {
                                setState(() {
                                  _selectedHotelId = v;
                                  _selectedRoomId = null;
                                });
                              }
                            : null,
                      ),
                      SizedBox(height: g),
                      DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue:
                            roomInteractive ? _selectedRoomId : null,
                        decoration:
                            ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: 'provisioning_field_room'.tr(),
                          prefixIcon: _prefix(Symbols.bed, textMuted),
                        ),
                        icon: AppDropdownTheme.menuTrailingIcon(),
                        dropdownColor:
                            AppDropdownTheme.menuBackground(
                          widget.isDark,
                        ),
                        borderRadius:
                            AppDropdownTheme.menuBorderRadius(),
                        elevation: AppDropdownTheme.menuElevation(),
                        style:
                            AppDropdownTheme.valueStyle(widget.isDark),
                        items: roomInteractive
                            ? rooms
                                .map(
                                  (r) {
                                    final full =
                                        r.currentOccupancy >= r.capacity;
                                    final base =
                                        AppDropdownTheme.menuItemStyle(
                                      widget.isDark,
                                      fontSize: 13,
                                    );
                                    return DropdownMenuItem<String?>(
                                      value: r.id,
                                      child: Text(
                                        '${r.roomNumber}'
                                        '${r.floor != null ? ' (F${r.floor})' : ''}'
                                        ' - ${r.currentOccupancy}/'
                                        '${r.capacity}',
                                        style: full
                                            ? base.copyWith(
                                                color: Colors
                                                    .green.shade400,
                                              )
                                            : base,
                                      ),
                                    );
                                  },
                                )
                                .toList()
                            : [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  enabled: false,
                                  child: Text(
                                    selectedHotel == null
                                        ? 'manage_select_hotel_first'
                                            .tr()
                                        : 'provisioning_no_rooms'.tr(),
                                    style:
                                        AppDropdownTheme.menuItemStyle(
                                      widget.isDark,
                                    ),
                                  ),
                                ),
                              ],
                        onChanged: roomInteractive
                            ? (v) =>
                                setState(() => _selectedRoomId = v)
                            : null,
                      ),
                      SizedBox(height: g),
                      TextFormField(
                        controller: _nationalIdCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: 'reg_passport'.tr(),
                          prefixIcon: _prefix(Symbols.badge, textMuted),
                        ),
                      ),
                      SizedBox(height: g),
                      TextFormField(
                        controller: _tasheraNumberCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: 'provisioning_tashera_number'.tr(),
                          prefixIcon: _prefix(Symbols.tag, textMuted),
                        ),
                      ),
                      SizedBox(height: g),
                      InkWell(
                        onTap: _pickTasheraDocument,
                        borderRadius: BorderRadius.circular(12.r),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: outline.withValues(alpha: 0.8),
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Symbols.upload_file,
                                color: _tasheraDocument != null ? AppColors.primary : textMuted,
                                size: 22.sp,
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'provisioning_tashera_document'.tr(),
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 13.sp,
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary,
                                      ),
                                    ),
                                    SizedBox(height: 2.h),
                                    Text(
                                      _tasheraDocumentName ?? 'provisioning_tashera_tap_to_upload'.tr(),
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 11.5.sp,
                                        color: _tasheraDocument != null ? AppColors.primary : textMuted,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (_tasheraDocument != null) ...[
                                SizedBox(width: 8.w),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _tasheraDocument = null;
                                      _tasheraDocumentName = null;
                                    });
                                  },
                                  child: Icon(Symbols.close, color: Colors.red, size: 20.sp),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (_documents.isNotEmpty) ...[
                        SizedBox(height: gSm),
                        ..._documents.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final file = entry.value;
                          final name = file.path.split(Platform.pathSeparator).last;
                          final isPdf = name.toLowerCase().endsWith('.pdf');
                          return Padding(
                            padding: EdgeInsets.only(bottom: 8.h),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8.r),
                                color: widget.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
                                border: Border.all(
                                  color: outline.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isPdf ? Symbols.picture_as_pdf : Symbols.image,
                                    color: AppColors.primary,
                                    size: 20.sp,
                                  ),
                                  SizedBox(width: 10.w),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 12.sp,
                                        color: textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _documents.removeAt(idx);
                                      });
                                    },
                                    child: Icon(Symbols.close, color: Colors.red, size: 18.sp),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                      if (_documents.length < 3) ...[
                        SizedBox(height: gSm),
                        InkWell(
                          onTap: _pickDocument,
                          borderRadius: BorderRadius.circular(12.r),
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                color: outline.withValues(alpha: 0.8),
                                style: BorderStyle.solid,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Symbols.upload_file,
                                  color: textMuted,
                                  size: 22.sp,
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'provisioning_documents'.tr(),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 13.sp,
                                          fontWeight: FontWeight.w600,
                                          color: textPrimary,
                                        ),
                                      ),
                                      SizedBox(height: 2.h),
                                      Text(
                                        'provisioning_tap_to_upload_doc'.tr(),
                                        style: TextStyle(
                                          fontFamily: 'Lexend',
                                          fontSize: 11.5.sp,
                                          color: textMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      SizedBox(height: g),
                      DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue: _selectedInsuranceCompanyId,
                        decoration: ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: 'provisioning_insurance_company'.tr(),
                          prefixIcon: _prefix(Symbols.health_and_safety, textMuted),
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
                              'provisioning_no_insurance'.tr(),
                              style: AppDropdownTheme.menuItemStyle(widget.isDark),
                            ),
                          ),
                          ...widget.insurances.map(
                            (ins) => DropdownMenuItem<String?>(
                              value: ins.id,
                              child: Text(
                                ins.name,
                                style: AppDropdownTheme.menuItemStyle(widget.isDark),
                              ),
                            ),
                          ),
                        ],
                        onChanged: (v) => setState(() => _selectedInsuranceCompanyId = v),
                      ),
                      SizedBox(height: g),
                      TextFormField(
                        controller: _medicalHistoryCtrl,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: ProvisioningFormTheme.fieldDecoration(
                          context: context,
                          isDark: widget.isDark,
                          hintText: 'reg_medical'.tr(),
                          prefixIcon:
                              _prefix(Symbols.medical_services, textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: ProvisioningFormTheme.gapLg(context)),
                FilledButton(
                  onPressed: widget.isProvisioning ? null : _handleSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: widget.isProvisioning
                      ? SizedBox(
                          height: 22.h,
                          width: 22.h,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Symbols.add_circle, size: 20.sp),
                            SizedBox(width: 8.w),
                            Text(
                              'reg_create_account'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdditionalDetailsExpansion extends StatelessWidget {
  const _AdditionalDetailsExpansion({
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
    required this.child,
  });

  final bool isDark;
  final Color textPrimary;
  final Color textMuted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dividerClr =
        isDark ? AppColors.dividerDark : AppColors.dividerLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 4.h),
          child: Divider(height: 1, thickness: 1, color: dividerClr),
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            maintainState: true,
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.only(top: 4.h, bottom: 4.h),
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            shape: const RoundedRectangleBorder(side: BorderSide.none),
            collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
            iconColor: AppColors.primary,
            collapsedIconColor: AppColors.primary,
            initiallyExpanded: false,
            title: Text(
              'provisioning_additional_details'.tr(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Text(
                'provisioning_optional_logistics'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w500,
                      fontSize: 12.5.sp,
                      color: textMuted.withValues(alpha: 0.95),
                    ),
              ),
            ),
            children: [child],
          ),
        ),
      ],
    );
  }
}

class _MorafeqInfoExpansion extends StatelessWidget {
  const _MorafeqInfoExpansion({
    required this.isDark,
    required this.textPrimary,
    required this.textMuted,
    required this.child,
  });

  final bool isDark;
  final Color textPrimary;
  final Color textMuted;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dividerClr =
        isDark ? AppColors.dividerDark : AppColors.dividerLight;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 4.h),
          child: Divider(height: 1, thickness: 1, color: dividerClr),
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            maintainState: true,
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.only(top: 4.h, bottom: 4.h),
            backgroundColor: Colors.transparent,
            collapsedBackgroundColor: Colors.transparent,
            shape: const RoundedRectangleBorder(side: BorderSide.none),
            collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
            iconColor: AppColors.primary,
            collapsedIconColor: AppColors.primary,
            initiallyExpanded: false,
            title: Text(
              'morafeq_companion_info'.tr(),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontFamily: 'Lexend',
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: Text(
                'morafeq_subtitle'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w500,
                      fontSize: 12.5.sp,
                      color: textMuted.withValues(alpha: 0.95),
                    ),
              ),
            ),
            children: [child],
          ),
        ),
      ],
    );
  }
}

class _SearchSelectionDialog extends StatefulWidget {
  const _SearchSelectionDialog({
    required this.title,
    required this.options,
    required this.initialValue,
    required this.isDark,
    required this.onSelected,
  });

  final String title;
  final List<String> options;
  final String? initialValue;
  final bool isDark;
  final ValueChanged<String> onSelected;

  @override
  State<_SearchSelectionDialog> createState() => _SearchSelectionDialogState();
}

class _SearchSelectionDialogState extends State<_SearchSelectionDialog> {
  final _searchController = TextEditingController();
  List<String> _filteredOptions = [];

  @override
  void initState() {
    super.initState();
    _filteredOptions = widget.options;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredOptions = widget.options
          .where((o) => o.toLowerCase().contains(q))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = widget.isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = widget.isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final bg = widget.isDark ? const Color(0xFF1A1A24) : Colors.white;
    final outline = widget.isDark ? AppColors.dividerDark : AppColors.dividerLight;

    return Dialog(
      backgroundColor: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
      child: Container(
        padding: EdgeInsets.all(16.w),
        width: 320.w,
        height: 400.h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(fontFamily: 'Lexend', fontSize: 13.sp, color: textPrimary),
              decoration: InputDecoration(
                hintText: 'common_search'.tr(),
                hintStyle: TextStyle(color: textMuted),
                prefixIcon: Icon(Symbols.search, size: 18.sp, color: textMuted),
                contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide: BorderSide(color: outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.r),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            Expanded(
              child: _filteredOptions.isEmpty
                  ? Center(
                      child: Text(
                        'No matches found',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 12.sp,
                          color: textMuted,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _filteredOptions.length,
                      separatorBuilder: (context, index) => Divider(height: 1, color: outline),
                      itemBuilder: (context, index) {
                        final option = _filteredOptions[index];
                        final isSelected = option == widget.initialValue;
                        return ListTile(
                          onTap: () {
                            widget.onSelected(option);
                            Navigator.pop(context);
                          },
                          contentPadding: EdgeInsets.symmetric(horizontal: 8.w),
                          title: Text(
                            _natTr(option),
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontSize: 13.sp,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                              color: isSelected ? AppColors.primary : textPrimary,
                            ),
                          ),
                          trailing: isSelected
                              ? Icon(Symbols.check, size: 18.sp, color: AppColors.primary)
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
