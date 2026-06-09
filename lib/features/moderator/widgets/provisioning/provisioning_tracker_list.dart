import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dropdown_theme.dart';
import '../../../../core/widgets/app_popup_menu.dart';
import '../../../../core/widgets/phone_number_text.dart';
import '../../models/provisioning_models.dart';
import '../../../shared/widgets/pilgrim_gender_avatar.dart';

class ProvisioningTrackerList extends StatelessWidget {
  final List<ProvisioningItem> items;
  final bool isLoading;
  final bool isDark;
  final String filterStatus;
  final Function(String val) onFilterChanged;
  final VoidCallback onRefresh;
  final Function(ProvisioningItem item) onShowQr;
  final Function(ProvisioningItem item) onShareQr;
  final VoidCallback onShareSelectedText;
  final VoidCallback onShareSelectedImages;
  final Function(ProvisioningItem item) onReissue;
  final Function(ProvisioningItem item) onDelete;
  final bool isSelectionMode;
  final Set<String> selectedIds;
  final VoidCallback onToggleSelectionMode;
  final Function(String id, bool selected) onSelectionChanged;
  final VoidCallback onSelectAll;
  final Function(String id)? onLongPressSelect;

  const ProvisioningTrackerList({
    super.key,
    required this.items,
    required this.isLoading,
    required this.isDark,
    required this.filterStatus,
    required this.onFilterChanged,
    required this.onRefresh,
    required this.onShowQr,
    required this.onShareQr,
    required this.onShareSelectedText,
    required this.onShareSelectedImages,
    required this.onReissue,
    required this.onDelete,
    required this.isSelectionMode,
    required this.selectedIds,
    required this.onToggleSelectionMode,
    required this.onSelectionChanged,
    required this.onSelectAll,
    this.onLongPressSelect,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted =
        isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Symbols.fact_check,
                color: AppColors.primary,
                size: 24.sp,
              ),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'provisioning_tracker_title'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w800,
                      fontSize: 19.sp,
                      height: 1.2,
                      color: textPrimary,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'provisioning_tracker_subtitle'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13.sp,
                      height: 1.35,
                      color: textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 20.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(child: _buildFilterDropdown()),
            SizedBox(width: 8.w),
            PopupMenuButton<String>(
              tooltip: 'group_actions'.tr(),
              padding: EdgeInsets.zero,
              offset: AppPopupMenu.offsetBelowChip,
              shape: AppPopupMenu.panelShape(),
              constraints: AppPopupMenu.panelConstraints(minWidth: 180),
              color: AppPopupMenu.panelColor(isDark),
              onSelected: (val) {
                if (val == 'share_text') onShareSelectedText();
                if (val == 'share_images') onShareSelectedImages();
                if (val == 'toggle_selection') onToggleSelectionMode();
                if (val == 'select_all') onSelectAll();
                if (val == 'refresh') onRefresh();
              },
              icon: Icon(Symbols.more_vert, size: 24.w, color: AppColors.primary),
              itemBuilder: (context) => [
                if (isSelectionMode) ...[
                  PopupMenuItem(
                    value: 'select_all',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.checklist,
                      label: 'provisioning_select_all'.tr(),
                      isDark: isDark,
                      iconColor: AppColors.primary,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share_images',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.picture_as_pdf,
                      label: 'provisioning_share_selected_images'.tr(),
                      isDark: isDark,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share_text',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.description,
                      label: 'provisioning_share_selected_text'.tr(),
                      isDark: isDark,
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'toggle_selection',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.cancel,
                      label: 'provisioning_cancel_selection'.tr(),
                      isDark: isDark,
                      destructive: true,
                    ),
                  ),
                ] else ...[
                  PopupMenuItem(
                    value: 'toggle_selection',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.rule,
                      label: 'provisioning_select_pilgrims'.tr(),
                      isDark: isDark,
                      iconColor: AppColors.primary,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share_images',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.picture_as_pdf,
                      label: 'provisioning_share_pending_images'.tr(),
                      isDark: isDark,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'share_text',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.description,
                      label: 'provisioning_share_pending_text'.tr(),
                      isDark: isDark,
                    ),
                  ),
                ],
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'refresh',
                  child: AppPopupMenu.actionRow(
                    icon: Symbols.refresh,
                    label: isSelectionMode
                        ? 'provisioning_refresh_selected_codes'.tr()
                        : 'group_refresh_status'.tr(),
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: 18.h),
        if (isLoading)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 36.h),
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 3,
              ),
            ),
          )
        else if (items.isEmpty)
          _buildEmptyState()
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _TrackerItemCard(
                item: item,
                isDark: isDark,
                onShowQr: () => onShowQr(item),
                onShareQr: () => onShareQr(item),
                onReissue: () => onReissue(item),
                onDelete: () => onDelete(item),
                isSelectionMode: isSelectionMode,
                isSelected: selectedIds.contains(item.pilgrimId),
                onSelectionChanged: (selected) => onSelectionChanged(item.pilgrimId, selected ?? false),
                onLongPress: () {
                  if (onLongPressSelect != null) {
                    onLongPressSelect!(item.pilgrimId);
                  }
                },
              );
            },
          ),
      ],
    );
  }

  Widget _buildFilterDropdown() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2230) : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: filterStatus,
          isExpanded: true,
          items: [
            DropdownMenuItem(
              value: 'all',
              child: Text(
                'group_status_all'.tr(),
                style: AppDropdownTheme.menuItemStyle(isDark, fontSize: 13),
              ),
            ),
            DropdownMenuItem(
              value: 'pending',
              child: Text(
                'group_status_pending_only'.tr(),
                style: AppDropdownTheme.menuItemStyle(isDark, fontSize: 13),
              ),
            ),
            DropdownMenuItem(
              value: 'activated',
              child: Text(
                'group_status_activated'.tr(),
                style: AppDropdownTheme.menuItemStyle(isDark, fontSize: 13),
              ),
            ),
          ],
          onChanged: (val) {
            if (val != null) onFilterChanged(val);
          },
          style: AppDropdownTheme.valueStyle(isDark, fontSize: 13),
          dropdownColor: AppDropdownTheme.menuBackground(isDark),
          borderRadius: AppDropdownTheme.menuBorderRadius(),
          elevation: AppDropdownTheme.menuElevation(),
          icon: AppDropdownTheme.menuTrailingIcon(
            icon: Symbols.filter_list,
            size: 18.w,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 40.h, horizontal: 20.w),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2230) : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Column(
        children: [
          Icon(
            Symbols.search_off,
            size: 48.w,
            color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
          ),
          SizedBox(height: 12.h),
          Text(
            'provisioning_no_matching_pilgrims'.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackerItemCard extends StatelessWidget {
  final ProvisioningItem item;
  final bool isDark;
  final VoidCallback onShowQr;
  final VoidCallback onShareQr;
  final VoidCallback onReissue;
  final VoidCallback onDelete;
  final bool isSelectionMode;
  final bool isSelected;
  final Function(bool?)? onSelectionChanged;
  final VoidCallback? onLongPress;

  const _TrackerItemCard({
    required this.item,
    required this.isDark,
    required this.onShowQr,
    required this.onShareQr,
    required this.onReissue,
    required this.onDelete,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelectionChanged,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final isActivated = item.status.toLowerCase() == 'activated';
    final isSelectable = !isActivated && item.token != null;

    final shellBorder = isSelectionMode && isSelected
        ? Border.all(color: AppColors.primary, width: 2)
        : null;

    Widget cardContent = Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: shellBorder,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: EdgeInsets.all(14.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isSelectionMode && isSelectable) ...[
                Checkbox(
                  value: isSelected,
                  onChanged: onSelectionChanged,
                  activeColor: AppColors.primary,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.r)),
                ),
                SizedBox(width: 4.w),
              ],
              PilgrimGenderAvatar(
                gender: item.gender,
                size: 42.w,
                imageUrl: item.profilePicture,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.fullName,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                      ),
                    ),
                    PhoneNumberText(
                      item.phoneNumber,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusBadge(status: item.status),
                  PopupMenuButton<String>(
                    tooltip: 'group_actions'.tr(),
                    padding: EdgeInsets.zero,
                    offset: AppPopupMenu.offsetRowTrailingMore,
                    shape: AppPopupMenu.panelShape(),
                    constraints: AppPopupMenu.panelConstraints(minWidth: 150),
                    color: AppPopupMenu.panelColor(isDark),
                    onSelected: (val) {
                      if (val == 'show_qr') onShowQr();
                      if (val == 'reissue') onReissue();
                      if (val == 'delete') onDelete();
                    },
                    icon: Icon(Symbols.more_vert, size: 22.w, color: AppColors.primary),
                    itemBuilder: (context) => [
                      if (!isActivated && item.token != null) ...[
                        PopupMenuItem(
                          value: 'show_qr',
                          child: AppPopupMenu.actionRow(
                            icon: Symbols.qr_code_2,
                            label: 'group_show_qr'.tr(),
                            isDark: isDark,
                            iconColor: AppColors.primary,
                          ),
                        ),
                      ],
                      PopupMenuItem(
                        value: 'reissue',
                        child: AppPopupMenu.actionRow(
                          icon: Symbols.refresh,
                          label: 'group_refresh_login_confirm'.tr(),
                          isDark: isDark,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: AppPopupMenu.actionRow(
                          icon: Symbols.delete,
                          label: 'group_delete'.tr(),
                          isDark: isDark,
                          destructive: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          
          if (!isActivated && item.token != null) ...[
            SizedBox(height: 4.h),
            Padding(
              padding: EdgeInsets.only(left: 54.w),
              child: Row(
                children: [
                  Text(
                    '${'group_code'.tr().toUpperCase()}: ',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    item.token!,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ],
          
          if (item.hotelName != null || item.busInfo != null) ...[
            SizedBox(height: 8.h),
            Padding(
              padding: EdgeInsets.only(left: 54.w),
              child: Wrap(
                spacing: 8.w,
                runSpacing: 4.h,
                children: [
                  if (item.hotelName != null)
                    _Tag(icon: Symbols.apartment, label: item.hotelName!, isDark: isDark),
                  if (item.busInfo != null)
                    _Tag(icon: Symbols.directions_bus, label: item.busInfo!, isDark: isDark),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    if (isSelectable) {
      return GestureDetector(
        onTap: isSelectionMode
            ? () {
                if (onSelectionChanged != null) {
                  onSelectionChanged!(!isSelected);
                }
              }
            : null,
        onLongPress: () {
          if (!isSelectionMode && onLongPress != null) {
            onLongPress!();
          }
        },
        child: cardContent,
      );
    }

    return cardContent;
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final isActivated = normalized == 'activated';
    final isExpired = normalized == 'expired';

    final bg = isActivated
        ? const Color(0xFFD1FAE5)
        : isExpired
            ? const Color(0xFFFEE2E2)
            : const Color(0xFFDBEAFE);
    final fg = isActivated
        ? const Color(0xFF065F46)
        : isExpired
            ? const Color(0xFF991B1B)
            : const Color(0xFF1E40AF);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(
        isActivated ? 'group_status_activated'.tr().toUpperCase() : isExpired ? 'status_expired'.tr().toUpperCase() : 'status_pending'.tr().toUpperCase(),
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 10.sp,
          fontWeight: FontWeight.w800,
          color: fg,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;
  const _Tag({required this.icon, required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2230) : const Color(0xFFF5F5F7),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14.sp,
            color: AppColors.primary.withValues(alpha: 0.85),
          ),
          SizedBox(width: 6.w),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
            ),
          ),
        ],
      ),
    );
  }
}
