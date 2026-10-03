import 'package:uuid/uuid.dart';
import 'package:workout_notes/services/ai_service.dart';

const _uuid = Uuid();

enum AiReasoningEffort { automatic, low, medium, high }

extension AiReasoningEffortX on AiReasoningEffort {
  String get storageKey => name;

  String? get apiValue => this == AiReasoningEffort.automatic ? null : name;

  static AiReasoningEffort fromStorageKey(String? value) {
    return AiReasoningEffort.values.firstWhere(
      (effort) => effort.storageKey == value,
      orElse: () => AiReasoningEffort.automatic,
    );
  }
}

/// A single AI provider configuration (OpenAI-compatible).
class AiProvider {
  final String id;
  final String name;
  final String baseUrl;
  final List<String> availableModels;
  final String selectedModel;
  final Map<String, AiReasoningEffort> reasoningEffortByModel;
  final DateTime createdAt;

  /// Optional cheaper model for background work (conversation summaries,
  /// titles). Empty means the selected model does it.
  final String utilityModel;

  /// Wire protocol: Chat Completions (any provider) or OpenAI Responses.
  final AiApiStyle apiStyle;

  /// Outcome of the last connection test, if any.
  final AiProviderCheck? lastCheck;

  const AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.availableModels,
    required this.selectedModel,
    this.reasoningEffortByModel = const {},
    required this.createdAt,
    this.utilityModel = '',
    this.apiStyle = AiApiStyle.chatCompletions,
    this.lastCheck,
  });

  factory AiProvider.create({
    required String name,
    required String baseUrl,
    String? selectedModel,
  }) {
    return AiProvider(
      id: _uuid.v4(),
      name: name,
      baseUrl: baseUrl,
      availableModels: const [],
      selectedModel: selectedModel ?? '',
      reasoningEffortByModel: const {},
      createdAt: DateTime.now(),
    );
  }

  AiProvider copyWith({
    String? name,
    String? baseUrl,
    List<String>? availableModels,
    String? selectedModel,
    Map<String, AiReasoningEffort>? reasoningEffortByModel,
    String? utilityModel,
    AiApiStyle? apiStyle,
    AiProviderCheck? lastCheck,
    bool clearLastCheck = false,
  }) {
    return AiProvider(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      availableModels: availableModels ?? this.availableModels,
      selectedModel: selectedModel ?? this.selectedModel,
      reasoningEffortByModel:
          reasoningEffortByModel ?? this.reasoningEffortByModel,
      createdAt: createdAt,
      utilityModel: utilityModel ?? this.utilityModel,
      apiStyle: apiStyle ?? this.apiStyle,
      lastCheck: clearLastCheck ? null : (lastCheck ?? this.lastCheck),
    );
  }

  AiReasoningEffort reasoningEffortFor([String? model]) {
    return reasoningEffortByModel[model ?? selectedModel] ??
        AiReasoningEffort.automatic;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'availableModels': availableModels,
    'selectedModel': selectedModel,
    'reasoningEffortByModel': reasoningEffortByModel.map(
      (model, effort) => MapEntry(model, effort.storageKey),
    ),
    'createdAt': createdAt.toIso8601String(),
    if (utilityModel.isNotEmpty) 'utilityModel': utilityModel,
    'apiStyle': apiStyle.storageKey,
    if (lastCheck != null) 'lastCheck': lastCheck!.toMap(),
  };

  factory AiProvider.fromMap(Map<String, dynamic> m) {
    return AiProvider(
      id: m['id'] as String,
      name: m['name'] as String,
      baseUrl: m['baseUrl'] as String,
      availableModels:
          (m['availableModels'] as List?)?.cast<String>() ?? const [],
      selectedModel: (m['selectedModel'] as String?) ?? '',
      reasoningEffortByModel:
          (m['reasoningEffortByModel'] as Map?)?.map(
            (model, effort) => MapEntry(
              model.toString(),
              AiReasoningEffortX.fromStorageKey(effort?.toString()),
            ),
          ) ??
          const {},
      createdAt:
          DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
      utilityModel: (m['utilityModel'] as String?) ?? '',
      apiStyle: AiApiStyle.fromStorageKey(m['apiStyle'] as String?),
      lastCheck: m['lastCheck'] is Map
          ? AiProviderCheck.fromMap((m['lastCheck'] as Map).cast())
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is AiProvider && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// What the last connection test found for the provider's selected model.
class AiProviderCheck {
  final String model;
  final bool ok;
  final bool toolsSupported;
  final bool streamingSupported;
  final int latencyMs;
  final String? errorCode;
  final DateTime checkedAt;

  const AiProviderCheck({
    required this.model,
    required this.ok,
    required this.toolsSupported,
    required this.streamingSupported,
    required this.latencyMs,
    required this.checkedAt,
    this.errorCode,
  });

  Map<String, dynamic> toMap() => {
    'model': model,
    'ok': ok,
    'toolsSupported': toolsSupported,
    'streamingSupported': streamingSupported,
    'latencyMs': latencyMs,
    if (errorCode != null) 'errorCode': errorCode,
    'checkedAt': checkedAt.toIso8601String(),
  };

  factory AiProviderCheck.fromMap(Map<String, dynamic> m) => AiProviderCheck(
    model: (m['model'] as String?) ?? '',
    ok: m['ok'] == true,
    toolsSupported: m['toolsSupported'] == true,
    streamingSupported: m['streamingSupported'] == true,
    latencyMs: (m['latencyMs'] as num?)?.toInt() ?? 0,
    errorCode: m['errorCode'] as String?,
    checkedAt:
        DateTime.tryParse(m['checkedAt'] as String? ?? '') ?? DateTime.now(),
  );
}
