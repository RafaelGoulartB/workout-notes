part of 'ai_chat_service.dart';

/// The part of a conversation a turn sends: the rolling summary of what was
/// folded away and every message after the summary cut.
class _History {
  final String? summary;

  /// Last message covered by [summary] (null: nothing summarized yet).
  final String? cutMessageId;

  /// Tool results up to this message are sent as short stubs.
  final String? toolsThroughMessageId;

  /// Messages after the cut, oldest first, without the current user message.
  final List<AiChatMessage> messages;

  const _History({
    required this.messages,
    this.summary,
    this.cutMessageId,
    this.toolsThroughMessageId,
  });
}

/// Builds OpenAI-compatible transcripts.
///
/// Layout, from most to least stable — each block only changes when
/// something it contains changes, so a provider's prefix cache covers almost
/// the whole request on every turn:
///
/// 1. `system`: product prompt + language/style + custom instructions,
///    then `<memory>` and `<conversation_summary>` (change rarely).
/// 2. History after the summary cut, append-only. Every user message carries
///    the time it was sent (`[2026-09-30 14:05 Tue]`), derived from stored
///    data, so it renders identically forever.
/// 3. The current user message, prefixed with the `<context>` snapshot. Next
///    turn that message is history and loses the snapshot, so a snapshot
///    change never invalidates the cached history before it.
/// 4. This turn's assistant steps and tool results (with reasoning extras).
extension AiChatWire on AiChatService {
  List<Map<String, dynamic>> _buildWire({
    required _TurnSetup setup,
    required _History history,
    required AiChatMessage currentUser,
    required List<AiChatMessage> turnMessages,
    required String snapshot,
    required String memoryBlock,
    required List<String> imageDataUrls,
    List<Map<String, dynamic>> extra = const [],
  }) {
    final responses = setup.provider.apiStyle == AiApiStyle.responses;
    final system = StringBuffer(setup.systemPrompt);
    if (memoryBlock.isNotEmpty) {
      system.write('\n\n<memory>\n$memoryBlock\n</memory>');
    }
    final summary = history.summary?.trim();
    if (summary != null && summary.isNotEmpty) {
      system.write(
        '\n\n<conversation_summary>\nEarlier messages of this conversation, '
        'summarized. Context only: personal facts still have to be read '
        'with the tools.\n$summary\n</conversation_summary>',
      );
    }
    final out = <Map<String, dynamic>>[
      {'role': 'system', 'content': system.toString()},
    ];

    // A boundary that is not in the window (deleted by a retry) stubs
    // nothing rather than everything.
    var stubbing =
        history.toolsThroughMessageId != null &&
        history.messages.any((m) => m.id == history.toolsThroughMessageId);
    final historyWire = <Map<String, dynamic>>[];
    for (final m in history.messages) {
      historyWire.addAll(
        _wireMessage(m, stub: stubbing, currentTurn: false, responses: false),
      );
      if (stubbing && m.id == history.toolsThroughMessageId) stubbing = false;
    }
    out.addAll(_repairToolPairs(historyWire));

    final userText = StringBuffer();
    if (snapshot.isNotEmpty) {
      userText.write('<context>\n$snapshot\n</context>\n\n');
    }
    userText.write(_userText(currentUser));
    if (imageDataUrls.isEmpty) {
      out.add({'role': 'user', 'content': userText.toString()});
    } else {
      out.add({
        'role': 'user',
        'content': [
          {'type': 'text', 'text': userText.toString()},
          for (final url in imageDataUrls)
            {
              'type': 'image_url',
              'image_url': {'url': url, 'detail': 'auto'},
            },
        ],
      });
    }
    final turnWire = <Map<String, dynamic>>[];
    for (final m in turnMessages) {
      turnWire.addAll(
        _wireMessage(m, stub: false, currentTurn: true, responses: responses),
      );
    }
    out.addAll(_repairToolPairs(turnWire));
    out.addAll(extra);
    return out;
  }

  /// `[2026-09-30 14:05 Tue] text` (+ a note for images of past turns).
  String _userText(AiChatMessage m) {
    final t = m.createdAt;
    final stamp =
        '[${dateKey(t)} ${_two(t.hour)}:${_two(t.minute)} '
        '${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][t.weekday - 1]}]';
    final text = m.content?.trim() ?? '';
    return '$stamp ${text.isEmpty ? '(image only)' : text}';
  }

  static String _two(int v) => DurationFormat.twoDigits(v);

  List<Map<String, dynamic>> _wireMessage(
    AiChatMessage m, {
    required bool stub,
    required bool currentTurn,
    required bool responses,
  }) {
    switch (m.role) {
      case AiMessageRole.system:
        return const [];
      case AiMessageRole.user:
        final images = m.attachments.length;
        return [
          {
            'role': 'user',
            'content':
                '${_userText(m)}'
                '${images == 0 ? '' : ' [$images image(s) were attached]'}',
          },
        ];
      case AiMessageRole.event:
        return [
          {
            'role': 'user',
            'content': '<app_event>${m.content ?? '{}'}</app_event>',
          },
        ];
      case AiMessageRole.assistant:
        final entry = <String, dynamic>{'role': 'assistant'};
        final text = m.content;
        entry['content'] = (text == null || text.isEmpty) ? null : text;
        if (m.toolCalls.isNotEmpty) {
          entry['tool_calls'] = [
            for (final c in m.toolCalls) c.toJson(includeExtras: currentTurn),
          ];
        }
        if (currentTurn) {
          for (final extra in m.providerExtras.entries) {
            // Responses reasoning items only make sense to that API.
            if (extra.key == 'responses_reasoning' && !responses) continue;
            if (extra.key == kAiCutOffExtra) continue; // app flag, not wire
            entry[extra.key] = extra.value;
          }
        }
        if (entry['content'] == null && m.toolCalls.isEmpty) return const [];
        return [entry];
      case AiMessageRole.tool:
        return [
          {
            'role': 'tool',
            'tool_call_id': m.toolCallId ?? '',
            'content': stub
                ? _toolStub(m)
                : _wireToolContent(m.content ?? '{"ok":false}'),
          },
        ];
    }
  }

  /// Keeps the transcript valid whatever was stored: every assistant tool
  /// call gets a result (a stub if it was lost) and results without their
  /// call are dropped.
  List<Map<String, dynamic>> _repairToolPairs(List<Map<String, dynamic>> wire) {
    final out = <Map<String, dynamic>>[];
    var i = 0;
    while (i < wire.length) {
      final message = wire[i];
      if (message['role'] == 'tool') {
        i++; // Orphan result: its call is not in the window.
        continue;
      }
      out.add(message);
      i++;
      final calls = message['tool_calls'];
      if (calls is! List || calls.isEmpty) continue;
      final ids = [
        for (final call in calls)
          if (call is Map) '${call['id']}',
      ];
      final results = <String, Map<String, dynamic>>{};
      while (i < wire.length && wire[i]['role'] == 'tool') {
        results['${wire[i]['tool_call_id']}'] = wire[i];
        i++;
      }
      for (final id in ids) {
        out.add(
          results[id] ??
              {
                'role': 'tool',
                'tool_call_id': id,
                'content': '{"ok":false,"code":"interrupted"}',
              },
        );
      }
    }
    return out;
  }

  String _toolStub(AiChatMessage m) {
    final decoded = AiChatService._decodeToolContent(m.content);
    final ok = decoded?['ok'] == true;
    final data = decoded?['data'];
    return jsonEncode({
      'ok': ok,
      if (!ok && decoded?['code'] != null) 'code': decoded!['code'],
      // Proposal and memory outcomes stay meaningful in a stub.
      if (data is Map && data['proposal_id'] != null)
        'proposal_id': data['proposal_id'],
      if (data is Map && data['memory_id'] != null) 'status': data['status'],
      'omitted': 'older result; call the tool again if you need it',
    });
  }

  /// Caps a tool result on the wire with valid JSON. The stored message keeps
  /// the full payload for the UI.
  String _wireToolContent(String content) {
    if (content.length <= kMaxToolResultChars) return content;
    final decoded = AiChatService._decodeToolContent(content);
    if (decoded != null) {
      final shrunk = _shrinkJson(decoded, kMaxToolResultChars - 200);
      if (shrunk != null) return shrunk;
    }
    return jsonEncode({
      'ok': decoded?['ok'] ?? true,
      'truncated': true,
      'note':
          'Result too large and cut. Narrow the query (shorter period, '
          'filters, next page) if you need the rest.',
      'partial': content.substring(0, kMaxToolResultChars ~/ 2),
    });
  }

  /// Drops rows from the end of the longest lists until the encoding fits.
  String? _shrinkJson(Map<String, dynamic> value, int maxChars) {
    final copy = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
    var encoded = jsonEncode(copy);
    var dropped = 0;
    for (var guard = 0; guard < 400 && encoded.length > maxChars; guard++) {
      final list = _longestList(copy);
      if (list == null || list.length <= 1) return null;
      final remove = (list.length / 4).ceil();
      list.removeRange(list.length - remove, list.length);
      dropped += remove;
      encoded = jsonEncode(copy);
    }
    if (encoded.length > maxChars) return null;
    copy['truncated_rows'] = dropped;
    copy['note'] = 'Some rows were dropped to fit; narrow the query for more.';
    return jsonEncode(copy);
  }

  List<dynamic>? _longestList(Object? node) {
    List<dynamic>? best;
    var bestLen = 0;
    void visit(Object? n) {
      if (n is List) {
        final len = jsonEncode(n).length;
        if (len > bestLen) {
          best = n;
          bestLen = len;
        }
        for (final item in n) {
          visit(item);
        }
      } else if (n is Map) {
        for (final v in n.values) {
          visit(v);
        }
      }
    }

    visit(node);
    return best;
  }

  // ===========================================================================
  // TOKEN ESTIMATES
  // ===========================================================================

  int _estimateChars(int chars) =>
      (TokenEstimator.estimateChars(chars) * _tokenScale).ceil();

  /// Learns the provider's chars-per-token ratio from reported usage.
  void _calibrateTokenScale({required int requestChars, int? promptTokens}) {
    if (promptTokens == null || promptTokens <= 0) return;
    final raw = TokenEstimator.estimateChars(requestChars);
    if (raw <= 0) return;
    _tokenScale = (promptTokens / raw).clamp(0.6, 2.5);
  }

  @visibleForTesting
  List<Map<String, dynamic>> buildWireForTest({
    required List<AiChatMessage> history,
    required AiChatMessage currentUser,
    List<AiChatMessage> turnMessages = const [],
    String? summary,
    String? toolsThroughMessageId,
    String snapshot = '',
    String memoryBlock = '',
    List<String> imageDataUrls = const [],
    String systemPrompt = 'system',
    AiApiStyle apiStyle = AiApiStyle.chatCompletions,
  }) => _buildWire(
    setup: _TurnSetup(
      provider: AiProvider.create(
        name: 'test',
        baseUrl: 'https://example.test/v1',
      ).copyWith(apiStyle: apiStyle),
      token: '',
      systemPrompt: systemPrompt,
      languageCode: 'en',
      domains: const {},
    ),
    history: _History(
      messages: history,
      summary: summary,
      toolsThroughMessageId: toolsThroughMessageId,
    ),
    currentUser: currentUser,
    turnMessages: turnMessages,
    snapshot: snapshot,
    memoryBlock: memoryBlock,
    imageDataUrls: imageDataUrls,
  );

  @visibleForTesting
  String wireToolContentForTest(String content) => _wireToolContent(content);
}
