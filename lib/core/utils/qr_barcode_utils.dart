import 'package:mobile_scanner/mobile_scanner.dart';

/// First non-empty barcode payload from [capture], or null.
String? firstBarcodeRawValue(BarcodeCapture capture) {
  final v = capture.barcodes.firstOrNull?.rawValue;
  if (v == null) return null;
  final t = v.trim();
  if (t.isEmpty) return null;
  return t;
}

/// Returns `token` query value when [raw] parses as a URI; otherwise [raw] trimmed.
String tokenOrQueryParamFromPayload(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri != null) {
    final qp = uri.queryParameters['token'];
    if (qp != null && qp.trim().isNotEmpty) return qp.trim();
  }
  return trimmed;
}
