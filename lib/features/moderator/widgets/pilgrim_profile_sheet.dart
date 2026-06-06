import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../calling/providers/call_provider.dart';
import '../../calling/screens/voice_call_screen.dart';
import '../providers/moderator_provider.dart';
import '../screens/document_viewer_screen.dart';
import '../screens/individual_messages_screen.dart';

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

class _PilgrimProfileSheet extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final bg = isDark ? AppColors.backgroundDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final cooldownSeconds = ref.watch(callProvider).cooldownSeconds;

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
              color: isDark ? Colors.white24 : Colors.black12,
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
                    color: isDark ? AppColors.surfaceDark : AppColors.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(
                      color: isDark ? AppColors.dividerDark : AppColors.primary.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 64.w,
                        height: 64.w,
                        decoration: BoxDecoration(
                          color: pilgrim.hasSOS ? AppColors.error : AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: pilgrim.hasSOS
                              ? Icon(Symbols.warning, color: Colors.white, size: 28.w, fill: 1)
                              : Text(
                                  pilgrim.initials,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22.sp,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      SizedBox(width: 16.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pilgrim.fullName,
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
                                    color: pilgrim.isOnline ? AppColors.success : Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                SizedBox(width: 6.w),
                                Text(
                                  pilgrim.isOnline ? 'dashboard_active'.tr() : 'profile_offline'.tr(),
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 12.sp,
                                    color: pilgrim.isOnline ? AppColors.success : textMuted,
                                  ),
                                ),
                                if (pilgrim.batteryPercent != null) ...[
                                  SizedBox(width: 12.w),
                                  Icon(
                                    Symbols.battery_5_bar,
                                    size: 14.w,
                                    color: _getBatteryColor(pilgrim.batteryStatus),
                                  ),
                                  SizedBox(width: 4.w),
                                  Text(
                                    '${pilgrim.batteryPercent}%',
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      fontSize: 12.sp,
                                      color: _getBatteryColor(pilgrim.batteryStatus),
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
                                groupId: groupId,
                                groupName: 'msg_private_header'.tr(),
                                recipientId: pilgrim.id,
                                recipientName: pilgrim.fullName,
                                currentUserId: currentUserId,
                                recipientLanguage: pilgrim.language,
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
                                remoteUserId: pilgrim.id,
                                remoteUserName: pilgrim.fullName,
                                remotePeerGender: pilgrim.gender,
                              );
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => VoiceCallScreen(
                                initialPeerName: pilgrim.fullName,
                                initialPeerGender: pilgrim.gender,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                if (pilgrim.phoneNumber != null) ...[
                  SizedBox(height: 12.h),
                  _ActionButton(
                    icon: Symbols.phone_forwarded,
                    label: 'profile_call_via_carrier'.tr(args: ['${pilgrim.phoneNumber}']),
                    color: textMuted,
                    isOutlined: true,
                    onTap: () async {
                      final cleaned = pilgrim.phoneNumber!.replaceAll(RegExp(r'[^\d+]'), '');
                      final uri = Uri.parse('tel:$cleaned');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ],

                SizedBox(height: 32.h),

                // Travel & Accommodation Section
                _SectionTitle(title: 'profile_travel_accommodation'.tr(), isDark: isDark),
                _ProfileInfoRow(
                  icon: Symbols.apartment,
                  label: 'group_hotel_name'.tr(),
                  value: pilgrim.hotelName ?? 'profile_not_assigned'.tr(),
                  isDark: isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.meeting_room,
                  label: 'group_room_number'.tr(),
                  value: pilgrim.roomNumber ?? 'profile_not_assigned'.tr(),
                  isDark: isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.directions_bus,
                  label: 'group_bus_number'.tr(),
                  value: pilgrim.busInfo ?? 'profile_not_assigned'.tr(),
                  isDark: isDark,
                ),

                SizedBox(height: 24.h),


                _ProfileInfoRow(
                  icon: Symbols.tag,
                  label: 'Tashera Number',
                  value: pilgrim.tasheraNumber ?? 'profile_not_provided'.tr(),
                  isDark: isDark,
                ),

                SizedBox(height: 24.h),

                // Insurance Details
                _SectionTitle(title: 'Insurance Details', isDark: isDark),
                _ProfileInfoRow(
                  icon: Symbols.health_and_safety,
                  label: 'Insurance Company',
                  value: pilgrim.insuranceCompany?.name ?? 'profile_not_provided'.tr(),
                  isDark: isDark,
                ),

                SizedBox(height: 24.h),

                // Medical History
                _SectionTitle(title: 'profile_medical_history'.tr(), isDark: isDark),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16.w),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: pilgrim.medicalHistory != null && pilgrim.medicalHistory!.isNotEmpty
                          ? AppColors.error.withValues(alpha: 0.2)
                          : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    (pilgrim.medicalHistory == null || pilgrim.medicalHistory!.isEmpty)
                        ? 'profile_no_medical_history'.tr()
                        : pilgrim.medicalHistory!,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 14.sp,
                      color: textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),

                SizedBox(height: 24.h),

                // Personal Details
                _SectionTitle(title: 'profile_personal_details'.tr(), isDark: isDark),
                _ProfileInfoRow(
                  icon: Symbols.badge,
                  label: 'profile_national_id'.tr(),
                  value: pilgrim.nationalId ?? 'profile_not_provided'.tr(),
                  isDark: isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.assignment_ind,
                  label: 'morafeq_name'.tr(),
                  value: pilgrim.morafeqName ?? 'profile_not_provided'.tr(),
                  isDark: isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.phone_callback,
                  label: 'morafeq_phone'.tr(),
                  value: pilgrim.morafeqPhone ?? 'profile_not_provided'.tr(),
                  isDark: isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.mail,
                  label: 'morafeq_email'.tr(),
                  value: pilgrim.morafeqEmail ?? 'profile_not_provided'.tr(),
                  isDark: isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.cake,
                  label: 'reg_age'.tr(),
                  value: pilgrim.age != null ? 'profile_age_years'.tr(args: ['${pilgrim.age}']) : 'profile_not_provided'.tr(),
                  isDark: isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.person,
                  label: 'reg_gender'.tr(),
                  value: pilgrim.gender != null ? 'profile_gender_${pilgrim.gender}'.tr() : 'profile_not_provided'.tr(),
                  isDark: isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.language,
                  label: 'settings_language'.tr(),
                  value: pilgrim.language.toUpperCase(),
                  isDark: isDark,
                ),
                _ProfileInfoRow(
                  icon: Symbols.public,
                  label: 'ethnicity'.tr(),
                  value: pilgrim.ethnicity,
                  isDark: isDark,
                ),

                SizedBox(height: 24.h),
                _SectionTitle(title: 'profile_documents'.tr(), isDark: isDark),
                if ((pilgrim.tasheraDocumentUrl == null || pilgrim.tasheraDocumentUrl!.isEmpty) && pilgrim.documents.isEmpty) ...[
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
                  if (pilgrim.tasheraDocumentUrl != null && pilgrim.tasheraDocumentUrl!.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.only(bottom: 8.h),
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => DocumentViewerScreen(
                                url: pilgrim.tasheraDocumentUrl!,
                                title: 'provisioning_tashera_document'.tr(),
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12.r),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.surfaceDark : AppColors.primary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: isDark ? AppColors.dividerDark : AppColors.primary.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                pilgrim.tasheraDocumentType == 'pdf' ? Symbols.picture_as_pdf : Symbols.image,
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
                  ...pilgrim.documents.map((doc) {
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
                            color: isDark ? AppColors.surfaceDark : AppColors.primary.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: isDark ? AppColors.dividerDark : AppColors.primary.withValues(alpha: 0.1),
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

  Color _getBatteryColor(BatteryStatus status) {
    return switch (status) {
      BatteryStatus.good => AppColors.success,
      BatteryStatus.medium => AppColors.warning,
      BatteryStatus.low => AppColors.error,
      BatteryStatus.unknown => AppColors.textMutedLight,
    };
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

  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.isDark,
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
                Text(
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
