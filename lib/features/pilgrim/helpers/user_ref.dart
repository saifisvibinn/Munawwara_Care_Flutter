/// Parses a user reference from API JSON (plain id string or populated object).
String? parseUserRefId(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    final text = value.trim();
    return text.isNotEmpty ? text : null;
  }
  if (value is Map) {
    for (final key in ['_id', 'id']) {
      final id = value[key];
      if (id == null) continue;
      final text = id.toString().trim();
      if (text.isNotEmpty) return text;
    }
  }
  return null;
}
