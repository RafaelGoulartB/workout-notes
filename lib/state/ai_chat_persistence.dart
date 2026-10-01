part of 'ai_chat_service.dart';

/// Persistence by explicit thread id: nothing here reads "the active thread"
/// to decide where a message goes, so a turn running in one conversation can
/// never write into another.
extension _AiChatPersistence on AiChatService {
  /// The open conversation, or a new one titled after [firstUserText].
  Future<String> _ensureThread(DateTime now, String firstUserText) async {
    final active = _state.activeThreadId;
    if (active != null) return active;
    final id = _uuid.v4();
    // An empty title is the neutral marker the UI localizes (e.g. a message
    // with images only).
    final title = _autoTitle(firstUserText);
    final preview = _preview(firstUserText);
    await _db.aiChatRepo.upsertAiChatThread(
      id: id,
      title: title,
      createdAt: now,
      updatedAt: now,
      lastMessagePreview: preview,
    );
    _persistedMessages.clear();
    _state = _state.copyWith(
      activeThreadId: id,
      messages: const [],
      proposals: const [],
      hasOlderMessages: false,
      totalThreadCount: (_state.totalThreadCount ?? _state.threads.length) + 1,
      threads: [
        AiChatThread(
          id: id,
          title: title,
          createdAt: now,
          updatedAt: now,
          lastMessagePreview: preview,
        ),
        ..._state.threads,
      ],
    );
    return id;
  }

  static String _autoTitle(String text) => text.length > 48
      ? '${text.substring(0, 45)}…'
      : (text.isEmpty ? AiChatThread.genericTitle : text);

  static String _preview(String text) =>
      text.length > 96 ? '${text.substring(0, 93)}…' : text;

  /// Writes [messages] of [threadId]; unchanged instances are skipped.
  Future<void> _persistMessages(
    String threadId,
    List<AiChatMessage> messages,
  ) async {
    final rows = <Map<String, dynamic>>[];
    for (final message in messages) {
      if (identical(_persistedMessages[message.id], message)) continue;
      rows.add(message.toRow()..['thread_id'] = threadId);
    }
    if (rows.isEmpty) return;
    await _db.aiChatRepo.upsertAiChatMessages(threadId, rows);
    for (final message in messages) {
      _persistedMessages[message.id] = message;
    }
  }

  /// Bumps the thread's update time and preview after a turn.
  Future<void> _touchThread(String threadId) async {
    final row = await _db.aiChatRepo.getAiChatThread(threadId);
    if (row == null) return;
    final stored = AiChatThread.fromRow(row);
    final last = await _db.aiChatRepo.getAiChatMessagesPage(threadId, limit: 6);
    String? preview;
    for (final r in last.reversed) {
      final m = AiChatMessage.fromRow(r);
      if ((m.isUser || m.isAssistant) && (m.content?.isNotEmpty ?? false)) {
        preview = _preview(m.content!);
        break;
      }
    }
    final thread = stored.copyWith(
      updatedAt: _clock(),
      lastMessagePreview: preview ?? stored.lastMessagePreview,
    );
    await _db.aiChatRepo.upsertAiChatThread(
      id: thread.id,
      title: thread.title,
      createdAt: thread.createdAt,
      updatedAt: thread.updatedAt,
      lastMessagePreview: thread.lastMessagePreview,
      isPinned: thread.isPinned,
    );
    _upsertThreadInMemory(thread);
  }

  /// Keeps the loaded thread list in step with a save without reloading it:
  /// the thread moves to the top of its pinned/unpinned group.
  void _upsertThreadInMemory(AiChatThread thread) {
    final threads = [
      for (final t in _state.threads)
        if (t.id != thread.id) t,
    ];
    var index = threads.indexWhere(
      (t) => t.isPinned == thread.isPinned
          ? !t.updatedAt.isAfter(thread.updatedAt)
          : !t.isPinned,
    );
    if (index < 0) index = threads.length;
    threads.insert(index, thread);
    _state = _state.copyWith(threads: threads);
    _emit();
  }

  /// Appends an app event to [threadId] (persisted; shown in the open
  /// conversation as a status line and sent to the model as `<app_event>`).
  Future<void> _appendEvent(String threadId, Map<String, dynamic> event) async {
    final message = AiChatMessage(
      id: _uuid.v4(),
      threadId: threadId,
      role: AiMessageRole.event,
      content: jsonEncode(event),
      createdAt: _nextTimestamp(),
    );
    await _persistMessages(threadId, [message]);
    if (_state.activeThreadId == threadId) {
      _state = _state.copyWith(messages: [..._state.messages, message]);
      _emit();
    }
  }

  void _replaceMessageInState(AiChatMessage message, {bool notify = true}) {
    final index = _state.messages.indexWhere((m) => m.id == message.id);
    if (index < 0) return;
    final messages = [..._state.messages];
    messages[index] = message;
    _state = _state.copyWith(messages: messages);
    if (notify) _emit();
  }

  /// A retry deleted the message the summary was cut at: the summary
  /// describes messages that no longer exist, so it is dropped.
  Future<void> _resetSummaryIfCutDeleted(String threadId) async {
    final row = await _db.aiChatRepo.getAiChatThreadSummary(threadId);
    final cut = row?['through_message_id'] as String?;
    if (cut == null) return;
    if (!await _db.aiChatRepo.messageExists(cut)) {
      await _db.aiChatRepo.deleteAiChatThreadSummary(threadId);
    }
  }
}
