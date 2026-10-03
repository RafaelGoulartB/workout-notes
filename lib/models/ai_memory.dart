/// Category of a long-term memory, used to group entries in the settings.
enum AiMemoryCategory {
  health,
  equipment,
  schedule,
  preference,
  goal,
  other;

  static AiMemoryCategory fromStorage(String? value) => values.firstWhere(
    (c) => c.name == value,
    orElse: () => AiMemoryCategory.other,
  );
}

/// A durable fact the coach remembers across conversations (injury,
/// equipment, schedule, preference, main goal…), visible and editable by the
/// user in the AI settings.
class AiMemory {
  final String id;
  final String content;
  final AiMemoryCategory category;
  final String? sourceThreadId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AiMemory({
    required this.id,
    required this.content,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    this.sourceThreadId,
  });

  AiMemory copyWith({String? content, AiMemoryCategory? category}) => AiMemory(
    id: id,
    content: content ?? this.content,
    category: category ?? this.category,
    sourceThreadId: sourceThreadId,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'content': content,
    'category': category.name,
    'source_thread_id': sourceThreadId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  static AiMemory fromRow(Map<String, dynamic> row) => AiMemory(
    id: row['id'] as String,
    content: row['content'] as String,
    category: AiMemoryCategory.fromStorage(row['category'] as String?),
    sourceThreadId: row['source_thread_id'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
  );
}
