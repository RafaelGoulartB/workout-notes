class AiChatThread {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessagePreview;
  final bool archived;
  final bool isPinned;

  const AiChatThread({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.lastMessagePreview,
    this.archived = false,
    this.isPinned = false,
  });

  AiChatThread copyWith({
    String? title,
    DateTime? updatedAt,
    String? lastMessagePreview,
    bool? archived,
    bool? isPinned,
  }) {
    return AiChatThread(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      archived: archived ?? this.archived,
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toRow() => {
    'id': id,
    'title': title,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'last_message_preview': lastMessagePreview,
    'archived': archived ? 1 : 0,
    'is_pinned': isPinned ? 1 : 0,
  };

  static AiChatThread fromRow(Map<String, dynamic> row) {
    return AiChatThread(
      id: row['id'] as String,
      title: row['title'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      lastMessagePreview: row['last_message_preview'] as String?,
      archived: ((row['archived'] as int?) ?? 0) == 1,
      isPinned: ((row['is_pinned'] as int?) ?? 0) == 1,
    );
  }
}
