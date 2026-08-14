import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_tool_call.dart';
import '../utils/text_sanitizer.dart';

class AiChatCompletion {
  final String? text;
  final List<AiToolCall> toolCalls;
  final bool hadReferencePlaceholders;
  final int? promptTokens;
  final int? completionTokens;

  const AiChatCompletion({
    this.text,
    this.toolCalls = const [],
    this.hadReferencePlaceholders = false,
    this.promptTokens,
    this.completionTokens,
  });

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

class AiServiceException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;
  final String? endpoint;
  final int? attemptCount;
  final List<String> compatibilityAdjustments;
  const AiServiceException(
    this.message, {
    this.code,
    this.statusCode,
    this.endpoint,
    this.attemptCount,
    this.compatibilityAdjustments = const [],
  });

  @override
  String toString() => 'AiServiceException($code): $message';
}

/// OpenAI-compatible HTTP client. Stateless; safe to share.
class AiService {
  final http.Client _client;
  final Future<void> Function(Duration) _delay;
  final Duration timeout;
  final Map<String, _ModelCompatibility> _modelCompatibility = {};

  AiService({
    http.Client? client,
    this.timeout = const Duration(seconds: 90),
    Future<void> Function(Duration)? delay,
  }) : _client = client ?? http.Client(),
       _delay = delay ?? ((duration) => Future<void>.delayed(duration));

  /// Normalises a user-provided base URL to end with `/v1`.
  static String normalizeBaseUri(String input) {
    var base = input.trim();
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/v1')) return base;
    return '$base/v1';
  }

  /// Fetches available models from `${baseUrl}/models`.
  Future<List<String>> listModels({
    required String baseUrl,
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/models');
    final res = await _client
        .get(uri, headers: _headers(token: token))
        .timeout(timeout);
    if (res.statusCode != 200) {
      throw AiServiceException(
        'Failed to list models (${res.statusCode})',
        code: 'list_models_failed',
      );
    }
    final body = jsonDecode(res.body);
    if (body is! Map) {
      throw const AiServiceException(
        'Invalid models response',
        code: 'invalid_response',
      );
    }
    final data = body['data'];
    if (data is! List) {
      throw const AiServiceException(
        'Invalid models response',
        code: 'invalid_response',
      );
    }
    final ids = <String>[];
    for (final item in data) {
      if (item is Map && item['id'] is String) {
        ids.add(item['id'] as String);
      }
    }
    ids.sort();
    return ids;
  }

  /// Sends a chat completion request. `tools` follows the OpenAI function-calling schema.
  Future<AiChatCompletion> sendChat({
    required String baseUrl,
    required String token,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Object? toolChoice,
    double temperature = 0.3,
  }) async {
    final uri = Uri.parse('$baseUrl/chat/completions');
    final compatibility = _modelCompatibility.putIfAbsent(
      _compatibilityKey(baseUrl, model),
      _ModelCompatibility.new,
    );
    var attempts = 0;
    var transientRetries = 0;
    late http.Response res;
    while (true) {
      attempts++;
      final payload = <String, dynamic>{
        'model': model,
        'messages': messages,
        if (!compatibility.omitTemperature)
          'temperature': compatibility.temperatureOverride ?? temperature,
      };
      if (tools != null && tools.isNotEmpty) {
        payload['tools'] = tools;
        if (!compatibility.omitToolChoice) {
          payload['tool_choice'] = toolChoice ?? 'auto';
        }
      }

      try {
        res = await _client
            .post(
              uri,
              headers: _headers(token: token),
              body: jsonEncode(payload),
            )
            .timeout(timeout);
      } on TimeoutException catch (error) {
        if (transientRetries < _maxTransientRetries) {
          await _waitBeforeRetry(transientRetries++);
          continue;
        }
        throw AiServiceException(
          'Provider request timed out after $attempts attempts: $error',
          code: 'timeout',
          endpoint: uri.toString(),
          attemptCount: attempts,
          compatibilityAdjustments: compatibility.adjustments.toList(),
        );
      } on http.ClientException catch (error) {
        if (transientRetries < _maxTransientRetries) {
          await _waitBeforeRetry(transientRetries++);
          continue;
        }
        throw AiServiceException(
          'Provider connection failed after $attempts attempts: $error',
          code: 'connection_error',
          endpoint: uri.toString(),
          attemptCount: attempts,
          compatibilityAdjustments: compatibility.adjustments.toList(),
        );
      }

      if (res.statusCode < 400) break;
      final adjustment = res.statusCode == 401 || res.statusCode == 404
          ? null
          : _applyCompatibilityAdjustment(
              responseBody: res.body,
              sentPayload: payload,
              compatibility: compatibility,
            );
      if (adjustment != null) continue;
      if (_isTransientStatus(res.statusCode) &&
          transientRetries < _maxTransientRetries) {
        await _waitBeforeRetry(transientRetries++);
        continue;
      }
      throw _httpException(
        response: res,
        uri: uri,
        attempts: attempts,
        adjustments: compatibility.adjustments.toList(),
      );
    }

    final body = jsonDecode(res.body);
    if (body is! Map) {
      throw const AiServiceException(
        'Invalid response body',
        code: 'invalid_response',
      );
    }
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiServiceException(
        'Empty choices in response',
        code: 'empty_choices',
      );
    }
    final message = (choices.first as Map)['message'];
    if (message is! Map) {
      throw const AiServiceException(
        'Missing message in choice',
        code: 'invalid_response',
      );
    }

    final rawText = _extractText(message['content']);
    // Keep reference placeholders intact. The orchestrator must be able to
    // reject and regenerate an invalid answer with the complete tool context;
    // deleting markers here loses both their position and the evidence that
    // the model failed to materialise the data.
    final text = rawText == null ? null : _sanitizeReasoning(rawText);
    final calls = <AiToolCall>[];
    final rawCalls = message['tool_calls'];
    if (rawCalls is List) {
      for (final raw in rawCalls) {
        if (raw is Map) {
          final parsed = AiToolCall.fromJson(raw.cast<String, dynamic>());
          calls.add(
            parsed.id.isEmpty
                ? AiToolCall(
                    id: 'call_${calls.length + 1}',
                    name: parsed.name,
                    arguments: parsed.arguments,
                  )
                : parsed,
          );
        }
      }
    }

    int? promptTokens;
    int? completionTokens;
    final usage = body['usage'];
    if (usage is Map) {
      promptTokens = (usage['prompt_tokens'] as num?)?.toInt();
      completionTokens = (usage['completion_tokens'] as num?)?.toInt();
    }

    return AiChatCompletion(
      text: text,
      toolCalls: calls,
      hadReferencePlaceholders:
          rawText != null &&
          TextSanitizer.containsReferencePlaceholder(rawText),
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );
  }

  /// Sends a multimodal request using the protocol expected by the provider.
  ///
  /// OpenCode exposes its GPT models through the OpenAI Responses API. Its
  /// Chat Completions compatibility endpoint accepts text but rejects image
  /// parts with HTTP 400, so vision requests must use `/responses` there.
  Future<AiChatCompletion> sendVision({
    required String baseUrl,
    required String token,
    required String model,
    required List<Map<String, dynamic>> messages,
  }) {
    return sendMultimodalChat(
      baseUrl: baseUrl,
      token: token,
      model: model,
      messages: messages,
    );
  }

  /// Sends a multimodal chat while preserving tool calling support.
  Future<AiChatCompletion> sendMultimodalChat({
    required String baseUrl,
    required String token,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Object? toolChoice,
  }) async {
    try {
      if (_usesResponsesApiForVision(baseUrl: baseUrl, model: model)) {
        return await _sendResponsesVision(
          baseUrl: baseUrl,
          token: token,
          model: model,
          messages: messages,
          tools: tools,
          toolChoice: toolChoice,
        );
      }
      return await sendChat(
        baseUrl: baseUrl,
        token: token,
        model: model,
        messages: messages,
        tools: tools,
        toolChoice: toolChoice,
      );
    } on AiServiceException catch (error) {
      if (error.code == 'http_error' || error.code == 'invalid_response') {
        throw const AiServiceException(
          'The provider rejected the multimodal request.',
          code: 'vision_not_supported',
        );
      }
      rethrow;
    }
  }

  bool _usesResponsesApiForVision({
    required String baseUrl,
    required String model,
  }) {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    final isOpenCode = host == 'opencode.ai' || host.endsWith('.opencode.ai');
    return isOpenCode && model.toLowerCase().startsWith('gpt-');
  }

  Future<AiChatCompletion> _sendResponsesVision({
    required String baseUrl,
    required String token,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Object? toolChoice,
  }) async {
    final instructions = messages
        .where((message) => message['role'] == 'system')
        .map((message) => message['content'])
        .whereType<String>()
        .join('\n\n');
    final input = <Map<String, dynamic>>[];
    for (final message in messages.where(
      (message) => message['role'] != 'system',
    )) {
      final role = message['role'];
      if (role == 'tool') {
        input.add({
          'type': 'function_call_output',
          'call_id': message['tool_call_id'],
          'output': message['content'] ?? '',
        });
        continue;
      }
      final content = message['content'];
      final parts = <Map<String, dynamic>>[];
      if (content is String) {
        parts.add({'type': 'input_text', 'text': content});
      } else if (content is List) {
        for (final rawPart in content) {
          if (rawPart is! Map) continue;
          if (rawPart['type'] == 'text' && rawPart['text'] is String) {
            parts.add({'type': 'input_text', 'text': rawPart['text']});
          } else if (rawPart['type'] == 'image_url') {
            final image = rawPart['image_url'];
            final url = image is Map ? image['url'] : image;
            if (url is String && url.isNotEmpty) {
              parts.add({'type': 'input_image', 'image_url': url});
            }
          }
        }
      }
      if (parts.isNotEmpty) {
        input.add({'role': role, 'content': parts});
      }
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

    final uri = Uri.parse('$baseUrl/responses');
    final payload = <String, dynamic>{
      'model': model,
      if (instructions.isNotEmpty) 'instructions': instructions,
      'input': input,
      if (tools != null && tools.isNotEmpty)
        'tools': tools.map(_responsesTool).toList(),
      if (tools != null && tools.isNotEmpty)
        'tool_choice': _responsesToolChoice(toolChoice),
    };
    final res = await _client
        .post(
          uri,
          headers: _headers(token: token),
          body: jsonEncode(payload),
        )
        .timeout(timeout);

    if (res.statusCode == 401) {
      throw AiServiceException(
        'Invalid or missing API token.',
        code: 'invalid_token',
        statusCode: res.statusCode,
        endpoint: uri.toString(),
      );
    }
    if (res.statusCode == 404) {
      throw AiServiceException(
        'Model or endpoint not found (404).',
        code: 'not_found',
        statusCode: res.statusCode,
        endpoint: uri.toString(),
      );
    }
    if (res.statusCode >= 400) {
      throw AiServiceException(
        'Request failed (${res.statusCode}): ${_truncate(res.body)}',
        code: 'http_error',
        statusCode: res.statusCode,
        endpoint: uri.toString(),
      );
    }

    final body = jsonDecode(res.body);
    if (body is! Map) {
      throw const AiServiceException(
        'Invalid response body',
        code: 'invalid_response',
      );
    }
    final rawText = _extractResponsesText(body);
    final text = rawText == null ? null : _sanitizeReasoning(rawText);
    final usage = body['usage'];
    return AiChatCompletion(
      text: text,
      toolCalls: _extractResponsesToolCalls(body),
      hadReferencePlaceholders:
          rawText != null &&
          TextSanitizer.containsReferencePlaceholder(rawText),
      promptTokens: usage is Map
          ? (usage['input_tokens'] as num?)?.toInt()
          : null,
      completionTokens: usage is Map
          ? (usage['output_tokens'] as num?)?.toInt()
          : null,
    );
  }

  Map<String, dynamic> _responsesTool(Map<String, dynamic> tool) {
    final function = tool['function'];
    if (function is! Map) return tool;
    return {
      'type': 'function',
      'name': function['name'],
      if (function['description'] != null)
        'description': function['description'],
      'parameters': function['parameters'] ?? const <String, dynamic>{},
    };
  }

  Object _responsesToolChoice(Object? choice) {
    if (choice is! Map) return choice ?? 'auto';
    final function = choice['function'];
    if (choice['type'] == 'function' && function is Map) {
      return {'type': 'function', 'name': function['name']};
    }
    return choice;
  }

  List<AiToolCall> _extractResponsesToolCalls(Map<dynamic, dynamic> body) {
    final output = body['output'];
    if (output is! List) return const [];
    final calls = <AiToolCall>[];
    for (final item in output) {
      if (item is! Map || item['type'] != 'function_call') continue;
      calls.add(
        AiToolCall.fromJson({
          'id': item['call_id'] ?? item['id'] ?? '',
          'type': 'function',
          'function': {
            'name': item['name'] ?? '',
            'arguments': item['arguments'] ?? '{}',
          },
        }),
      );
    }
    return calls;
  }

  String? _extractResponsesText(Map<dynamic, dynamic> body) {
    final direct = body['output_text'];
    if (direct is String && direct.isNotEmpty) return direct;
    final output = body['output'];
    if (output is! List) return null;
    final buffer = StringBuffer();
    for (final item in output) {
      if (item is! Map || item['type'] != 'message') continue;
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is Map && part['type'] == 'output_text') {
          final text = part['text'];
          if (text is String) buffer.write(text);
        }
      }
    }
    final text = buffer.toString();
    return text.isEmpty ? null : text;
  }

  String _compatibilityKey(String baseUrl, String model) {
    final uri = Uri.tryParse(baseUrl);
    final endpoint = uri == null
        ? baseUrl.trim().toLowerCase()
        : '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}'
              '${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
    return '$endpoint|${model.trim().toLowerCase()}';
  }

  String? _applyCompatibilityAdjustment({
    required String responseBody,
    required Map<String, dynamic> sentPayload,
    required _ModelCompatibility compatibility,
  }) {
    final error = responseBody.toLowerCase();
    final mentionsTemperature = error.contains('temperature');
    final temperatureMustBeOne =
        mentionsTemperature &&
        (RegExp(
              r'(only|must be|has to be|required|allowed|support(?:ed|s)?)\D{0,24}1(?:\.0+)?\b',
            ).hasMatch(error) ||
            RegExp(r'1(?:\.0+)?\D{0,24}(only|temperature)').hasMatch(error));
    if (temperatureMustBeOne &&
        sentPayload['temperature'] != 1 &&
        compatibility.temperatureOverride != 1) {
      compatibility.temperatureOverride = 1;
      return compatibility.record('temperature=1');
    }
    final temperatureUnsupported =
        mentionsTemperature &&
        (error.contains('unsupported') ||
            error.contains('not supported') ||
            error.contains('unknown parameter') ||
            error.contains('unrecognized') ||
            error.contains('not allowed'));
    if (temperatureUnsupported &&
        sentPayload.containsKey('temperature') &&
        !compatibility.omitTemperature) {
      compatibility.omitTemperature = true;
      return compatibility.record('temperature omitted');
    }
    final toolChoiceUnsupported =
        error.contains('tool_choice') &&
        (error.contains('unsupported') ||
            error.contains('not supported') ||
            error.contains('unknown') ||
            error.contains('unrecognized') ||
            error.contains('not allowed'));
    if (toolChoiceUnsupported &&
        sentPayload.containsKey('tool_choice') &&
        !compatibility.omitToolChoice) {
      compatibility.omitToolChoice = true;
      return compatibility.record('tool_choice omitted');
    }
    return null;
  }

  AiServiceException _httpException({
    required http.Response response,
    required Uri uri,
    required int attempts,
    required List<String> adjustments,
  }) {
    if (response.statusCode == 401) {
      return AiServiceException(
        'Invalid or missing API token.',
        code: 'invalid_token',
        statusCode: response.statusCode,
        endpoint: uri.toString(),
        attemptCount: attempts,
        compatibilityAdjustments: adjustments,
      );
    }
    if (response.statusCode == 404) {
      return AiServiceException(
        'Model or endpoint not found (404).',
        code: 'not_found',
        statusCode: response.statusCode,
        endpoint: uri.toString(),
        attemptCount: attempts,
        compatibilityAdjustments: adjustments,
      );
    }
    final unavailable = const {502, 503, 504}.contains(response.statusCode);
    return AiServiceException(
      'Request failed (${response.statusCode}) after $attempts attempt(s): '
      '${_truncate(response.body)}',
      code: unavailable ? 'provider_unavailable' : 'http_error',
      statusCode: response.statusCode,
      endpoint: uri.toString(),
      attemptCount: attempts,
      compatibilityAdjustments: adjustments,
    );
  }

  bool _isTransientStatus(int statusCode) =>
      statusCode == 408 ||
      statusCode == 425 ||
      statusCode == 429 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  Future<void> _waitBeforeRetry(int retryIndex) =>
      _delay(Duration(milliseconds: retryIndex == 0 ? 350 : 900));

  Map<String, String> _headers({required String token}) => {
    // Local providers (e.g. Ollama) have no token; sending an empty
    // Bearer header can make some servers reject the request.
    if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  String? _extractText(dynamic content) {
    if (content == null) return null;
    if (content is String) {
      return content;
    }
    if (content is List) {
      final buf = StringBuffer();
      for (final part in content) {
        if (part is Map) {
          final type = part['type'];
          if (type == 'text') {
            final t = part['text'];
            if (t is String) buf.write(t);
          }
        }
      }
      final out = buf.toString();
      return out.isEmpty ? null : out;
    }
    return null;
  }

  String _sanitizeReasoning(String input) =>
      TextSanitizer.stripReasoning(input);

  String _truncate(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

  static const int _maxTransientRetries = 2;
}

class _ModelCompatibility {
  double? temperatureOverride;
  bool omitTemperature = false;
  bool omitToolChoice = false;
  final Set<String> adjustments = {};

  String record(String adjustment) {
    adjustments.add(adjustment);
    return adjustment;
  }
}
