import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:workout_notes/models/ai_tool_call.dart';
import 'package:workout_notes/utils/text_sanitizer.dart';

/// Wire protocol spoken to a provider.
enum AiApiStyle {
  /// OpenAI-compatible `/chat/completions` (every provider).
  chatCompletions,

  /// OpenAI `/responses`. Keeps reasoning between tool calls (encrypted
  /// reasoning items are sent back), which Chat Completions discards.
  responses;

  String get storageKey => name;

  static AiApiStyle fromStorageKey(String? value) => values.firstWhere(
    (style) => style.name == value,
    orElse: () => AiApiStyle.chatCompletions,
  );
}

class AiChatCompletion {
  final String? text;
  final List<AiToolCall> toolCalls;
  final bool hadReferencePlaceholders;
  final int? promptTokens;
  final int? completionTokens;

  /// Prompt tokens the provider served from its prompt cache, when reported.
  final int? cachedTokens;

  /// Opaque assistant-message fields to send back verbatim within the same
  /// turn (`reasoning_content`, `reasoning`, `reasoning_details`, Responses
  /// reasoning items…). Empty when the provider returned none.
  final Map<String, dynamic> providerExtras;
  final String? finishReason;

  const AiChatCompletion({
    this.text,
    this.toolCalls = const [],
    this.hadReferencePlaceholders = false,
    this.promptTokens,
    this.completionTokens,
    this.cachedTokens,
    this.providerExtras = const {},
    this.finishReason,
  });

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// Incremental progress of a streamed completion.
class AiStreamDelta {
  /// Visible answer text received so far (cumulative, sanitized).
  final String text;

  /// True while the provider streams reasoning before any answer text.
  final bool reasoning;

  /// Names of the tool calls the model has started so far.
  final List<String> toolNames;

  const AiStreamDelta({
    this.text = '',
    this.reasoning = false,
    this.toolNames = const [],
  });
}

class AiServiceException implements Exception {
  final String message;

  /// Stable code: invalid_token, payment_required, forbidden, not_found,
  /// payload_too_large, context_length_exceeded, bad_request, rate_limited,
  /// provider_unavailable, timeout, connection_error, cancelled,
  /// invalid_response, empty_choices, vision_not_supported, …
  final String? code;
  final int? statusCode;
  final String? endpoint;
  final int? attemptCount;
  final Duration? retryAfter;
  final List<String> compatibilityAdjustments;
  const AiServiceException(
    this.message, {
    this.code,
    this.statusCode,
    this.endpoint,
    this.attemptCount,
    this.retryAfter,
    this.compatibilityAdjustments = const [],
  });

  @override
  String toString() => 'AiServiceException($code): $message';
}

/// Where learned per-model compatibility flags are kept between launches.
abstract interface class AiCompatibilityStore {
  Map<String, Map<String, dynamic>> load();
  Future<void> save(Map<String, Map<String, dynamic>> value);
}

/// Result of a provider connection test.
class AiProbeResult {
  final bool ok;
  final bool toolsSupported;
  final bool streamingSupported;
  final int latencyMs;
  final String? errorCode;
  final String? errorMessage;

  const AiProbeResult({
    required this.ok,
    this.toolsSupported = false,
    this.streamingSupported = false,
    this.latencyMs = 0,
    this.errorCode,
    this.errorMessage,
  });
}

/// OpenAI-compatible HTTP client. Safe to share.
///
/// - Requests can be streamed (SSE) with an *idle* timeout instead of a total
///   one, and aborted for real through `abortTrigger`.
/// - Opaque provider fields (reasoning, signatures) are surfaced in
///   [AiChatCompletion.providerExtras] / [AiToolCall.extras] so the caller can
///   send them back inside the same turn.
/// - Parameters a model rejects (temperature, reasoning_effort, streaming…)
///   are learned per endpoint+model and persisted through an
///   [AiCompatibilityStore], so the next launch does not fail again.
///
/// Ownership: the app uses one long-lived [AiService.shared]; it is never
/// closed. An instance closes its `http.Client` in [close] only when it
/// created that client itself.
class AiService {
  /// The app-wide instance. Do not [close] it.
  static final AiService shared = AiService();

  final http.Client _client;
  final bool _ownsClient;
  final Future<void> Function(Duration) _delay;

  /// Total timeout of a non-streamed request.
  final Duration timeout;

  /// Streamed requests: longest wait for the first byte (reasoning models
  /// think before answering) and between two chunks afterwards.
  final Duration firstByteTimeout;
  final Duration idleTimeout;

  final Map<String, _ModelCompatibility> _modelCompatibility = {};
  AiCompatibilityStore? _store;

  AiService({
    http.Client? client,
    this.timeout = const Duration(seconds: 180),
    this.firstByteTimeout = const Duration(seconds: 180),
    this.idleTimeout = const Duration(seconds: 60),
    Future<void> Function(Duration)? delay,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _delay = delay ?? (Future<void>.delayed);

  /// Releases the HTTP client if this instance created it.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// Loads persisted compatibility flags and keeps saving new ones there.
  void attachCompatibilityStore(AiCompatibilityStore store) {
    _store = store;
    try {
      for (final entry in store.load().entries) {
        _modelCompatibility[entry.key] = _ModelCompatibility.fromJson(
          entry.value,
        );
      }
    } catch (error) {
      debugPrint('Loading AI compatibility flags failed: $error');
    }
  }

  /// Forgets what was learned about [baseUrl]+[model] (used after the user
  /// edits a provider).
  Future<void> resetCompatibility(String baseUrl, String model) async {
    _modelCompatibility.remove(_compatibilityKey(baseUrl, model));
    await _persistCompatibility();
  }

  /// Learned adjustments for [baseUrl]+[model], for diagnostics.
  List<String> compatibilityAdjustments(String baseUrl, String model) =>
      _modelCompatibility[_compatibilityKey(baseUrl, model)]?.adjustments
          .toList() ??
      const [];

  /// Normalises a user-provided base URL: trims, drops credentials, query and
  /// fragment, removes the trailing slash and adds `/v1` only when the URL
  /// has no path at all (so `.../v1beta/openai` stays as typed).
  static String normalizeBaseUri(String input) {
    var base = input.trim();
    if (base.isEmpty) return '';
    final parsed = Uri.tryParse(base);
    if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
      base = Uri(
        scheme: parsed.scheme,
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : null,
        path: parsed.path,
      ).toString();
    }
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final uri = Uri.tryParse(base);
    if (uri != null && (uri.path.isEmpty || uri.path == '/')) {
      return '$base/v1';
    }
    return base;
  }

  /// Whether [input] is an absolute http(s) URL with a host.
  static bool isValidBaseUri(String input) {
    final uri = Uri.tryParse(input.trim());
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;
  }

  /// Fetches available models from `${baseUrl}/models`.
  Future<List<String>> listModels({
    required String baseUrl,
    required String token,
  }) async {
    final uri = Uri.parse('$baseUrl/models');
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: _headers(token: token))
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw AiServiceException(
        'Listing models timed out.',
        code: 'timeout',
        endpoint: uri.toString(),
      );
    } on http.ClientException catch (error) {
      throw AiServiceException(
        'Connection failed: ${error.message}',
        code: 'connection_error',
        endpoint: uri.toString(),
      );
    }
    if (res.statusCode != 200) {
      throw _httpException(
        statusCode: res.statusCode,
        body: res.body,
        headers: res.headers,
        uri: uri,
        attempts: 1,
        adjustments: const [],
      );
    }
    final body = _decodeJson(res.body);
    final data = body is Map ? body['data'] : null;
    if (data is! List) {
      throw const AiServiceException(
        'Invalid models response',
        code: 'invalid_response',
      );
    }
    final ids = <String>[
      for (final item in data)
        if (item is Map && item['id'] is String) item['id'] as String,
    ]..sort();
    return ids;
  }

  /// Sends one completion request.
  ///
  /// [messages] use the OpenAI Chat Completions shape; assistant messages may
  /// carry provider extras (they are passed through untouched). With
  /// [stream] the answer is read as Server-Sent Events and [onDelta] receives
  /// progress; providers that reject streaming fall back to a plain request
  /// (remembered per model). [abortTrigger] cancels the HTTP request.
  Future<AiChatCompletion> sendChat({
    required String baseUrl,
    required String token,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Object? toolChoice,
    double? temperature = 0.3,
    String? reasoningEffort,
    AiApiStyle apiStyle = AiApiStyle.chatCompletions,
    bool stream = false,
    void Function(AiStreamDelta delta)? onDelta,
    Future<void>? abortTrigger,
    String? cacheKey,
    int? maxOutputTokens,
  }) async {
    final compatibility = _compatibilityFor(baseUrl, model);
    final responses = apiStyle == AiApiStyle.responses;
    final uri = Uri.parse(
      responses ? '$baseUrl/responses' : '$baseUrl/chat/completions',
    );
    var attempts = 0;
    var transientRetries = 0;
    while (true) {
      attempts++;
      final streaming = stream && !compatibility.streamUnsupported;
      final payload = responses
          ? _responsesPayload(
              model: model,
              messages: messages,
              tools: tools,
              toolChoice: toolChoice,
              temperature: temperature,
              reasoningEffort: reasoningEffort,
              compatibility: compatibility,
              stream: streaming,
              maxOutputTokens: maxOutputTokens,
              cacheKey: cacheKey,
              baseUrl: baseUrl,
            )
          : _chatPayload(
              model: model,
              messages: messages,
              tools: tools,
              toolChoice: toolChoice,
              temperature: temperature,
              reasoningEffort: reasoningEffort,
              compatibility: compatibility,
              stream: streaming,
              maxOutputTokens: maxOutputTokens,
              cacheKey: cacheKey,
              baseUrl: baseUrl,
            );
      final abort = Completer<void>();
      unawaited(
        abortTrigger?.then((_) {
          if (!abort.isCompleted) abort.complete();
        }),
      );
      final request =
          http.AbortableRequest('POST', uri, abortTrigger: abort.future)
            ..headers.addAll(_headers(token: token, stream: streaming))
            ..body = jsonEncode(payload);

      http.StreamedResponse res;
      try {
        res = await _client
            .send(request)
            .timeout(streaming ? firstByteTimeout : timeout);
      } on TimeoutException {
        if (!abort.isCompleted) abort.complete();
        // A request that already used the whole timeout is not repeated: the
        // provider may still be working on it (and billing it).
        throw AiServiceException(
          'The provider did not answer in time.',
          code: 'timeout',
          endpoint: uri.toString(),
          attemptCount: attempts,
          compatibilityAdjustments: compatibility.adjustments.toList(),
        );
      } on http.RequestAbortedException {
        throw _cancelled(uri);
      } on http.ClientException catch (error) {
        if (abortTrigger != null && abort.isCompleted) throw _cancelled(uri);
        if (transientRetries < _maxTransientRetries) {
          await _waitBeforeRetry(transientRetries++);
          continue;
        }
        throw AiServiceException(
          'Provider connection failed after $attempts attempts: '
          '${error.message}',
          code: 'connection_error',
          endpoint: uri.toString(),
          attemptCount: attempts,
          compatibilityAdjustments: compatibility.adjustments.toList(),
        );
      }

      if (res.statusCode >= 400) {
        final body = await _readBody(res, abort);
        final adjustment = res.statusCode == 401 || res.statusCode == 404
            ? null
            : _applyCompatibilityAdjustment(
                responseBody: body,
                sentPayload: payload,
                compatibility: compatibility,
              );
        if (adjustment != null) {
          await _persistCompatibility();
          continue;
        }
        final retryAfter = _retryAfter(res.headers);
        if (_isTransientStatus(res.statusCode) &&
            transientRetries < _maxTransientRetries &&
            (retryAfter == null || retryAfter <= _maxRetryAfter)) {
          await _delay(retryAfter ?? _backoff(transientRetries));
          transientRetries++;
          continue;
        }
        throw _httpException(
          statusCode: res.statusCode,
          body: body,
          headers: res.headers,
          uri: uri,
          attempts: attempts,
          adjustments: compatibility.adjustments.toList(),
        );
      }

      try {
        if (streaming) {
          return responses
              ? await _readResponsesStream(res, abort, onDelta, uri)
              : await _readChatStream(res, abort, onDelta, uri);
        }
        final body = await _readBody(res, abort).timeout(timeout);
        return responses ? _parseResponses(body) : _parseChat(body);
      } on http.RequestAbortedException {
        throw _cancelled(uri);
      } on http.ClientException catch (error) {
        if (abortTrigger != null && abort.isCompleted) throw _cancelled(uri);
        throw AiServiceException(
          'The connection dropped while reading the answer: ${error.message}',
          code: 'connection_error',
          endpoint: uri.toString(),
          attemptCount: attempts,
        );
      } on TimeoutException {
        if (!abort.isCompleted) abort.complete();
        throw AiServiceException(
          'The provider stopped sending data.',
          code: 'timeout',
          endpoint: uri.toString(),
          attemptCount: attempts,
        );
      }
    }
  }

  /// Sends a multimodal request (images in user content) for a one-off
  /// extraction such as reading a nutrition label.
  ///
  /// OpenCode serves its GPT models through the Responses API for images; the
  /// chat-completions shape is rejected there, so it is routed accordingly.
  Future<AiChatCompletion> sendVision({
    required String baseUrl,
    required String token,
    required String model,
    required List<Map<String, dynamic>> messages,
  }) => sendMultimodalChat(
    baseUrl: baseUrl,
    token: token,
    model: model,
    messages: messages,
  );

  /// Multimodal chat preserving tool calling. Maps a provider rejection of
  /// the image parts to `vision_not_supported`.
  Future<AiChatCompletion> sendMultimodalChat({
    required String baseUrl,
    required String token,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Object? toolChoice,
    String? reasoningEffort,
    AiApiStyle apiStyle = AiApiStyle.chatCompletions,
    bool stream = false,
    void Function(AiStreamDelta delta)? onDelta,
    Future<void>? abortTrigger,
    String? cacheKey,
  }) async {
    try {
      return await sendChat(
        baseUrl: baseUrl,
        token: token,
        model: model,
        messages: messages,
        tools: tools,
        toolChoice: toolChoice,
        reasoningEffort: reasoningEffort,
        apiStyle: usesResponsesApiForVision(baseUrl: baseUrl, model: model)
            ? AiApiStyle.responses
            : apiStyle,
        stream: stream,
        onDelta: onDelta,
        abortTrigger: abortTrigger,
        cacheKey: cacheKey,
      );
    } on AiServiceException catch (error) {
      if (error.code == 'bad_request' || error.code == 'invalid_response') {
        throw AiServiceException(
          'The provider rejected the multimodal request.',
          code: 'vision_not_supported',
          statusCode: error.statusCode,
          endpoint: error.endpoint,
        );
      }
      rethrow;
    }
  }

  /// OpenCode's chat-completions endpoint rejects image parts for GPT models.
  static bool usesResponsesApiForVision({
    required String baseUrl,
    required String model,
  }) {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    final isOpenCode = host == 'opencode.ai' || host.endsWith('.opencode.ai');
    return isOpenCode && model.toLowerCase().startsWith('gpt-');
  }

  /// Small connection test: one streamed request with a trivial tool the
  /// model must call. Reports what worked.
  Future<AiProbeResult> probe({
    required String baseUrl,
    required String token,
    required String model,
    AiApiStyle apiStyle = AiApiStyle.chatCompletions,
  }) async {
    final watch = Stopwatch()..start();
    try {
      final completion = await sendChat(
        baseUrl: baseUrl,
        token: token,
        model: model,
        apiStyle: apiStyle,
        stream: true,
        maxOutputTokens: 512,
        messages: const [
          {
            'role': 'system',
            'content':
                'Connection test. Call the tool `ping` with value 1, nothing else.',
          },
          {'role': 'user', 'content': 'ping'},
        ],
        tools: const [
          {
            'type': 'function',
            'function': {
              'name': 'ping',
              'description': 'Connection test tool.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'value': {'type': 'integer'},
                },
              },
            },
          },
        ],
      );
      final compatibility = _compatibilityFor(baseUrl, model);
      return AiProbeResult(
        ok: true,
        toolsSupported: completion.toolCalls.any((c) => c.name == 'ping'),
        streamingSupported: !compatibility.streamUnsupported,
        latencyMs: watch.elapsedMilliseconds,
      );
    } on AiServiceException catch (error) {
      return AiProbeResult(
        ok: false,
        latencyMs: watch.elapsedMilliseconds,
        errorCode: error.code,
        errorMessage: error.message,
      );
    }
  }

  // ===========================================================================
  // PAYLOADS
  // ===========================================================================

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

  /// Chat-completions `tool_choice` in the Responses shape (a forced
  /// function is `{type: function, name}` there).
  static Object _responsesToolChoice(Object choice) {
    if (choice is Map) {
      final function = choice['function'];
      if (choice['type'] == 'function' && function is Map) {
        return {'type': 'function', 'name': function['name']};
      }
    }
    return choice;
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

  static bool _isOpenAiHost(String baseUrl) {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    return host == 'api.openai.com';
  }

  static bool _wantsCacheControl(String baseUrl, String model) {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    if (host != 'openrouter.ai' && !host.endsWith('.openrouter.ai')) {
      return false;
    }
    final id = model.toLowerCase();
    return id.startsWith('anthropic/') || id.startsWith('google/');
  }

  // ===========================================================================
  // RESPONSES (non-streamed bodies)
  // ===========================================================================

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
            parsed.id.isEmpty
                ? parsed.withId('call_${calls.length + 1}')
                : parsed,
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
                'id':
                    item['call_id'] ?? item['id'] ?? 'call_${calls.length + 1}',
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
    );
  }

  /// Every assistant-message field besides the standard ones, kept opaque.
  static Map<String, dynamic> _messageExtras(Map<dynamic, dynamic> message) {
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

  static ({int? prompt, int? completion, int? cached}) _usage(Object? usage) {
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

  // ===========================================================================
  // STREAMING
  // ===========================================================================

  /// Server-Sent Events lines of [res], with the first-byte and idle timeouts.
  Stream<String> _sseData(http.StreamedResponse res) async* {
    final lines = res.stream
        .transform(
          _IdleTimeout<List<int>>(first: firstByteTimeout, idle: idleTimeout),
        )
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final data = StringBuffer();
    await for (final line in lines) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          yield data.toString();
          data.clear();
        }
        continue;
      }
      if (line.startsWith(':')) continue;
      if (line.startsWith('data:')) {
        final value = line.substring(5).trimLeft();
        if (data.isNotEmpty) data.write('\n');
        data.write(value);
      }
    }
    if (data.isNotEmpty) yield data.toString();
  }

  Future<AiChatCompletion> _readChatStream(
    http.StreamedResponse res,
    Completer<void> abort,
    void Function(AiStreamDelta)? onDelta,
    Uri uri,
  ) async {
    final text = StringBuffer();
    final extras = <String, dynamic>{};
    final reasoningText = StringBuffer();
    final reasoningContent = StringBuffer();
    final reasoningDetails = <int, Map<String, dynamic>>{};
    final calls = <int, _StreamedCall>{};
    String? finishReason;
    ({int? prompt, int? completion, int? cached}) usage = (
      prompt: null,
      completion: null,
      cached: null,
    );
    var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
    var lastNames = 0;

    Timer? trailing;
    void emit({bool force = false}) {
      if (onDelta == null) return;
      final now = DateTime.now();
      if (!force &&
          calls.length == lastNames &&
          now.difference(lastEmit) < const Duration(milliseconds: 60)) {
        // Throttled: make sure the latest text still shows if the stream
        // pauses right after this chunk.
        trailing ??= Timer(const Duration(milliseconds: 60), () {
          trailing = null;
          emit(force: true);
        });
        return;
      }
      trailing?.cancel();
      trailing = null;
      lastEmit = now;
      lastNames = calls.length;
      onDelta(
        AiStreamDelta(
          text: TextSanitizer.stripReasoning(text.toString()),
          reasoning:
              text.isEmpty &&
              (reasoningText.isNotEmpty || reasoningContent.isNotEmpty),
          toolNames: [
            for (final call in calls.values)
              if (call.name.isNotEmpty) call.name,
          ],
        ),
      );
    }

    try {
      await for (final data in _sseData(res)) {
        if (data == '[DONE]') break;
        final chunk = _decodeJson(data);
        if (chunk is! Map) continue;
        _throwEmbeddedError(chunk);
        if (chunk['usage'] != null) usage = _usage(chunk['usage']);
        final choices = chunk['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final choice = choices.first;
        if (choice is! Map) continue;
        finishReason = (choice['finish_reason'] as String?) ?? finishReason;
        final delta = choice['delta'];
        if (delta is! Map) continue;
        final content = delta['content'];
        if (content is String) text.write(content);
        final rc = delta['reasoning_content'];
        if (rc is String) reasoningContent.write(rc);
        final reasoning = delta['reasoning'];
        if (reasoning is String) reasoningText.write(reasoning);
        final details = delta['reasoning_details'];
        if (details is List) {
          for (final raw in details) {
            if (raw is! Map) continue;
            final index =
                (raw['index'] as num?)?.toInt() ?? reasoningDetails.length;
            final existing = reasoningDetails[index];
            reasoningDetails[index] = existing == null
                ? raw.cast<String, dynamic>()
                : _mergeStreamed(existing, raw.cast<String, dynamic>());
          }
        }
        for (final entry in delta.entries) {
          final key = '${entry.key}';
          if (const {
            'role',
            'content',
            'tool_calls',
            'reasoning_content',
            'reasoning',
            'reasoning_details',
            'refusal',
          }.contains(key)) {
            continue;
          }
          if (entry.value == null) continue;
          extras[key] = extras.containsKey(key) && entry.value is String
              ? '${extras[key]}${entry.value}'
              : entry.value;
        }
        final toolCalls = delta['tool_calls'];
        if (toolCalls is List) {
          for (final raw in toolCalls) {
            if (raw is! Map) continue;
            final index = (raw['index'] as num?)?.toInt() ?? calls.length;
            final call = calls.putIfAbsent(index, _StreamedCall.new);
            call.absorb(raw.cast<String, dynamic>());
          }
        }
        emit();
      }
    } on http.RequestAbortedException {
      rethrow;
    } finally {
      trailing?.cancel();
    }
    emit(force: true);

    if (reasoningContent.isNotEmpty) {
      extras['reasoning_content'] = reasoningContent.toString();
    }
    if (reasoningText.isNotEmpty) {
      extras['reasoning'] = reasoningText.toString();
    }
    if (reasoningDetails.isNotEmpty) {
      final keys = reasoningDetails.keys.toList()..sort();
      extras['reasoning_details'] = [for (final k in keys) reasoningDetails[k]];
    }
    final orderedCalls = (calls.keys.toList()..sort())
        .map((k) => calls[k]!)
        .toList();
    final parsedCalls = <AiToolCall>[];
    for (final call in orderedCalls) {
      if (call.name.isEmpty) continue;
      final parsed = AiToolCall.fromJson(call.toJson());
      parsedCalls.add(
        parsed.id.isEmpty
            ? parsed.withId('call_${parsedCalls.length + 1}')
            : parsed,
      );
    }
    final rawText = text.isEmpty ? null : text.toString();
    if (rawText == null && parsedCalls.isEmpty && finishReason == null) {
      throw AiServiceException(
        'The stream ended without an answer.',
        code: 'invalid_response',
        endpoint: uri.toString(),
      );
    }
    return _completion(
      rawText: rawText,
      calls: parsedCalls,
      extras: extras,
      usage: usage,
      finishReason: finishReason,
    );
  }

  Future<AiChatCompletion> _readResponsesStream(
    http.StreamedResponse res,
    Completer<void> abort,
    void Function(AiStreamDelta)? onDelta,
    Uri uri,
  ) async {
    final text = StringBuffer();
    final names = <String>[];
    Map<dynamic, dynamic>? completed;
    await for (final data in _sseData(res)) {
      if (data == '[DONE]') break;
      final event = _decodeJson(data);
      if (event is! Map) continue;
      _throwEmbeddedError(event);
      switch (event['type']) {
        case 'response.output_text.delta':
          final delta = event['delta'];
          if (delta is String) text.write(delta);
        case 'response.output_item.added':
          final item = event['item'];
          if (item is Map && item['type'] == 'function_call') {
            names.add('${item['name'] ?? ''}');
          }
        case 'response.reasoning_summary_text.delta':
        case 'response.reasoning_text.delta':
          onDelta?.call(
            AiStreamDelta(reasoning: text.isEmpty, toolNames: names),
          );
          continue;
        case 'response.completed':
        case 'response.incomplete':
          final response = event['response'];
          if (response is Map) completed = response;
        case 'response.failed':
          final response = event['response'];
          final error = response is Map ? response['error'] : null;
          throw AiServiceException(
            'The provider failed the response: '
            '${error is Map ? error['message'] : 'unknown error'}',
            code: 'bad_request',
            endpoint: uri.toString(),
          );
      }
      onDelta?.call(AiStreamDelta(text: text.toString(), toolNames: names));
    }
    if (completed == null) {
      throw AiServiceException(
        'The stream ended without a completed response.',
        code: 'invalid_response',
        endpoint: uri.toString(),
      );
    }
    return _completionFromResponsesBody(completed);
  }

  static Map<String, dynamic> _mergeStreamed(
    Map<String, dynamic> base,
    Map<String, dynamic> delta,
  ) {
    final merged = Map<String, dynamic>.from(base);
    for (final entry in delta.entries) {
      final previous = merged[entry.key];
      if (previous is String && entry.value is String && entry.key != 'type') {
        merged[entry.key] = previous + (entry.value as String);
      } else if (entry.value != null) {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  // ===========================================================================
  // ERRORS AND COMPATIBILITY
  // ===========================================================================

  Future<String> _readBody(http.StreamedResponse res, Completer<void> abort) =>
      res.stream.bytesToString();

  AiServiceException _cancelled(Uri uri) => AiServiceException(
    'Request cancelled.',
    code: 'cancelled',
    endpoint: uri.toString(),
  );

  static void _throwEmbeddedError(Map<dynamic, dynamic> body) {
    final error = body['error'];
    final choices = body['choices'];
    if (error == null || (choices is List && choices.isNotEmpty)) return;
    final message = error is Map ? '${error['message'] ?? error}' : '$error';
    final code = error is Map ? (error['code'] as Object?) : null;
    final status = code is num ? code.toInt() : null;
    throw AiServiceException(
      'Provider error: ${_truncate(message)}',
      code: status == 429
          ? 'rate_limited'
          : _looksLikeContextLength(message.toLowerCase())
          ? 'context_length_exceeded'
          : 'bad_request',
      statusCode: status,
    );
  }

  _ModelCompatibility _compatibilityFor(String baseUrl, String model) =>
      _modelCompatibility.putIfAbsent(
        _compatibilityKey(baseUrl, model),
        _ModelCompatibility.new,
      );

  String _compatibilityKey(String baseUrl, String model) {
    final uri = Uri.tryParse(baseUrl);
    final endpoint = uri == null
        ? baseUrl.trim().toLowerCase()
        : '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}'
              '${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
    return '$endpoint|${model.trim().toLowerCase()}';
  }

  Future<void> _persistCompatibility() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.save({
        for (final entry in _modelCompatibility.entries)
          if (entry.value.adjustments.isNotEmpty)
            entry.key: entry.value.toJson(),
      });
    } catch (error) {
      debugPrint('Saving AI compatibility flags failed: $error');
    }
  }

  static bool _rejects(String error, String parameter) =>
      error.contains(parameter) &&
      (error.contains('unsupported') ||
          error.contains('not supported') ||
          error.contains('unknown') ||
          error.contains('unrecognized') ||
          error.contains('not allowed') ||
          error.contains('extra inputs') ||
          error.contains('additional properties') ||
          error.contains('invalid') ||
          error.contains('does not support'));

  String? _applyCompatibilityAdjustment({
    required String responseBody,
    required Map<String, dynamic> sentPayload,
    required _ModelCompatibility compatibility,
  }) {
    final error = responseBody.toLowerCase();
    String? learn(bool condition, void Function() apply, String label) {
      if (!condition) return null;
      apply();
      return compatibility.record(label);
    }

    final mentionsReasoningEffort =
        error.contains('reasoning_effort') ||
        (error.contains('reasoning') && error.contains('effort'));
    final reasoningUnsupported =
        mentionsReasoningEffort &&
        (_rejects(error, 'reasoning') || _rejects(error, 'effort'));
    if (reasoningUnsupported &&
        (sentPayload.containsKey('reasoning_effort') ||
            sentPayload.containsKey('reasoning')) &&
        !compatibility.omitReasoningEffort) {
      return learn(
        true,
        () => compatibility.omitReasoningEffort = true,
        'reasoning_effort omitted',
      );
    }
    if (error.contains('temperature')) {
      final mustBeOne =
          RegExp(
            r'(only|must be|has to be|required|allowed|support(?:ed|s)?)\D{0,24}1(?:\.0+)?\b',
          ).hasMatch(error) ||
          RegExp(r'1(?:\.0+)?\D{0,24}(only|temperature)').hasMatch(error);
      if (mustBeOne &&
          sentPayload['temperature'] != 1 &&
          compatibility.temperatureOverride != 1) {
        return learn(
          true,
          () => compatibility.temperatureOverride = 1,
          'temperature=1',
        );
      }
      if (_rejects(error, 'temperature') &&
          sentPayload.containsKey('temperature') &&
          !compatibility.omitTemperature) {
        return learn(
          true,
          () => compatibility.omitTemperature = true,
          'temperature omitted',
        );
      }
    }
    if (sentPayload.containsKey('stream_options') &&
        error.contains('stream_options') &&
        !compatibility.omitStreamOptions) {
      return learn(
        true,
        () => compatibility.omitStreamOptions = true,
        'stream_options omitted',
      );
    }
    if (sentPayload['stream'] == true &&
        _rejects(error, 'stream') &&
        !compatibility.streamUnsupported) {
      return learn(
        true,
        () => compatibility.streamUnsupported = true,
        'streaming disabled',
      );
    }
    if (sentPayload.containsKey('prompt_cache_key') &&
        error.contains('prompt_cache_key')) {
      return learn(
        !compatibility.omitCacheKey,
        () => compatibility.omitCacheKey = true,
        'prompt_cache_key omitted',
      );
    }
    if (sentPayload.containsKey('cache_control') &&
        error.contains('cache_control')) {
      return learn(
        !compatibility.omitCacheControl,
        () => compatibility.omitCacheControl = true,
        'cache_control omitted',
      );
    }
    if ((sentPayload.containsKey('max_completion_tokens') ||
            sentPayload.containsKey('max_output_tokens')) &&
        (error.contains('max_completion_tokens') ||
            error.contains('max_output_tokens'))) {
      return learn(
        !compatibility.omitMaxTokens,
        () => compatibility.omitMaxTokens = true,
        'max tokens omitted',
      );
    }
    if (sentPayload.containsKey('include') && error.contains('include')) {
      return learn(
        !compatibility.omitReasoningInclude,
        () => compatibility.omitReasoningInclude = true,
        'reasoning include omitted',
      );
    }
    if (sentPayload.containsKey('tool_choice') &&
        _rejects(error, 'tool_choice') &&
        !compatibility.omitToolChoice) {
      return learn(
        true,
        () => compatibility.omitToolChoice = true,
        'tool_choice omitted',
      );
    }
    return null;
  }

  /// Whether the provider for [baseUrl]+[model] honours `tool_choice`.
  bool supportsToolChoice(String baseUrl, String model) =>
      !_compatibilityFor(baseUrl, model).omitToolChoice;

  static bool _looksLikeContextLength(String error) =>
      error.contains('context length') ||
      error.contains('context_length') ||
      error.contains('maximum context') ||
      error.contains('context window') ||
      error.contains('too many tokens') ||
      error.contains('prompt is too long') ||
      error.contains('reduce the length');

  AiServiceException _httpException({
    required int statusCode,
    required String body,
    required Map<String, String> headers,
    required Uri uri,
    required int attempts,
    required List<String> adjustments,
  }) {
    final detail = _errorDetail(body);
    final lower = body.toLowerCase();
    final code = switch (statusCode) {
      401 => 'invalid_token',
      402 => 'payment_required',
      403 => 'forbidden',
      404 => 'not_found',
      408 => 'timeout',
      413 => 'payload_too_large',
      429 => 'rate_limited',
      >= 500 => 'provider_unavailable',
      _ when _looksLikeContextLength(lower) => 'context_length_exceeded',
      _ => 'bad_request',
    };
    return AiServiceException(
      'Request failed ($statusCode) after $attempts attempt(s): $detail',
      code: code,
      statusCode: statusCode,
      endpoint: uri.toString(),
      attemptCount: attempts,
      retryAfter: _retryAfter(headers),
      compatibilityAdjustments: adjustments,
    );
  }

  static String _errorDetail(String body) {
    final decoded = _decodeJson(body);
    if (decoded is Map) {
      final error = decoded['error'];
      if (error is Map && error['message'] != null) {
        return _truncate('${error['message']}');
      }
      if (error is String) return _truncate(error);
      if (decoded['message'] != null) return _truncate('${decoded['message']}');
    }
    return _truncate(body);
  }

  static Duration? _retryAfter(Map<String, String> headers) {
    final raw = headers['retry-after'];
    if (raw == null) return null;
    final seconds = int.tryParse(raw.trim());
    if (seconds != null) return Duration(seconds: seconds);
    try {
      final date = HttpDateParser.parse(raw);
      final wait = date.difference(DateTime.now().toUtc());
      return wait.isNegative ? Duration.zero : wait;
    } on FormatException {
      return null;
    }
  }

  bool _isTransientStatus(int statusCode) =>
      statusCode == 429 ||
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504 ||
      statusCode == 529;

  Duration _backoff(int retryIndex) =>
      Duration(milliseconds: retryIndex == 0 ? 1000 : 3000);

  Future<void> _waitBeforeRetry(int retryIndex) => _delay(_backoff(retryIndex));

  Map<String, String> _headers({required String token, bool stream = false}) =>
      {
        // Local providers (e.g. Ollama) have no token; sending an empty
        // Bearer header can make some servers reject the request.
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Accept': stream ? 'text/event-stream' : 'application/json',
      };

  static Object? _decodeJson(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  String? _extractText(dynamic content) {
    if (content == null) return null;
    if (content is String) return content;
    if (content is List) {
      final buf = StringBuffer();
      for (final part in content) {
        if (part is Map && part['type'] == 'text' && part['text'] is String) {
          buf.write(part['text']);
        }
      }
      return buf.isEmpty ? null : buf.toString();
    }
    return null;
  }

  static String _truncate(String s) =>
      s.length > 300 ? '${s.substring(0, 300)}…' : s;

  static const int _maxTransientRetries = 2;

  /// Longer waits are reported to the user instead of blocking the turn.
  static const Duration _maxRetryAfter = Duration(seconds: 20);
}

/// Minimal RFC 7231 date parser for `Retry-After`.
abstract final class HttpDateParser {
  static const _months = {
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };

  static DateTime parse(String value) {
    final match = RegExp(
      r'(\d{1,2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(value);
    final month = match == null ? null : _months[match.group(2)!.toLowerCase()];
    if (match == null || month == null) {
      throw const FormatException('Not an HTTP date');
    }
    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
  }
}

/// A tool call being assembled from stream deltas.
class _StreamedCall {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();
  Map<String, dynamic> extras = {};

  void absorb(Map<String, dynamic> delta) {
    final deltaId = delta['id'];
    if (deltaId is String && deltaId.isNotEmpty) id = deltaId;
    final function = delta['function'];
    if (function is Map) {
      final deltaName = function['name'];
      if (deltaName is String && deltaName.isNotEmpty) name += deltaName;
      final args = function['arguments'];
      if (args is String) arguments.write(args);
    }
    for (final entry in delta.entries) {
      if (const {'id', 'type', 'function', 'index'}.contains(entry.key)) {
        continue;
      }
      if (entry.value == null) continue;
      final previous = extras[entry.key];
      extras[entry.key] = previous is Map && entry.value is Map
          ? {...previous, ...(entry.value as Map)}
          : entry.value;
    }
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': arguments.toString()},
    ...extras,
  };
}

/// Fails a byte stream that stays silent longer than [first] before the
/// first event or [idle] between two events.
class _IdleTimeout<T> extends StreamTransformerBase<T, T> {
  final Duration first;
  final Duration idle;
  const _IdleTimeout({required this.first, required this.idle});

  @override
  Stream<T> bind(Stream<T> stream) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;
    Timer? timer;
    var started = false;

    void arm() {
      timer?.cancel();
      timer = Timer(started ? idle : first, () {
        controller.addError(TimeoutException('stream idle'));
        unawaited(subscription?.cancel());
        unawaited(controller.close());
      });
    }

    controller = StreamController<T>(
      onListen: () {
        arm();
        subscription = stream.listen(
          (event) {
            started = true;
            arm();
            controller.add(event);
          },
          onError: controller.addError,
          onDone: () {
            timer?.cancel();
            unawaited(controller.close());
          },
          cancelOnError: true,
        );
      },
      onCancel: () async {
        timer?.cancel();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }
}

class _ModelCompatibility {
  double? temperatureOverride;
  bool omitTemperature = false;
  bool omitToolChoice = false;
  bool omitReasoningEffort = false;
  bool omitStreamOptions = false;
  bool streamUnsupported = false;
  bool omitCacheKey = false;
  bool omitCacheControl = false;
  bool omitMaxTokens = false;
  bool omitReasoningInclude = false;
  final Set<String> adjustments = {};

  _ModelCompatibility();

  factory _ModelCompatibility.fromJson(Map<String, dynamic> json) {
    final c = _ModelCompatibility()
      ..temperatureOverride = (json['temperatureOverride'] as num?)?.toDouble()
      ..omitTemperature = json['omitTemperature'] == true
      ..omitToolChoice = json['omitToolChoice'] == true
      ..omitReasoningEffort = json['omitReasoningEffort'] == true
      ..omitStreamOptions = json['omitStreamOptions'] == true
      ..streamUnsupported = json['streamUnsupported'] == true
      ..omitCacheKey = json['omitCacheKey'] == true
      ..omitCacheControl = json['omitCacheControl'] == true
      ..omitMaxTokens = json['omitMaxTokens'] == true
      ..omitReasoningInclude = json['omitReasoningInclude'] == true;
    final adjustments = json['adjustments'];
    if (adjustments is List) {
      c.adjustments.addAll(adjustments.whereType<String>());
    }
    return c;
  }

  Map<String, dynamic> toJson() => {
    if (temperatureOverride != null) 'temperatureOverride': temperatureOverride,
    'omitTemperature': omitTemperature,
    'omitToolChoice': omitToolChoice,
    'omitReasoningEffort': omitReasoningEffort,
    'omitStreamOptions': omitStreamOptions,
    'streamUnsupported': streamUnsupported,
    'omitCacheKey': omitCacheKey,
    'omitCacheControl': omitCacheControl,
    'omitMaxTokens': omitMaxTokens,
    'omitReasoningInclude': omitReasoningInclude,
    'adjustments': adjustments.toList(),
  };

  String record(String adjustment) {
    adjustments.add(adjustment);
    return adjustment;
  }
}
