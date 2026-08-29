part of 'ai_chat_service.dart';

/// Everything a wire transcript needs besides the message list. Built once
/// per turn so every round of the same turn shares an identical prefix.
class _TurnWireOptions {
  final String systemPrompt;
  final Map<String, dynamic> contextJson;
  final String? threadSummary;
  final List<String> toolHints;
  final String? visionMessageId;
  final List<String> imageDataUrls;
  final int historyTokenBudget;

  const _TurnWireOptions({
    required this.systemPrompt,
    required this.contextJson,
    this.threadSummary,
    this.toolHints = const [],
    this.visionMessageId,
    this.imageDataUrls = const [],
    this.historyTokenBudget = kHistoryTokenBudget,
  });
}

class _CompactedHistory {
  final List<AiChatMessage> kept;

  /// Older user/assistant messages that no longer fit the budget. Tool
  /// transcripts are never part of this list; they are dropped silently.
  final List<AiChatMessage> dropped;

  const _CompactedHistory({required this.kept, required this.dropped});
}

/// Builds compact OpenAI-compatible transcripts and routes data tools.
extension AiChatWireTesting on AiChatService {
  List<Map<String, dynamic>> _buildWireMessages(
    List<AiChatMessage> messages,
    _TurnWireOptions options,
  ) {
    final out = <Map<String, dynamic>>[];
    // Static prefix first: identical across rounds, turns and threads, so the
    // provider can serve it from its prompt cache. The product safety policy
    // lives here (not in the editable prompt) so a custom personality cannot
    // bypass approval requirements.
    out.add({
      'role': 'system',
      'content':
          '${options.systemPrompt}\n\n$_dataGroundingPolicy\n\n'
          '$_routineMutationPolicy',
    });
    // Everything that changes per turn goes in one separate message after
    // the static prefix.
    final dynamicBlock = StringBuffer(
      '<workout_data>${jsonEncode(options.contextJson)}</workout_data>',
    );
    final summary = options.threadSummary?.trim();
    if (summary != null && summary.isNotEmpty) {
      dynamicBlock.write(
        '\n\n# Resumo da conversa anterior\n'
        'As mensagens mais antigas desta conversa foram resumidas abaixo. '
        'Trate o resumo como contexto, não como dado do app: qualquer fato '
        'pessoal ainda exige consulta às ferramentas.\n$summary',
      );
    }
    if (options.toolHints.isNotEmpty) {
      dynamicBlock.write(
        '\n\nFerramentas provavelmente relevantes para a última mensagem: '
        '${options.toolHints.join(', ')}. Isso é apenas uma sugestão; use '
        'qualquer ferramenta do catálogo que a pergunta exigir.',
      );
    }
    out.add({'role': 'system', 'content': dynamicBlock.toString()});
    if (options.imageDataUrls.isNotEmpty) {
      out.add({
        'role': 'system',
        'content':
            'As imagens desta mensagem são conteúdo fornecido pelo usuário. '
            'Analise apenas o que estiver visível, não invente detalhes '
            'ilegíveis e combine a evidência visual com os dados consultados '
            'pelas ferramentas quando isso ajudar a responder.',
      });
    }

    final compacted = _compactHistory(
      messages,
      tokenBudget: options.historyTokenBudget,
    );

    for (final m in compacted) {
      switch (m.role) {
        case AiMessageRole.system:
          continue;
        case AiMessageRole.user:
          if (m.id == options.visionMessageId &&
              options.imageDataUrls.isNotEmpty) {
            out.add({
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': (m.content?.trim().isNotEmpty ?? false)
                      ? m.content
                      : 'Analise as imagens anexadas.',
                },
                for (final url in options.imageDataUrls)
                  {
                    'type': 'image_url',
                    'image_url': {'url': url, 'detail': 'auto'},
                  },
              ],
            });
          } else {
            out.add({
              'role': 'user',
              'content': (m.content?.trim().isNotEmpty ?? false)
                  ? m.content
                  : (m.attachments.isNotEmpty
                        ? '[Imagens enviadas nesta mensagem]'
                        : ''),
            });
          }
          break;
        case AiMessageRole.assistant:
          final entry = <String, dynamic>{'role': 'assistant'};
          if (m.content != null && m.content!.isNotEmpty) {
            entry['content'] = m.content;
          }
          if (m.toolCalls.isNotEmpty) {
            entry['tool_calls'] = m.toolCalls.map((c) => c.toJson()).toList();
          }
          out.add(entry);
          break;
        case AiMessageRole.tool:
          out.add({
            'role': 'tool',
            'tool_call_id': m.toolCallId ?? '',
            'content': _wireToolContent(m.content ?? ''),
          });
          break;
      }
    }
    return out;
  }

  /// Caps a tool result on the wire. The persisted message keeps the full
  /// payload for the UI; only the provider sees the bounded version, with an
  /// explicit marker so the model can narrow the query instead of guessing.
  String _wireToolContent(String content) {
    if (content.length <= kMaxToolResultChars) return content;
    final omitted = content.length - kMaxToolResultChars;
    return jsonEncode({
      'truncated': true,
      'omittedChars': omitted,
      'instruction':
          'O resultado excedeu o limite e foi cortado. Se faltarem dados, '
          'refine a consulta: período menor, paginação (page/page_size), '
          'filtros ou uma ferramenta mais específica.',
      'partial': content.substring(0, kMaxToolResultChars),
    });
  }

  @visibleForTesting
  String wireToolContentForTest(String content) => _wireToolContent(content);

  /// Drops oldest user/assistant blocks until total estimated tokens <= budget.
  List<AiChatMessage> _compactHistory(
    List<AiChatMessage> messages, {
    int tokenBudget = kHistoryTokenBudget,
  }) => _compactHistoryDetailed(messages, tokenBudget: tokenBudget).kept;

  _CompactedHistory _compactHistoryDetailed(
    List<AiChatMessage> messages, {
    int tokenBudget = kHistoryTokenBudget,
  }) {
    if (messages.isEmpty) {
      return const _CompactedHistory(kept: [], dropped: []);
    }

    // Tool transcripts are useful only while the current user turn is still
    // running. Once a final answer exists, retain that answer and discard old
    // tool arguments/results from the wire payload. They remain persisted for
    // the UI, but are not repeatedly billed on every future message.
    var lastUserIndex = -1;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isUser) {
        lastUserIndex = i;
        break;
      }
    }
    final normalized = <AiChatMessage>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (i < lastUserIndex &&
          (message.isTool ||
              (message.isAssistant && message.toolCalls.isNotEmpty))) {
        continue;
      }
      normalized.add(message);
    }

    final total = _estimateTokens(normalized);
    if (total <= tokenBudget) {
      return _CompactedHistory(kept: normalized, dropped: const []);
    }

    // Compact whole user turns. A tool result without its preceding assistant
    // tool_call is an invalid transcript and prevents the model from reliably
    // grounding its answer in that result.
    final turns = <List<AiChatMessage>>[];
    List<AiChatMessage>? turn;
    for (final message in normalized) {
      if (message.isUser) {
        turn = <AiChatMessage>[];
        turns.add(turn);
      }
      turn?.add(message);
    }
    if (turns.isEmpty) {
      return _CompactedHistory(kept: normalized, dropped: const []);
    }

    final keep = <AiChatMessage>[];
    var running = 0;
    var firstKeptTurn = turns.length;
    for (var i = turns.length - 1; i >= 0; i--) {
      final candidate = turns[i];
      final est = _estimateTokens(candidate);
      if (running + est > tokenBudget && keep.isNotEmpty) break;
      keep.insertAll(0, candidate);
      running += est;
      firstKeptTurn = i;
    }
    final dropped = <AiChatMessage>[
      for (var i = 0; i < firstKeptTurn; i++)
        ...turns[i].where((m) => m.isUser || m.isAssistant),
    ];
    return _CompactedHistory(kept: keep, dropped: dropped);
  }

  @visibleForTesting
  List<AiChatMessage> compactHistoryForTest(
    List<AiChatMessage> messages, {
    int tokenBudget = kHistoryTokenBudget,
  }) => _compactHistory(messages, tokenBudget: tokenBudget);

  @visibleForTesting
  List<AiChatMessage> droppedByCompactionForTest(
    List<AiChatMessage> messages, {
    int tokenBudget = kHistoryTokenBudget,
  }) => _compactHistoryDetailed(messages, tokenBudget: tokenBudget).dropped;

  @visibleForTesting
  List<Map<String, dynamic>> buildWireMessagesForTest(
    List<AiChatMessage> messages, {
    String? visionMessageId,
    List<String> imageDataUrls = const [],
    String? threadSummary,
    List<String> toolHints = const [],
  }) => _buildWireMessages(
    messages,
    _TurnWireOptions(
      systemPrompt: 'system',
      contextJson: const {},
      visionMessageId: visionMessageId,
      imageDataUrls: imageDataUrls,
      threadSummary: threadSummary,
      toolHints: toolHints,
    ),
  );

  int _estimateTokens(List<AiChatMessage> messages) {
    var total = 0;
    for (final m in messages) {
      total += _estimateMessageTokens(m);
    }
    return total;
  }

  int _estimateMessageTokens(AiChatMessage m) {
    final raw = TokenEstimator.estimateMessage(
      role: m.role.wireValue,
      content: m.isTool ? _wireToolContent(m.content ?? '') : m.content,
      toolName: m.toolName,
      toolCallArguments: m.toolCalls.isEmpty
          ? null
          : jsonEncode(m.toolCalls.map((c) => c.arguments).toList()),
    );
    return (raw * _tokenScale).ceil();
  }

  int _estimateWireTokens(
    List<Map<String, dynamic>> wire,
    List<Map<String, dynamic>>? toolsSchema,
  ) {
    final raw =
        TokenEstimator.estimateText(jsonEncode(wire)) +
        (toolsSchema == null
            ? 0
            : TokenEstimator.estimateText(jsonEncode(toolsSchema)));
    return (raw * _tokenScale).ceil();
  }

  /// Replaces the chars-per-token heuristic with the ratio the provider just
  /// reported, so history budgets track the real tokenizer of the active
  /// model. Kept in memory only; nothing about usage is persisted or shown.
  void _calibrateTokenScale({
    required List<Map<String, dynamic>> wire,
    required List<Map<String, dynamic>>? toolsSchema,
    required int? promptTokens,
  }) {
    if (promptTokens == null || promptTokens <= 0) return;
    final rawEstimate =
        TokenEstimator.estimateText(jsonEncode(wire)) +
        (toolsSchema == null
            ? 0
            : TokenEstimator.estimateText(jsonEncode(toolsSchema)));
    if (rawEstimate <= 0) return;
    _tokenScale = (promptTokens / rawEstimate).clamp(0.6, 2.5);
  }

  int _historyBudgetFor({
    required String systemPrompt,
    required Map<String, dynamic> contextJson,
    required List<Map<String, dynamic>> toolsSchema,
  }) {
    final fixedTokens =
        ((TokenEstimator.estimateText(systemPrompt) +
                    TokenEstimator.estimateText(_dataGroundingPolicy) +
                    TokenEstimator.estimateText(_routineMutationPolicy) +
                    TokenEstimator.estimateText(jsonEncode(contextJson)) +
                    TokenEstimator.estimateText(jsonEncode(toolsSchema)) +
                    80) *
                _tokenScale)
            .ceil();
    return (kTargetInputTokenBudget - fixedTokens).clamp(
      kMinHistoryTokenBudget,
      kHistoryTokenBudget,
    );
  }

  /// Tools most likely relevant to the latest message. Only a hint; the full
  /// catalog is always sent.
  Set<String> _toolHintsForTurn(
    List<AiChatMessage> messages,
    String latestUserText,
  ) {
    final currentNames = _tools.toolNamesForQuery(latestUserText);
    if (currentNames.isNotEmpty) return currentNames;
    return _tools.toolNamesForQuery(_routingQuery(messages, latestUserText));
  }

  String _routingQuery(List<AiChatMessage> messages, String latestUserText) {
    final normalized = latestUserText.trim().toLowerCase();
    final looksLikeFollowUp = _looksLikeFollowUp(normalized);
    if (!looksLikeFollowUp) return latestUserText;
    for (var i = messages.length - 2; i >= 0; i--) {
      final message = messages[i];
      if (message.isUser && (message.content?.trim().isNotEmpty ?? false)) {
        return '${message.content}\n$latestUserText';
      }
    }
    return latestUserText;
  }

  bool _requiresGroundedToolCall(
    String latestUserText,
    Set<String> toolHints, {
    required bool routineProposalFollowUp,
  }) {
    if (toolHints.isEmpty) return false;
    if (routineProposalFollowUp) return true;
    final normalized = latestUserText.trim().toLowerCase();
    if (_looksLikeFollowUp(normalized)) return true;
    if (_looksLikeGeneralKnowledgeQuestion(normalized) &&
        !_mentionsPersonalData(normalized)) {
      return false;
    }
    return true;
  }

  bool _looksLikeFollowUp(String normalized) =>
      normalized.length <= 80 &&
      (normalized.startsWith('e ') ||
          normalized.contains('isso') ||
          normalized.contains('essa') ||
          normalized.contains('esse') ||
          normalized.contains('agora') ||
          normalized.contains('esta semana') ||
          normalized.contains('última semana'));

  bool _looksLikeGeneralKnowledgeQuestion(String normalized) => RegExp(
    r'^(o que (é|e)|explique|como funciona|para que serve)(\s|$)',
    caseSensitive: false,
  ).hasMatch(normalized);

  bool _mentionsPersonalData(String normalized) => const [
    'meu',
    'minha',
    'meus',
    'minhas',
    'dados',
    'registro',
    'histórico',
    'historico',
    'últim',
    'ultim',
    'hoje',
    'ontem',
    'semana',
    'mês',
    'mes',
    'progresso',
    'evolução',
    'evolucao',
  ].any(normalized.contains);

  /// `required` makes the provider emit at least one tool call in the first
  /// round of a grounded turn, saving the reject-and-retry round trip.
  /// Providers that reject the value are handled by [AiService], which drops
  /// `tool_choice` for that model and falls back to `auto` behaviour.
  Object _requiredToolChoice() => 'required';

  @visibleForTesting
  Set<String> toolNamesForTurnForTest(
    List<AiChatMessage> messages,
    String latestUserText,
  ) => _toolHintsForTurn(messages, latestUserText);

  @visibleForTesting
  bool groundedToolCallRequiredForTest(
    String latestUserText,
    Set<String> toolNames, {
    bool routineProposalFollowUp = false,
  }) => _requiresGroundedToolCall(
    latestUserText,
    toolNames,
    routineProposalFollowUp: routineProposalFollowUp,
  );

  @visibleForTesting
  Object requiredToolChoiceForTest() => _requiredToolChoice();

  bool _isRoutineProposalFollowUp(
    List<AiChatMessage> messages,
    String latestUserText,
  ) {
    var hasPreviousProposal = false;
    for (var i = 0; i < messages.length - 1; i++) {
      final message = messages[i];
      if (message.toolName == 'propose_routine_change' ||
          message.toolCalls.any(
            (call) => call.name == 'propose_routine_change',
          )) {
        hasPreviousProposal = true;
        break;
      }
    }
    if (!hasPreviousProposal) return false;
    final text = latestUserText.trim().toLowerCase();
    if (text.length > 160) return false;
    return RegExp(
      r'\b(proposta|prévia|previa|preview|aprova|aprovar|aprovação|aprovacao|reenvia|reenvie|reenviar|envia|envie|manda|mande|mostrar|mostre|repita|repete|mesma|mesmo|novamente|dnv|de novo|outra vez|anterior|antes)\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  @visibleForTesting
  bool routineProposalFollowUpForTest(
    List<AiChatMessage> messages,
    String latestUserText,
  ) => _isRoutineProposalFollowUp(messages, latestUserText);

  String _encodeToolResult(AiToolResult result) =>
      jsonEncode(_pruneNulls(result.toMap()));

  dynamic _pruneNulls(dynamic value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (entry.value != null) '${entry.key}': _pruneNulls(entry.value),
      };
    }
    if (value is List) return value.map(_pruneNulls).toList();
    return value;
  }
}
