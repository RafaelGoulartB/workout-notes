import 'ai_provider.dart';

/// Persisted AI configuration: providers, active id, system prompt, context mode.
class AiSettings {
  final List<AiProvider> providers;
  final String? activeProviderId;
  final String systemPrompt;
  final AiContextMode contextMode;

  const AiSettings({
    this.providers = const [],
    this.activeProviderId,
    this.systemPrompt = '',
    this.contextMode = AiContextMode.standard,
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
  }) {
    return AiSettings(
      providers: providers ?? this.providers,
      activeProviderId:
          clearActiveProvider ? null : (activeProviderId ?? this.activeProviderId),
      systemPrompt: systemPrompt ?? this.systemPrompt,
      contextMode: contextMode ?? this.contextMode,
    );
  }
}
