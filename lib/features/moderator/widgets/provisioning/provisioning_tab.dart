import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

import '../../../../core/services/api_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dropdown_theme.dart';
import '../../../../core/widgets/custom_dialog.dart';
import '../../../../core/widgets/standard_snackbar.dart';
import '../../../auth/providers/auth_provider.dart';
import '../../models/provisioning_models.dart';
import 'provisioning_summary.dart';
import 'create_pilgrim_card.dart';
import 'provisioning_tracker_list.dart';

class ProvisioningTab extends ConsumerStatefulWidget {
  const ProvisioningTab({super.key});

  @override
  ConsumerState<ProvisioningTab> createState() => _ProvisioningTabState();
}

class _ProvisioningTabState extends ConsumerState<ProvisioningTab> {
  bool _isLoadingGroups = false;
  bool _isLoadingStatus = false;
  bool _isLoadingResources = false;
  bool _isProvisioning = false;
  bool _isSharing = false;
  final ScreenshotController _screenshotController = ScreenshotController();


  String? _selectedGroupId;
  List<GroupOption> _groups = const [];
  List<HotelOption> _hotels = const [];
  List<BusOption> _buses = const [];
  List<ProvisioningItem> _items = const [];
  ProvisioningSummary _summary = const ProvisioningSummary();

  bool _provisioningStatusSupported = true;
  String _filterStatus = 'pending';
  bool _isBulkCapturing = false;
  double _bulkCaptureProgress = 0;
  bool _isSelectionMode = false;
  final Set<String> _selectedPilgrimIds = {};
  /// Bumped after a successful provision so [CreatePilgrimCard] remounts with empty fields.
  int _createPilgrimFormGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _isLoadingGroups = true;
    });

    try {
      final resp = await ApiService.dio.get('/groups/dashboard');
      final raw = resp.data;
      final data = raw is Map<String, dynamic>
          ? (raw['data'] as List<dynamic>? ?? const [])
          : (raw as List<dynamic>? ?? const []);

      final groups = data
          .whereType<Map>()
          .map((g) {
            final map = Map<String, dynamic>.from(g);
            return GroupOption(
              id: map['_id']?.toString() ?? map['id']?.toString() ?? '',
              name: map['group_name']?.toString() ?? 'provisioning_unnamed_group'.tr(),
            );
          })
          .where((g) => g.id.isNotEmpty)
          .toList();

      if (mounted) {
        setState(() {
          final seen = <String>{};
          _groups = groups.where((g) => seen.add(g.id)).toList();
          if (_selectedGroupId == null && _groups.isNotEmpty) {
            _selectedGroupId = _groups.first.id;
          } else if (_selectedGroupId != null &&
              !_groups.any((g) => g.id == _selectedGroupId)) {
            _selectedGroupId = _groups.isNotEmpty ? _groups.first.id : null;
          }
        });
      }

      if (_selectedGroupId != null) {
        await Future.wait([_loadResourceOptions(), _loadProvisioningStatus()]);
      }
    } on DioException catch (_) {
      // Error handled by StandardSnackBar if needed, or ignored for background loads
    } finally {
      if (mounted) setState(() => _isLoadingGroups = false);
    }
  }

  Future<void> _loadResourceOptions() async {
    final groupId = _selectedGroupId;
    if (groupId == null) {
      setState(() {
        _hotels = const [];
        _buses = const [];
      });
      return;
    }

    setState(() => _isLoadingResources = true);

    try {
      final resp = await ApiService.dio.get('/groups/$groupId/resource-options');
      final raw = resp.data;
      final payload = raw is Map<String, dynamic>
          ? (raw['data'] as Map<String, dynamic>? ?? raw)
          : <String, dynamic>{};

      final hotelsRaw = (payload['hotels'] as List<dynamic>? ?? const []);
      final busesRaw = (payload['buses'] as List<dynamic>? ?? const []);

      if (!mounted) return;
      setState(() {
        _hotels = hotelsRaw.whereType<Map>().map((h) {
          final map = Map<String, dynamic>.from(h);
          final roomsRaw = (map['rooms'] as List<dynamic>? ?? const []);
          return HotelOption(
            id: map['_id']?.toString() ?? '',
            name: map['name']?.toString() ?? 'provisioning_default_hotel'.tr(),
            rooms: roomsRaw.whereType<Map>().map((r) {
              final room = Map<String, dynamic>.from(r);
              return RoomOption(
                id: room['_id']?.toString() ?? '',
                roomNumber: room['room_number']?.toString() ?? '-',
                floor: room['floor']?.toString(),
                active: room['active'] != false,
                capacity: (room['capacity'] as num?)?.toInt() ?? 1,
                currentOccupancy: (room['current_occupancy'] as num?)?.toInt() ?? 0,
              );
            }).toList(),
          );
        }).toList();

        _buses = busesRaw.whereType<Map>().map((b) {
          final map = Map<String, dynamic>.from(b);
          return BusOption(
            id: map['_id']?.toString() ?? '',
            busNumber: map['bus_number']?.toString() ?? '-',
            destination: map['destination']?.toString() ?? '',
          );
        }).toList();
      });
    } on DioException catch (_) {
      // Logic for fallback is omitted for brevity as it was for older backends
    } finally {
      if (mounted) setState(() => _isLoadingResources = false);
    }
  }

  Future<void> _loadProvisioningStatus() async {
    final groupId = _selectedGroupId;
    if (groupId == null || !_provisioningStatusSupported) return;

    setState(() => _isLoadingStatus = true);

    try {
      final resp = await ApiService.dio.get('/auth/groups/$groupId/provisioning-status');
      final raw = resp.data;
      final payload = raw is Map<String, dynamic>
          ? (raw['data'] as Map<String, dynamic>? ?? raw)
          : <String, dynamic>{};
      final summaryMap = (payload['summary'] as Map<String, dynamic>? ?? <String, dynamic>{});
      final itemsRaw = (payload['items'] as List<dynamic>? ?? const []);

      if (!mounted) return;
      setState(() {
        _summary = ProvisioningSummary.fromJson(summaryMap);
        _items = itemsRaw.whereType<Map>().map((i) => ProvisioningItem.fromJson(Map<String, dynamic>.from(i))).toList();
      });
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        if (!mounted) return;
        setState(() => _provisioningStatusSupported = false);
      }
    } finally {
      if (mounted) setState(() => _isLoadingStatus = false);
    }
  }

  Future<void> _handleCreatePilgrim(Map<String, dynamic> data) async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;

    setState(() => _isProvisioning = true);

    try {
      await ApiService.dio.post('/auth/groups/$groupId/provision-pilgrim', data: data);
      await _loadProvisioningStatus();
      if (mounted) {
        setState(() => _createPilgrimFormGeneration++);
        StandardSnackBar.showSuccess(context, 'group_pilgrim_created_success'.tr());
      }
    } on DioException catch (e) {
      if (mounted) StandardSnackBar.showError(context, ApiService.parseError(e));
    } finally {
      if (mounted) setState(() => _isProvisioning = false);
    }
  }

  void _handleShareSelectedText() {
    final itemsToShare = _isSelectionMode
        ? _items.where((i) => _selectedPilgrimIds.contains(i.pilgrimId) && i.token != null).toList()
        : _items.where((i) => i.status.toLowerCase() == 'pending').toList();

    if (itemsToShare.isEmpty) {
      StandardSnackBar.showError(context, 'provisioning_no_valid_accounts'.tr());
      return;
    }

    final group = _groups.where((g) => g.id == _selectedGroupId).firstOrNull;
    final groupName = group?.name ?? 'provisioning_fallback_group'.tr();
    final modName = ref.read(authProvider).fullName ?? 'provisioning_fallback_moderator'.tr();

    final StringBuffer buffer = StringBuffer();
    buffer.writeln('provisioning_share_credentials_intro'.tr(args: ['app_title'.tr()]));
    buffer.writeln('provisioning_share_line_group'.tr(args: [groupName]));
    buffer.writeln('provisioning_share_line_invited'.tr(args: [modName]));
    buffer.writeln('provisioning_share_separator'.tr());
    
    for (var item in itemsToShare) {
      buffer.writeln('\n${'provisioning_share_line_name'.tr(args: [item.fullName])}');
      buffer.writeln('provisioning_share_line_code'.tr(args: [item.token ?? '---']));
    }
    
    buffer.writeln('\n${'provisioning_share_separator'.tr()}');
    buffer.writeln('provisioning_share_footer'.tr());
    
    Share.share(buffer.toString(), subject: 'provisioning_share_subject'.tr(args: [groupName]));
  }

  Future<void> _handleShareSelectedImages() async {
    final itemsToShare = _isSelectionMode
        ? _items.where((i) => _selectedPilgrimIds.contains(i.pilgrimId) && i.token != null).toList()
        : _items.where((i) => i.status.toLowerCase() == 'pending').toList();

    if (itemsToShare.isEmpty) {
      StandardSnackBar.showError(context, 'provisioning_no_valid_accounts'.tr());
      return;
    }

    setState(() {
      _isBulkCapturing = true;
      _bulkCaptureProgress = 0;
    });

    final group = _groups.where((g) => g.id == _selectedGroupId).firstOrNull;
    final groupName = group?.name ?? 'provisioning_fallback_group'.tr();
    final modName = ref.read(authProvider).fullName ?? 'provisioning_fallback_moderator'.tr();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mediaQuery = MediaQuery.of(context);

    try {
      final files = <XFile>[];
      final tempDir = await getTemporaryDirectory();

      for (int i = 0; i < itemsToShare.length; i++) {
        if (!mounted) break;
        final item = itemsToShare[i];
        if (mounted) setState(() => _bulkCaptureProgress = (i + 1) / itemsToShare.length);

        // Capture image
        final Uint8List imageBytes = await _screenshotController.captureFromWidget(
          MediaQuery(
            data: mediaQuery,
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: 300.w,
                child: _LoginCredentialCard(
                  item: item,
                  groupName: groupName,
                  modName: modName,
                  isDark: isDark,
                  isForSharing: true,
                ),
              ),
            ),
          ),
          context: context,
          delay: const Duration(milliseconds: 100),
        );

        if (imageBytes.isNotEmpty) {
          final String fileName = 'login_${item.fullName.replaceAll(' ', '_')}.png';
          final File file = File('${tempDir.path}/$fileName');
          await file.writeAsBytes(imageBytes);
          files.add(XFile(file.path));
        }
      }

      if (files.isNotEmpty) {
        await Share.shareXFiles(files, text: 'provisioning_share_caption_group'.tr(args: [groupName]));
      }
    } catch (e) {
      if (mounted) StandardSnackBar.showError(context, 'provisioning_generate_images_failed'.tr(args: ['$e']));
    } finally {
      if (mounted) {
        setState(() {
          _isBulkCapturing = false;
        });
      }
    }
  }

  Future<void> _handleReissue(ProvisioningItem item) async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;

    final confirmed = await StandardDialog.show(
      context: context,
      title: 'group_refresh_login_title',
      confirmText: 'group_refresh_login_confirm',
      content: 'group_refresh_login_body',
      contentArgs: [item.fullName],
    );

    if (confirmed != true) return;

    try {
      final resp = await ApiService.dio.post('/auth/groups/$groupId/pilgrims/${item.pilgrimId}/reissue-login');
      final raw = resp.data;
      final payload = raw is Map<String, dynamic> ? (raw['data'] as Map<String, dynamic>? ?? raw) : <String, dynamic>{};
      final login = (payload['one_time_login'] as Map<String, dynamic>? ?? <String, dynamic>{});
      final token = login['token']?.toString();

      if (token != null) {
        await _loadProvisioningStatus();
        final newItem = item.copyWith(token: token);
        final group = _groups.where((g) => g.id == _selectedGroupId).firstOrNull;
        final modName = ref.read(authProvider).fullName ?? 'provisioning_fallback_moderator'.tr();
        _showCredentialDialog(newItem, group?.name ?? 'provisioning_fallback_group'.tr(), modName);
      }
    } on DioException catch (e) {
      if (mounted) StandardSnackBar.showError(context, ApiService.parseError(e));
    }
  }

  Future<void> _handleDelete(ProvisioningItem item) async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;

    final confirmed = await StandardDialog.show(
      context: context,
      title: 'group_delete_pilgrim_title',
      confirmText: 'group_delete',
      isDestructive: true,
      contentWidget: Text(
        'group_delete_pilgrim_body'.tr(args: [item.fullName]),
        style: const TextStyle(fontFamily: 'Lexend'),
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.dio.delete('/auth/groups/$groupId/pilgrims/${item.pilgrimId}');
      await _loadProvisioningStatus();
      if (mounted) StandardSnackBar.showSuccess(context, 'provisioning_pilgrim_removed'.tr());
    } on DioException catch (e) {
      if (mounted) StandardSnackBar.showError(context, ApiService.parseError(e));
    }
  }

  Future<void> _handleShareQr(ProvisioningItem item) async {
    final group = _groups.where((g) => g.id == _selectedGroupId).firstOrNull;
    final modName = ref.read(authProvider).fullName ?? 'provisioning_fallback_moderator'.tr();
    
    _showCredentialDialog(item, group?.name ?? 'provisioning_fallback_group'.tr(), modName);
  }

  void _showCredentialDialog(ProvisioningItem item, String groupName, String modName) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _LoginCredentialCard(
                item: item,
                groupName: groupName,
                modName: modName,
                isDark: Theme.of(context).brightness == Brightness.dark,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 300,
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, size: 18),
                        label: Text('group_close'.tr(), style: const TextStyle(fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.textDark,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatefulBuilder(
                        builder: (context, setDialogState) {
                          return ElevatedButton.icon(
                            onPressed: _isSharing ? null : () async {
                              setDialogState(() => _isSharing = true);
                              try {
                                final bytes = await _screenshotController.captureFromWidget(
                                  MediaQuery(
                                    data: const MediaQueryData(),
                                    child: Material(
                                      child: Directionality(
                                        textDirection: ui.TextDirection.ltr,
                                        child: _LoginCredentialCard(
                                          item: item,
                                          groupName: groupName,
                                          modName: modName,
                                          isDark: false,
                                          width: 300,
                                        ),
                                      ),
                                    ),
                                  ),
                                  context: context,
                                );
                                
                                final directory = await getTemporaryDirectory();
                                final imagePath = await File('${directory.path}/login_qr_${item.pilgrimId}.png').create();
                                await imagePath.writeAsBytes(bytes);
                                
                                await Share.shareXFiles([XFile(imagePath.path)], text: 'provisioning_share_caption_person'.tr(args: [item.fullName]));
                              } catch (e) {
                                if (context.mounted) StandardSnackBar.showError(context, 'provisioning_generate_image_failed'.tr());
                              } finally {
                                if (context.mounted) setDialogState(() => _isSharing = false);
                              }
                            },
                            icon: _isSharing 
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.share, size: 18),
                            label: Text(
                              _isSharing ? 'provisioning_wait'.tr() : 'group_share_invite'.tr(),
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        }
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final groupName = _groups.firstWhere((g) => g.id == _selectedGroupId, orElse: () => GroupOption(id: '', name: 'provisioning_fallback_group'.tr())).name;
    final modName = ref.read(authProvider).fullName ?? 'provisioning_fallback_moderator'.tr();
    
    final filteredItems = _items.where((i) {
      if (_filterStatus == 'pending') return i.status != 'activated';
      if (_filterStatus == 'activated') return i.status == 'activated';
      return true;
    }).toList();

    return Stack(
      children: [
        RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            await Future.wait([_loadGroups(), _loadProvisioningStatus()]);
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 100.h),
            children: [
              _buildHeader(isDark),
              SizedBox(height: 24.h),
              
              _buildGroupSelector(isDark),
              SizedBox(height: 24.h),
              
              ProvisioningSummaryCards(summary: _summary, isDark: isDark),
              SizedBox(height: 24.h),
              
              CreatePilgrimCard(
                key: ValueKey('create_${_selectedGroupId}_$_createPilgrimFormGeneration'),
                isDark: isDark,
                isProvisioning: _isProvisioning,
                hotels: _hotels,
                buses: _buses,
                isLoadingResources: _isLoadingResources,
                onCreate: _handleCreatePilgrim,
              ),
              SizedBox(height: 32.h),
              
              if (_selectedGroupId != null)
                ProvisioningTrackerList(
                  items: filteredItems,
                  isLoading: _isLoadingStatus,
                  isDark: isDark,
                  filterStatus: _filterStatus,
                  onFilterChanged: (v) => setState(() => _filterStatus = v),
                  onRefresh: _loadProvisioningStatus,
                  onShowQr: (item) => _showCredentialDialog(item, groupName, modName),
                  onShareQr: (item) => _handleShareQr(item),
                  onShareSelectedText: _handleShareSelectedText,
                  onShareSelectedImages: _handleShareSelectedImages,
                  onReissue: _handleReissue,
                  onDelete: _handleDelete,
                  isSelectionMode: _isSelectionMode,
                  selectedIds: _selectedPilgrimIds,
                  onToggleSelectionMode: () {
                    setState(() {
                      _isSelectionMode = !_isSelectionMode;
                      if (!_isSelectionMode) _selectedPilgrimIds.clear();
                    });
                  },
                  onSelectionChanged: (id, selected) {
                    setState(() {
                      if (selected) {
                        _selectedPilgrimIds.add(id);
                      } else {
                        _selectedPilgrimIds.remove(id);
                      }
                    });
                  },
                  onSelectAll: () {
                    setState(() {
                      final itemsWithTokens = filteredItems.where((i) => i.token != null).map((i) => i.pilgrimId).toList();
                      if (_selectedPilgrimIds.length == itemsWithTokens.length) {
                         _selectedPilgrimIds.clear();
                      } else {
                         _selectedPilgrimIds.addAll(itemsWithTokens);
                      }
                    });
                  },
                ),
            ],
          ),
        ),
        if (_isBulkCapturing)
          Container(
            color: Colors.black54,
            child: Center(
              child: Card(
                color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 32.h),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 60.w,
                        height: 60.w,
                        child: CircularProgressIndicator(
                          value: _bulkCaptureProgress,
                          strokeWidth: 6,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          color: AppColors.primary,
                        ),
                      ),
                      SizedBox(height: 24.h),
                      Text(
                        'provisioning_generating_images'.tr(),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontWeight: FontWeight.w800,
                          fontSize: 18.sp,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                      SizedBox(height: 8.h),
                      Text(
                        'provisioning_progress_complete'.tr(args: ['${(_bulkCaptureProgress * 100).toInt()}']),
                        style: TextStyle(
                          fontFamily: 'Lexend',
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
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

  Widget _buildHeader(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'provisioning_header_title'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontWeight: FontWeight.w800,
            fontSize: 28.sp,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        Text(
          'provisioning_header_subtitle'.tr(),
          style: TextStyle(
            fontFamily: 'Lexend',
            fontSize: 14.sp,
            color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
          ),
        ),
      ],
    );
  }

  Widget _buildGroupSelector(bool isDark) {
    return Container(
      decoration: AppDropdownTheme.inlineContainerDecoration(isDark),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedGroupId,
          isExpanded: true,
          hint: Text(
            'group_select'.tr(),
            style: AppDropdownTheme.menuItemStyle(isDark),
          ),
          items: _groups
              .map(
                (g) => DropdownMenuItem(
                  value: g.id,
                  child: Text(
                    g.name,
                    style: AppDropdownTheme.menuItemStyle(isDark),
                  ),
                ),
              )
              .toList(),
          onChanged: _isLoadingGroups
              ? null
              : (v) async {
                  setState(() {
                    _selectedGroupId = v;
                  });
                  await Future.wait([
                    _loadResourceOptions(),
                    _loadProvisioningStatus(),
                  ]);
                },
          style: AppDropdownTheme.valueStyle(isDark),
          dropdownColor: AppDropdownTheme.menuBackground(isDark),
          borderRadius: AppDropdownTheme.menuBorderRadius(),
          elevation: AppDropdownTheme.menuElevation(),
          icon: _isLoadingGroups
              ? SizedBox(
                  width: 16.w,
                  height: 16.w,
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : AppDropdownTheme.menuTrailingIcon(),
        ),
      ),
    );
  }
}

class _LoginCredentialCard extends StatelessWidget {
  final ProvisioningItem item;
  final String groupName;
  final String modName;
  final bool isDark;
  final double? width;
  final bool isForSharing;

  const _LoginCredentialCard({
    required this.item,
    required this.groupName,
    required this.modName,
    required this.isDark,
    this.width,
    this.isForSharing = false,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? const Color(0xFF1E1E2E) : Colors.white;
    final textPrimary = isDark ? Colors.white : AppColors.textDark;
    final textSecondary = isDark ? AppColors.textMutedLight : AppColors.textMutedDark;

    return Container(
      width: width ?? 300, // Reduced from 320 to 300 for better mobile fit
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with Logo and App Name
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.05),
              ),
              child: Row(
                children: [
                  Image.asset('assets/static/logo.jpeg', width: 40, height: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'app_title'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.primary,
                          ),
                        ),
                        Text(
                          'provisioning_card_subtitle'.tr(),
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 10,
                            color: textSecondary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Group and Mod Info
                  Text(
                    groupName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'group_moderated_by'.tr(args: [modName]),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12,
                      color: AppColors.primary.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  Text(
                    item.fullName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: textPrimary,
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // QR Code
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: QrImageView(
                      data: item.token ?? '',
                      version: QrVersions.auto,
                      size: 180,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: Color(0xFF1A1A1A),
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Login Code
                  Text(
                    'group_code'.tr().toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMutedDark,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      item.token ?? '-',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.0,
                        color: AppColors.primary,
                        fontFamily: 'Lexend',
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Footer Warning
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Symbols.warning, size: 14, color: Colors.orange.shade700),
                            const SizedBox(width: 6),
                            Text(
                              'provisioning_security_warning'.tr(),
                              style: TextStyle(
                                fontFamily: 'Lexend',
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'provisioning_security_warning_body'.tr(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 10,
                            color: textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
