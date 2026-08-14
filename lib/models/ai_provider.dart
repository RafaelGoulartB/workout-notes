import 'package:uuid/uuid.dart';

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

  const AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.availableModels,
    required this.selectedModel,
    this.reasoningEffortByModel = const {},
    required this.createdAt,
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
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is AiProvider && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

enum AiContextMode { minimal, standard, full }

extension AiContextModeX on AiContextMode {
  String get storageKey {
    switch (this) {
      case AiContextMode.minimal:
        return 'minimal';
      case AiContextMode.standard:
        return 'standard';
      case AiContextMode.full:
        return 'full';
    }
  }

  String get label {
    switch (this) {
      case AiContextMode.minimal:
        return 'Minimal';
      case AiContextMode.standard:
        return 'Standard';
      case AiContextMode.full:
        return 'Full';
    }
  }

  static AiContextMode fromStorageKey(String? value) {
    switch (value) {
      case 'minimal':
        return AiContextMode.minimal;
      case 'full':
        return AiContextMode.full;
      case 'standard':
      default:
        return AiContextMode.standard;
    }
  }
}
