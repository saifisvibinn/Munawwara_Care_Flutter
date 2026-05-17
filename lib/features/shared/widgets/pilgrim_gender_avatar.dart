import 'package:flutter/material.dart';

/// Pilgrim portrait for **male** / **female** accounts (flat assets under
/// `assets/static/`).
///
/// For [gender] null, `other`, or unknown values we show the **male** ihram
/// asset as a generic pilgrim default so the UI never falls back to initials.
class PilgrimGenderAvatar extends StatelessWidget {
  static const maleAsset = 'assets/static/pilgrim_male.png';
  static const femaleAsset = 'assets/static/pilgrim_female.png';

  static const _maleAsset = maleAsset;
  static const _femaleAsset = femaleAsset;

  /// Asset path for CallKit / native caller ID (moderator receiving pilgrim call).
  static String assetPathForGender(String? gender) {
    if (_isFemale(gender)) return femaleAsset;
    return maleAsset;
  }

  static bool _isFemale(String? gender) {
    final g = gender?.toLowerCase().trim() ?? '';
    return g == 'female' || g == 'f' || g.startsWith('fem');
  }

  final String? gender;
  final double size;

  const PilgrimGenderAvatar({
    super.key,
    required this.gender,
    required this.size,
  });

  String get _assetPath {
    if (_isFemale(gender)) return _femaleAsset;
    return _maleAsset;
  }

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          _assetPath,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) {
            return ColoredBox(
              color: Colors.white24,
              child: Icon(
                Icons.person,
                size: size * 0.55,
                color: Colors.white,
              ),
            );
          },
        ),
      ),
    );
  }
}
