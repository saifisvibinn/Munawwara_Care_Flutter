import 'package:easy_localization/easy_localization.dart';

import '../providers/call_provider.dart';

/// True when [name] is missing or the backend / CallKit placeholder.
bool isUnresolvedCallPeerName(String? name) {
  if (name == null) return true;
  final trimmed = name.trim();
  if (trimmed.isEmpty) return true;
  return trimmed.toLowerCase() == 'unknown';
}

/// Best label for the in-call header (never returns the literal "Unknown").
String resolveCallPeerDisplayName({
  required CallState call,
  String? cachedName,
}) {
  if (call.displayPeerAsSupportBranding) {
    return 'call_support_display_name'.tr();
  }

  for (final candidate in <String?>[
    cachedName,
    call.incomingDisplayName,
    call.remoteUserName,
  ]) {
    if (!isUnresolvedCallPeerName(candidate)) {
      return candidate!.trim();
    }
  }

  return '';
}

/// Up to two initials for avatar rings.
String callPeerInitials(String displayName) {
  return displayName
      .trim()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .take(2)
      .map((w) => w[0].toUpperCase())
      .join();
}
