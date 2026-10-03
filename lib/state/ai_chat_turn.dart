part of 'ai_chat_service.dart';

/// The agent loop: one provider round after another until the model answers
/// without tool calls. Tools stay available while the request fits the turn
/// budget; the last round keeps the same tools with `tool_choice: none`, so
/// the request prefix stays cacheable and providers that require `tools`
/// next to tool messages are satisfied.
extension AiChatTurn on AiChatService {
  Future<void> _runTurn(_TurnContext ctx) async {
    final setup = ctx.setup;
    var status = AiTurnStatus.done;
    try {
      final imageDataUrls = ctx.userMessage.attachments.isEmpty
          ? const <String>[]
          : await _imageStore.readDataUrls(ctx.userMessage.attachments);
      final tools = _toolSchema(setup.domains);
      final snapshot = await _context.buildSnapshot(domains: setup.domains);
      final memoryBlock = await _memory.contextBlock();
      var history = await _loadHistory(ctx.threadId, ctx.userMessage);
      history = await _compactIfNeeded(
        ctx,
        history,
        fixedChars:
            setup.systemPrompt.length + tools.chars + memoryBlock.length,
      );

      final extra = <Map<String, dynamic>>[];
      var forceFinal = false;
      var placeholderRetried = false;
      var emptyRetried = false;
      var contextRetried = false;
      int? lastPromptTokens;

      while (true) {
        if (ctx.cancelled) throw const _TurnCancelled();
        ctx.round++;
        final wire = _buildWire(
          setup: setup,
          history: history,
          currentUser: ctx.userMessage,
          turnMessages: ctx.messages,
          snapshot: snapshot,
          memoryBlock: memoryBlock,
          imageDataUrls: imageDataUrls,
          extra: extra,
        );
        final wireChars = jsonEncode(wire).length;
        ctx.lastRequestChars = wireChars + tools.chars;
        final estimate = _estimateChars(wireChars + tools.chars);
        final finalRound =
            forceFinal ||
            ctx.round > kMaxToolRounds ||
            estimate > kMaxTurnInputTokens ||
            (lastPromptTokens ?? 0) > kMaxTurnInputTokens;
        final toolChoiceSupported = _service.supportsToolChoice(
          setup.provider.baseUrl,
          setup.provider.selectedModel,
        );
        _updateTurn(
          ctx,
          (t) => t.copyWith(
            phase: AiTurnPhase.waiting,
            round: ctx.round,
            draftText: '',
            toolNames: const [],
          ),
        );

        final watch = Stopwatch()..start();
        AiChatCompletion completion;
        try {
          completion = await _request(
            ctx,
            wire: wire,
            tools: finalRound && !toolChoiceSupported ? null : tools.schema,
            toolChoice: finalRound ? 'none' : null,
            hasImages: imageDataUrls.isNotEmpty,
          );
        } on AiServiceException catch (error) {
          if (error.code == 'cancelled' || ctx.cancelled) {
            throw const _TurnCancelled();
          }
          // Too long for this model: fold more history away once and retry.
          if (error.code == 'context_length_exceeded' && !contextRetried) {
            contextRetried = true;
            history = await _compactIfNeeded(
              ctx,
              history,
              fixedChars:
                  setup.systemPrompt.length + tools.chars + memoryBlock.length,
              force: true,
            );
            ctx.round--;
            continue;
          }
          rethrow;
        }
        watch.stop();
        _calibrateTokenScale(
          requestChars: wireChars + tools.chars,
          promptTokens: completion.promptTokens,
        );
        lastPromptTokens = completion.promptTokens;
        ctx.diagnostics.add(
          AiRoundDiagnostics(
            round: ctx.round,
            requestChars: wireChars + tools.chars,
            promptTokens: completion.promptTokens,
            cachedTokens: completion.cachedTokens,
            completionTokens: completion.completionTokens,
            durationMs: watch.elapsedMilliseconds,
            toolCalls: [for (final c in completion.toolCalls) c.name],
            streamed: true,
          ),
        );
        if (ctx.cancelled) throw const _TurnCancelled();

        // A provider that ignored tool_choice:none on the final round: keep
        // whatever text it wrote, never run more tools.
        final calls = finalRound ? const <AiToolCall>[] : completion.toolCalls;
        if (calls.isEmpty) {
          final text = completion.text?.trim();
          if (text == null || text.isEmpty) {
            if (!emptyRetried) {
              emptyRetried = true;
              forceFinal = true;
              extra.add({
                'role': 'user',
                'content':
                    '<app_event>{"type":"empty_answer"}</app_event> '
                    'Answer the user now with what you already have.',
              });
              continue;
            }
            throw const AiServiceException(
              'The model returned an empty answer.',
              code: 'empty_answer',
            );
          }
          if (TextSanitizer.containsReferencePlaceholder(text) &&
              !placeholderRetried) {
            placeholderRetried = true;
            forceFinal = true;
            extra
              ..add({'role': 'assistant', 'content': text})
              ..add({'role': 'user', 'content': AiPrompts.placeholderRewrite});
            continue;
          }
          final answer = AiChatMessage(
            id: _uuid.v4(),
            threadId: ctx.threadId,
            role: AiMessageRole.assistant,
            content: TextSanitizer.sanitize(text).trim(),
            createdAt: _nextTimestamp(),
            providerExtras: completion.providerExtras,
          );
          await _commitStep(ctx, [answer]);
          break;
        }

        await _runToolStep(ctx, completion, calls);
      }
    } on _TurnCancelled {
      status = AiTurnStatus.cancelled;
    } on AiServiceException catch (error) {
      if (error.code == 'cancelled' || ctx.cancelled) {
        status = AiTurnStatus.cancelled;
      } else {
        status = AiTurnStatus.failed;
        _failTurn(ctx, error);
      }
    } catch (error, stackTrace) {
      debugPrint('AI turn failed: $error\n$stackTrace');
      status = ctx.cancelled ? AiTurnStatus.cancelled : AiTurnStatus.failed;
      if (status == AiTurnStatus.failed) _failTurn(ctx, error);
    } finally {
      await _finishTurn(ctx, status);
    }
  }

  /// Sends one round, streaming the answer into the live turn progress.
  Future<AiChatCompletion> _request(
    _TurnContext ctx, {
    required List<Map<String, dynamic>> wire,
    required List<Map<String, dynamic>>? tools,
    required Object? toolChoice,
    required bool hasImages,
  }) {
    final provider = ctx.setup.provider;
    void onDelta(AiStreamDelta delta) {
      if (ctx.cancelled) return;
      _updateTurn(
        ctx,
        (t) => t.copyWith(
          phase: delta.toolNames.isNotEmpty
              ? AiTurnPhase.usingTools
              : delta.text.isNotEmpty
              ? AiTurnPhase.writing
              : delta.reasoning
              ? AiTurnPhase.thinking
              : AiTurnPhase.waiting,
          draftText: delta.text,
          toolNames: delta.toolNames,
        ),
      );
    }

    if (hasImages) {
      return _service.sendMultimodalChat(
        baseUrl: provider.baseUrl,
        token: ctx.setup.token,
        model: provider.selectedModel,
        reasoningEffort: ctx.setup.reasoningEffort,
        apiStyle: provider.apiStyle,
        messages: wire,
        tools: tools,
        toolChoice: toolChoice,
        stream: true,
        onDelta: onDelta,
        abortTrigger: ctx.abortTrigger,
        cacheKey: ctx.threadId,
      );
    }
    return _service.sendChat(
      baseUrl: provider.baseUrl,
      token: ctx.setup.token,
      model: provider.selectedModel,
      reasoningEffort: ctx.setup.reasoningEffort,
      apiStyle: provider.apiStyle,
      messages: wire,
      tools: tools,
      toolChoice: toolChoice,
      stream: true,
      onDelta: onDelta,
      abortTrigger: ctx.abortTrigger,
      cacheKey: ctx.threadId,
    );
  }

  /// Runs one assistant step's tool calls: reads in parallel, then proposals
  /// and memory changes in call order. The assistant message and all its
  /// results are committed together, so the stored transcript never holds a
  /// tool call without its result.
  Future<void> _runToolStep(
    _TurnContext ctx,
    AiChatCompletion completion,
    List<AiToolCall> providerCalls,
  ) async {
    final calls = await _uniqueCallIds(ctx, providerCalls);
    final assistant = AiChatMessage(
      id: _uuid.v4(),
      threadId: ctx.threadId,
      role: AiMessageRole.assistant,
      content: completion.text == null
          ? null
          : TextSanitizer.sanitize(completion.text!).trim(),
      toolCalls: calls,
      createdAt: _nextTimestamp(),
      providerExtras: completion.providerExtras,
    );
    _updateTurn(
      ctx,
      (t) => t.copyWith(
        phase: AiTurnPhase.usingTools,
        toolNames: [for (final c in calls) c.name],
        draftText: '',
      ),
    );

    // Identical calls in the same turn (same tool, same arguments) reuse the
    // earlier result instead of querying again.
    final previous = <String, AiChatMessage>{};
    for (final m in ctx.messages) {
      if (!m.isAssistant) continue;
      for (final call in m.toolCalls) {
        final result = ctx.messages.where(
          (r) => r.isTool && r.toolCallId == call.id,
        );
        if (result.isNotEmpty) previous[_callKey(call)] = result.first;
      }
    }

    final results = List<AiToolResult?>.filled(calls.length, null);
    // Only tools of the catalog this turn was offered may run: a domain the
    // user switched off stays closed even if the model calls its tool by
    // name (from an older turn, a summary or a guess).
    final allowed = _allowedToolNames(ctx.setup.domains);
    for (var i = 0; i < calls.length; i++) {
      if (!allowed.contains(calls[i].name)) {
        results[i] = AiToolResult(
          ok: false,
          code: 'tool_not_available',
          message: 'Tool "${calls[i].name}" is not available.',
          hint:
              'The user switched off access to this data or the tool does '
              'not exist. Use only the tools you were given; tell the user '
              'if the answer needs data you cannot read.',
        );
      }
    }
    await Future.wait([
      for (var i = 0; i < calls.length; i++)
        if (results[i] == null && !_isSequentialTool(calls[i].name))
          () async {
            final call = calls[i];
            if (call.argumentsError != null) {
              results[i] = AiToolResult(
                ok: false,
                code: 'invalid_arguments_json',
                message: '${call.argumentsError}',
                hint: 'Send the call again with a valid JSON object.',
              );
              return;
            }
            final cached = previous[_callKey(call)];
            if (cached != null) {
              final decoded = AiChatService._decodeToolContent(cached.content);
              if (decoded != null) {
                results[i] = AiToolResult.fromMap(decoded);
                return;
              }
            }
            results[i] = await _tools.executeRead(
              toolName: call.name,
              args: call.arguments,
            );
          }(),
    ]);
    for (var i = 0; i < calls.length; i++) {
      final call = calls[i];
      if (results[i] != null) continue;
      if (call.argumentsError != null) {
        results[i] = AiToolResult(
          ok: false,
          code: 'invalid_arguments_json',
          message: '${call.argumentsError}',
          hint: 'Send the call again with a valid JSON object.',
        );
      } else if (_proposals.handles(call.name)) {
        results[i] = await _proposals.prepare(
          threadId: ctx.threadId,
          toolCallId: call.id,
          toolName: call.name,
          args: call.arguments,
        );
      } else if (_memory.handles(call.name)) {
        results[i] = await _memory.execute(
          toolName: call.name,
          args: call.arguments,
          threadId: ctx.threadId,
        );
      }
    }

    final toolMessages = [
      for (var i = 0; i < calls.length; i++)
        AiChatMessage(
          id: _uuid.v4(),
          threadId: ctx.threadId,
          role: AiMessageRole.tool,
          content: jsonEncode(results[i]!.toMap()),
          toolCallId: calls[i].id,
          toolName: calls[i].name,
          toolResult: results[i],
          createdAt: _nextTimestamp(),
        ),
    ];
    await _commitStep(ctx, [assistant, ...toolMessages]);

    // New proposal cards appear as soon as they are prepared.
    for (var i = 0; i < calls.length; i++) {
      final data = results[i]!.data;
      if (results[i]!.ok && data is Map && data['proposal_id'] is String) {
        final proposal = await _proposals.get(data['proposal_id'] as String);
        if (proposal != null) _replaceProposal(proposal);
      }
    }
  }

  /// Tool-call ids must be unique in a conversation: results, proposals and
  /// cards are paired by id. Some servers reuse ids (`call_0` every round);
  /// a repeated or empty id is renamed, consistently on the assistant message
  /// and its result.
  Future<List<AiToolCall>> _uniqueCallIds(
    _TurnContext ctx,
    List<AiToolCall> calls,
  ) async {
    final seen = <String>{
      for (final m in ctx.messages) ...[for (final c in m.toolCalls) c.id],
    };
    final out = <AiToolCall>[];
    for (final call in calls) {
      var id = call.id;
      if (id.isEmpty ||
          seen.contains(id) ||
          await _db.aiChatRepo.toolCallIdExists(ctx.threadId, id)) {
        id = 'call_${_uuid.v4().replaceAll('-', '').substring(0, 20)}';
      }
      seen.add(id);
      out.add(id == call.id ? call : call.withId(id));
    }
    return out;
  }

  bool _isSequentialTool(String name) =>
      _proposals.handles(name) || _memory.handles(name);

  static String _callKey(AiToolCall call) =>
      '${call.name}:${jsonEncode(AiChatService._sortedArgs(call.arguments))}';

  /// Appends [messages] to the turn, persists them in the turn's thread and
  /// shows them when that thread is on screen.
  Future<void> _commitStep(
    _TurnContext ctx,
    List<AiChatMessage> messages,
  ) async {
    ctx.messages.addAll(messages);
    await _persistMessages(ctx.threadId, messages);
    if (_state.activeThreadId == ctx.threadId) {
      final known = {for (final m in _state.messages) m.id};
      _state = _state.copyWith(
        messages: [
          ..._state.messages,
          for (final m in messages)
            if (!known.contains(m.id)) m,
        ],
      );
      _emit();
    }
  }

  void _updateTurn(
    _TurnContext ctx,
    AiTurnProgress Function(AiTurnProgress) update,
  ) {
    final turn = _state.turn;
    if (turn == null || turn.userMessageId != ctx.userMessage.id) return;
    _state = _state.copyWith(turn: update(turn));
    _emit();
  }

  void _failTurn(_TurnContext ctx, Object error) {
    if (_state.activeThreadId != ctx.threadId) return;
    _state = _state.copyWith(
      error: _readableError(error),
      errorDetails: _technicalErrorDetails(
        error,
        stage: 'round_${ctx.round}',
        ctx: ctx,
      ),
      errorAction: AiErrorAction.retryTurn,
    );
  }

  Future<void> _finishTurn(_TurnContext ctx, AiTurnStatus status) async {
    final finished = ctx.userMessage.copyWith(turnStatus: status);
    try {
      await _persistMessages(ctx.threadId, [finished]);
      await _touchThread(ctx.threadId);
    } catch (error) {
      debugPrint('Finishing the AI turn failed: $error');
    }
    if (identical(_turn, ctx)) _turn = null;
    _replaceMessageInState(finished, notify: false);
    _state = _state.copyWith(
      clearTurn: true,
      lastTurnDiagnostics: List.unmodifiable(ctx.diagnostics),
    );
    _emit();
    if (status == AiTurnStatus.done) {
      unawaited(_maybeGenerateTitle(ctx));
    }
  }

  // ===========================================================================
  // HISTORY AND COMPACTION
  // ===========================================================================

  /// Everything after the summary cut (from SQLite, the source of truth),
  /// minus the current user message and anything after it.
  Future<_History> _loadHistory(String threadId, AiChatMessage current) async {
    final summaryRow = await _db.aiChatRepo.getAiChatThreadSummary(threadId);
    String? cutCreatedAt;
    final cutId = summaryRow?['through_message_id'] as String?;
    if (cutId != null && cutId.isNotEmpty) {
      final cutRow = await _db.aiChatRepo.getAiChatMessage(cutId);
      cutCreatedAt = cutRow?['created_at'] as String?;
    }
    final rows = await _db.aiChatRepo.getAiChatMessagesAfter(
      threadId,
      afterCreatedAt: cutCreatedAt,
      afterId: cutCreatedAt == null ? null : cutId,
    );
    final messages = <AiChatMessage>[];
    for (final row in rows) {
      final message = AiChatMessage.fromRow(row);
      if (message.id == current.id) break;
      messages.add(message);
    }
    return _History(
      messages: messages,
      summary: cutCreatedAt == null ? null : summaryRow?['summary'] as String?,
      cutMessageId: cutCreatedAt == null ? null : cutId,
      toolsThroughMessageId: summaryRow?['tools_through_message_id'] as String?,
    );
  }

  /// Folds old turns into the summary when the history passes the high-water
  /// mark (or when [force]d after a context-length error), keeping the newest
  /// turns that fit under the low-water mark. Tool results of all but the
  /// last two kept turns become stubs at the same moment.
  Future<_History> _compactIfNeeded(
    _TurnContext ctx,
    _History history, {
    required int fixedChars,
    bool force = false,
  }) async {
    if (history.messages.isEmpty) return history;
    final fixedTokens = _estimateChars(fixedChars + 2000);
    var budget = (kTargetInputTokens - fixedTokens).clamp(
      kMinHistoryTokens,
      kMaxHistoryTokens,
    );
    if (force) budget = (budget * 0.5).round();
    final turns = _groupTurns(history.messages);
    int turnTokens(List<AiChatMessage> turn, {required bool stub}) {
      var chars = 0;
      for (final m in turn) {
        chars += jsonEncode(
          _wireMessage(m, stub: stub, currentTurn: false, responses: false),
        ).length;
      }
      return _estimateChars(chars);
    }

    var total = 0;
    var stubbing =
        history.toolsThroughMessageId != null &&
        history.messages.any((m) => m.id == history.toolsThroughMessageId);
    for (final turn in turns) {
      total += turnTokens(turn, stub: stubbing);
      if (stubbing && turn.any((m) => m.id == history.toolsThroughMessageId)) {
        stubbing = false;
      }
    }
    if (!force && total <= budget * kCompactHighWater) return history;

    // Keep the newest turns that fit under the low-water mark.
    final keepBudget = budget * kCompactLowWater;
    var kept = 0;
    var running = 0;
    for (var i = turns.length - 1; i >= 0; i--) {
      final cost = turnTokens(turns[i], stub: turns.length - i > 2);
      if (running + cost > keepBudget && kept > 0) break;
      running += cost;
      kept++;
    }
    if (force && kept == turns.length && turns.length > 1) kept--;
    final dropped = [
      for (final turn in turns.take(turns.length - kept)) ...turn,
    ];
    final keptTurns = turns.skip(turns.length - kept).toList();
    if (dropped.isEmpty && keptTurns.length < 3) return history;

    _updateTurn(ctx, (t) => t.copyWith(phase: AiTurnPhase.compacting));
    var summary = history.summary;
    if (dropped.isNotEmpty) {
      summary = await _summarize(ctx, history.summary, dropped);
    }
    final cutId = dropped.isNotEmpty ? dropped.last.id : history.cutMessageId;
    final toolsThrough = keptTurns.length >= 3
        ? keptTurns[keptTurns.length - 3].last.id
        : null;
    // Saved even when nothing was folded away (only the tool results were
    // stubbed): the boundary must be the same on the next turns or the
    // history prefix changes and the provider cache misses. An empty cut
    // means "no summary cut yet".
    if (cutId != null || toolsThrough != null) {
      await _db.aiChatRepo.upsertAiChatThreadSummary(
        threadId: ctx.threadId,
        summary: summary ?? '',
        throughMessageId: cutId ?? '',
        toolsThroughMessageId: toolsThrough,
      );
      // Payloads before the cut are never sent again: stop storing them.
      if (dropped.isNotEmpty) {
        await _db.aiChatRepo.archiveToolPayloads(
          ctx.threadId,
          throughCreatedAt: dropped.last.createdAt.toIso8601String(),
          archivedContent: '{"ok":true,"archived":true}',
        );
      }
    }
    return _History(
      messages: [for (final turn in keptTurns) ...turn],
      summary: summary,
      cutMessageId: cutId,
      toolsThroughMessageId: toolsThrough,
    );
  }

  /// Splits messages into turns (a user message and everything after it).
  /// Anything before the first user message joins the first turn.
  List<List<AiChatMessage>> _groupTurns(List<AiChatMessage> messages) {
    final turns = <List<AiChatMessage>>[];
    for (final message in messages) {
      if (message.isUser || turns.isEmpty) {
        turns.add([message]);
      } else {
        turns.last.add(message);
      }
    }
    return turns;
  }

  /// One summary call (utility model when configured). On failure the old
  /// summary is kept with a note, so the turn still goes on.
  Future<String?> _summarize(
    _TurnContext ctx,
    String? existing,
    List<AiChatMessage> delta,
  ) async {
    final provider = ctx.setup.provider;
    final model = provider.utilityModel.isNotEmpty
        ? provider.utilityModel
        : provider.selectedModel;
    final request = StringBuffer();
    if (existing != null && existing.trim().isNotEmpty) {
      request.write('Current summary:\n$existing\n\n');
    }
    request.write('New messages to fold in:\n${_transcriptForSummary(delta)}');
    try {
      final completion = await _service.sendChat(
        baseUrl: provider.baseUrl,
        token: ctx.setup.token,
        model: model,
        reasoningEffort: provider.utilityModel.isNotEmpty
            ? null
            : ctx.setup.reasoningEffort,
        apiStyle: provider.apiStyle,
        abortTrigger: ctx.abortTrigger,
        messages: [
          {
            'role': 'system',
            'content': AiPrompts.threadSummary(ctx.setup.languageCode),
          },
          {'role': 'user', 'content': request.toString()},
        ],
      );
      final text = TextSanitizer.sanitize(completion.text ?? '').trim();
      if (text.isNotEmpty) return text;
    } on AiServiceException catch (error) {
      if (error.code == 'cancelled') rethrow;
      debugPrint('AI thread summary failed: $error');
    }
    final note = ctx.setup.languageCode == 'pt'
        ? '(Algumas mensagens antigas não puderam ser resumidas.)'
        : '(Some older messages could not be summarized.)';
    return [
      if (existing != null && existing.trim().isNotEmpty) existing,
      note,
    ].join('\n');
  }

  String _transcriptForSummary(List<AiChatMessage> messages) {
    const perMessage = 1500;
    const total = 24000;
    final buffer = StringBuffer();
    for (final message in messages) {
      if (!message.isUser && !message.isAssistant && !message.isEvent) {
        continue;
      }
      final content = message.content?.trim();
      if (content == null || content.isEmpty) continue;
      final compact = content.length <= perMessage
          ? content
          : '${content.substring(0, perMessage)}…';
      final who = message.isUser
          ? 'User'
          : message.isEvent
          ? 'App event'
          : 'Coach';
      final line = '$who: $compact\n';
      if (buffer.length + line.length > total) {
        buffer.write('[remaining messages omitted for length]\n');
        break;
      }
      buffer.write(line);
    }
    return buffer.toString();
  }

  /// A short descriptive title for a new conversation, made by the utility
  /// model when one is configured. Best effort.
  Future<void> _maybeGenerateTitle(_TurnContext ctx) async {
    final provider = ctx.setup.provider;
    if (provider.utilityModel.isEmpty) return;
    final text = ctx.userMessage.content?.trim() ?? '';
    if (text.isEmpty) return;
    // Only the first exchange, and never over a title the user typed.
    final row = await _db.aiChatRepo.getAiChatThread(ctx.threadId);
    if (row == null ||
        AiChatThread.fromRow(row).title !=
            _AiChatPersistence._autoTitle(text)) {
      return;
    }
    try {
      final completion = await _service.sendChat(
        baseUrl: provider.baseUrl,
        token: ctx.setup.token,
        model: provider.utilityModel,
        apiStyle: provider.apiStyle,
        maxOutputTokens: 40,
        messages: [
          {
            'role': 'system',
            'content': AiPrompts.threadTitle(ctx.setup.languageCode),
          },
          {'role': 'user', 'content': text},
        ],
      );
      var title = TextSanitizer.sanitize(
        completion.text ?? '',
      ).trim().replaceAll(RegExp(r'''^["'“”]+|["'“”.]+$'''), '');
      if (title.isEmpty) return;
      if (title.length > 60) title = '${title.substring(0, 57)}…';
      await renameThread(ctx.threadId, title);
    } catch (error) {
      debugPrint('AI thread title failed: $error');
    }
  }

  @visibleForTesting
  String transcriptForSummaryForTest(List<AiChatMessage> messages) =>
      _transcriptForSummary(messages);
}

/// Thrown inside the loop when the user stopped the turn.
class _TurnCancelled implements Exception {
  const _TurnCancelled();
}
