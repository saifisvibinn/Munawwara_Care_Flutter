import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../core/services/tameny_location_service.dart';

class TamenyTrackingToggle extends StatefulWidget {
  const TamenyTrackingToggle({super.key});

  @override
  State<TamenyTrackingToggle> createState() => _TamenyTrackingToggleState();
}

class _TamenyTrackingToggleState extends State<TamenyTrackingToggle> {
  bool _isEnabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadState();
  }

  Future<void> _loadState() async {
    final enabled = await TamenyLocationService.isEnabled();
    setState(() {
      _isEnabled = enabled;
      _isLoading = false;
    });
  }

  Future<void> _handleToggle(bool value) async {
    setState(() => _isLoading = true);
    
    if (value) {
      final success = await TamenyLocationService.enableTracking(context);
      setState(() {
        _isEnabled = success;
        _isLoading = false;
      });
    } else {
      await TamenyLocationService.disableTracking();
      setState(() {
        _isEnabled = false;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'tameny_toggle_title'.tr(),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Switch(
                        value: _isEnabled,
                        onChanged: _handleToggle,
                        activeThumbColor: const Color(0xFF2E7D32),
                      ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _isEnabled
                  ? '✓ ${'tameny_toggle_desc_enabled'.tr()}'
                  : 'tameny_toggle_desc_disabled'.tr(),
              style: TextStyle(
                fontSize: 13,
                color: _isEnabled ? Colors.green[700] : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
