import 'package:flutter/material.dart';

/// A point of interest on the pilgrim Explore screen (near the user’s location).
class ExplorePlace {
  final String sourceRef;
  final String name;
  final String categoryKey;
  final double latitude;
  final double longitude;

  /// Chain / operator label from OSM `brand` / `operator` tags.
  final String? brandName;

  const ExplorePlace({
    required this.sourceRef,
    required this.name,
    required this.categoryKey,
    required this.latitude,
    required this.longitude,
    this.brandName,
  });

  /// Map the backend category key to a local Material icon.
  IconData get icon {
    switch (categoryKey) {
      case 'restaurant':
      case 'food':
        return Icons.restaurant;
      case 'hospital':
        return Icons.local_hospital;
      case 'mosque':
        return Icons.mosque;
      case 'pharmacy':
        return Icons.local_pharmacy;
      case 'toilet':
        return Icons.wc;
      case 'drinking_water':
        return Icons.water_drop;
      case 'shopping':
        return Icons.shopping_bag;
      case 'landmarks':
        return Icons.account_balance;
      default:
        return Icons.place;
    }
  }
}
