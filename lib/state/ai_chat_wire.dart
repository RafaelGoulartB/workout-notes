part of 'ai_chat_service.dart';

/// Builds compact OpenAI-compatible transcripts and routes data tools.
extension AiChatWireTesting on AiChatService {
  List<Map<String, dynamic>> _buildWireMessages(
    List<AiChatMessage> messages, {
    required String systemPrompt,
    required Map<String, dynamic> contextJson,
    bool includeRoutinePolicy = false,
    String? visionMessageId,
    List<String> imageDataUrls = const [],
    int historyTokenBudget = kHistoryTokenBudget,
  }) {
    final out = <Map<String, dynamic>>[];
    out.add({
      'role': 'system',
      'content':
          '$systemPrompt\n\n$_dataGroundingPolicy\n\n'
          '<workout_data>${jsonEncode(contextJson)}</workout_data>',
    });
    // This product safety policy is intentionally separate from the editable
    // prompt so a custom personality cannot bypass approval requirements.
    if (includeRoutinePolicy) {
      out.add({'role': 'system', 'content': _routineMutationPolicy});
    }
    if (imageDataUrls.isNotEmpty) {
      out.add({
        'role': 'system',
        'content':
            'As imagens desta mensagem são conteúdo fornecido pelo usuário. '
            'Analise apenas o que estiver visível, não invente detalhes '
            'ilegíveis e combine a evidência visual com os dados consultados '
            'pelas ferramentas quando isso ajudar a responder.',
      });
    }

    // Compact history if too long.
    final compacted = _compactHistory(
      messages,
      tokenBudget: historyTokenBudget,
    );

    for (final m in compacted) {
      switch (m.role) {
        case AiMessageRole.system:
          continue;
        case AiMessageRole.user:
          if (m.id == visionMessageId && imageDataUrls.isNotEmpty) {
            out.add({
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': (m.content?.trim().isNotEmpty ?? false)
                      ? m.content
                      : 'Analise as imagens anexadas.',
                },
                for (final url in imageDataUrls)
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
            'content': m.content ?? '',
          });
          break;
      }
    }
    return out;
  }

  /// Drops oldest user/assistant blocks until total estimated tokens <= budget.
  List<AiChatMessage> _compactHistory(
    List<AiChatMessage> messages, {
    int tokenBudget = kHistoryTokenBudget,
  }) {
    if (messages.isEmpty) return messages;

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
    if (total <= tokenBudget) return normalized;

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
    if (turns.isEmpty) return normalized;

    final keep = <AiChatMessage>[];
    var running = 0;
    for (var i = turns.length - 1; i >= 0; i--) {
      final candidate = turns[i];
      final est = _estimateTokens(candidate);
      if (running + est > tokenBudget && keep.isNotEmpty) break;
      keep.insertAll(0, candidate);
      running += est;
    }
    return keep;
  }

  @visibleForTesting
  List<AiChatMessage> compactHistoryForTest(List<AiChatMessage> messages) =>
      _compactHistory(messages);

  @visibleForTesting
  List<Map<String, dynamic>> buildWireMessagesForTest(
    List<AiChatMessage> messages, {
    bool includeRoutinePolicy = false,
    String? visionMessageId,
    List<String> imageDataUrls = const [],
  }) => _buildWireMessages(
    messages,
    systemPrompt: 'system',
    contextJson: const {},
    includeRoutinePolicy: includeRoutinePolicy,
    visionMessageId: visionMessageId,
    imageDataUrls: imageDataUrls,
  );

  int _estimateTokens(List<AiChatMessage> messages) {
    var total = 0;
    for (final m in messages) {
      total += _estimateMessageTokens(m);
    }
    return total;
  }

  int _estimateMessageTokens(AiChatMessage m) {
    return TokenEstimator.estimateMessage(
      role: m.role.wireValue,
      content: m.content,
      toolName: m.toolName,
      toolCallArguments: m.toolCalls.isEmpty
          ? null
          : jsonEncode(m.toolCalls.map((c) => c.arguments).toList()),
    );
  }

  int _historyBudgetFor({
    required String systemPrompt,
    required Map<String, dynamic> contextJson,
    required List<Map<String, dynamic>> toolsSchema,
    required bool includeRoutinePolicy,
  }) {
    final fixedTokens =
        TokenEstimator.estimateText(systemPrompt) +
        TokenEstimator.estimateText(_dataGroundingPolicy) +
        (includeRoutinePolicy
            ? TokenEstimator.estimateText(_routineMutationPolicy)
            : 0) +
        TokenEstimator.estimateText(jsonEncode(contextJson)) +
        TokenEstimator.estimateText(jsonEncode(toolsSchema)) +
        80;
    return (kTargetInputTokenBudget - fixedTokens).clamp(
      kMinHistoryTokenBudget,
      kHistoryTokenBudget,
    );
  }

  Set<String> _toolNamesForTurn(
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
    Set<String> toolNames, {
    required bool routineProposalFollowUp,
  }) {
    if (toolNames.isEmpty) return false;
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

  Object _requiredToolChoice(Set<String> toolNames) {
    if (toolNames.length == 1) {
      return {
        'type': 'function',
        'function': {'name': toolNames.single},
      };
    }
    return 'required';
  }

  @visibleForTesting
  Set<String> toolNamesForTurnForTest(
    List<AiChatMessage> messages,
    String latestUserText,
  ) => _toolNamesForTurn(messages, latestUserText);

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
  Object requiredToolChoiceForTest(Set<String> toolNames) =>
      _requiredToolChoice(toolNames);

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
