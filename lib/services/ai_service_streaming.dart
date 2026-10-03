part of 'ai_service.dart';

/// Server-Sent Events reading for both protocols.
extension AiServiceStreaming on AiService {
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
    var sawDone = false;
    var capped = false;
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
        if (data == '[DONE]') {
          sawDone = true;
          break;
        }
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
        if (text.length + reasoningContent.length + reasoningText.length >
            maxStreamedChars) {
          // Runaway stream: stop reading (cancelling the subscription closes
          // the connection) and end the answer as truncated.
          capped = true;
          break;
        }
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
        parsed.id.isEmpty ? parsed.withId(_fallbackCallId()) : parsed,
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
      // Calls of a stream cut by the safety cap are most likely incomplete.
      calls: capped ? const [] : parsedCalls,
      extras: extras,
      usage: usage,
      finishReason: finishReason,
      // Neither a finish reason nor [DONE]: the connection ended mid-answer.
      truncated: capped || (finishReason == null && !sawDone),
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
    var capped = false;
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
      if (text.length > maxStreamedChars) {
        capped = true;
        break;
      }
    }
    if (completed == null || capped) {
      // No terminal event: what arrived is the (cut off) answer. Tool calls
      // are not rebuilt from a partial stream.
      if (text.isEmpty) {
        throw AiServiceException(
          'The stream ended without a completed response.',
          code: 'invalid_response',
          endpoint: uri.toString(),
        );
      }
      return _completion(
        rawText: text.toString(),
        calls: const [],
        extras: const {},
        usage: (prompt: null, completion: null, cached: null),
        truncated: true,
      );
    }
    return _completionFromResponsesBody(completed);
  }
}

Map<String, dynamic> _mergeStreamed(
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
