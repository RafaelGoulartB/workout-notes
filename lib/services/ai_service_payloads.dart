part of 'ai_service.dart';

/// Request bodies for the chat-completions and Responses protocols.
extension AiServicePayloads on AiService {
  Map<String, dynamic> _chatPayload({
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>>? tools,
    required Object? toolChoice,
    required double? temperature,
    required String? reasoningEffort,
    required _ModelCompatibility compatibility,
    required bool stream,
    required int? maxOutputTokens,
    required String? cacheKey,
    required String baseUrl,
  }) {
    final hasTools = tools != null && tools.isNotEmpty;
    final payload = <String, dynamic>{
      'model': model,
      'messages': messages,
      if (temperature != null && !compatibility.omitTemperature)
        'temperature': compatibility.temperatureOverride ?? temperature,
      if (reasoningEffort != null && !compatibility.omitReasoningEffort)
        'reasoning_effort': reasoningEffort,
      if (maxOutputTokens != null && !compatibility.omitMaxTokens)
        'max_completion_tokens': maxOutputTokens,
      if (stream) 'stream': true,
      if (stream && !compatibility.omitStreamOptions)
        'stream_options': {'include_usage': true},
    };
    if (hasTools) {
      payload['tools'] = tools;
      if (toolChoice != null && !compatibility.omitToolChoice) {
        payload['tool_choice'] = toolChoice;
      }
    }
    if (cacheKey != null &&
        !compatibility.omitCacheKey &&
        _isOpenAiHost(baseUrl)) {
      payload['prompt_cache_key'] = cacheKey;
    }
    if (!compatibility.omitCacheControl && _wantsCacheControl(baseUrl, model)) {
      // OpenRouter's automatic mode: one breakpoint that follows the end of
      // the conversation (Anthropic and Gemini need explicit caching).
      payload['cache_control'] = {'type': 'ephemeral'};
    }
    return payload;
  }

  Map<String, dynamic> _responsesPayload({
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>>? tools,
    required Object? toolChoice,
    required double? temperature,
    required String? reasoningEffort,
    required _ModelCompatibility compatibility,
    required bool stream,
    required int? maxOutputTokens,
    required String? cacheKey,
    required String baseUrl,
  }) {
    final instructions = messages
        .where((message) => message['role'] == 'system')
        .map((message) => message['content'])
        .whereType<String>()
        .join('\n\n');
    final input = <Map<String, dynamic>>[];
    for (final message in messages) {
      final role = message['role'];
      if (role == 'system') continue;
      if (role == 'tool') {
        input.add({
          'type': 'function_call_output',
          'call_id': message['tool_call_id'],
          'output': message['content'] ?? '',
        });
        continue;
      }
      final isAssistant = role == 'assistant';
      // Reasoning items of this assistant step go first, exactly as returned.
      final reasoningItems = message['responses_reasoning'];
      if (reasoningItems is List) {
        for (final item in reasoningItems) {
          if (item is Map) input.add(item.cast<String, dynamic>());
        }
      }
      final parts = <Map<String, dynamic>>[];
      final content = message['content'];
      final textType = isAssistant ? 'output_text' : 'input_text';
      if (content is String && content.isNotEmpty) {
        parts.add({'type': textType, 'text': content});
      } else if (content is List) {
        for (final rawPart in content) {
          if (rawPart is! Map) continue;
          if (rawPart['type'] == 'text' && rawPart['text'] is String) {
            parts.add({'type': textType, 'text': rawPart['text']});
          } else if (rawPart['type'] == 'image_url') {
            final image = rawPart['image_url'];
            final url = image is Map ? image['url'] : image;
            if (url is String && url.isNotEmpty) {
              parts.add({'type': 'input_image', 'image_url': url});
            }
          }
        }
      }
      if (parts.isNotEmpty) input.add({'role': role, 'content': parts});
      final toolCalls = message['tool_calls'];
      if (toolCalls is List) {
        for (final rawCall in toolCalls) {
          if (rawCall is! Map) continue;
          final function = rawCall['function'];
          if (function is! Map) continue;
          input.add({
            'type': 'function_call',
            'call_id': rawCall['id'],
            'name': function['name'],
            'arguments': function['arguments'] ?? '{}',
          });
        }
      }
    }
    final hasTools = tools != null && tools.isNotEmpty;
    return {
      'model': model,
      if (instructions.isNotEmpty) 'instructions': instructions,
      'input': input,
      'store': false,
      if (!compatibility.omitReasoningInclude)
        'include': ['reasoning.encrypted_content'],
      if (hasTools) 'tools': tools.map(_responsesTool).toList(),
      if (hasTools && toolChoice != null && !compatibility.omitToolChoice)
        'tool_choice': _responsesToolChoice(toolChoice),
      if (reasoningEffort != null && !compatibility.omitReasoningEffort)
        'reasoning': {'effort': reasoningEffort},
      if (temperature != null && !compatibility.omitTemperature)
        'temperature': compatibility.temperatureOverride ?? temperature,
      if (maxOutputTokens != null && !compatibility.omitMaxTokens)
        'max_output_tokens': maxOutputTokens,
      if (cacheKey != null &&
          !compatibility.omitCacheKey &&
          _isOpenAiHost(baseUrl))
        'prompt_cache_key': cacheKey,
      if (stream) 'stream': true,
    };
  }

  Map<String, dynamic> _responsesTool(Map<String, dynamic> tool) {
    final function = tool['function'];
    if (function is! Map) return tool;
    return {
      'type': 'function',
      'name': function['name'],
      if (function['description'] != null)
        'description': function['description'],
      'parameters':
          function['parameters'] ??
          const {'type': 'object', 'properties': <String, dynamic>{}},
    };
  }
}

/// Chat-completions `tool_choice` in the Responses shape (a forced
/// function is `{type: function, name}` there).
Object _responsesToolChoice(Object choice) {
  if (choice is Map) {
    final function = choice['function'];
    if (choice['type'] == 'function' && function is Map) {
      return {'type': 'function', 'name': function['name']};
    }
  }
  return choice;
}

bool _isOpenAiHost(String baseUrl) {
  final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
  return host == 'api.openai.com';
}

bool _wantsCacheControl(String baseUrl, String model) {
  final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
  if (host != 'openrouter.ai' && !host.endsWith('.openrouter.ai')) {
    return false;
  }
  final id = model.toLowerCase();
  return id.startsWith('anthropic/') || id.startsWith('google/');
}
