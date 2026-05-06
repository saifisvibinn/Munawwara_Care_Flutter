/// Resolves a **chain favicon** from OSM `brand` / `operator` and from
/// substrings in the **venue name** when tags are missing.
///
/// Uses Google’s favicon service (reliable in `Image.network` on mobile).
/// Extend [_brandToDomain] for more chains.
class ExploreBrandLogo {
  ExploreBrandLogo._();

  static const _brandToDomain = <String, String>{
    // Global QSR / coffee
    'mcdonalds': 'mcdonalds.com',
    "mcdonald's": 'mcdonalds.com',
    'starbucks': 'starbucks.com',
    'kfc': 'kfc.com',
    'kentucky fried chicken': 'kfc.com',
    'subway': 'subway.com',
    'burger king': 'burgerking.com',
    'dominos': 'dominos.com',
    "domino's": 'dominos.com',
    'pizza hut': 'pizzahut.com',
    'dunkin': 'dunkindonuts.com',
    'dunkin donuts': 'dunkindonuts.com',
    'taco bell': 'tacobell.com',
    'wendys': 'wendys.com',
    "wendy's": 'wendys.com',
    'hardees': 'hardees.com',
    "hardee's": 'hardees.com',
    'popeyes': 'popeyes.com',
    'chipotle': 'chipotle.com',
    'five guys': 'fiveguys.com',
    'shake shack': 'shakeshack.com',
    'tim hortons': 'timhortons.com',
    'costa coffee': 'costa.co.uk',
    'costa': 'costa.co.uk',
    // Saudi / Gulf common
    'al baik': 'albaik.com',
    'albaik': 'albaik.com',
    'al tazaj': 'tazaj.com',
    'kudu': 'kudu.com.sa',
    'herfy': 'herfy.com',
    'shawarmer': 'shawarmer.com',
    'maestro pizza': 'maestropizza.com',
    'panda supermarket': 'panda.com.sa',
    'panda': 'panda.com.sa',
    'tamimi markets': 'tamimimarkets.com',
    'tamimi': 'tamimimarkets.com',
    'carrefour': 'carrefour.com',
    'lulu hypermarket': 'luluhypermarket.com',
    'lulu': 'luluhypermarket.com',
    'danube': 'danube.sa',
    'bindawood': 'bindawood.com',
    'extra': 'extra.com.sa',
    'nahdi pharmacy': 'nahdi.sa',
    'nahdi': 'nahdi.sa',
    'dr soliman fakeeh hospital': 'fakeeh.care',
    'boots': 'boots.com',
    'superdrug': 'superdrug.com',
    'walgreens': 'walgreens.com',
    'cvs pharmacy': 'cvs.com',
    'cvs': 'cvs.com',
    'rite aid': 'riteaid.com',
    '7-eleven': '7-eleven.com',
    '7 eleven': '7-eleven.com',
    'circle k': 'circlek.com',
    'amazon': 'amazon.com',
    'ikea': 'ikea.com',
    'apple': 'apple.com',
    'zara': 'zara.com',
    'hm': 'hm.com',
    'h&m': 'hm.com',
    'nike': 'nike.com',
    'adidas': 'adidas.com',
    'baskin robbins': 'baskinrobbins.com',
    "baskin-robbins": 'baskinrobbins.com',
    'krispy kreme doughnuts': 'krispykreme.com',
    'krispy kreme': 'krispykreme.com',
    'greggs': 'greggs.co.uk',
    'pret a manger': 'pret.com',
    'pret': 'pret.com',
    'subway restaurant': 'subway.com',
    'texas chicken': 'texaschicken.com',
    'al romansiah': 'romansiah.com',
    'romansiah': 'romansiah.com',
  };

  static String _normalize(String raw) {
    return raw
        .toLowerCase()
        .trim()
        .replaceAll("'", '')
        .replaceAll('’', '')
        .replaceAll('&', 'and');
  }

  static String? _domainFromLabel(String? label) {
    if (label == null || label.trim().isEmpty) return null;
    final key = _normalize(label);
    final direct = _brandToDomain[key];
    if (direct != null) return direct;
    final first = _normalize(key.split(',').first);
    return _brandToDomain[first];
  }

  /// Picks a domain using [brand]/operator first, then substring match on [venueName].
  static String? domainForBrandOrVenue(String? brand, String venueName) {
    final fromBrand = _domainFromLabel(brand);
    if (fromBrand != null) return fromBrand;

    final n = _normalize(venueName);
    if (n.isEmpty) return null;
    final keys = _brandToDomain.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final k in keys) {
      if (n.contains(k)) return _brandToDomain[k];
    }
    return null;
  }

  /// Public URL for `Image.network` (non-landmark cards).
  static String? chainLogoUrl({
    String? brand,
    required String venueName,
  }) {
    final domain = domainForBrandOrVenue(brand, venueName);
    if (domain == null) return null;
    return Uri.https('www.google.com', '/s2/favicons', <String, String>{
      'domain': domain,
      'sz': '128',
    }).toString();
  }
}
