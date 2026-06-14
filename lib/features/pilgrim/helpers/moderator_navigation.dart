import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/open_maps_navigation.dart';
import '../providers/pilgrim_provider.dart';

Future<void> launchModeratorWalkingDirections({
  required BuildContext context,
  required double lat,
  required double lng,
}) =>
    OpenMapsNavigation.launch(context, lat, lng);

/// Opens walking directions for an active moderator navigation beacon.
Future<void> launchModeratorBeaconDirections(
  BuildContext context,
  ModeratorBeacon beacon,
) =>
    launchModeratorWalkingDirections(
      context: context,
      lat: beacon.lat,
      lng: beacon.lng,
    );

/// Group moderators with the creator listed first when [createdBy] is known.
List<ModeratorInfo> sortedGroupModerators(
  List<ModeratorInfo> moderators, {
  String? createdBy,
}) {
  if (moderators.isEmpty) return moderators;
  final leaderId = createdBy?.trim();
  if (leaderId == null || leaderId.isEmpty) {
    return List<ModeratorInfo>.from(moderators);
  }
  final sorted = List<ModeratorInfo>.from(moderators);
  sorted.sort((a, b) {
    if (a.id == leaderId) return -1;
    if (b.id == leaderId) return 1;
    return a.fullName.compareTo(b.fullName);
  });
  return sorted;
}

/// Whether [moderatorId] is the group leader (creator).
bool isGroupLeaderModerator({
  required String moderatorId,
  String? createdBy,
}) {
  final leaderId = createdBy?.trim();
  if (leaderId == null || leaderId.isEmpty) return false;
  return moderatorId == leaderId;
}

/// Active nav beacons for moderators in this group, creator first.
List<ModeratorBeacon> activeNavBeaconsForGroup({
  required Map<String, ModeratorBeacon> beacons,
  required List<ModeratorInfo> moderators,
  String? createdBy,
}) {
  if (beacons.isEmpty || moderators.isEmpty) return const [];
  final ordered = sortedGroupModerators(moderators, createdBy: createdBy);
  return ordered
      .map((m) => beacons[m.id])
      .whereType<ModeratorBeacon>()
      .toList();
}

/// Comma-separated moderator names for compact cards (creator first).
String formatModeratorNamesList(
  List<ModeratorInfo> moderators, {
  String? createdBy,
}) {
  final sorted = sortedGroupModerators(moderators, createdBy: createdBy);
  if (sorted.isEmpty) return '';
  return sorted.map((m) => m.fullName).join(', ');
}

/// Formats distance from the pilgrim to a target point for display.
String? formatDistanceToPoint({
  required LatLng? from,
  required double? lat,
  required double? lng,
}) {
  if (from == null || lat == null || lng == null) return null;
  final meters = Geolocator.distanceBetween(
    from.latitude,
    from.longitude,
    lat,
    lng,
  );
  if (meters < 1000) {
    return '${meters.toStringAsFixed(0)} m';
  }
  return '${(meters / 1000).toStringAsFixed(1)} km';
}

/// Distance to a moderator using live beacon coords when available.
String? distanceToModerator({
  required LatLng? from,
  required ModeratorInfo moderator,
  required Map<String, ModeratorBeacon> navBeacons,
}) {
  final beacon = navBeacons[moderator.id];
  return formatDistanceToPoint(
    from: from,
    lat: beacon?.lat ?? moderator.lat,
    lng: beacon?.lng ?? moderator.lng,
  );
}
