import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/utils/ai_endpoint_policy.dart';

typedef _Handler = Future<http.StreamedResponse> Function(int attempt);

class _Client extends http.BaseClient {
  final _Handler handler;
  int attempts = 0;

  _Client(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(attempts++);
}

/// A connect-phase failure, like `IOClient` raises for a refused connection.
class _SocketFailure extends http.ClientException implements SocketException {
  @override
  final OSError? osError;

  _SocketFailure(super.message, {this.osError});

  @override
  InternetAddress? get address => null;

  @override
  int? get port => null;
}

http.StreamedResponse _body(String text, {int status = 200}) =>
    http.StreamedResponse(Stream.value(utf8.encode(text)), status);

http.StreamedResponse _sse(List<Object> events) => http.StreamedResponse(
  Stream.value(
    utf8.encode(
      events.map((e) => 'data: ${e is String ? e : jsonEncode(e)}\n\n').join(),
    ),
  ),
  200,
);

Map<String, dynamic> _delta(String text, {String? finish}) => {
  'choices': [
    {
      'delta': {'content': text},
      'finish_reason': ?finish,
    },
  ],
};

Future<AiChatCompletion> _send(
  AiService service, {
  bool stream = true,
  AiApiStyle style = AiApiStyle.chatCompletions,
  String baseUrl = 'https://provider.test/v1',
}) => service.sendChat(
  baseUrl: baseUrl,
  token: 't',
  model: 'm',
  apiStyle: style,
  stream: stream,
  messages: const [
    {'role': 'user', 'content': 'oi'},
  ],
);

void main() {
  group('retrying a POST', () {
    test(
      'a drop after the request may have been sent is not repeated',
      () async {
        final client = _Client(
          (_) async => throw http.ClientException('reset'),
        );
        final service = AiService(client: client, delay: (_) async {});
        await expectLater(
          _send(service),
          throwsA(
            isA<AiServiceException>().having(
              (e) => e.code,
              'code',
              'connection_error',
            ),
          ),
        );
        expect(client.attempts, 1);
      },
    );

    test('a socket reset (not a connect failure) is not repeated', () async {
      final client = _Client(
        (_) async => throw _SocketFailure(
          'Connection reset by peer',
          osError: const OSError('Connection reset by peer', 104),
        ),
      );
      final service = AiService(client: client, delay: (_) async {});
      await expectLater(_send(service), throwsA(isA<AiServiceException>()));
      expect(client.attempts, 1);
    });

    test('a refused connection never reached the server: retried', () async {
      final client = _Client((attempt) async {
        if (attempt < 2) {
          throw _SocketFailure(
            'Connection failed',
            osError: const OSError('Connection refused', 111),
          );
        }
        return _body('{"choices":[{"message":{"content":"ok"}}]}');
      });
      final service = AiService(client: client, delay: (_) async {});
      final completion = await _send(service, stream: false);
      expect(completion.text, 'ok');
      expect(client.attempts, 3);
    });

    test('a DNS failure is retried, then reported', () async {
      final client = _Client(
        (_) async => throw _SocketFailure(
          "Failed host lookup: 'provider.test'",
          osError: const OSError('Name or service not known', -2),
        ),
      );
      final service = AiService(client: client, delay: (_) async {});
      await expectLater(
        _send(service),
        throwsA(
          isA<AiServiceException>().having(
            (e) => e.code,
            'code',
            'connection_error',
          ),
        ),
      );
      expect(client.attempts, 3);
    });
  });

  group('bounded buffers', () {
    test('an error body is read only up to 64 KB', () async {
      var delivered = 0;
      final client = _Client((_) async {
        Stream<List<int>> chunks() async* {
          for (var i = 0; i < 400; i++) {
            delivered += 1024;
            yield List.filled(1024, 120); // 'x'
          }
        }

        return http.StreamedResponse(chunks(), 400);
      });
      final service = AiService(client: client, delay: (_) async {});
      await expectLater(
        _send(service),
        throwsA(
          isA<AiServiceException>().having(
            (e) => e.code,
            'code',
            'bad_request',
          ),
        ),
      );
      expect(delivered, lessThan(AiService.maxErrorBodyBytes + 2048));
    });

    test('a runaway stream ends as truncated at the cap', () async {
      final client = _Client(
        (_) async => _sse([
          for (var i = 0; i < 50; i++) _delta('x' * 100),
          _delta('', finish: 'stop'),
          '[DONE]',
        ]),
      );
      final service = AiService(
        client: client,
        delay: (_) async {},
        maxStreamedChars: 1000,
      );
      final completion = await _send(service);
      expect(completion.truncated, isTrue);
      expect(completion.text!.length, lessThan(1500));
      expect(completion.text!.length, greaterThanOrEqualTo(1000));
    });

    test('a normal stream is not touched by the cap', () async {
      final client = _Client(
        (_) async => _sse([
          _delta('uma resposta '),
          _delta('inteira', finish: 'stop'),
          '[DONE]',
        ]),
      );
      final completion = await _send(AiService(client: client));
      expect(completion.text, 'uma resposta inteira');
      expect(completion.truncated, isFalse);
    });
  });

  group('truncated answers', () {
    test('finish_reason length / content_filter are truncated', () async {
      for (final reason in ['length', 'content_filter']) {
        final client = _Client(
          (_) async => _sse([_delta('meio', finish: reason), '[DONE]']),
        );
        final completion = await _send(AiService(client: client));
        expect(completion.text, 'meio');
        expect(completion.truncated, isTrue, reason: reason);
      }
    });

    test('a stream without finish reason or [DONE] is truncated', () async {
      final client = _Client((_) async => _sse([_delta('meio')]));
      final completion = await _send(AiService(client: client));
      expect(completion.text, 'meio');
      expect(completion.truncated, isTrue);
    });

    test('[DONE] without a finish reason is a complete answer', () async {
      final client = _Client((_) async => _sse([_delta('inteira'), '[DONE]']));
      final completion = await _send(AiService(client: client));
      expect(completion.truncated, isFalse);
    });

    test('a stop without [DONE] is a complete answer', () async {
      final client = _Client(
        (_) async => _sse([_delta('inteira', finish: 'stop')]),
      );
      final completion = await _send(AiService(client: client));
      expect(completion.truncated, isFalse);
    });

    test('a plain response cut by the output limit is truncated', () async {
      final client = _Client(
        (_) async => _body(
          '{"choices":[{"message":{"content":"meio"},"finish_reason":"length"}]}',
        ),
      );
      final completion = await _send(AiService(client: client), stream: false);
      expect(completion.truncated, isTrue);
    });

    test('a Responses stream with response.incomplete is truncated', () async {
      final client = _Client(
        (_) async => _sse([
          {'type': 'response.output_text.delta', 'delta': 'meio'},
          {
            'type': 'response.incomplete',
            'response': {
              'status': 'incomplete',
              'output': [
                {
                  'type': 'message',
                  'content': [
                    {'type': 'output_text', 'text': 'meio'},
                  ],
                },
              ],
            },
          },
        ]),
      );
      final completion = await _send(
        AiService(client: client),
        style: AiApiStyle.responses,
      );
      expect(completion.text, 'meio');
      expect(completion.truncated, isTrue);
    });

    test('a Responses stream that never completes keeps its text', () async {
      final client = _Client(
        (_) async => _sse([
          {'type': 'response.output_text.delta', 'delta': 'meio'},
        ]),
      );
      final completion = await _send(
        AiService(client: client),
        style: AiApiStyle.responses,
      );
      expect(completion.text, 'meio');
      expect(completion.truncated, isTrue);
    });

    test('a completed Responses stream is complete', () async {
      final client = _Client(
        (_) async => _sse([
          {'type': 'response.output_text.delta', 'delta': 'inteira'},
          {
            'type': 'response.completed',
            'response': {
              'status': 'completed',
              'output': [
                {
                  'type': 'message',
                  'content': [
                    {'type': 'output_text', 'text': 'inteira'},
                  ],
                },
              ],
            },
          },
        ]),
      );
      final completion = await _send(
        AiService(client: client),
        style: AiApiStyle.responses,
      );
      expect(completion.truncated, isFalse);
    });
  });

  group('endpoint policy', () {
    test('http only for local, private and link-local hosts', () {
      for (final url in [
        'http://localhost:11434/v1',
        'http://127.0.0.1:8080/v1',
        'http://127.5.5.5/v1',
        'http://10.0.2.2:11434/v1',
        'http://10.1.2.3/v1',
        'http://172.16.0.5/v1',
        'http://172.31.255.1/v1',
        'http://192.168.1.20:1234/v1',
        'http://169.254.10.10/v1',
        'http://[::1]:8080/v1',
        'http://[fd12:3456::1]/v1',
        'http://[fe80::1]/v1',
        'http://[::ffff:192.168.0.4]/v1',
        'http://mac-mini.local:11434/v1',
        'https://api.openai.com/v1',
      ]) {
        expect(AiEndpointPolicy.isAllowed(url), isTrue, reason: url);
      }
      for (final url in [
        'http://api.openai.com/v1',
        'http://10.evil.com/v1',
        'http://192.168.evil.com/v1',
        'http://172.32.0.1/v1',
        'http://172.15.0.1/v1',
        'http://8.8.8.8/v1',
        'http://169.255.0.1/v1',
        'http://[2001:db8::1]/v1',
        'http://localhost.evil.com/v1',
        'http://notlocal/v1',
        'ftp://localhost/v1',
        'localhost:11434',
        '',
      ]) {
        expect(AiEndpointPolicy.isAllowed(url), isFalse, reason: url);
      }
    });

    test('tokenless local endpoints use the same ranges', () {
      expect(AiEndpointPolicy.isLocalEndpoint('http://10.0.2.2:1/v1'), isTrue);
      expect(
        AiEndpointPolicy.isLocalEndpoint('http://10.evil.com/v1'),
        isFalse,
      );
      expect(
        AiEndpointPolicy.isLocalEndpoint('https://api.openai.com/v1'),
        isFalse,
      );
    });

    test(
      'the service refuses an insecure endpoint before any request',
      () async {
        final client = _Client((_) async => _body('{}'));
        final service = AiService(client: client);
        await expectLater(
          _send(service, baseUrl: 'http://api.example.com/v1'),
          throwsA(
            isA<AiServiceException>().having(
              (e) => e.code,
              'code',
              'insecure_endpoint',
            ),
          ),
        );
        await expectLater(
          service.listModels(baseUrl: 'http://api.example.com/v1', token: 't'),
          throwsA(isA<AiServiceException>()),
        );
        expect(client.attempts, 0);
      },
    );

    test('the service talks plain http to a LAN host', () async {
      final client = _Client(
        (_) async => _body('{"choices":[{"message":{"content":"ok"}}]}'),
      );
      final completion = await _send(
        AiService(client: client),
        stream: false,
        baseUrl: 'http://192.168.1.20:11434/v1',
      );
      expect(completion.text, 'ok');
    });
  });
}
