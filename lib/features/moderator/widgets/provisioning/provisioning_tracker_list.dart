import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dropdown_theme.dart';
import '../../../../core/widgets/app_popup_menu.dart';
import '../../models/provisioning_models.dart';

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
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'provisioning_tracker_title'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 16.sp,
                      color: textPrimary,
                    ),
                  ),
                  Text(
                    'provisioning_tracker_subtitle'.tr(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 11.sp,
                      color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelectionMode) ...[
              IconButton(
                onPressed: onSelectAll,
                icon: Icon(Symbols.checklist, size: 20.w, color: AppColors.primary),
                tooltip: 'provisioning_select_all'.tr(),
              ),
              PopupMenuButton<String>(
                tooltip: 'provisioning_bulk_share_selected'.tr(),
                padding: EdgeInsets.zero,
                offset: AppPopupMenu.offsetBelowChip,
                shape: AppPopupMenu.panelShape(),
                constraints: AppPopupMenu.panelConstraints(),
                color: AppPopupMenu.panelColor(isDark),
                onSelected: (val) {
                  if (val == 'text') onShareSelectedText();
                  if (val == 'images') onShareSelectedImages();
                },
                icon: Icon(Symbols.ios_share, size: 20.w, color: AppColors.primary),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'images',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.image,
                      label: 'provisioning_share_selected_images'.tr(),
                      isDark: isDark,
                      iconColor: AppColors.primary,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'text',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.description,
                      label: 'provisioning_share_selected_text'.tr(),
                      isDark: isDark,
                      iconColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ] else ...[
              PopupMenuButton<String>(
                tooltip: 'provisioning_bulk_share_pending'.tr(),
                padding: EdgeInsets.zero,
                offset: AppPopupMenu.offsetBelowChip,
                shape: AppPopupMenu.panelShape(),
                constraints: AppPopupMenu.panelConstraints(),
                color: AppPopupMenu.panelColor(isDark),
                onSelected: (val) {
                  if (val == 'text') onShareSelectedText();
                  if (val == 'images') onShareSelectedImages();
                },
                icon: Icon(Symbols.ios_share, size: 20.w, color: AppColors.primary),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'images',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.image,
                      label: 'provisioning_share_pending_images'.tr(),
                      isDark: isDark,
                      iconColor: AppColors.primary,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'text',
                    child: AppPopupMenu.actionRow(
                      icon: Symbols.description,
                      label: 'provisioning_share_pending_text'.tr(),
                      isDark: isDark,
                      iconColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ],
            IconButton(
              onPressed: onToggleSelectionMode,
              icon: Icon(isSelectionMode ? Symbols.cancel : Symbols.rule, size: 20.w, color: isSelectionMode ? Colors.red : AppColors.primary),
              tooltip: isSelectionMode ? 'provisioning_cancel_selection'.tr() : 'provisioning_select_pilgrims'.tr(),
            ),
            SizedBox(width: 4.w),
            _buildFilterDropdown(),
          ],
        ),
        SizedBox(height: 16.h),
        if (items.isEmpty)
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
              );
            },
          ),
      ],
    );
  }

  Widget _buildFilterDropdown() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: AppDropdownTheme.inlineContainerDecoration(isDark),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: filterStatus,
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
        color: isDark ? AppColors.surfaceDark.withValues(alpha: 0.5) : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Icon(Symbols.search_off, size: 48.w, color: AppColors.textMutedLight),
          SizedBox(height: 12.h),
          Text(
            'provisioning_no_matching_pilgrims'.tr(),
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
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    final textMuted = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;
    final isActivated = item.status.toLowerCase() == 'activated';

    final isSelectable = !isActivated && item.token != null;

    Widget cardContent = Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
          color: isSelectionMode && isSelected 
              ? AppColors.primary 
              : (isDark ? AppColors.dividerDark : AppColors.dividerLight),
          width: isSelectionMode && isSelected ? 2 : 1,
        ),
      ),
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isSelectionMode && isSelectable) ...[
                Checkbox(
                  value: isSelected,
                  onChanged: onSelectionChanged,
                  activeColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.r)),
                ),
                SizedBox(width: 8.w),
              ],
              _Avatar(initials: _getInitials(item.fullName), isDark: isDark),
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
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    Text(
                      item.phoneNumber,
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontSize: 12.sp,
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusBadge(status: item.status),
            ],
          ),
          
          if (!isActivated && item.token != null) ...[
            SizedBox(height: 16.h),
            Container(
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '${'group_code'.tr().toUpperCase()}: ',
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        item.token!,
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _ActionButton(
                        icon: Symbols.qr_code_2,
                        onPressed: onShowQr,
                        color: AppColors.primary,
                        isDark: isDark,
                      ),
                      SizedBox(width: 8.w),
                      _ActionButton(
                        icon: Symbols.share,
                        onPressed: onShareQr,
                        color: AppColors.primary,
                        isDark: isDark,
                      ),
                      SizedBox(width: 8.w),
                      _ActionButton(
                        icon: Symbols.refresh,
                        onPressed: onReissue,
                        color: textPrimary,
                        isDark: isDark,
                      ),
                      SizedBox(width: 8.w),
                      _ActionButton(
                        icon: Symbols.delete,
                        onPressed: onDelete,
                        color: Colors.red.shade400,
                        isDark: isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else if (isActivated) ...[
             SizedBox(height: 12.h),
             Row(
               mainAxisAlignment: MainAxisAlignment.end,
               children: [
                 _ActionButton(
                    icon: Symbols.refresh,
                    onPressed: onReissue,
                    color: textPrimary,
                    isDark: isDark,
                  ),
                  SizedBox(width: 8.w),
                  _ActionButton(
                    icon: Symbols.delete,
                    onPressed: onDelete,
                    color: Colors.red.shade400,
                    isDark: isDark,
                  ),
               ],
             ),
          ],
          
          if (item.hotelName != null || item.busInfo != null) ...[
            SizedBox(height: 12.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 4.h,
              children: [
                if (item.hotelName != null)
                  _Tag(icon: Symbols.apartment, label: item.hotelName!, isDark: isDark),
                if (item.busInfo != null)
                  _Tag(icon: Symbols.directions_bus, label: item.busInfo!, isDark: isDark),
              ],
            ),
          ],
        ],
      ),
    );

    if (isSelectionMode && isSelectable) {
      return GestureDetector(
        onTap: () {
          if (onSelectionChanged != null) {
            onSelectionChanged!(!isSelected);
          }
        },
        child: cardContent,
      );
    }

    return cardContent;
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts.last[0]).toUpperCase();
  }
}

class _Avatar extends StatelessWidget {
  final String initials;
  final bool isDark;
  const _Avatar({required this.initials, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42.w,
      height: 42.w,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w700,
            fontSize: 16.sp,
            color: AppColors.primary,
          ),
        ),
      ),
    );
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

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Color color;
  final bool isDark;

  const _ActionButton({
    required this.icon,
    required this.onPressed,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isDark ? Colors.white10 : Colors.white,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10.r),
        child: Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            border: Border.all(color: isDark ? Colors.white10 : Colors.grey.shade200),
            borderRadius: BorderRadius.circular(10.r),
          ),
          child: Icon(icon, size: 18.w, color: color),
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
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: isDark ? Colors.white10 : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10.w, color: AppColors.textMutedLight),
          SizedBox(width: 4.w),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 10.sp,
              fontWeight: FontWeight.w500,
              color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
            ),
          ),
        ],
      ),
    );
  }
}
