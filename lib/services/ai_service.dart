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
  const AiServiceException(this.message, {this.code});

  @override
  String toString() => 'AiServiceException($code): $message';
}

/// OpenAI-compatible HTTP client. Stateless; safe to share.
class AiService {
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  AiService({http.Client? client, this.timeout = const Duration(seconds: 90)})
    : _client = client ?? http.Client(),
      _ownsClient = client == null;

  /// Releases the internally-created HTTP client.
  ///
  /// Callers that injected a client retain ownership of it, which keeps tests
  /// and shared application clients from being closed unexpectedly.
  void close() {
    if (_ownsClient) _client.close();
  }

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
    final payload = <String, dynamic>{
      'model': model,
      'messages': messages,
      'temperature': temperature,
    };
    if (tools != null && tools.isNotEmpty) {
      payload['tools'] = tools;
      payload['tool_choice'] = toolChoice ?? 'auto';
    }

    final res = await _client
        .post(
          uri,
          headers: _headers(token: token),
          body: jsonEncode(payload),
        )
        .timeout(timeout);

    if (res.statusCode == 401) {
      throw const AiServiceException(
        'Invalid or missing API token.',
        code: 'invalid_token',
      );
    }
    if (res.statusCode == 404) {
      throw const AiServiceException(
        'Model or endpoint not found (404).',
        code: 'not_found',
      );
    }
    if (res.statusCode >= 400) {
      throw AiServiceException(
        'Request failed (${res.statusCode}): ${_truncate(res.body)}',
        code: 'http_error',
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
          calls.add(AiToolCall.fromJson(raw.cast<String, dynamic>()));
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

  Map<String, String> _headers({required String token}) => {
    'Authorization': 'Bearer $token',
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
}
