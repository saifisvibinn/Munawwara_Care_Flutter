import 'package:latlong2/latlong.dart';

/// Marker kinds rendered on in-app maps (FlutterMap + native MapKit).
enum AppMapMarkerKind {
  pilgrim,
  area,
  hospital,
  beacon,
}

/// Platform-neutral marker payload for [AppPlatformMap].
class AppMapMarkerData {
  const AppMapMarkerData({
    required this.id,
    required this.point,
    required this.kind,
    this.title,
    this.subtitle,
    this.tintArgb = 0xFF2E7D32,
    this.glyphName,
    this.cluster = true,
    this.payload,
  });

  final String id;
  final LatLng point;
  final AppMapMarkerKind kind;
  final String? title;
  final String? subtitle;
  final int tintArgb;
  final String? glyphName;
  final bool cluster;
  final Object? payload;

  Map<String, dynamic> toMapKitJson() => {
        'id': id,
        'latitude': point.latitude,
        'longitude': point.longitude,
        'kind': kind.name,
        if (title != null) 'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        'tintArgb': tintArgb,
        if (glyphName != null) 'glyphName': glyphName,
      };
}
