import 'package:latlong2/latlong.dart';

import '../../../core/map/app_map_marker_data.dart';
import '../../../core/theme/app_colors.dart';
import '../../shared/models/suggested_area_model.dart';
import '../providers/moderator_provider.dart';
import 'pilgrim_marker_layout.dart';

/// Builds [AppMapMarkerData] for native MapKit on moderator map screens.
class ModeratorMapMarkers {
  ModeratorMapMarkers._();

  static int _pilgrimTint(PilgrimInGroup pilgrim, {String? focusedId}) {
    if (pilgrim.hasSOS) return 0xFFDC2626;
    if (focusedId == pilgrim.id) return AppColors.accentGold.toARGB32();
    return AppColors.primary.toARGB32();
  }

  static List<AppMapMarkerData> pilgrims(
    List<PilgrimInGroup> located, {
    String? focusedId,
  }) {
    return PilgrimMarkerLayout.pointsForMarkers(located).map((item) {
      final p = item.pilgrim;
      return AppMapMarkerData(
        id: 'pilgrim_${p.id}',
        point: item.point,
        kind: AppMapMarkerKind.pilgrim,
        title: p.fullName,
        subtitle: p.hasSOS ? 'SOS' : null,
        tintArgb: _pilgrimTint(p, focusedId: focusedId),
        glyphName: 'person.fill',
        payload: p,
      );
    }).toList();
  }

  static List<AppMapMarkerData> areas(List<SuggestedArea> areas) {
    return areas
        .map(
          (area) => AppMapMarkerData(
            id: 'area_${area.id}',
            point: LatLng(area.latitude, area.longitude),
            kind: AppMapMarkerKind.area,
            title: area.name,
            subtitle: area.isMeetpoint ? 'Meetpoint' : null,
            tintArgb: area.isMeetpoint
                ? 0xFFDC2626
                : AppColors.primary.toARGB32(),
            glyphName: area.isMeetpoint
                ? 'exclamationmark.triangle.fill'
                : 'mappin',
            payload: area,
          ),
        )
        .toList();
  }
}
