part of 'ai_service.dart';

/// Error mapping, retry timing and small request/response helpers.
extension AiServiceErrors on AiService {
  /// Reads at most [maxBytes] of the body (the rest is dropped and the
  /// connection closed); with [failWhenOver] a larger body is an error.
  Future<String> _readBody(
    http.StreamedResponse res, {
    required int maxBytes,
    bool failWhenOver = false,
  }) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in res.stream) {
      if (bytes.length + chunk.length > maxBytes) {
        if (failWhenOver) {
          throw AiServiceException(
            'The provider response is too large.',
            code: 'invalid_response',
            endpoint: res.request?.url.toString(),
          );
        }
        bytes.add(chunk.sublist(0, maxBytes - bytes.length));
        break;
      }
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  AiServiceException _cancelled(Uri uri) => AiServiceException(
    'Request cancelled.',
    code: 'cancelled',
    endpoint: uri.toString(),
  );

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
}

/// Whether [error] happened while connecting (refused, unreachable, DNS
/// failure), i.e. before any byte of the request left the device.
bool _failedBeforeSending(http.ClientException error) {
  if (error is! SocketException) return false;
  final socket = error as SocketException;
  final os = socket.osError;
  // ECONNREFUSED 111, ENETUNREACH 101, EHOSTUNREACH 113 (Linux/Android).
  if (os != null && const {111, 101, 113}.contains(os.errorCode)) return true;
  final text = '${socket.message} ${os?.message ?? ''}'.toLowerCase();
  return text.contains('failed host lookup') ||
      text.contains('connection refused') ||
      text.contains('network is unreachable') ||
      text.contains('no route to host');
}

void _throwEmbeddedError(Map<dynamic, dynamic> body) {
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

bool _looksLikeContextLength(String error) =>
    error.contains('context length') ||
    error.contains('context_length') ||
    error.contains('maximum context') ||
    error.contains('context window') ||
    error.contains('too many tokens') ||
    error.contains('prompt is too long') ||
    error.contains('reduce the length');

String _errorDetail(String body) {
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

Duration? _retryAfter(Map<String, String> headers) {
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

Object? _decodeJson(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException {
    return null;
  }
}

int _fallbackCallCounter = 0;

/// Id for a tool call the provider sent without one. Unique across
/// rounds, turns and launches: proposals and same-turn result reuse are
/// keyed by tool-call id, so `call_1` coming back every round would make a
/// new proposal reuse an old one and pair results with the wrong call.
String _fallbackCallId() =>
    'call_gen_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
    '_${(_fallbackCallCounter++).toRadixString(36)}';

String _truncate(String s) => s.length > 300 ? '${s.substring(0, 300)}…' : s;

const int _maxTransientRetries = 2;

/// Longer waits are reported to the user instead of blocking the turn.
const Duration _maxRetryAfter = Duration(seconds: 20);
