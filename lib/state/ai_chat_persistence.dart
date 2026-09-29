part of 'ai_chat_service.dart';

/// Persists chat transcripts and finalises approved routine proposals.
extension _AiChatPersistence on AiChatService {
  Future<String> _ensureThread(
    List<AiChatMessage> messages,
    DateTime now,
    String firstUserText,
  ) async {
    if (_state.activeThreadId != null) return _state.activeThreadId!;
    final id = _uuid.v4();
    final title = firstUserText.length > 48
        ? '${firstUserText.substring(0, 45)}…'
        : firstUserText;
    // An empty title is the neutral marker: the UI localizes it.
    final resolvedTitle = title.isEmpty ? AiChatThread.genericTitle : title;
    final preview = firstUserText.length > 96
        ? '${firstUserText.substring(0, 93)}…'
        : firstUserText;
    await _db.aiChatRepo.upsertAiChatThread(
      id: id,
      title: resolvedTitle,
      createdAt: now,
      updatedAt: now,
      lastMessagePreview: preview,
      isPinned: false,
    );
    // Keep the just-created thread in memory before the first turn is
    // persisted. Otherwise `_persistCurrentThread` cannot resolve it and
    // overwrites its descriptive title with the generic marker.
    _state = _state.copyWith(
      totalThreadCount: (_state.totalThreadCount ?? _state.threads.length) + 1,
      threads: [
        AiChatThread(
          id: id,
          title: resolvedTitle,
          createdAt: now,
          updatedAt: now,
          lastMessagePreview: preview,
        ),
        ..._state.threads,
      ],
    );
    return id;
  }

  Future<void> _persistCurrentThread() async {
    final id = _state.activeThreadId;
    if (id == null) return;
    try {
      final preview = _lastUserOrAssistantPreview();
      // A thread opened from search may not be among the loaded pages; read
      // its stored row so title, creation time and pin are never reset.
      final existing = _state.activeThread ?? await _loadStoredThread(id);
      final now = DateTime.now();
      final thread = AiChatThread(
        id: id,
        title: existing?.title ?? AiChatThread.genericTitle,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        lastMessagePreview: preview,
        isPinned: existing?.isPinned ?? false,
      );
      await _db.aiChatRepo.upsertAiChatThread(
        id: id,
        title: thread.title,
        createdAt: thread.createdAt,
        updatedAt: thread.updatedAt,
        lastMessagePreview: preview,
        isPinned: thread.isPinned,
      );
      // Messages are immutable: the same instance as the last save is clean
      // without encoding it again. Others are encoded once and only written
      // when their row really changed.
      final changedRows = <Map<String, dynamic>>[];
      final seen = <String, ({AiChatMessage message, String signature})>{};
      for (final message in _state.messages) {
        if (message.role == AiMessageRole.system) continue;
        final known = _persistedMessages[message.id];
        if (identical(known?.message, message)) continue;
        final row = message.toRow()..['thread_id'] = id;
        final signature = jsonEncode(row);
        if (known?.signature != signature) changedRows.add(row);
        seen[message.id] = (message: message, signature: signature);
      }
      await _db.aiChatRepo.upsertAiChatMessages(id, changedRows);
      _persistedMessages.addAll(seen);
      _upsertThreadInMemory(thread);
    } catch (_) {}
  }

  Future<AiChatThread?> _loadStoredThread(String id) async {
    final row = await _db.aiChatRepo.getAiChatThread(id);
    return row == null ? null : AiChatThread.fromRow(row);
  }

  /// Keeps the loaded thread list in step with a save without reloading it:
  /// the saved thread moves to the top of its pinned/unpinned group
  /// (`is_pinned DESC, updated_at DESC`) and loaded pages are preserved.
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

  void _replaceProposal(AiRoutineProposal proposal, {bool notify = true}) {
    final proposals = [..._state.routineProposals];
    final index = proposals.indexWhere((item) => item.id == proposal.id);
    if (index == -1) {
      proposals.add(proposal);
    } else {
      proposals[index] = proposal;
    }
    _state = _state.copyWith(routineProposals: proposals);
    if (notify) _emit();
  }

  Future<void> _sendAppliedProposalSummary(AiRoutineProposal proposal) async {
    if (_settings == null || !_settings!.isConfigured) return;
    final provider = _settings!.activeProvider!;
    final token = await _settings!.getToken(provider.id);
    if (token == null || token.isEmpty || provider.selectedModel.isEmpty) {
      return;
    }
    _state = _state.copyWith(
      phase: AiTurnPhase.sending,
      phaseMessage: 'finalising',
      clearError: true,
    );
    _emit();
    try {
      final context = await _context.build(mode: _settings!.contextMode);
      final wire = _buildWireMessages(
        _state.messages,
        _TurnWireOptions(
          systemPrompt: _settings!.effectiveSystemPrompt,
          contextJson: context,
        ),
      );
      wire.add({
        'role': 'user',
        'content': appliedProposalEventPrompt(
          proposal,
          languageCode: _settings!.appLanguageCode,
        ),
      });
      final completion = await _service.sendChat(
        baseUrl: provider.baseUrl,
        token: token,
        model: provider.selectedModel,
        reasoningEffort: provider.reasoningEffortFor().apiValue,
        messages: wire,
      );
      final text = completion.text?.trim();
      if (text == null || text.isEmpty) {
        throw const AiServiceException(
          'Resumo vazio.',
          code: 'invalid_response',
        );
      }
      final summary = AiChatMessage(
        id: _uuid.v4(),
        threadId: _state.activeThreadId ?? '',
        role: AiMessageRole.assistant,
        content: text,
        createdAt: DateTime.now(),
      );
      _state = _state.copyWith(
        messages: [..._state.messages, summary],
        phase: AiTurnPhase.idle,
        phaseMessage: null,
      );
      await _db.aiChatRepo.updateAiRoutineProposal(proposal.id, {
        'error_code': null,
        'error_message': null,
      });
      final refreshed = await _routineMutations.getProposal(proposal.id);
      if (refreshed != null) _replaceProposal(refreshed, notify: false);
      _emit();
      await _persistCurrentThread();
    } catch (_) {
      // The routine is already committed. Keep it applied and expose a retry
      // on the proposal card instead of risking a second mutation.
      await _db.aiChatRepo.updateAiRoutineProposal(proposal.id, {
        'error_code': 'summary_pending',
        'error_message': 'Resumo da IA pendente.',
      });
      final refreshed = await _routineMutations.getProposal(proposal.id);
      if (refreshed != null) _replaceProposal(refreshed, notify: false);
      _state = _state.copyWith(phase: AiTurnPhase.idle, phaseMessage: null);
      _emit();
    }
  }

  String? _lastUserOrAssistantPreview() {
    for (var i = _state.messages.length - 1; i >= 0; i--) {
      final m = _state.messages[i];
      if (m.isUser || m.isAssistant) {
        final text = m.content;
        if (text == null || text.isEmpty) continue;
        return text.length > 96 ? '${text.substring(0, 93)}…' : text;
      }
    }
    return null;
  }
}

/// Internal event that asks the model to summarise an applied proposal. The
/// reply language follows the app language the user picked in Settings.
String appliedProposalEventPrompt(
  AiRoutineProposal proposal, {
  required String languageCode,
}) {
  final language = languageCode == 'pt' ? 'português brasileiro' : 'inglês';
  final confirmed = jsonEncode({
    'action': proposal.action.storageValue,
    'routineName': proposal.routineName,
    'routineId': proposal.appliedRoutineId,
    'diff': proposal.diff,
  });
  return 'EVENTO INTERNO DO APP: a proposta foi aplicada com sucesso. Responda agora, em $language, com um resumo breve e factual do que foi feito. Não use ferramentas e não diga que houve aprovação pendente. Dados confirmados: $confirmed';
}
