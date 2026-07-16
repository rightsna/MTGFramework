import 'ai_provider.dart';

/// Shared AI settings value type used across the MTG tools/editors. Holds the
/// selected [provider], a key per provider ([apiKeys]), the current model, and
/// the prompt tiers. The export/translate fields are optional and only used by
/// apps that translate on export. Persistence lives per-app (see `AiConfigStore`).
class AiConfig {
  /// Currently selected backend.
  final AiProvider provider;

  /// API key per provider (so switching providers keeps each key).
  final Map<AiProvider, String> apiKeys;

  final String model;

  /// App-wide style guide reused across **every** generation.
  final String style;

  /// Last per-call content prompt (remembered so it can be tweaked and reused).
  final String prompt;

  /// Per-group prompt (group key → prompt) — the middle tier between the
  /// app-wide [style] and the per-call [prompt].
  final Map<String, String> groupPrompts;

  /// (Optional) target language codes Export should additionally produce a
  /// translated `stage.<lang>.json` for. Empty = base only.
  final List<String> exportLanguages;

  /// (Optional) text model used to translate stages on export — separate from
  /// the image [model], reusing the same key.
  final String translateModel;

  const AiConfig({
    this.provider = AiProvider.gemini,
    this.apiKeys = const {},
    this.model = defaultModel,
    this.style = '',
    this.prompt = '',
    this.groupPrompts = const {},
    this.exportLanguages = const [],
    this.translateModel = defaultTranslateModel,
  });

  static const defaultModel = 'gemini-2.5-flash-image';
  static const defaultTranslateModel = 'gemini-2.5-flash';

  /// API key for the currently selected [provider].
  String get apiKey => apiKeys[provider] ?? '';
  bool get hasKey => apiKey.trim().isNotEmpty;

  AiConfig copyWith({
    AiProvider? provider,
    String? apiKey, // convenience: sets the (resulting) provider's key
    Map<AiProvider, String>? apiKeys,
    String? model,
    String? style,
    String? prompt,
    Map<String, String>? groupPrompts,
    List<String>? exportLanguages,
    String? translateModel,
  }) {
    final p = provider ?? this.provider;
    var keys = apiKeys ?? this.apiKeys;
    if (apiKey != null) keys = {...keys, p: apiKey};
    return AiConfig(
      provider: p,
      apiKeys: keys,
      model: model ?? this.model,
      style: style ?? this.style,
      prompt: prompt ?? this.prompt,
      groupPrompts: groupPrompts ?? this.groupPrompts,
      exportLanguages: exportLanguages ?? this.exportLanguages,
      translateModel: translateModel ?? this.translateModel,
    );
  }

  Map<String, dynamic> toJson() => {
        'provider': provider.name,
        'apiKeys': {for (final e in apiKeys.entries) e.key.name: e.value},
        'model': model,
        'style': style,
        'prompt': prompt,
        'groupPrompts': groupPrompts,
        'exportLanguages': exportLanguages,
        'translateModel': translateModel,
      };

  factory AiConfig.fromJson(Map<String, dynamic> json) {
    final keys = <AiProvider, String>{};
    final rawKeys = json['apiKeys'];
    if (rawKeys is Map) {
      for (final e in rawKeys.entries) {
        final name = e.key.toString();
        final match = AiProvider.values.where((x) => x.name == name);
        if (match.isNotEmpty && e.value is String) {
          keys[match.first] = e.value as String;
        }
      }
    }
    // Migrate legacy single 'apiKey' (Gemini-only configs) into the map.
    final legacy = json['apiKey'];
    if (legacy is String &&
        legacy.isNotEmpty &&
        !keys.containsKey(AiProvider.gemini)) {
      keys[AiProvider.gemini] = legacy;
    }
    final provider = AiProvider.values.firstWhere(
      (x) => x.name == json['provider'],
      orElse: () => AiProvider.gemini,
    );
    return AiConfig(
      provider: provider,
      apiKeys: keys,
      model: (json['model'] ?? defaultModel) as String,
      style: (json['style'] ?? '') as String,
      prompt: (json['prompt'] ?? '') as String,
      groupPrompts: ((json['groupPrompts'] as Map?) ?? const {})
          .map((k, v) => MapEntry(k.toString(), v.toString())),
      exportLanguages: ((json['exportLanguages'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      translateModel:
          (json['translateModel'] ?? defaultTranslateModel) as String,
    );
  }
}
