part of 'ai_service.dart';

const String _anthropicVersion = '2023-06-01';

/// Lets the request carry `thinking.block_binding` (see [_anthropicPayload]).
const String _anthropicThinkingBindingBeta =
    'thinking-binding-controls-2026-08-01';

/// Assistant-message extra holding the content blocks of a Claude answer
/// that contained thinking, exactly as returned. Sent back verbatim within
/// the same turn (thinking blocks must come back unchanged and in order).
const String kAnthropicContentExtra = 'anthropic_content';

/// Anthropic's Messages API: the Chat Completions transcript the app builds
/// is translated here, and answers come back as [AiChatCompletion]s.
extension AiServiceAnthropic on AiService {
  Map<String, dynamic> _anthropicPayload({
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>>? tools,
    required Object? toolChoice,
    required String? reasoningEffort,
    required _ModelCompatibility compatibility,
    required bool stream,
    required int? maxOutputTokens,
  }) {
    final system = messages
        .where((message) => message['role'] == 'system')
        .map((message) => _extractText(message['content']))
        .whereType<String>()
        .where((text) => text.trim().isNotEmpty)
        .join('\n\n');
    final hasTools = tools != null && tools.isNotEmpty;
    final thinking =
        !compatibility.omitThinking && _anthropicAdaptiveThinking(model);
    final requested = maxOutputTokens ?? (stream ? 64000 : 16000);
    final cap = compatibility.maxTokensCap;
    final caching = !compatibility.omitCacheControl;
    final choice =
        hasTools && toolChoice != null && !compatibility.omitToolChoice
        ? _anthropicToolChoice(toolChoice)
        : null;
    return {
      'model': model,
      'max_tokens': cap != null && cap < requested ? cap : requested,
      if (system.isNotEmpty)
        'system': [
          {
            'type': 'text',
            'text': system,
            // The stable prefix (tools + system) gets its own read point.
            if (caching) 'cache_control': {'type': 'ephemeral'},
          },
        ],
      'messages': _anthropicMessages(messages),
      if (hasTools) 'tools': tools.map(_anthropicTool).toList(),
      'tool_choice': ?choice,
      if (thinking)
        'thinking': {
          'type': 'adaptive',
          // A history the app had to rewrite mid-turn (a forced compaction)
          // drops the stale thinking blocks instead of failing the request.
          if (!compatibility.omitBlockBinding)
            'block_binding': {'prefix_mismatch_behavior': 'drop_block'},
        },
      if (thinking &&
          reasoningEffort != null &&
          !compatibility.omitReasoningEffort)
        'output_config': {'effort': reasoningEffort},
      // Automatic caching: one breakpoint that follows the conversation.
      if (caching) 'cache_control': {'type': 'ephemeral'},
      if (stream) 'stream': true,
    };
  }

  /// Merges consecutive messages of the same role (tool results become one
  /// user message, as the API requires) and starts with a user message.
  List<Map<String, dynamic>> _anthropicMessages(
    List<Map<String, dynamic>> messages,
  ) {
    final out = <Map<String, dynamic>>[];
    void add(String role, List<Map<String, dynamic>> blocks) {
      if (blocks.isEmpty) return;
      if (out.isNotEmpty && out.last['role'] == role) {
        (out.last['content'] as List<Map<String, dynamic>>).addAll(blocks);
      } else {
        out.add({'role': role, 'content': blocks});
      }
    }

    for (final message in messages) {
      switch (message['role']) {
        case 'system':
          continue;
        case 'tool':
          final content = _extractText(message['content']);
          add('user', [
            {
              'type': 'tool_result',
              'tool_use_id': _anthropicId(message['tool_call_id']),
              'content': content == null || content.isEmpty ? '{}' : content,
            },
          ]);
        case 'assistant':
          add('assistant', _anthropicAssistantBlocks(message));
        default:
          add('user', _anthropicUserBlocks(message['content']));
      }
    }
    if (out.isNotEmpty && out.first['role'] != 'user') {
      // The window can start at an assistant step after a summary cut.
      out.insert(0, {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': '(earlier messages are summarized above)'},
        ],
      });
    }
    return out;
  }

  List<Map<String, dynamic>> _anthropicUserBlocks(Object? content) {
    if (content is String) {
      return content.trim().isEmpty
          ? const []
          : [
              {'type': 'text', 'text': content},
            ];
    }
    final blocks = <Map<String, dynamic>>[];
    if (content is List) {
      for (final part in content) {
        if (part is! Map) continue;
        if (part['type'] == 'text') {
          final text = part['text'];
          if (text is String && text.trim().isNotEmpty) {
            blocks.add({'type': 'text', 'text': text});
          }
        } else if (part['type'] == 'image_url') {
          final image = part['image_url'];
          final url = image is Map ? image['url'] : image;
          if (url is String && url.isNotEmpty) blocks.add(_anthropicImage(url));
        }
      }
    }
    return blocks;
  }

  /// Text and tool calls of an assistant step. A step of the current turn
  /// that carries [kAnthropicContentExtra] is replayed as returned (thinking
  /// included); its tool calls take the ids the app finally gave them.
  List<Map<String, dynamic>> _anthropicAssistantBlocks(
    Map<String, dynamic> message,
  ) {
    final rawCalls = message['tool_calls'];
    final calls = <Map<dynamic, dynamic>>[
      if (rawCalls is List)
        for (final call in rawCalls)
          if (call is Map) call,
    ];
    final blocks = <Map<String, dynamic>>[];
    var nextCall = 0;
    final stored = message[kAnthropicContentExtra];
    if (stored is List) {
      for (final raw in stored) {
        if (raw is! Map) continue;
        final block = raw.cast<String, dynamic>();
        switch (block['type']) {
          case 'tool_use':
            // Calls the app dropped (a final round) are not replayed.
            if (nextCall < calls.length) {
              blocks.add(_anthropicToolUse(calls[nextCall++]));
            }
          case 'text':
            final text = block['text'];
            if (text is String && text.trim().isNotEmpty) blocks.add(block);
          default:
            blocks.add(block);
        }
      }
    } else {
      final text = _extractText(message['content']);
      if (text != null && text.trim().isNotEmpty) {
        blocks.add({'type': 'text', 'text': text});
      }
    }
    for (; nextCall < calls.length; nextCall++) {
      blocks.add(_anthropicToolUse(calls[nextCall]));
    }
    return blocks;
  }

  Map<String, dynamic> _anthropicToolUse(Map<dynamic, dynamic> call) {
    final function = call['function'];
    final arguments = function is Map ? function['arguments'] : null;
    Object? input = arguments;
    if (arguments is String) {
      input = arguments.trim().isEmpty ? null : _decodeJson(arguments);
    }
    return {
      'type': 'tool_use',
      'id': _anthropicId(call['id']),
      'name': function is Map ? '${function['name'] ?? ''}' : '',
      // The API needs an object; unparseable arguments were already
      // answered with an invalid_args error.
      'input': input is Map ? input : const <String, dynamic>{},
    };
  }

  Map<String, dynamic> _anthropicTool(Map<String, dynamic> tool) {
    final function = tool['function'];
    if (function is! Map) return tool;
    return {
      'name': function['name'],
      if (function['description'] != null)
        'description': function['description'],
      'input_schema':
          function['parameters'] ??
          const {'type': 'object', 'properties': <String, dynamic>{}},
    };
  }

  AiChatCompletion _parseAnthropic(String rawBody) {
    final body = _decodeJson(rawBody);
    if (body is! Map) {
      throw const AiServiceException(
        'Invalid response body',
        code: 'invalid_response',
      );
    }
    _throwAnthropicError(body);
    final content = body['content'];
    if (content is! List) {
      throw const AiServiceException(
        'Missing content in response',
        code: 'invalid_response',
      );
    }
    return _anthropicCompletion(
      blocks: [
        for (final block in content)
          if (block is Map) block.cast<String, dynamic>(),
      ],
      usage: body['usage'],
      stopReason: body['stop_reason'] as String?,
    );
  }

  /// [rawToolInputs]: tool-call id → streamed input that is not a JSON
  /// object, kept so the call reports its arguments error.
  AiChatCompletion _anthropicCompletion({
    required List<Map<String, dynamic>> blocks,
    required Object? usage,
    required String? stopReason,
    Map<String, String> rawToolInputs = const {},
    bool truncated = false,
  }) {
    final text = StringBuffer();
    final calls = <AiToolCall>[];
    var thinking = false;
    for (final block in blocks) {
      switch (block['type']) {
        case 'text':
          final value = block['text'];
          if (value is String) text.write(value);
        case 'tool_use':
          final id = block['id'] is String && (block['id'] as String).isNotEmpty
              ? block['id'] as String
              : _fallbackCallId();
          calls.add(
            AiToolCall.fromJson({
              'id': id,
              'type': 'function',
              'function': {
                'name': block['name'] ?? '',
                'arguments':
                    rawToolInputs[block['id']] ??
                    jsonEncode(block['input'] ?? const {}),
              },
            }),
          );
        case 'thinking':
        case 'redacted_thinking':
          thinking = true;
      }
    }
    return _completion(
      rawText: text.isEmpty ? null : text.toString(),
      calls: calls,
      extras: thinking ? {kAnthropicContentExtra: blocks} : const {},
      usage: _anthropicUsage(usage),
      finishReason: stopReason,
      truncated: truncated,
    );
  }

  Future<AiChatCompletion> _readAnthropicStream(
    http.StreamedResponse res,
    void Function(AiStreamDelta)? onDelta,
    Uri uri,
  ) async {
    final blocks = <int, Map<String, dynamic>>{};
    final inputs = <int, StringBuffer>{};
    final text = StringBuffer();
    final names = <String>[];
    final usage = <String, dynamic>{};
    String? stopReason;
    var thinking = false;
    var stopped = false;
    var capped = false;
    var streamedChars = 0;

    await for (final data in _sseData(res)) {
      final event = _decodeJson(data);
      if (event is! Map) continue;
      switch (event['type']) {
        case 'error':
          _throwAnthropicError(event);
        case 'message_start':
          final message = event['message'];
          final startUsage = message is Map ? message['usage'] : null;
          if (startUsage is Map) _mergeUsage(usage, startUsage);
          continue;
        case 'content_block_start':
          final index = (event['index'] as num?)?.toInt() ?? blocks.length;
          final block = event['content_block'];
          if (block is! Map) continue;
          blocks[index] = Map<String, dynamic>.from(block);
          switch (block['type']) {
            case 'tool_use':
              inputs[index] = StringBuffer();
              names.add('${block['name'] ?? ''}');
            case 'thinking':
            case 'redacted_thinking':
              thinking = true;
          }
        case 'content_block_delta':
          final block = blocks[(event['index'] as num?)?.toInt()];
          final delta = event['delta'];
          if (block == null || delta is! Map) continue;
          switch (delta['type']) {
            case 'text_delta':
              final value = '${delta['text'] ?? ''}';
              block['text'] = '${block['text'] ?? ''}$value';
              text.write(value);
              streamedChars += value.length;
            case 'thinking_delta':
              final value = '${delta['thinking'] ?? ''}';
              block['thinking'] = '${block['thinking'] ?? ''}$value';
              streamedChars += value.length;
              continue; // Reasoning progress is reported on the block start.
            case 'signature_delta':
              block['signature'] =
                  '${block['signature'] ?? ''}${delta['signature'] ?? ''}';
              continue;
            case 'input_json_delta':
              inputs[(event['index'] as num).toInt()]?.write(
                delta['partial_json'] ?? '',
              );
              continue;
            default:
              continue;
          }
        case 'message_delta':
          final delta = event['delta'];
          if (delta is Map && delta['stop_reason'] is String) {
            stopReason = delta['stop_reason'] as String;
          }
          final deltaUsage = event['usage'];
          if (deltaUsage is Map) _mergeUsage(usage, deltaUsage);
          continue;
        case 'message_stop':
          stopped = true;
          continue;
        default:
          continue; // ping, content_block_stop, unknown events
      }
      onDelta?.call(
        AiStreamDelta(
          text: TextSanitizer.stripReasoning(text.toString()),
          reasoning: text.isEmpty && thinking,
          toolNames: List.of(names),
        ),
      );
      if (streamedChars > maxStreamedChars) {
        // Runaway stream: stop reading and end the answer as truncated.
        capped = true;
        break;
      }
    }

    final rawToolInputs = <String, String>{};
    final ordered = <Map<String, dynamic>>[];
    for (final index in blocks.keys.toList()..sort()) {
      final block = blocks[index]!;
      final input = inputs[index]?.toString() ?? '';
      if (block['type'] == 'tool_use' && input.trim().isNotEmpty) {
        final decoded = _decodeJson(input);
        if (decoded is Map) {
          block['input'] = decoded;
        } else {
          block['input'] = const <String, dynamic>{};
          rawToolInputs['${block['id']}'] = input;
        }
      }
      ordered.add(block);
    }
    if (ordered.isEmpty && stopReason == null) {
      throw AiServiceException(
        'The stream ended without an answer.',
        code: 'invalid_response',
        endpoint: uri.toString(),
      );
    }
    final cut = capped || !stopped;
    return _anthropicCompletion(
      // Tool calls of a stream that did not finish are most likely
      // incomplete: only the text is kept.
      blocks: cut
          ? [
              for (final block in ordered)
                if (block['type'] == 'text') block,
            ]
          : ordered,
      usage: usage,
      stopReason: stopReason,
      rawToolInputs: rawToolInputs,
      truncated: cut,
    );
  }
}

/// Request betas implied by [payload] (Anthropic only).
List<String> _anthropicBetas(Map<String, dynamic> payload) {
  final thinking = payload['thinking'];
  return [
    if (thinking is Map && thinking.containsKey('block_binding'))
      _anthropicThinkingBindingBeta,
  ];
}

/// Whether [model] takes `thinking: {type: adaptive}` and `effort`: Claude
/// 4.6 and later (Opus/Sonnet), every Claude 5 model. Older models, unknown
/// ids and proxies' aliases are sent without thinking settings.
bool _anthropicAdaptiveThinking(String model) {
  final match = RegExp(
    r'claude-(opus|sonnet|haiku|fable|mythos)-(\d+)(?:-(\d{1,2}))?(?![0-9])',
  ).firstMatch(model.toLowerCase());
  if (match == null) return false;
  final major = int.parse(match.group(2)!);
  final minor = int.tryParse(match.group(3) ?? '') ?? 0;
  if (major >= 5) return true;
  return major == 4 && minor >= 6 && match.group(1) != 'haiku';
}

/// Chat-completions `tool_choice` in Anthropic's shape.
Map<String, dynamic>? _anthropicToolChoice(Object choice) {
  if (choice is String) {
    return switch (choice) {
      'none' => const {'type': 'none'},
      'auto' => const {'type': 'auto'},
      'required' => const {'type': 'any'},
      _ => null,
    };
  }
  if (choice is Map) {
    final function = choice['function'];
    if (choice['type'] == 'function' && function is Map) {
      return {'type': 'tool', 'name': function['name']};
    }
  }
  return null;
}

/// `data:` URLs become base64 sources; anything else is fetched by URL.
Map<String, dynamic> _anthropicImage(String url) {
  final match = RegExp(
    r'^data:([^;,]+);base64,(.*)$',
    dotAll: true,
  ).firstMatch(url);
  return {
    'type': 'image',
    'source': match == null
        ? {'type': 'url', 'url': url}
        : {
            'type': 'base64',
            'media_type': match.group(1),
            'data': match.group(2),
          },
  };
}

/// Tool-use ids must match `^[a-zA-Z0-9_-]+$`; ids from another provider
/// (a thread that switched providers) are mapped the same way everywhere.
String _anthropicId(Object? id) {
  final value = '${id ?? ''}'.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  return value.isEmpty ? 'call_unknown' : value;
}

void _mergeUsage(Map<String, dynamic> into, Map<dynamic, dynamic> from) {
  for (final entry in from.entries) {
    if (entry.value is num) into['${entry.key}'] = entry.value;
  }
}

/// Anthropic's `input_tokens` excludes cached tokens; the prompt total adds
/// what was read from and written to the cache.
({int? prompt, int? completion, int? cached}) _anthropicUsage(Object? usage) {
  if (usage is! Map) return (prompt: null, completion: null, cached: null);
  int? read(String key) => (usage[key] as num?)?.toInt();
  final input = read('input_tokens');
  final cached = read('cache_read_input_tokens');
  return (
    prompt: input == null
        ? null
        : input + (cached ?? 0) + (read('cache_creation_input_tokens') ?? 0),
    completion: read('output_tokens'),
    cached: cached,
  );
}

/// `{type: error, error: {type, message}}` in a body or a stream event.
void _throwAnthropicError(Map<dynamic, dynamic> body) {
  final error = body['error'];
  if (body['type'] != 'error' && error == null) return;
  final type = error is Map ? '${error['type'] ?? ''}' : '';
  final message = error is Map ? '${error['message'] ?? error}' : '$error';
  throw AiServiceException(
    'Provider error: ${_truncate(message)}',
    code: switch (type) {
      'rate_limit_error' => 'rate_limited',
      'overloaded_error' || 'api_error' => 'provider_unavailable',
      'authentication_error' => 'invalid_token',
      'permission_error' => 'forbidden',
      'not_found_error' => 'not_found',
      _ when _looksLikeContextLength(message.toLowerCase()) =>
        'context_length_exceeded',
      _ => 'bad_request',
    },
  );
}
