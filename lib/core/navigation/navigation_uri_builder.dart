import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'navigation_app.dart';

/// Builds ordered URI lists for turn-by-turn navigation per app.
class NavigationUriBuilder {
  NavigationUriBuilder._();

  static List<Uri> urisFor(NavigationApp app, double lat, double lng) {
    switch (app) {
      case NavigationApp.appleMaps:
        return _appleMapsUris(lat, lng);
      case NavigationApp.googleMaps:
        return _googleMapsUris(lat, lng);
      case NavigationApp.systemSelection:
        return _systemFallbackUris(lat, lng);
    }
  }

  static List<Uri> _appleMapsUris(double lat, double lng) => [
        Uri.parse('maps://?daddr=$lat,$lng'),
        Uri.parse('http://maps.apple.com/?daddr=$lat,$lng'),
      ];

  static List<Uri> _googleMapsUris(double lat, double lng) {
    if (kIsWeb) {
      return [
        Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
        ),
      ];
    }

    if (Platform.isIOS) {
      return [
        Uri.parse('comgooglemaps://?daddr=$lat,$lng&directionsmode=driving'),
        Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
        ),
      ];
    }

    return [
      Uri.parse('google.navigation:q=$lat,$lng'),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
      ),
    ];
  }

  /// Android geo intent when no dedicated maps app is available.
  static List<Uri> _systemFallbackUris(double lat, double lng) {
    if (kIsWeb) {
      return [
        Uri.parse(
          'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
        ),
      ];
    }

    if (Platform.isIOS) {
      return _appleMapsUris(lat, lng);
    }

    return [
      Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
      Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
      ),
    ];
  }
}
