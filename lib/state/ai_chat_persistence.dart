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
    final resolvedTitle = title.isEmpty ? 'Nova conversa' : title;
    final preview = firstUserText.length > 96
        ? '${firstUserText.substring(0, 93)}…'
        : firstUserText;
    await _db.upsertAiChatThread(
      id: id,
      title: resolvedTitle,
      createdAt: now,
      updatedAt: now,
      lastMessagePreview: preview,
      isPinned: false,
    );
    // Keep the just-created thread in memory before the first turn is
    // persisted. Otherwise `_persistCurrentThread` cannot resolve it and
    // overwrites its descriptive title with the generic fallback "Conversa".
    _state = _state.copyWith(
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
      await _db.upsertAiChatThread(
        id: id,
        title: _state.activeThread?.title ?? 'Conversa',
        createdAt: _state.activeThread?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        lastMessagePreview: preview,
        isPinned: _state.activeThread?.isPinned ?? false,
      );
      final rows = _state.messages
          .where((m) => m.role != AiMessageRole.system)
          .map((m) => m.toRow()..['thread_id'] = id)
          .toList();
      await _db.replaceAiChatMessages(id, rows);
      await refreshThreads();
    } catch (_) {}
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
        systemPrompt: _settings!.effectiveSystemPrompt,
        contextJson: context,
      );
      wire.add({
        'role': 'user',
        'content':
            'EVENTO INTERNO DO APP: a proposta foi aplicada com sucesso. Responda agora, em português brasileiro, com um resumo breve e factual do que foi feito. Não use ferramentas e não diga que houve aprovação pendente. Dados confirmados: ${jsonEncode({'action': proposal.action.storageValue, 'routineName': proposal.routineName, 'routineId': proposal.appliedRoutineId, 'diff': proposal.diff})}',
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
      await _db.updateAiRoutineProposal(proposal.id, {
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
      await _db.updateAiRoutineProposal(proposal.id, {
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
