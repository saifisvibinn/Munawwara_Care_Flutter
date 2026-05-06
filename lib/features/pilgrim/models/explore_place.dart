/// A point of interest on the pilgrim Explore screen (near the user’s location).
///
/// [cardImageUrl]: optional **chain favicon** URL (from [brandName] and/or
/// venue [name]); [landmarks] use `null` → gradient + icon in the UI.
class ExplorePlace {
  final String sourceRef;
  final String name;
  final String categoryKey;
  final double latitude;
  final double longitude;

  /// Chain / operator label from OSM `brand` / `operator` tags.
  final String? brandName;

  /// Network image for the card header, or null → gradient + category icon.
  final String? cardImageUrl;

  const ExplorePlace({
    required this.sourceRef,
    required this.name,
    required this.categoryKey,
    required this.latitude,
    required this.longitude,
    this.brandName,
    this.cardImageUrl,
  });
}
