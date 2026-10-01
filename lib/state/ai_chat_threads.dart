part of 'ai_chat_service.dart';

/// A page of SQLite thread-search results.
class AiThreadSearchPage {
  final List<AiChatThread> threads;
  final bool hasMore;

  /// Total matches; only set on the first page.
  final int? total;

  const AiThreadSearchPage({
    required this.threads,
    required this.hasMore,
    this.total,
  });
}

/// Public thread lifecycle operations kept separate from turn execution.
/// None of them disturbs a running turn: it stays bound to its own thread.
extension AiChatThreadManagement on AiChatService {
  static const int _messagePageSize = 80;
  static const int _threadPageSize = 100;

  Future<void> refreshThreads({bool notify = true}) async {
    try {
      final rows = await _db.aiChatRepo.getAiChatThreadsPage(
        limit: _threadPageSize + 1,
      );
      final hasOlder = rows.length > _threadPageSize;
      final total = await _db.aiChatRepo.countAiChatThreads();
      _state = _state.copyWith(
        threads: rows.take(_threadPageSize).map(AiChatThread.fromRow).toList(),
        hasOlderThreads: hasOlder,
        isLoadingOlderThreads: false,
        totalThreadCount: total,
      );
      if (notify) _emit();
    } catch (error) {
      debugPrint('Loading AI chat threads failed: $error');
    }
  }

  /// One page of threads matching [query] straight from SQLite (title,
  /// preview and message text; case- and accent-insensitive). [total] is
  /// only computed for the first page.
  Future<AiThreadSearchPage> searchThreads(
    String query, {
    int offset = 0,
    int limit = _threadPageSize,
  }) async {
    final rows = await _db.aiChatRepo.searchAiChatThreadsPage(
      query: query,
      limit: limit + 1,
      offset: offset,
    );
    final hasMore = rows.length > limit;
    final total = offset == 0
        ? (hasMore
              ? await _db.aiChatRepo.countAiChatThreads(query: query)
              : rows.length)
        : null;
    return AiThreadSearchPage(
      threads: rows.take(limit).map(AiChatThread.fromRow).toList(),
      hasMore: hasMore,
      total: total,
    );
  }

  Future<void> loadOlderThreads() async {
    if (!_state.hasOlderThreads || _state.isLoadingOlderThreads) return;
    _state = _state.copyWith(isLoadingOlderThreads: true);
    _emit();
    try {
      final rows = await _db.aiChatRepo.getAiChatThreadsPage(
        limit: _threadPageSize + 1,
        offset: _state.threads.length,
      );
      _state = _state.copyWith(
        threads: [
          ..._state.threads,
          ...rows.take(_threadPageSize).map(AiChatThread.fromRow),
        ],
        hasOlderThreads: rows.length > _threadPageSize,
        isLoadingOlderThreads: false,
      );
      _emit();
    } catch (e) {
      _state = _state.copyWith(
        error: _readableError(e),
        isLoadingOlderThreads: false,
      );
      _emit();
    }
  }

  /// Shows an empty conversation. A running turn keeps going in its thread.
  Future<void> newChat() async {
    if (_state.activeThreadId == null && _state.messages.isEmpty) return;
    _state = _state.copyWith(
      clearActiveThread: true,
      messages: const [],
      proposals: const [],
      hasOlderMessages: false,
      isLoadingOlderMessages: false,
      clearError: true,
    );
    _persistedMessages.clear();
    _emit();
  }

  Future<void> openThread(String threadId) async {
    if (_state.activeThreadId == threadId) return;
    try {
      final rows = await _db.aiChatRepo.getAiChatMessagesPage(
        threadId,
        limit: _messagePageSize + 1,
      );
      final hasOlder = rows.length > _messagePageSize;
      final visible = (hasOlder ? rows.sublist(1) : rows)
          .map(AiChatMessage.fromRow)
          .toList();
      final messages = await _markInterruptedTurns(threadId, visible);
      _persistedMessages
        ..clear()
        ..addEntries(messages.map((m) => MapEntry(m.id, m)));
      final proposals = await _proposals.forThread(threadId);
      _state = _state.copyWith(
        activeThreadId: threadId,
        messages: messages,
        clearError: true,
        proposals: proposals,
        hasOlderMessages: hasOlder,
        isLoadingOlderMessages: false,
      );
      _emit();
    } catch (e) {
      _state = _state.copyWith(error: _readableError(e));
      _emit();
    }
  }

  /// A user message still marked `running` with no turn running for it was
  /// cut short (app killed, crash): mark it interrupted, persistently.
  Future<List<AiChatMessage>> _markInterruptedTurns(
    String threadId,
    List<AiChatMessage> messages,
  ) async {
    final runningId = _turn?.threadId == threadId
        ? _turn!.userMessage.id
        : null;
    final out = <AiChatMessage>[];
    for (final m in messages) {
      if (m.isUser &&
          m.turnStatus == AiTurnStatus.running &&
          m.id != runningId) {
        final interrupted = m.copyWith(turnStatus: AiTurnStatus.interrupted);
        await _db.aiChatRepo.setTurnStatus(m.id, AiTurnStatus.interrupted.name);
        out.add(interrupted);
      } else {
        out.add(m);
      }
    }
    return out;
  }

  /// Loads the page before the oldest loaded message (keyset pagination).
  Future<void> loadOlderMessages() async {
    final threadId = _state.activeThreadId;
    if (threadId == null ||
        !_state.hasOlderMessages ||
        _state.isLoadingOlderMessages ||
        _state.messages.isEmpty) {
      return;
    }
    _state = _state.copyWith(isLoadingOlderMessages: true);
    _emit();
    try {
      final oldest = _state.messages.first;
      final rows = await _db.aiChatRepo.getAiChatMessagesPage(
        threadId,
        limit: _messagePageSize + 1,
        beforeCreatedAt: oldest.createdAt.toIso8601String(),
        beforeId: oldest.id,
      );
      if (_state.activeThreadId != threadId) return;
      final hasOlder = rows.length > _messagePageSize;
      final older = (hasOlder ? rows.sublist(1) : rows)
          .map(AiChatMessage.fromRow)
          .toList();
      for (final m in older) {
        _persistedMessages[m.id] = m;
      }
      _state = _state.copyWith(
        messages: [...older, ..._state.messages],
        hasOlderMessages: hasOlder,
        isLoadingOlderMessages: false,
      );
      _emit();
    } catch (e) {
      _state = _state.copyWith(
        error: _readableError(e),
        isLoadingOlderMessages: false,
      );
      _emit();
    }
  }

  /// Deletes a conversation (its running turn, if any, is cancelled first).
  Future<void> deleteThread(String threadId) async {
    if (_turn?.threadId == threadId) cancelTurn();
    final attachments = <AiImageAttachment>[];
    try {
      for (final raw in await _db.aiChatRepo.getAttachmentsJson(threadId)) {
        final decoded = jsonDecode(raw);
        if (decoded is! List) continue;
        for (final item in decoded) {
          if (item is Map) {
            attachments.add(
              AiImageAttachment.fromJson(item.cast<String, dynamic>()),
            );
          }
        }
      }
    } catch (error) {
      // Attachment cleanup is best-effort; orphans are swept on next launch.
      debugPrint('Reading AI attachments to delete failed: $error');
    }
    try {
      await _db.aiChatRepo.deleteAiChatThread(threadId);
      await _imageStore.deleteAll(attachments);
      final threads = _state.threads.where((t) => t.id != threadId).toList();
      final clearActive = _state.activeThreadId == threadId;
      if (clearActive) _persistedMessages.clear();
      _state = _state.copyWith(
        threads: threads,
        totalThreadCount: _state.totalThreadCount == null
            ? null
            : (_state.totalThreadCount! - 1).clamp(0, 1 << 30),
        clearActiveThread: clearActive,
        messages: clearActive ? const [] : _state.messages,
        proposals: clearActive ? const [] : _state.proposals,
        hasOlderMessages: clearActive ? false : _state.hasOlderMessages,
        isLoadingOlderMessages: false,
      );
      _emit();
    } catch (e) {
      _state = _state.copyWith(error: _readableError(e));
      _emit();
    }
  }

  Future<bool> renameThread(String threadId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return false;
    try {
      await _db.aiChatRepo.renameAiChatThread(threadId, trimmed);
      _state = _state.copyWith(
        threads: [
          for (final t in _state.threads)
            t.id == threadId ? t.copyWith(title: trimmed) : t,
        ],
      );
      _emit();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: _readableError(e));
      _emit();
      return false;
    }
  }

  Future<bool> setThreadPinned(String threadId, bool isPinned) async {
    try {
      await _db.aiChatRepo.setAiChatThreadPinned(threadId, isPinned);
      final thread = _state.threads.where((t) => t.id == threadId);
      if (thread.isNotEmpty) {
        _upsertThreadInMemory(thread.first.copyWith(isPinned: isPinned));
      } else {
        await refreshThreads();
      }
      return true;
    } catch (e) {
      _state = _state.copyWith(error: _readableError(e));
      _emit();
      return false;
    }
  }
}
