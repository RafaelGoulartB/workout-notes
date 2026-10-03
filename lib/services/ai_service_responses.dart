part of 'ai_service.dart';

/// Parsing of non-streamed provider bodies into [AiChatCompletion]s.
extension AiServiceResponses on AiService {
  AiChatCompletion _parseChat(String rawBody) {
    final body = _decodeJson(rawBody);
    if (body is! Map) {
      throw const AiServiceException(
        'Invalid response body',
        code: 'invalid_response',
      );
    }
    _throwEmbeddedError(body);
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiServiceException(
        'Empty choices in response',
        code: 'empty_choices',
      );
    }
    final choice = choices.first;
    final message = choice is Map ? choice['message'] : null;
    if (message is! Map) {
      throw const AiServiceException(
        'Missing message in choice',
        code: 'invalid_response',
      );
    }
    final rawText = _extractText(message['content']);
    final calls = <AiToolCall>[];
    final rawCalls = message['tool_calls'];
    if (rawCalls is List) {
      for (final raw in rawCalls) {
        if (raw is Map) {
          final parsed = AiToolCall.fromJson(raw.cast<String, dynamic>());
          calls.add(
            parsed.id.isEmpty ? parsed.withId(_fallbackCallId()) : parsed,
          );
        }
      }
    }
    final usage = _usage(body['usage']);
    return _completion(
      rawText: rawText,
      calls: calls,
      extras: _messageExtras(message),
      usage: usage,
      finishReason: choice is Map ? choice['finish_reason'] as String? : null,
    );
  }

  AiChatCompletion _parseResponses(String rawBody) {
    final body = _decodeJson(rawBody);
    if (body is! Map) {
      throw const AiServiceException(
        'Invalid response body',
        code: 'invalid_response',
      );
    }
    _throwEmbeddedError(body);
    return _completionFromResponsesBody(body);
  }

  AiChatCompletion _completionFromResponsesBody(Map<dynamic, dynamic> body) {
    final output = body['output'];
    final calls = <AiToolCall>[];
    final reasoningItems = <Map<String, dynamic>>[];
    final text = StringBuffer();
    if (output is List) {
      for (final item in output) {
        if (item is! Map) continue;
        switch (item['type']) {
          case 'function_call':
            calls.add(
              AiToolCall.fromJson({
                'id': item['call_id'] ?? item['id'] ?? _fallbackCallId(),
                'type': 'function',
                'function': {
                  'name': item['name'] ?? '',
                  'arguments': item['arguments'] ?? '{}',
                },
              }),
            );
          case 'reasoning':
            reasoningItems.add(item.cast<String, dynamic>());
          case 'message':
            final content = item['content'];
            if (content is List) {
              for (final part in content) {
                if (part is Map && part['type'] == 'output_text') {
                  final value = part['text'];
                  if (value is String) text.write(value);
                }
              }
            }
        }
      }
    }
    var rawText = text.isEmpty ? null : text.toString();
    final direct = body['output_text'];
    if (rawText == null && direct is String && direct.isNotEmpty) {
      rawText = direct;
    }
    final usage = body['usage'];
    return _completion(
      rawText: rawText,
      calls: calls,
      extras: reasoningItems.isEmpty
          ? const {}
          : {'responses_reasoning': reasoningItems},
      usage: (
        prompt: usage is Map ? (usage['input_tokens'] as num?)?.toInt() : null,
        completion: usage is Map
            ? (usage['output_tokens'] as num?)?.toInt()
            : null,
        cached: usage is Map
            ? ((usage['input_tokens_details'] as Map?)?['cached_tokens']
                      as num?)
                  ?.toInt()
            : null,
      ),
      finishReason: body['status'] as String?,
    );
  }

  AiChatCompletion _completion({
    required String? rawText,
    required List<AiToolCall> calls,
    required Map<String, dynamic> extras,
    required ({int? prompt, int? completion, int? cached}) usage,
    String? finishReason,
    bool truncated = false,
  }) {
    final text = rawText == null ? null : TextSanitizer.stripReasoning(rawText);
    return AiChatCompletion(
      text: text == null || text.trim().isEmpty ? null : text,
      toolCalls: calls,
      hadReferencePlaceholders:
          rawText != null &&
          TextSanitizer.containsReferencePlaceholder(rawText),
      promptTokens: usage.prompt,
      completionTokens: usage.completion,
      cachedTokens: usage.cached,
      providerExtras: extras,
      finishReason: finishReason,
      truncated: truncated || _isCutOffReason(finishReason),
    );
  }
}

/// Finish reasons (Chat Completions) and statuses (Responses) of an answer
/// that did not end on its own: output limit, content filter, incomplete.
bool _isCutOffReason(String? reason) => const {
  'length',
  'content_filter',
  'max_tokens',
  'max_output_tokens',
  'incomplete',
}.contains(reason);

/// Every assistant-message field besides the standard ones, kept opaque.
Map<String, dynamic> _messageExtras(Map<dynamic, dynamic> message) {
  const standard = {
    'role',
    'content',
    'tool_calls',
    'refusal',
    'annotations',
    'audio',
    'function_call',
  };
  return {
    for (final entry in message.entries)
      if (!standard.contains(entry.key) &&
          entry.value != null &&
          !(entry.value is String && (entry.value as String).isEmpty) &&
          !(entry.value is List && (entry.value as List).isEmpty))
        '${entry.key}': entry.value,
  };
}

({int? prompt, int? completion, int? cached}) _usage(Object? usage) {
  if (usage is! Map) return (prompt: null, completion: null, cached: null);
  final details = usage['prompt_tokens_details'];
  final cached =
      (details is Map ? details['cached_tokens'] as num? : null) ??
      usage['prompt_cache_hit_tokens'] as num? ??
      usage['cache_read_input_tokens'] as num?;
  return (
    prompt: (usage['prompt_tokens'] as num?)?.toInt(),
    completion: (usage['completion_tokens'] as num?)?.toInt(),
    cached: cached?.toInt(),
  );
}
