/// Normalizes ids from FCM/local notification payloads before API calls.
String normalizeRouteId(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return value;

  try {
    value = Uri.decodeComponent(value).trim();
  } catch (_) {}

  while (value.length >= 2 &&
      ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'")))) {
    value = value.substring(1, value.length - 1).trim();
  }

  return value;
}
