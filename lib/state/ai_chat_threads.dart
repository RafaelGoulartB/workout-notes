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
extension AiChatThreadManagement on AiChatService {
  static const int _messagePageSize = 100;
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
    } catch (_) {}
  }

  /// One page of threads matching [query] straight from SQLite (title,
  /// preview and message text), so conversations outside the loaded pages are
  /// found too. [total] is only computed for the first page.
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
    final total = offset == 0
        ? await _db.aiChatRepo.countAiChatThreads(query: query)
        : null;
    return AiThreadSearchPage(
      threads: rows.take(limit).map(AiChatThread.fromRow).toList(),
      hasMore: rows.length > limit,
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

  Future<void> newChat() async {
    if (_state.activeThreadId == null && _state.messages.isEmpty) return;
    _state = _state.copyWith(
      clearActiveThread: true,
      messages: const [],
      hasOlderMessages: false,
      isLoadingOlderMessages: false,
      clearError: true,
      phase: AiTurnPhase.idle,
    );
    _persistedMessages.clear();
    _emit();
  }

  Future<void> openThread(String threadId) async {
    if (_state.activeThreadId == threadId) return;
    try {
      final rows = await _db.aiChatRepo.getAiChatMessagesThreadPage(
        threadId,
        limit: _messagePageSize + 1,
      );
      final hasOlder = rows.length > _messagePageSize;
      final visibleRows = hasOlder ? rows.sublist(1) : rows;
      final messages = visibleRows.map(AiChatMessage.fromRow).toList();
      _persistedMessages
        ..clear()
        ..addEntries(
          messages.map(
            (message) => MapEntry(message.id, (
              message: message,
              signature: jsonEncode(message.toRow()),
            )),
          ),
        );
      final proposals = await _routineMutations.getThreadProposals(threadId);
      _state = _state.copyWith(
        activeThreadId: threadId,
        messages: messages,
        clearError: true,
        phase: AiTurnPhase.idle,
        routineProposals: proposals,
        hasOlderMessages: hasOlder,
        isLoadingOlderMessages: false,
      );
      _recoverInterruptedTurn(messages);
      _emit();
    } catch (e) {
      _state = _state.copyWith(error: _readableError(e));
      _emit();
    }
  }

  Future<void> loadOlderMessages() async {
    final threadId = _state.activeThreadId;
    if (threadId == null ||
        !_state.hasOlderMessages ||
        _state.isLoadingOlderMessages) {
      return;
    }
    _state = _state.copyWith(isLoadingOlderMessages: true);
    _emit();
    try {
      final rows = await _db.aiChatRepo.getAiChatMessagesThreadPage(
        threadId,
        limit: _messagePageSize + 1,
        offset: _state.messages.length,
      );
      final hasOlder = rows.length > _messagePageSize;
      final visibleRows = hasOlder ? rows.sublist(1) : rows;
      final older = visibleRows.map(AiChatMessage.fromRow).toList();
      _persistedMessages.addEntries(
        older.map(
          (message) => MapEntry(message.id, (
            message: message,
            signature: jsonEncode(message.toRow()),
          )),
        ),
      );
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

  Future<void> deleteThread(String threadId) async {
    var attachments = <AiImageAttachment>[];
    try {
      final rows = await _db.aiChatRepo.getAiChatMessagesThread(threadId);
      attachments = rows
          .map(AiChatMessage.fromRow)
          .expand((message) => message.attachments)
          .toList();
    } catch (_) {}
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
      await refreshThreads(notify: false);
      _state = _state.copyWith(clearError: true);
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
      await refreshThreads(notify: false);
      _state = _state.copyWith(clearError: true);
      _emit();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: _readableError(e));
      _emit();
      return false;
    }
  }
}
