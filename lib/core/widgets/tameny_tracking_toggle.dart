import 'package:flutter/material.dart';
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
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مشاركة الموقع دائماً',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Always Share Location',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
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
                        activeColor: const Color(0xFF2E7D32),
                      ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _isEnabled
                  ? '✓ موقعك يُرسل لقائد المجموعة حتى عند إغلاق التطبيق\n(Location sent even when app is closed)'
                  : 'فعّل لمشاركة موقعك حتى عند إغلاق التطبيق\n(Enable to share location even when closed)',
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
