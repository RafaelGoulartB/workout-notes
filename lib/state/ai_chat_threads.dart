part of 'ai_chat_service.dart';

/// Public thread lifecycle operations kept separate from turn execution.
extension AiChatThreadManagement on AiChatService {
  Future<void> refreshThreads({bool notify = true}) async {
    try {
      final rows = await _db.getAiChatThreads();
      _state = _state.copyWith(
        threads: rows.map(AiChatThread.fromRow).toList(),
      );
      if (notify) _emit();
    } catch (_) {}
  }

  Future<void> newChat() async {
    if (_state.activeThreadId == null && _state.messages.isEmpty) return;
    _state = _state.copyWith(
      clearActiveThread: true,
      messages: const [],
      clearError: true,
      phase: AiTurnPhase.idle,
    );
    _emit();
  }

  Future<void> openThread(String threadId) async {
    if (_state.activeThreadId == threadId) return;
    try {
      final rows = await _db.getAiChatMessagesThread(threadId);
      final messages = rows.map(AiChatMessage.fromRow).toList();
      final proposals = await _routineMutations.getThreadProposals(threadId);
      _state = _state.copyWith(
        activeThreadId: threadId,
        messages: messages,
        clearError: true,
        phase: AiTurnPhase.idle,
        routineProposals: proposals,
      );
      _recoverInterruptedTurn(messages);
      _emit();
    } catch (e) {
      _state = _state.copyWith(error: _readableError(e));
      _emit();
    }
  }

  Future<void> deleteThread(String threadId) async {
    var attachments = <AiImageAttachment>[];
    try {
      final rows = await _db.getAiChatMessagesThread(threadId);
      attachments = rows
          .map(AiChatMessage.fromRow)
          .expand((message) => message.attachments)
          .toList();
    } catch (_) {}
    try {
      await _db.deleteAiChatThread(threadId);
      await _imageStore.deleteAll(attachments);
      final threads = _state.threads.where((t) => t.id != threadId).toList();
      final clearActive = _state.activeThreadId == threadId;
      _state = _state.copyWith(
        threads: threads,
        clearActiveThread: clearActive,
        messages: clearActive ? const [] : _state.messages,
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
      await _db.renameAiChatThread(threadId, trimmed);
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
      await _db.setAiChatThreadPinned(threadId, isPinned);
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
