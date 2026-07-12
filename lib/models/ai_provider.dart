import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A single AI provider configuration (OpenAI-compatible).
class AiProvider {
  final String id;
  final String name;
  final String baseUrl;
  final List<String> availableModels;
  final String selectedModel;
  final DateTime createdAt;

  const AiProvider({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.availableModels,
    required this.selectedModel,
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
      createdAt: DateTime.now(),
    );
  }

  AiProvider copyWith({
    String? name,
    String? baseUrl,
    List<String>? availableModels,
    String? selectedModel,
  }) {
    return AiProvider(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      availableModels: availableModels ?? this.availableModels,
      selectedModel: selectedModel ?? this.selectedModel,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'availableModels': availableModels,
    'selectedModel': selectedModel,
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
