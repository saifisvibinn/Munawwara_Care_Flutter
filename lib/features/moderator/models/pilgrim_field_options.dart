/// Server-driven ethnicity labels and pilgrim language codes
/// (`GET /auth/platform-options/pilgrim-fields`).
class PilgrimLanguageOption {
  const PilgrimLanguageOption({
    required this.code,
    required this.label,
  });

  final String code;
  final String label;
}

class PilgrimFieldOptions {
  const PilgrimFieldOptions({
    required this.ethnicities,
    required this.languages,
  });

  final List<String> ethnicities;
  final List<PilgrimLanguageOption> languages;

  static PilgrimFieldOptions fallback() {
    return PilgrimFieldOptions(
      ethnicities: const [
        'Arab',
        'South Asian',
        'Turkic',
        'Persian',
        'Malay/Indonesian',
        'African',
        'Kurdish',
        'Berber',
        'European Muslim',
        'Other',
      ],
      languages: const [
        PilgrimLanguageOption(code: 'en', label: 'English'),
        PilgrimLanguageOption(code: 'ar', label: 'Arabic'),
        PilgrimLanguageOption(code: 'ur', label: 'Urdu'),
        PilgrimLanguageOption(code: 'fr', label: 'French'),
        PilgrimLanguageOption(code: 'id', label: 'Bahasa Indonesia'),
        PilgrimLanguageOption(code: 'tr', label: 'Turkish'),
        PilgrimLanguageOption(code: 'fa', label: 'Persian'),
        PilgrimLanguageOption(code: 'ms', label: 'Bahasa Malaysia'),
      ],
    );
  }

  factory PilgrimFieldOptions.fromJson(Map<String, dynamic> json) {
    final eth = (json['ethnicities'] as List<dynamic>? ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final langs = (json['languages'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((m) {
          final map = Map<String, dynamic>.from(m);
          return PilgrimLanguageOption(
            code: map['code']?.toString().trim() ?? '',
            label: map['label']?.toString().trim() ?? '',
          );
        })
        .where((l) => l.code.isNotEmpty)
        .toList();
    return PilgrimFieldOptions(ethnicities: eth, languages: langs);
  }
}
