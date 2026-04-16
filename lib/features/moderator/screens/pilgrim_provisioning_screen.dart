import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/api_service.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/moderator_provider.dart';

class PilgrimProvisioningScreen extends ConsumerStatefulWidget {
  const PilgrimProvisioningScreen({super.key});

  @override
  ConsumerState<PilgrimProvisioningScreen> createState() =>
      _PilgrimProvisioningScreenState();
}

class _PilgrimProvisioningScreenState
    extends ConsumerState<PilgrimProvisioningScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _nationalIdCtrl = TextEditingController();
  final _medicalHistoryCtrl = TextEditingController();

  bool _isLoadingGroups = false;
  bool _isLoadingStatus = false;
  bool _isLoadingResources = false;
  bool _isProvisioning = false;
  String? _error;

  String? _selectedGroupId;
  String _selectedLanguage = 'en';
  String _selectedVisaStatus = 'unknown';
  String _selectedEthnicity = 'Other';
  String? _selectedHotelId;
  String? _selectedRoomId;
  String? _selectedBusId;

  List<_GroupOption> _groups = const [];
  List<_HotelOption> _hotels = const [];
  List<_BusOption> _buses = const [];
  List<_ProvisioningItem> _items = const [];
  _ProvisioningSummary _summary = const _ProvisioningSummary();

  bool _provisioningStatusSupported = true;
  String _filterStatus = 'pending';

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _ageCtrl.dispose();
    _nationalIdCtrl.dispose();
    _medicalHistoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _isLoadingGroups = true;
      _error = null;
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
            return _GroupOption(
              id: map['_id']?.toString() ?? map['id']?.toString() ?? '',
              name: map['group_name']?.toString() ?? 'Unnamed Group',
            );
          })
          .where((g) => g.id.isNotEmpty)
          .toList();

      setState(() {
        _groups = groups;
        if (_selectedGroupId == null && groups.isNotEmpty) {
          _selectedGroupId = groups.first.id;
        }
      });

      if (_selectedGroupId != null) {
        await Future.wait([_loadResourceOptions(), _loadProvisioningStatus()]);
      }
    } on DioException catch (e) {
      setState(() {
        _error = ApiService.parseError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingGroups = false;
        });
      }
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
      final resp = await ApiService.dio.get(
        '/groups/$groupId/resource-options',
      );
      final raw = resp.data;
      final payload = raw is Map<String, dynamic>
          ? (raw['data'] as Map<String, dynamic>? ?? raw)
          : <String, dynamic>{};

      final hotelsRaw = (payload['hotels'] as List<dynamic>? ?? const []);
      final busesRaw = (payload['buses'] as List<dynamic>? ?? const []);

      final hotels = hotelsRaw
          .whereType<Map>()
          .map((h) {
            final map = Map<String, dynamic>.from(h);
            final roomsRaw = (map['rooms'] as List<dynamic>? ?? const []);
            return _HotelOption(
              id: map['_id']?.toString() ?? '',
              name: map['name']?.toString() ?? 'Hotel',
              rooms: roomsRaw.whereType<Map>().map((r) {
                final room = Map<String, dynamic>.from(r);
                return _RoomOption(
                  id: room['_id']?.toString() ?? '',
                  roomNumber: room['room_number']?.toString() ?? '-',
                  floor: room['floor']?.toString(),
                  active: room['active'] != false,
                );
              }).toList(),
            );
          })
          .where((h) => h.id.isNotEmpty)
          .toList();

      final buses = busesRaw
          .whereType<Map>()
          .map((b) {
            final map = Map<String, dynamic>.from(b);
            return _BusOption(
              id: map['_id']?.toString() ?? '',
              busNumber: map['bus_number']?.toString() ?? '-',
              destination: map['destination']?.toString() ?? '',
            );
          })
          .where((b) => b.id.isNotEmpty)
          .toList();

      setState(() {
        _hotels = hotels;
        _buses = buses;
        if (_selectedHotelId != null &&
            !_hotels.any((h) => h.id == _selectedHotelId)) {
          _selectedHotelId = null;
          _selectedRoomId = null;
        }
        if (_selectedBusId != null &&
            !_buses.any((b) => b.id == _selectedBusId)) {
          _selectedBusId = null;
        }
      });
    } on DioException catch (e) {
      // Graceful fallback for older backends.
      if (e.response?.statusCode == 404) {
        try {
          final fallback = await ApiService.dio.get('/groups/$groupId');
          final fallbackRaw = fallback.data;
          final groupPayload = fallbackRaw is Map<String, dynamic>
              ? (fallbackRaw['data'] as Map<String, dynamic>? ?? fallbackRaw)
              : <String, dynamic>{};

          final hotelsRaw =
              (groupPayload['assigned_hotel_ids'] as List<dynamic>? ??
              const []);
          final busesRaw =
              (groupPayload['assigned_bus_ids'] as List<dynamic>? ?? const []);

          setState(() {
            _hotels = hotelsRaw
                .whereType<Map>()
                .map((h) {
                  final map = Map<String, dynamic>.from(h);
                  final roomsRaw = (map['rooms'] as List<dynamic>? ?? const []);
                  return _HotelOption(
                    id: map['_id']?.toString() ?? '',
                    name: map['name']?.toString() ?? 'Hotel',
                    rooms: roomsRaw.whereType<Map>().map((r) {
                      final room = Map<String, dynamic>.from(r);
                      return _RoomOption(
                        id: room['_id']?.toString() ?? '',
                        roomNumber: room['room_number']?.toString() ?? '-',
                        floor: room['floor']?.toString(),
                        active: room['active'] != false,
                      );
                    }).toList(),
                  );
                })
                .where((h) => h.id.isNotEmpty)
                .toList();

            _buses = busesRaw
                .whereType<Map>()
                .map((b) {
                  final map = Map<String, dynamic>.from(b);
                  return _BusOption(
                    id: map['_id']?.toString() ?? '',
                    busNumber: map['bus_number']?.toString() ?? '-',
                    destination: map['destination']?.toString() ?? '',
                  );
                })
                .where((b) => b.id.isNotEmpty)
                .toList();
          });
        } catch (_) {
          // Ignore fallback errors.
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingResources = false);
      }
    }
  }

  Future<void> _loadProvisioningStatus() async {
    final groupId = _selectedGroupId;
    if (groupId == null) {
      setState(() {
        _summary = const _ProvisioningSummary();
        _items = const [];
      });
      return;
    }

    if (!_provisioningStatusSupported) {
      setState(() {
        _summary = const _ProvisioningSummary();
        _items = const [];
      });
      return;
    }

    setState(() => _isLoadingStatus = true);

    try {
      final resp = await ApiService.dio.get(
        '/auth/groups/$groupId/provisioning-status',
      );
      final raw = resp.data;
      final payload = raw is Map<String, dynamic>
          ? (raw['data'] as Map<String, dynamic>? ?? raw)
          : <String, dynamic>{};
      final summaryMap =
          (payload['summary'] as Map<String, dynamic>? ?? <String, dynamic>{});
      final itemsRaw = (payload['items'] as List<dynamic>? ?? const []);

      final newTokenMap = <String, Map<String, String?>>{};
      for (final p in _items) {
        if (p.token != null) {
          newTokenMap[p.pilgrimId] = {'token': p.token, 'qr': p.qrDataUrl};
        }
      }

      setState(() {
        _provisioningStatusSupported = true;
        _summary = _ProvisioningSummary.fromJson(summaryMap);
        _items = itemsRaw.whereType<Map>().map((i) {
          final parsed = _ProvisioningItem.fromJson(
            Map<String, dynamic>.from(i),
          );
          final existing = newTokenMap[parsed.pilgrimId];
          if (existing != null) {
            return parsed.copyWith(
              token: existing['token'],
              qrDataUrl: existing['qr'],
            );
          }
          return parsed;
        }).toList();
      });
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        setState(() {
          _provisioningStatusSupported = false;
          _summary = const _ProvisioningSummary();
          _items = const [];
        });
      } else {
        setState(() {
          _error = ApiService.parseError(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingStatus = false);
      }
    }
  }

  Future<void> _createPilgrim() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final groupId = _selectedGroupId;
    if (groupId == null) {
      setState(() => _error = 'Please select a group first.');
      return;
    }

    setState(() {
      _isProvisioning = true;
      _error = null;
    });

    final selectedHotel = _hotels
        .where((h) => h.id == _selectedHotelId)
        .firstOrNull;
    final selectedRoom = selectedHotel?.rooms
        .where((r) => r.id == _selectedRoomId)
        .firstOrNull;
    final selectedBus = _buses.where((b) => b.id == _selectedBusId).firstOrNull;

    try {
      await ApiService.dio.post(
        '/auth/groups/$groupId/provision-pilgrim',
        data: {
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
        },
      );

      _fullNameCtrl.clear();
      _phoneCtrl.clear();
      _ageCtrl.clear();
      _nationalIdCtrl.clear();
      _medicalHistoryCtrl.clear();
      setState(() {
        _selectedLanguage = 'en';
        _selectedEthnicity = 'Other';
        _selectedVisaStatus = 'unknown';
        _selectedHotelId = null;
        _selectedRoomId = null;
        _selectedBusId = null;
      });

      await _loadProvisioningStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Pilgrim account created successfully.'),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
        );
      }
    } on DioException catch (e) {
      setState(() => _error = ApiService.parseError(e));
    } finally {
      if (mounted) {
        setState(() => _isProvisioning = false);
      }
    }
  }

  Future<void> _reissueLogin(_ProvisioningItem item) async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;

    try {
      final resp = await ApiService.dio.post(
        '/auth/groups/$groupId/pilgrims/${item.pilgrimId}/reissue-login',
      );
      final raw = resp.data;
      final payload = raw is Map<String, dynamic>
          ? (raw['data'] as Map<String, dynamic>? ?? raw)
          : <String, dynamic>{};
      final login =
          (payload['one_time_login'] as Map<String, dynamic>? ??
          <String, dynamic>{});
      final token = login['token']?.toString();
      final qr = login['qr_code_data_url']?.toString();

      await _loadProvisioningStatus();

      if (token != null && mounted) {
        await Share.share(
          'One-time login for ${item.fullName}\nToken: $token\nUse it within 24 hours.',
          subject: 'Pilgrim one-time login',
        );
      }

      if (qr != null && mounted) {
        _showQrDialog(name: item.fullName, token: token, qrDataUrl: qr);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ApiService.parseError(e)),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _deleteProvisioned(_ProvisioningItem item) async {
    final groupId = _selectedGroupId;
    if (groupId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete pilgrim account?'),
        content: Text('This will remove ${item.fullName} from the system.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.dio.delete(
        '/auth/groups/$groupId/pilgrims/${item.pilgrimId}',
      );
      await _loadProvisioningStatus();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ApiService.parseError(e)),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showQrDialog({
    required String name,
    String? token,
    required String qrDataUrl,
  }) {
    final bytes = _decodeDataUrl(qrDataUrl);
    if (bytes == null) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('One-time login for $name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.memory(
              bytes,
              width: 220.w,
              height: 220.w,
              fit: BoxFit.contain,
            ),
            if (token != null && token.isNotEmpty) ...[
              SizedBox(height: 10.h),
              SelectableText(
                token,
                style: TextStyle(
                  fontFamily: 'Lexend',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Uint8List? _decodeDataUrl(String dataUrl) {
    final idx = dataUrl.indexOf(',');
    if (idx < 0 || idx + 1 >= dataUrl.length) return null;
    try {
      return Uint8List.fromList(base64Decode(dataUrl.substring(idx + 1)));
    } catch (_) {
      return null;
    }
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '-';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    final local = parsed.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$mm/$dd ${local.year} $hh:$mi';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(moderatorProvider.select((m) => m.groups.length), (prev, next) {
      if (prev != null && prev != next) {
        _loadGroups();
      }
    });

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final filteredItems = _items.where((i) {
      if (_filterStatus == 'pending') return i.status != 'activated';
      if (_filterStatus == 'activated') return i.status == 'activated';
      return true;
    }).toList();

    final cardBg = isDark ? AppColors.surfaceDark : Colors.white;
    final textPrimary = isDark ? AppColors.textLight : AppColors.textDark;
    final textMuted = isDark
        ? AppColors.textMutedLight
        : AppColors.textMutedDark;

    final selectedHotel = _hotels
        .where((h) => h.id == _selectedHotelId)
        .firstOrNull;
    final rooms = (selectedHotel?.rooms ?? const <_RoomOption>[])
        .where((r) => r.active)
        .toList();

    return SafeArea(
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          await Future.wait([_loadGroups(), _loadProvisioningStatus()]);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 100.h),
          children: [
            Text(
              'Pilgrim Provisioning',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontWeight: FontWeight.w800,
                fontSize: 28.sp,
                color: textPrimary,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'Create pilgrim accounts and track activation status.',
              style: TextStyle(
                fontFamily: 'Lexend',
                fontSize: 13.sp,
                color: textMuted,
              ),
            ),
            SizedBox(height: 16.h),

            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: isDark
                      ? AppColors.dividerDark
                      : AppColors.dividerLight,
                ),
              ),
              padding: EdgeInsets.all(12.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Target Group',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w600,
                      color: textMuted,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedGroupId,
                    isExpanded: true,
                    decoration: _inputDecoration(isDark),
                    hint: const Text('Select group'),
                    items: _groups
                        .map(
                          (g) => DropdownMenuItem<String>(
                            value: g.id,
                            child: Text(
                              g.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _isLoadingGroups
                        ? null
                        : (value) async {
                            setState(() {
                              _selectedGroupId = value;
                              _selectedHotelId = null;
                              _selectedRoomId = null;
                              _selectedBusId = null;
                            });
                            await Future.wait([
                              _loadResourceOptions(),
                              _loadProvisioningStatus(),
                            ]);
                          },
                  ),
                ],
              ),
            ),

            SizedBox(height: 16.h),
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(
                  color: isDark
                      ? AppColors.dividerDark
                      : AppColors.dividerLight,
                ),
              ),
              padding: EdgeInsets.all(14.w),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Provision Pilgrim Accounts',
                            style: TextStyle(
                              fontFamily: 'Lexend',
                              fontWeight: FontWeight.w700,
                              fontSize: 18.sp,
                              color: textPrimary,
                            ),
                          ),
                        ),
                        Icon(
                          Symbols.person_add,
                          color: AppColors.primary,
                          size: 22.w,
                        ),
                      ],
                    ),
                    SizedBox(height: 14.h),
                    Text(
                      'Basic Information',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 15.sp,
                        color: textPrimary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    TextFormField(
                      controller: _fullNameCtrl,
                      decoration: _inputDecoration(isDark, label: 'Full name (3-100 chars)'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Full name is required'
                          : null,
                    ),
                    SizedBox(height: 10.h),
                    TextFormField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: _inputDecoration(
                        isDark,
                        label: 'Phone number (without country code)',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Phone number is required'
                          : null,
                    ),
                    SizedBox(height: 10.h),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _ageCtrl,
                            keyboardType: TextInputType.number,
                            decoration: _inputDecoration(isDark, label: 'Age (0-120)'),
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedLanguage,
                            isExpanded: true,
                            decoration: _inputDecoration(
                              isDark,
                              label: 'Language (required)',
                            ),
                            items: const [
                              DropdownMenuItem(value: 'en', child: Text('English')),
                              DropdownMenuItem(value: 'ar', child: Text('Arabic')),
                              DropdownMenuItem(value: 'ur', child: Text('Urdu')),
                              DropdownMenuItem(value: 'fr', child: Text('French')),
                              DropdownMenuItem(value: 'id', child: Text('Indonesian')),
                              DropdownMenuItem(value: 'tr', child: Text('Turkish')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _selectedLanguage = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10.h),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedEthnicity,
                            isExpanded: true,
                            decoration: _inputDecoration(
                              isDark,
                              label: 'Ethnicity (required)',
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Arab', child: Text('Arab')),
                              DropdownMenuItem(value: 'South Asian', child: Text('South Asian')),
                              DropdownMenuItem(value: 'Turkic', child: Text('Turkic')),
                              DropdownMenuItem(value: 'Persian', child: Text('Persian')),
                              DropdownMenuItem(value: 'Malay/Indonesian', child: Text('Malay/Indonesian')),
                              DropdownMenuItem(value: 'African', child: Text('African')),
                              DropdownMenuItem(value: 'Kurdish', child: Text('Kurdish')),
                              DropdownMenuItem(value: 'Berber', child: Text('Berber')),
                              DropdownMenuItem(value: 'European Muslim', child: Text('European Muslim')),
                              DropdownMenuItem(value: 'Other', child: Text('Other')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _selectedEthnicity = v);
                            },
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedVisaStatus,
                            isExpanded: true,
                            decoration: _inputDecoration(
                              isDark,
                              label: 'Visa status (required)',
                            ),
                            items: const [
                              DropdownMenuItem(value: 'unknown', child: Text('Unknown')),
                              DropdownMenuItem(value: 'pending', child: Text('Pending')),
                              DropdownMenuItem(value: 'issued', child: Text('Issued')),
                              DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                              DropdownMenuItem(value: 'expired', child: Text('Expired')),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() => _selectedVisaStatus = v);
                            },
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 20.h),
                    Text(
                      'Extra Details (Optional)',
                      style: TextStyle(
                        fontFamily: 'Lexend',
                        fontWeight: FontWeight.w600,
                        fontSize: 15.sp,
                        color: textPrimary,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    DropdownButtonFormField<String>(
                      value: _selectedHotelId,
                      isExpanded: true,
                      decoration: _inputDecoration(
                        isDark,
                        label: 'Hotel',
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('No hotel'),
                        ),
                        ..._hotels.map(
                          (h) => DropdownMenuItem<String>(
                            value: h.id,
                            child: Text(
                              h.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: _isLoadingResources
                          ? null
                          : (v) {
                              setState(() {
                                _selectedHotelId = v;
                                _selectedRoomId = null;
                              });
                            },
                    ),
                    SizedBox(height: 10.h),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedRoomId,
                            isExpanded: true,
                            decoration: _inputDecoration(
                              isDark,
                              label: 'Room',
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('No room'),
                              ),
                              ...rooms.map(
                                (r) => DropdownMenuItem<String>(
                                  value: r.id,
                                  child: Text(
                                    r.floor == null
                                        ? r.roomNumber
                                        : '${r.roomNumber} - F${r.floor}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: selectedHotel == null
                                ? null
                                : (v) => setState(() => _selectedRoomId = v),
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedBusId,
                            isExpanded: true,
                            decoration: _inputDecoration(
                              isDark,
                              label: 'Bus',
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: null,
                                child: Text('No bus'),
                              ),
                              ..._buses.map(
                                (b) => DropdownMenuItem<String>(
                                  value: b.id,
                                  child: Text(
                                    b.destination.isEmpty
                                        ? b.busNumber
                                        : '${b.busNumber} - ${b.destination}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _selectedBusId = v),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10.h),
                    TextFormField(
                      controller: _nationalIdCtrl,
                      decoration: _inputDecoration(isDark, label: 'National ID (optional)'),
                    ),
                    SizedBox(height: 10.h),
                    TextFormField(
                      controller: _medicalHistoryCtrl,
                      maxLines: 3,
                      maxLength: 500,
                      decoration: _inputDecoration(isDark, label: 'Medical history (max 500 chars)'),
                    ),
                    SizedBox(height: 14.h),
                    SizedBox(
                      width: double.infinity,
                      height: 52.h,
                      child: ElevatedButton.icon(
                        onPressed: _isProvisioning ? null : _createPilgrim,
                        icon: _isProvisioning
                            ? SizedBox(
                                width: 18.w,
                                height: 18.w,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.black,
                                ),
                              )
                            : Icon(Symbols.add_circle, size: 20.w),
                        label: Text(
                          _isProvisioning ? 'Creating...' : 'Create Pilgrim',
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontWeight: FontWeight.w700,
                            fontSize: 18.sp,
                            color: Colors.black,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8400),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26.r),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),

                    SizedBox(height: 10.h),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isLoadingStatus
                                ? null
                                : () => _loadProvisioningStatus(),
                            icon: Icon(Symbols.sync, size: 16.w),
                            label: const Text('Refresh Status'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: textPrimary,
                              side: BorderSide(
                                color: isDark
                                    ? AppColors.dividerDark
                                    : AppColors.dividerLight,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 12.h),

            if (_selectedGroupId != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Track Provisioning',
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontWeight: FontWeight.w700,
                      fontSize: 16.sp,
                      color: textPrimary,
                    ),
                  ),
                  DropdownButton<String>(
                    value: _filterStatus,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All Status')),
                      DropdownMenuItem(
                        value: 'pending',
                        child: Text('Pending Only'),
                      ),
                      DropdownMenuItem(
                        value: 'activated',
                        child: Text('Activated'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _filterStatus = val);
                    },
                    style: TextStyle(
                      fontFamily: 'Lexend',
                      fontSize: 13.sp,
                      color: textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    dropdownColor: isDark
                        ? const Color(0xFF2A2A3C)
                        : Colors.white,
                    underline: const SizedBox(),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              if (filteredItems.isEmpty)
                _EmptyCard(text: 'No matching pilgrims.', isDark: isDark)
              else
                ...filteredItems.map((item) {
                  return Container(
                    margin: EdgeInsets.only(bottom: 8.h),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: isDark
                            ? AppColors.dividerDark
                            : AppColors.dividerLight,
                      ),
                    ),
                    padding: EdgeInsets.all(12.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item.fullName,
                                style: TextStyle(
                                  fontFamily: 'Lexend',
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            _StatusBadge(status: item.status),
                          ],
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          item.phoneNumber,
                          style: TextStyle(
                            fontFamily: 'Lexend',
                            fontSize: 12.sp,
                            color: textMuted,
                          ),
                        ),
                        if (item.token != null &&
                            item.token!.isNotEmpty &&
                            item.status != 'activated') ...[
                          SizedBox(height: 12.h),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Token: ${item.token}',
                                  style: TextStyle(
                                    fontFamily: 'Lexend',
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                onPressed: () {
                                  _showQrDialog(
                                    name: item.fullName,
                                    token: item.token,
                                    qrDataUrl: item.qrDataUrl ?? '',
                                  );
                                },
                                icon: Icon(
                                  Symbols.qr_code_2,
                                  size: 20.w,
                                  color: textPrimary,
                                ),
                              ),
                              SizedBox(width: 14.w),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                onPressed: () => _reissueLogin(item),
                                icon: Icon(
                                  Symbols.refresh,
                                  size: 20.w,
                                  color: textPrimary,
                                ),
                              ),
                              SizedBox(width: 14.w),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                onPressed: () => _deleteProvisioned(item),
                                icon: Icon(
                                  Symbols.delete,
                                  size: 20.w,
                                  color: Colors.red.shade400,
                                ),
                              ),
                            ],
                          ),
                        ] else if (item.status == 'activated' ||
                            item.status == 'expired') ...[
                          SizedBox(height: 12.h),
                          Row(
                            children: [
                              if (item.qrDataUrl != null)
                                TextButton.icon(
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () {
                                    _showQrDialog(
                                      name: item.fullName,
                                      token: item.token,
                                      qrDataUrl: item.qrDataUrl!,
                                    );
                                  },
                                  icon: Icon(
                                    Symbols.qr_code_2,
                                    size: 16.w,
                                    color: AppColors.primary,
                                  ),
                                  label: Text(
                                    'View ID Card',
                                    style: TextStyle(
                                      fontFamily: 'Lexend',
                                      color: AppColors.primary,
                                      fontSize: 12.sp,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              IconButton(
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                onPressed: () => _reissueLogin(item),
                                icon: Icon(
                                  Symbols.refresh,
                                  size: 20.w,
                                  color: textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }),
              SizedBox(height: 20.h),
            ],
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(bool isDark, {String? label}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontFamily: 'Lexend', fontSize: 12.sp),
      filled: true,
      fillColor: isDark ? const Color(0xFF1A2433) : const Color(0xFFE9EBF0),
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.r),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.r),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14.r),
        borderSide: BorderSide(
          color: AppColors.primary.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

class _GroupOption {
  final String id;
  final String name;

  const _GroupOption({required this.id, required this.name});
}

class _ProvisioningSummary {
  final int totalProvisioned;
  final int pendingCount;
  final int activatedCount;

  const _ProvisioningSummary({
    this.totalProvisioned = 0,
    this.pendingCount = 0,
    this.activatedCount = 0,
  });

  factory _ProvisioningSummary.fromJson(Map<String, dynamic> map) {
    int toInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    return _ProvisioningSummary(
      totalProvisioned: toInt(map['total_provisioned']),
      pendingCount: toInt(map['pending_count']),
      activatedCount: toInt(map['activated_count']),
    );
  }
}

class _ProvisioningItem {
  final String pilgrimId;
  final String fullName;
  final String phoneNumber;
  final String status;
  final String? token;
  final String? expiresAt;
  final String? qrDataUrl;

  const _ProvisioningItem({
    required this.pilgrimId,
    required this.fullName,
    required this.phoneNumber,
    required this.status,
    this.token,
    this.expiresAt,
    this.qrDataUrl,
  });

  _ProvisioningItem copyWith({
    String? pilgrimId,
    String? fullName,
    String? phoneNumber,
    String? status,
    String? token,
    String? expiresAt,
    String? qrDataUrl,
  }) {
    return _ProvisioningItem(
      pilgrimId: pilgrimId ?? this.pilgrimId,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      status: status ?? this.status,
      token: token ?? this.token,
      expiresAt: expiresAt ?? this.expiresAt,
      qrDataUrl: qrDataUrl ?? this.qrDataUrl,
    );
  }

  factory _ProvisioningItem.fromJson(Map<String, dynamic> map) {
    final pilgrim =
        (map['pilgrim'] as Map<String, dynamic>? ?? <String, dynamic>{});
    final login =
        (map['one_time_login'] as Map<String, dynamic>? ?? <String, dynamic>{});

    return _ProvisioningItem(
      pilgrimId: pilgrim['_id']?.toString() ?? '',
      fullName: pilgrim['full_name']?.toString() ?? 'Unknown Pilgrim',
      phoneNumber: pilgrim['phone_number']?.toString() ?? '-',
      status: map['status']?.toString() ?? 'pending',
      token: login['token']?.toString(),
      expiresAt: login['expires_at']?.toString(),
      qrDataUrl: login['qr_code_data_url']?.toString(),
    );
  }
}

class _HotelOption {
  final String id;
  final String name;
  final List<_RoomOption> rooms;

  const _HotelOption({
    required this.id,
    required this.name,
    required this.rooms,
  });
}

class _RoomOption {
  final String id;
  final String roomNumber;
  final String? floor;
  final bool active;

  const _RoomOption({
    required this.id,
    required this.roomNumber,
    this.floor,
    this.active = true,
  });
}

class _BusOption {
  final String id;
  final String busNumber;
  final String destination;

  const _BusOption({
    required this.id,
    required this.busNumber,
    required this.destination,
  });
}

class _StatCard extends StatelessWidget {
  final String title;
  final int value;
  final Color color;
  final bool isDark;

  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 86.h,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border(
          left: BorderSide(color: color, width: 3),
          top: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          ),
          right: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          ),
          bottom: BorderSide(
            color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
          ),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.textMutedLight
                  : AppColors.textMutedDark,
              letterSpacing: 0.9,
            ),
          ),
          SizedBox(height: 5.h),
          Text(
            '$value',
            style: TextStyle(
              fontFamily: 'Lexend',
              fontSize: 34.sp,
              fontWeight: FontWeight.w800,
              height: 1,
              color: isDark ? AppColors.textLight : AppColors.textDark,
            ),
          ),
        ],
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
        ? const Color(0xFFB9F6D5)
        : isExpired
        ? const Color(0xFFF8CDD2)
        : const Color(0xFFD8E0F5);
    final fg = isActivated
        ? const Color(0xFF0A8B50)
        : isExpired
        ? const Color(0xFFB71C1C)
        : const Color(0xFF3E5174);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999.r),
      ),
      child: Text(
        isActivated
            ? 'CODE USED'
            : isExpired
            ? 'EXPIRED'
            : 'PENDING',
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 11.sp,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;
  final bool isDark;

  const _EmptyCard({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isDark ? AppColors.dividerDark : AppColors.dividerLight,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Lexend',
          fontSize: 13.sp,
          color: isDark ? AppColors.textMutedLight : AppColors.textMutedDark,
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
