const String _ltrIsolateStart = '\u2066';
const String _ltrIsolateEnd = '\u2069';

/// Wraps [value] so digits and symbols render left-to-right in RTL locales.
String formatLtrDisplay(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return value;
  }
  return '$_ltrIsolateStart$trimmed$_ltrIsolateEnd';
}

/// Formats a phone number for on-screen display in RTL layouts.
String formatPhoneNumberForDisplay(String phoneNumber) =>
    formatLtrDisplay(phoneNumber);

/// Whether [value] looks like a phone number rather than free text.
bool looksLikePhoneNumber(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  return RegExp(r'^[\d+\s\-().]+$').hasMatch(trimmed);
}
