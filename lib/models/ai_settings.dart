import 'ai_provider.dart';

/// Persisted AI configuration: providers, active id, system prompt, context mode.
class AiSettings {
  final List<AiProvider> providers;
  final String? activeProviderId;
  final String systemPrompt;
  final AiContextMode contextMode;
  final AiResponseStyle responseStyle;
  final bool showMessageTimestamps;
  final bool autoExpandToolDetails;

  const AiSettings({
    this.providers = const [],
    this.activeProviderId,
    this.systemPrompt = '',
    this.contextMode = AiContextMode.standard,
    this.responseStyle = AiResponseStyle.balanced,
    this.showMessageTimestamps = true,
    this.autoExpandToolDetails = false,
  });

  bool get isConfigured =>
      providers.isNotEmpty &&
      activeProviderId != null &&
      activeProviderId!.isNotEmpty &&
      _activeProvider != null;

  AiProvider? get _activeProvider {
    if (activeProviderId == null) return null;
    for (final p in providers) {
      if (p.id == activeProviderId) return p;
    }
    return null;
  }

  AiProvider? get activeProvider {
    final p = _activeProvider;
    if (p != null) return p;
    if (providers.isEmpty) return null;
    return providers.first;
  }

  AiSettings copyWith({
    List<AiProvider>? providers,
    String? activeProviderId,
    bool clearActiveProvider = false,
    String? systemPrompt,
    AiContextMode? contextMode,
    AiResponseStyle? responseStyle,
    bool? showMessageTimestamps,
    bool? autoExpandToolDetails,
  }) {
    return AiSettings(
      providers: providers ?? this.providers,
      activeProviderId: clearActiveProvider
          ? null
          : (activeProviderId ?? this.activeProviderId),
      systemPrompt: systemPrompt ?? this.systemPrompt,
      contextMode: contextMode ?? this.contextMode,
      responseStyle: responseStyle ?? this.responseStyle,
      showMessageTimestamps:
          showMessageTimestamps ?? this.showMessageTimestamps,
      autoExpandToolDetails:
          autoExpandToolDetails ?? this.autoExpandToolDetails,
    );
  }
}

/// Controls answer length without changing the coach's expertise or tool use.
enum AiResponseStyle { concise, balanced, detailed }

extension AiResponseStyleX on AiResponseStyle {
  String get storageKey => name;

  String get systemInstruction {
    switch (this) {
      case AiResponseStyle.concise:
        return 'Preferência de resposta: seja conciso. Responda diretamente, '
            'use poucos parágrafos e inclua apenas os dados e próximos passos '
            'essenciais, sem omitir alertas importantes.';
      case AiResponseStyle.balanced:
        return 'Preferência de resposta: use um nível equilibrado de detalhe, '
            'com explicação breve dos dados e próximos passos práticos.';
      case AiResponseStyle.detailed:
        return 'Preferência de resposta: seja detalhado. Explique as evidências, '
            'limitações, relações entre os dados e recomendações práticas com '
            'clareza, mantendo a leitura confortável no celular.';
    }
  }

  static AiResponseStyle fromStorageKey(String? value) {
    return AiResponseStyle.values.firstWhere(
      (style) => style.storageKey == value,
      orElse: () => AiResponseStyle.balanced,
    );
  }
}
