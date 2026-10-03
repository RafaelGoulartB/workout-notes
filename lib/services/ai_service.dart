import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:typed_data' show BytesBuilder;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:workout_notes/models/ai_tool_call.dart';
import 'package:workout_notes/utils/ai_endpoint_policy.dart';
import 'package:workout_notes/utils/text_sanitizer.dart';

part 'ai_model_compatibility.dart';
part 'ai_service_errors.dart';
part 'ai_service_payloads.dart';
part 'ai_service_responses.dart';
part 'ai_service_streaming.dart';

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

  /// The answer was cut off: the provider hit its output limit
  /// (`finish_reason: length`), filtered the content, reported an incomplete
  /// response, or the stream ended without its terminal marker (or hit the
  /// local safety cap). The text is what arrived; it is never re-requested.
  final bool truncated;

  const AiChatCompletion({
    this.text,
    this.toolCalls = const [],
    this.hadReferencePlaceholders = false,
    this.promptTokens,
    this.completionTokens,
    this.cachedTokens,
    this.providerExtras = const {},
    this.finishReason,
    this.truncated = false,
  });
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

  /// Safety cap on the text (answer plus reasoning) of one streamed answer.
  /// Far above any real answer; a runaway stream ends as truncated instead of
  /// filling memory.
  final int maxStreamedChars;

  /// Longest error body read from a failed request.
  static const int maxErrorBodyBytes = 64 * 1024;

  /// Longest successful non-streamed body accepted.
  static const int maxResponseBodyBytes = 16 * 1024 * 1024;

  final Map<String, _ModelCompatibility> _modelCompatibility = {};

  AiCompatibilityStore? _store;

  AiService({
    http.Client? client,
    this.timeout = const Duration(seconds: 180),
    this.firstByteTimeout = const Duration(seconds: 180),
    this.idleTimeout = const Duration(seconds: 60),
    this.maxStreamedChars = 2000000,
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

  /// Throws `insecure_endpoint` unless [baseUrl] is `https`, or `http` on a
  /// local host ([AiEndpointPolicy]). Providers saved before this rule hit it
  /// at send time.
  static void requireAllowedEndpoint(String baseUrl) {
    if (AiEndpointPolicy.isAllowed(baseUrl)) return;
    throw AiServiceException(
      'Plain http:// is only allowed for local or private-network hosts; use '
      'https:// for this provider.',
      code: 'insecure_endpoint',
      endpoint: baseUrl,
    );
  }

  /// Fetches available models from `${baseUrl}/models`.
  Future<List<String>> listModels({
    required String baseUrl,
    required String token,
  }) async {
    requireAllowedEndpoint(baseUrl);
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
    requireAllowedEndpoint(baseUrl);
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
        // Repeating a POST is only safe when the request cannot have reached
        // the server (nothing connected). A drop after the request went out
        // may have started a billed generation: surface it instead.
        if (_failedBeforeSending(error) &&
            transientRetries < _maxTransientRetries) {
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
        final body = await _readBody(res, maxBytes: maxErrorBodyBytes);
        // Only a request the provider refused as invalid (400/422) teaches a
        // compatibility flag; outages and auth errors never do.
        final adjustment = res.statusCode != 400 && res.statusCode != 422
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
        final body = await _readBody(
          res,
          maxBytes: maxResponseBodyBytes,
          failWhenOver: true,
        ).timeout(timeout);
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

  /// Whether the provider for [baseUrl]+[model] honours `tool_choice`.
  bool supportsToolChoice(String baseUrl, String model) =>
      !_compatibilityFor(baseUrl, model).omitToolChoice;
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
