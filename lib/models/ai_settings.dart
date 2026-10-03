import 'package:workout_notes/models/ai_provider.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';

/// Persisted AI configuration: providers, active id, the user's custom
/// instructions, answer style, which data domains the coach may read, and
/// whether the user accepted sending data to the provider.
class AiSettings {
  final List<AiProvider> providers;
  final String? activeProviderId;

  /// Tone / focus / persona added on top of the product prompt. Empty means
  /// no personalisation.
  final String customInstructions;
  final AiResponseStyle responseStyle;
  final bool showMessageTimestamps;

  /// Domains the coach may read and propose changes to.
  final Set<AiToolDomain> enabledDomains;

  /// The user acknowledged that messages and the data the coach reads are
  /// sent to the configured provider.
  final bool dataSharingAccepted;

  /// Shows raw tool payloads and per-turn diagnostics (developer option).
  final bool developerMode;

  const AiSettings({
    this.providers = const [],
    this.activeProviderId,
    this.customInstructions = '',
    this.responseStyle = AiResponseStyle.balanced,
    this.showMessageTimestamps = true,
    this.enabledDomains = const {...AiToolDomain.values},
    this.dataSharingAccepted = false,
    this.developerMode = false,
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

  /// [enabledDomains] plus the always-on core domain.
  Set<AiToolDomain> get effectiveDomains => {
    AiToolDomain.core,
    ...enabledDomains,
  };

  AiSettings copyWith({
    List<AiProvider>? providers,
    String? activeProviderId,
    bool clearActiveProvider = false,
    String? customInstructions,
    AiResponseStyle? responseStyle,
    bool? showMessageTimestamps,
    Set<AiToolDomain>? enabledDomains,
    bool? dataSharingAccepted,
    bool? developerMode,
  }) {
    return AiSettings(
      providers: providers ?? this.providers,
      activeProviderId: clearActiveProvider
          ? null
          : (activeProviderId ?? this.activeProviderId),
      customInstructions: customInstructions ?? this.customInstructions,
      responseStyle: responseStyle ?? this.responseStyle,
      showMessageTimestamps:
          showMessageTimestamps ?? this.showMessageTimestamps,
      enabledDomains: enabledDomains ?? this.enabledDomains,
      dataSharingAccepted: dataSharingAccepted ?? this.dataSharingAccepted,
      developerMode: developerMode ?? this.developerMode,
    );
  }
}

/// Controls answer length without changing the coach's expertise or tool use.
enum AiResponseStyle { concise, balanced, detailed }

extension AiResponseStyleX on AiResponseStyle {
  String get storageKey => name;

  static AiResponseStyle fromStorageKey(String? value) {
    return AiResponseStyle.values.firstWhere(
      (style) => style.storageKey == value,
      orElse: () => AiResponseStyle.balanced,
    );
  }
}
