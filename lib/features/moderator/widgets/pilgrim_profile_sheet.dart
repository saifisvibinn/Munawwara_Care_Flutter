import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_number_utils.dart';
import '../../../core/widgets/phone_number_text.dart';
import '../../calling/providers/call_provider.dart';
import '../../calling/screens/voice_call_screen.dart';
import '../../shared/widgets/pilgrim_gender_avatar.dart';
import '../providers/moderator_provider.dart';
import '../screens/document_viewer_screen.dart';
import '../screens/individual_messages_screen.dart';

/// True when [value] matches backend AES iv:ciphertext hex wire format.
bool _looksLikeEncryptedField(String? value) {
  if (value == null || value.isEmpty) return false;
  final colon = value.indexOf(':');
  if (colon != 32) return false;
  return RegExp(r'^[0-9a-f]+:', caseSensitive: false).hasMatch(value);
}

void showPilgrimProfileSheet(
  BuildContext context,
  PilgrimInGroup pilgrim,
  String groupId,
  String currentUserId,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) {
      return _PilgrimProfileSheet(
        pilgrim: pilgrim,
        groupId: groupId,
        currentUserId: currentUserId,
        isDark: isDark,
      );
    },
  );
}

class _PilgrimProfileSheet extends ConsumerStatefulWidget {
  final PilgrimInGroup pilgrim;
  final String groupId;
  final String currentUserId;
  final bool isDark;

  const _PilgrimProfileSheet({
    required this.pilgrim,
    required this.groupId,
    required this.currentUserId,
    required this.isDark,
  });

  @override
  ConsumerState<_PilgrimProfileSheet> createState() =>
      _PilgrimProfileSheetState();
}

class _PilgrimProfileSheetState extends ConsumerState<_PilgrimProfileSheet> {
  late PilgrimInGroup _pilgrim;
  bool _isLoadingDetails = true;
  String? _detailsError;

  @override
  void initState() {
    super.initState();
    _pilgrim = widget.pilgrim;
    _loadProfileDetails();
  }

  Future<void> _loadProfileDetails() async {
    final fetched = await ref
        .read(moderatorProvider.notifier)
        .fetchPilgrimById(widget.pilgrim.id);
    if (!mounted) return;
    setState(() {
      _isLoadingDetails = false;
      if (fetched != null) {
        _pilgrim = widget.pilgrim.mergeProfileDetails(fetched);
        _detailsError = null;
      } else {
        _detailsError = 'profile_details_load_failed'.tr();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.isDark ? AppColors.backgroundDark : Colors.white;
    final textPrimary =
        widget.isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted =
        widget.isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final cooldownSeconds = ref.watch(callProvider).cooldownSeconds;
    final medicalHistory = _pilgrim.medicalHistory;
    final hasEncryptedMedicalHistory =
        _looksLikeEncryptedField(medicalHistory);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: EdgeInsets.only(top: 12.h),
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: widget.isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),

          // Header
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 10.h, 10.w, 10.h),
            child: Row(
              children: [
                Text(
                  'profile_title'.tr(),
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Symbols.close, color: textMuted),
                ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              children: [
                // Top Info Card
                Container(
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: widget.isDark ? AppColors.surfaceDark : AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(
                      color: widget.isDark ? AppColors.dividerDark : AppColors.primary.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      _PilgrimProfileAvatar(
                        gender: _pilgrim.gender,
                        imageUrl: _pilgrim.profilePicture,
                        hasSos: _pilgrim.hasSOS,
                        size: 64.w,
                      ),
                      SizedBox(width: 16.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _pilgrim.fullName,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                                color: textPrimary,
                              ),
                            ),
                            SizedBox(height: 4.h),
                            Row(
                              children: [
                                Container(
                                  width: 8.w,
                                  height: 8.w,
                                  decoration: BoxDecoration(
                                    color: _pilgrim.isOnline ? AppColors.success : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                SizedBox(width: 6.w),
                                Text(
                                  _pilgrim.isOnline ? 'dashboard_active'.tr() : 'profile_offline'.tr(),
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 12.sp,
                                    color: _pilgrim.isOnline ? AppColors.success : textMuted,
                                  ),
                                ),
                                if (_pilgrim.batteryPercent != null) ...[
                                  SizedBox(width: 12.w),
                                  Icon(
                                    Symbols.battery_5_bar,
                                    size: 14.w,
                                    color: _getBatteryColor(_pilgrim.batteryStatus),
                                  ),
                                  SizedBox(width: 4.w),
                                  Text(
                                    '${_pilgrim.batteryPercent}%',
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 12.sp,
                                      color: _getBatteryColor(_pilgrim.batteryStatus),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 24.h),

                // Quick Actions
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Symbols.chat,
                        label: 'tab_chat'.tr(),
                        color: AppColors.primary,
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => IndividualMessagesScreen(
                                groupId: widget.groupId,
                                groupName: 'msg_private_header'.tr(),
                                recipientId: _pilgrim.id,
                                recipientName: _pilgrim.fullName,
                                currentUserId: widget.currentUserId,
                                recipientLanguage: _pilgrim.language,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: _ActionButton(
                        icon: Symbols.call,
                        label: cooldownSeconds > 0 ? '${'call_internet'.tr()} ($cooldownSeconds)' : 'call_internet'.tr(),
                        color: cooldownSeconds > 0 ? AppColors.success.withValues(alpha: 0.5) : AppColors.success,
                        onTap: cooldownSeconds > 0 ? null : () {
                          Navigator.pop(context);
                          ref.read(callProvider.notifier).startCall(
                                remoteUserId: _pilgrim.id,
                                remoteUserName: _pilgrim.fullName,
                                remotePeerGender: _pilgrim.gender,
                                remotePeerProfilePicture:
                                    _pilgrim.profilePicture,
                              );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VoiceCallScreen(
                                initialPeerName: _pilgrim.fullName,
                                initialPeerGender: _pilgrim.gender,
                                initialPeerProfilePicture:
                                    _pilgrim.profilePicture,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                if (_pilgrim.phoneNumber != null) ...[
                  SizedBox(height: 12.h),
                  _ActionButton(
                    icon: Symbols.phone_forwarded,
                    label: 'profile_call_via_carrier'.tr(
                      args: [
                        formatPhoneNumberForDisplay(_pilgrim.phoneNumber!),
                      ],
                    ),
                    color: textMuted,
                    isOutlined: true,
                    onTap: () async {
                      final cleaned = _pilgrim.phoneNumber!.replaceAll(RegExp(r'[^\d+]'), '');
                      final uri = Uri.parse('tel:$cleaned');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ],

                SizedBox(height: 32.h),

                // Travel & Accommodation Section
                _SectionTitle(title: 'profile_travel_accommodation'.tr(), isDark: widget.isDark),
                _ProfileInfoRow(
                  icon: Symbols.apartment,
                  label: 'group_hotel_name'.tr(),
                  value: _pilgrim.hotelName ?? 'profile_not_assigned'.tr(),
                  isDark: widget.isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.meeting_room,
                  label: 'group_room_number'.tr(),
                  value: _pilgrim.roomNumber ?? 'profile_not_assigned'.tr(),
                  isDark: widget.isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.directions_bus,
                  label: 'group_bus_number'.tr(),
                  value: _pilgrim.busInfo ?? 'profile_not_assigned'.tr(),
                  isDark: widget.isDark,
                ),

                SizedBox(height: 24.h),


                _ProfileInfoRow(
                  icon: Symbols.tag,
                  label: 'Tashera Number',
                  value: _sensitiveFieldLabel(_pilgrim.tasheraNumber),
                  isDark: widget.isDark,
                ),

                SizedBox(height: 24.h),

                // Insurance Details
                _SectionTitle(title: 'Insurance Details', isDark: widget.isDark),
                _ProfileInfoRow(
                  icon: Symbols.health_and_safety,
                  label: 'Insurance Company',
                  value: _pilgrim.insuranceCompany?.name ?? 'profile_not_provided'.tr(),
                  isDark: widget.isDark,
                ),

                SizedBox(height: 24.h),

                // Medical History
                _SectionTitle(title: 'profile_medical_history'.tr(), isDark: widget.isDark),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: widget.isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: medicalHistory != null &&
                              medicalHistory.isNotEmpty &&
                              !hasEncryptedMedicalHistory
                          ? AppColors.error.withValues(alpha: 0.2)
                          : Colors.transparent,
                    ),
                  ),
                  child: _isLoadingDetails
                      ? Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 8.h),
                            child: SizedBox(
                              width: 22.w,
                              height: 22.w,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            ),
                          ),
                        )
                      : hasEncryptedMedicalHistory
                          ? SelectableText.rich(
                              TextSpan(
                                text: 'profile_medical_history_unavailable'.tr(),
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14.sp,
                                  color: AppColors.error,
                                  height: 1.5,
                                ),
                              ),
                            )
                          : Text(
                              (medicalHistory == null || medicalHistory.isEmpty)
                                  ? 'profile_no_medical_history'.tr()
                                  : medicalHistory,
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 14.sp,
                                color: textPrimary,
                                height: 1.5,
                              ),
                            ),
                ),
                if (_detailsError != null && !hasEncryptedMedicalHistory) ...[
                  SizedBox(height: 8.h),
                  SelectableText.rich(
                    TextSpan(
                      text: _detailsError,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12.sp,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],

                SizedBox(height: 24.h),

                // Personal Details
                _SectionTitle(title: 'profile_personal_details'.tr(), isDark: widget.isDark),
                _ProfileInfoRow(
                  icon: Symbols.badge,
                  label: 'profile_national_id'.tr(),
                  value: _sensitiveFieldLabel(_pilgrim.nationalId),
                  isDark: widget.isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.assignment_ind,
                  label: 'morafeq_name'.tr(),
                  value: _pilgrim.morafeqName ?? 'profile_not_provided'.tr(),
                  isDark: widget.isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.phone_callback,
                  label: 'morafeq_phone'.tr(),
                  value: _pilgrim.morafeqPhone ?? 'profile_not_provided'.tr(),
                  isDark: widget.isDark,
                  forceLtr: _pilgrim.morafeqPhone != null &&
                      _pilgrim.morafeqPhone!.isNotEmpty,
                ),
                _ProfileInfoRow(
                  icon: Symbols.mail,
                  label: 'morafeq_email'.tr(),
                  value: _pilgrim.morafeqEmail ?? 'profile_not_provided'.tr(),
                  isDark: widget.isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.cake,
                  label: 'reg_age'.tr(),
                  value: _pilgrim.age != null ? 'profile_age_years'.tr(args: ['${_pilgrim.age}']) : 'profile_not_provided'.tr(),
                  isDark: widget.isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.person,
                  label: 'reg_gender'.tr(),
                  value: _pilgrim.gender != null ? 'profile_gender_${_pilgrim.gender}'.tr() : 'profile_not_provided'.tr(),
                  isDark: widget.isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.language,
                  label: 'settings_language'.tr(),
                  value: _pilgrim.language.toUpperCase(),
                  isDark: widget.isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.public,
                  label: 'ethnicity'.tr(),
                  value: _pilgrim.ethnicity,
                  isDark: widget.isDark,
                ),

                SizedBox(height: 24.h),
                _SectionTitle(title: 'profile_documents'.tr(), isDark: widget.isDark),
                if ((_pilgrim.tasheraDocumentUrl == null || _pilgrim.tasheraDocumentUrl!.isEmpty) && _pilgrim.documents.isEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    alignment: Alignment.center,
                    child: Text(
                      'profile_no_documents'.tr(),
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 13.sp,
                        color: textMuted,
                      ),
                    ),
                  ),
                ] else ...[
                  if (_pilgrim.tasheraDocumentUrl != null && _pilgrim.tasheraDocumentUrl!.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.only(bottom: 8.h),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DocumentViewerScreen(
                                url: _pilgrim.tasheraDocumentUrl!,
                                title: 'provisioning_tashera_document'.tr(),
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12.r),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                          decoration: BoxDecoration(
                            color: widget.isDark ? AppColors.surfaceDark : AppColors.primary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: widget.isDark ? AppColors.dividerDark : AppColors.primary.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _pilgrim.tasheraDocumentType == 'pdf' ? Symbols.picture_as_pdf : Symbols.image,
                                color: AppColors.primary,
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
                                        fontSize: 13.5.sp,
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary,
                                      ),
                                    ),
                                    SizedBox(height: 2.h),
                                    Text(
                                      'profile_view_document'.tr(),
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 11.5.sp,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Symbols.open_in_new, color: textMuted, size: 18.sp),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  ..._pilgrim.documents.map((doc) {
                    final isPdf = doc.fileType == 'pdf' || doc.fileUrl.toLowerCase().endsWith('.pdf');
                    return Padding(
                      padding: EdgeInsets.only(bottom: 8.h),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DocumentViewerScreen(
                                url: doc.fileUrl,
                                title: doc.name,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12.r),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                          decoration: BoxDecoration(
                            color: widget.isDark ? AppColors.surfaceDark : AppColors.primary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: widget.isDark ? AppColors.dividerDark : AppColors.primary.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isPdf ? Symbols.picture_as_pdf : Symbols.image,
                                color: AppColors.primary,
                                size: 22.sp,
                              ),
                              SizedBox(width: 12.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      doc.name,
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 13.5.sp,
                                        fontWeight: FontWeight.w600,
                                        color: textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: 2.h),
                                    Text(
                                      'profile_view_document'.tr(),
                                      style: TextStyle(
                                        fontFamily: 'Lexend',
                                        fontSize: 11.5.sp,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Symbols.open_in_new, color: textMuted, size: 18.sp),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],

                SizedBox(height: 40.h),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _sensitiveFieldLabel(String? value) {
    if (value == null || value.isEmpty) {
      return 'profile_not_provided'.tr();
    }
    if (_looksLikeEncryptedField(value)) {
      return 'profile_not_provided'.tr();
    }
    return value;
  }

  Color _getBatteryColor(BatteryStatus status) {
    return switch (status) {
      BatteryStatus.good => AppColors.success,
      BatteryStatus.medium => AppColors.warning,
      BatteryStatus.low => AppColors.error,
      BatteryStatus.unknown => AppColors.textMutedLight,
    };
  }
}

/// Pilgrim portrait with an optional SOS warning badge overlay.
class _PilgrimProfileAvatar extends StatelessWidget {
  final String? gender;
  final String? imageUrl;
  final bool hasSos;
  final double size;

  const _PilgrimProfileAvatar({
    required this.gender,
    required this.imageUrl,
    required this.hasSos,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final badgeSize = size * 0.34;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: hasSos
                  ? Border.all(color: AppColors.error, width: 2.5)
                  : null,
              color: AppColors.primary.withValues(alpha: 0.12),
            ),
            child: ClipOval(
              child: PilgrimGenderAvatar(
                gender: gender,
                size: size,
                imageUrl: imageUrl,
              ),
            ),
          ),
          if (hasSos)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Icon(
                  Symbols.warning,
                  color: Colors.white,
                  size: badgeSize * 0.62,
                  fill: 1,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionTitle({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 11.sp,
          fontWeight: FontWeight.w800,
          color: AppColors.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isDark;
  final bool forceLtr;

  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
    this.forceLtr = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, size: 16.w, color: AppColors.primary),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Lexend',
                    fontSize: 11.sp,
                    color: AppColors.textMutedLight,
                  ),
                ),
                forceLtr
                    ? PhoneNumberText(
                        value,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 14.sp,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      )
                    : Text(
                        value,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w600,
                          fontSize: 14.sp,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isOutlined;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isOutlined = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isOutlined) {
      return SizedBox(
        width: double.infinity,
        height: 48.h,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 18.w, color: color),
          label: Text(
            label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 13.sp,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
          ),
        ),
      );
    }

    return SizedBox(
      height: 48.h,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white, size: 18.w),
        label: Text(
          label,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        ),
      ),
    );
  }
}
