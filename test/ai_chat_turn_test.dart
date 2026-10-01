import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/repositories/ai_memory_repository.dart';
import 'package:workout_notes/services/ai_context_service.dart';
import 'package:workout_notes/services/ai_memory_service.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/services/ai_tool_registry.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/state/ai_chat_service.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';

import 'support/test_db.dart';

/// End-to-end tests of the agent loop against a scripted OpenAI-compatible
/// provider that streams Server-Sent Events.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Provider provider;
  late AiChatService chat;
  late AiSettingsNotifier settings;

  Future<void> setUpChat({
    _Script? script,
    AiProposalService? proposals,
  }) async {
    await installTestDb();
    SharedPreferences.setMockInitialValues({
      'app_locale': 'pt',
      'ai_providers_v1': jsonEncode([
        {
          'id': 'p1',
          'name': 'Test',
          'baseUrl': 'https://provider.test/v1',
          'availableModels': ['m'],
          'selectedModel': 'm',
          'createdAt': '2026-01-01T00:00:00.000',
        },
      ]),
      'ai_active_provider_id_v1': 'p1',
      'ai_data_sharing_accepted_v1': true,
    });
    FlutterSecureStorage.setMockInitialValues({'ai_token:p1': 'secret'});
    provider = _Provider(script ?? (_) => _Reply.text('ok'));
    final service = AiService(client: provider, delay: (_) async {});
    settings = AiSettingsNotifier(
      prefs: await SharedPreferences.getInstance(),
      service: service,
    );
    await settings.load();
    chat = AiChatService.instance..reset();
    chat.overrideForTest(
      service: service,
      settings: settings,
      tools: _FakeRegistry(),
      proposals: proposals ?? _FakeProposals(),
      memory: AiMemoryService(repo: AiMemoryRepository()),
      context: _FakeContext(),
    );
  }

  tearDown(() async {
    AiChatService.instance.reset();
    await uninstallTestDb();
  });

  Future<void> idle() async {
    for (var i = 0; i < 2000 && chat.state.turn != null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(chat.state.turn, isNull, reason: 'turn did not finish');
  }

  Future<List<AiChatMessage>> stored(String threadId) async =>
      (await DatabaseHelper.instance.aiChatRepo.getAiChatMessagesAfter(
        threadId,
      )).map(AiChatMessage.fromRow).toList();

  test('streams the answer, persists the turn and lays out the wire', () async {
    await setUpChat(script: (_) => _Reply.text('Olá! Tudo certo.'));
    final drafts = <String>[];
    chat.addListener(() {
      final draft = chat.state.turn?.draftText;
      if (draft != null && draft.isNotEmpty) drafts.add(draft);
    });

    expect(await chat.send('Oi'), isTrue);
    await idle();

    final threadId = chat.state.activeThreadId!;
    final messages = await stored(threadId);
    expect(messages.map((m) => m.role), [
      AiMessageRole.user,
      AiMessageRole.assistant,
    ]);
    expect(messages.first.turnStatus, AiTurnStatus.done);
    expect(messages.last.content, 'Olá! Tudo certo.');
    expect(drafts, isNotEmpty);

    final payload = provider.payloads.single;
    expect(payload['stream'], isTrue);
    final wire = (payload['messages'] as List).cast<Map>();
    expect(wire.first['role'], 'system');
    expect(wire.first['content'], contains('Reply in Brazilian Portuguese'));
    final user = wire.last['content'] as String;
    expect(user, startsWith('<context>\ntoday: 2026-09-30'));
    expect(
      user,
      matches(RegExp(r'\[\d{4}-\d{2}-\d{2} \d{2}:\d{2} \w{3}\] Oi$')),
    );
    expect(payload['tools'], isNotEmpty);
    expect(payload, isNot(contains('tool_choice')));
  });

  test('runs tools in parallel, then answers with the results', () async {
    await setUpChat(
      script: (p) => _toolMessages(p).isEmpty
          ? _Reply.tools([
              _call('c1', 'get_sleep', {'days': 7}),
              _call('c2', 'get_nutrition', {'days': 7}),
            ])
          : _Reply.text('Dormiu bem e comeu bem.'),
    );
    await chat.send('Como foi minha semana?');
    await idle();

    final messages = await stored(chat.state.activeThreadId!);
    expect(messages.map((m) => m.role), [
      AiMessageRole.user,
      AiMessageRole.assistant,
      AiMessageRole.tool,
      AiMessageRole.tool,
      AiMessageRole.assistant,
    ]);
    expect(messages[2].toolName, 'get_sleep');
    expect((jsonDecode(messages[2].content!) as Map)['ok'], isTrue);
    final second = (provider.payloads[1]['messages'] as List).cast<Map>();
    expect(second.where((m) => m['role'] == 'tool'), hasLength(2));
  });

  test('a model that keeps calling tools ends with tool_choice none and the '
      'same tools', () async {
    await setUpChat(
      script: (p) => p['tool_choice'] == 'none'
          ? _Reply.text('Resposta final.')
          : _Reply.tools([
              _call('c${p.hashCode}', 'get_sleep', {'days': p.hashCode % 90}),
            ]),
    );
    await chat.send('Analise tudo');
    await idle();

    final last = provider.payloads.last;
    expect(last['tool_choice'], 'none');
    expect(last['tools'], provider.payloads.first['tools']);
    expect(provider.payloads.length, kMaxToolRounds + 1);
    final messages = await stored(chat.state.activeThreadId!);
    expect(messages.last.content, 'Resposta final.');
  });

  test('reasoning extras are echoed inside the turn and dropped after it; '
      'tool-call signatures are kept', () async {
    var turn = 0;
    await setUpChat(
      script: (p) {
        if (_toolMessages(p).isEmpty && turn == 0) {
          turn++;
          return _Reply.tools([
            _call(
              'c1',
              'get_sleep',
              {'days': 7},
              extras: {
                'extra_content': {
                  'google': {'thought_signature': 'sig-1'},
                },
              },
            ),
          ], reasoning: 'pensando no sono');
        }
        return _Reply.text('ok');
      },
    );
    await chat.send('Sono?');
    await idle();
    await chat.send('E agora?');
    await idle();

    Map assistantWithCalls(Map payload) => (payload['messages'] as List)
        .cast<Map>()
        .firstWhere((m) => m['role'] == 'assistant' && m['tool_calls'] != null);

    final sameTurn = assistantWithCalls(provider.payloads[1]);
    expect(sameTurn['reasoning_content'], 'pensando no sono');
    expect(
      ((sameTurn['tool_calls'] as List).first as Map)['extra_content'],
      containsPair('google', {'thought_signature': 'sig-1'}),
    );
    final nextTurn = assistantWithCalls(provider.payloads[2]);
    expect(nextTurn, isNot(contains('reasoning_content')));
    expect((nextTurn['tool_calls'] as List).first, contains('extra_content'));
  });

  test('history before the current message is byte-identical across turns '
      '(cache-friendly prefix)', () async {
    await setUpChat(script: (_) => _Reply.text('resposta'));
    await chat.send('primeira');
    await idle();
    await chat.send('segunda');
    await idle();
    await chat.send('terceira');
    await idle();

    final turn2 = (provider.payloads[1]['messages'] as List).cast<Map>();
    final turn3 = (provider.payloads[2]['messages'] as List).cast<Map>();
    // system + first exchange are identical; only the newest user message
    // (which carries the snapshot) differs.
    expect(
      jsonEncode(turn3.take(3).toList()),
      jsonEncode(turn2.take(3).toList()),
    );
    expect(turn3[3]['content'], isNot(contains('<context>')));
    expect(turn3.last['content'], contains('<context>'));
  });

  test(
    'switching conversations mid-turn keeps the turn in its own thread',
    () async {
      final gate = Completer<void>();
      await setUpChat(
        script: (_) => _Reply.text('resposta de A', gate: gate.future),
      );
      await chat.send('pergunta em A');
      final threadA = chat.state.activeThreadId!;
      await DatabaseHelper.instance.aiChatRepo.upsertAiChatThread(
        id: 'thread-b',
        title: 'B',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      await chat.openThread('thread-b');
      expect(chat.state.isBusyElsewhere, isTrue);
      gate.complete();
      await idle();

      expect((await stored(threadA)).map((m) => m.content), [
        'pergunta em A',
        'resposta de A',
      ]);
      expect(await stored('thread-b'), isEmpty);
      expect(chat.state.activeThreadId, 'thread-b');
      expect(chat.state.messages, isEmpty);
    },
  );

  test('cancel aborts the request and marks the turn cancelled', () async {
    await setUpChat(
      script: (_) => _Reply.text('nunca', gate: Completer<void>().future),
    );
    await chat.send('demora');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    chat.cancelTurn();
    await idle();

    final messages = await stored(chat.state.activeThreadId!);
    expect(messages.single.turnStatus, AiTurnStatus.cancelled);
    expect(provider.aborted, 1);
    expect(chat.state.error, isNull);
  });

  test('a second send while a turn runs is refused', () async {
    final gate = Completer<void>();
    await setUpChat(script: (_) => _Reply.text('ok', gate: gate.future));
    final first = chat.send('um');
    final second = chat.send('dois');
    expect(await first, isTrue);
    expect(await second, isFalse);
    gate.complete();
    await idle();
    expect(provider.payloads, hasLength(1));
  });

  test(
    'retry deletes what followed and answers the same message again',
    () async {
      var n = 0;
      await setUpChat(script: (_) => _Reply.text('resposta ${++n}'));
      await chat.send('pergunta');
      await idle();
      final threadId = chat.state.activeThreadId!;
      final user = (await stored(threadId)).first;

      await chat.retryTurn(user.id);
      await idle();

      final messages = await stored(threadId);
      expect(messages.map((m) => m.content), ['pergunta', 'resposta 2']);
      expect(messages.first.id, user.id);
      expect(chat.state.messages.map((m) => m.content), [
        'pergunta',
        'resposta 2',
      ]);
    },
  );

  test(
    'a provider failure keeps the user message and offers a retry',
    () async {
      await setUpChat(
        script: (_) => const _Reply.error(400, '{"error":{"message":"bad"}}'),
      );
      await chat.send('falha');
      await idle();
      final messages = await stored(chat.state.activeThreadId!);
      expect(messages.single.turnStatus, AiTurnStatus.failed);
      expect(chat.state.error, 'ai_error:bad_request');
      expect(chat.state.errorAction.name, 'retryTurn');
    },
  );

  test(
    'a running turn left behind by a killed app opens as interrupted',
    () async {
      await setUpChat();
      final repo = DatabaseHelper.instance.aiChatRepo;
      await repo.upsertAiChatThread(
        id: 'old',
        title: 'Old',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      await repo.upsertAiChatMessages('old', [
        AiChatMessage(
          id: 'u1',
          threadId: 'old',
          role: AiMessageRole.user,
          content: 'perdida',
          createdAt: DateTime(2026, 9, 1, 8),
          turnStatus: AiTurnStatus.running,
        ).toRow(),
      ]);
      await chat.openThread('old');
      expect(chat.state.messages.single.turnStatus, AiTurnStatus.interrupted);
      expect((await stored('old')).single.turnStatus, AiTurnStatus.interrupted);
    },
  );

  test(
    'compaction is hysteretic: one summary call, then a stable prefix',
    () async {
      var summaries = 0;
      await setUpChat(
        script: (p) {
          final system = ((p['messages'] as List).first as Map)['content'];
          if ('$system'.startsWith('You maintain the compact summary')) {
            summaries++;
            return _Reply.text(
              'Resumo: o usuário treina força.',
              stream: false,
            );
          }
          return _Reply.text('resposta curta');
        },
      );
      // A long conversation already stored.
      final repo = DatabaseHelper.instance.aiChatRepo;
      await repo.upsertAiChatThread(
        id: 't',
        title: 'Long',
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 1),
      );
      final rows = <Map<String, dynamic>>[];
      for (var i = 0; i < 40; i++) {
        rows
          ..add(
            AiChatMessage(
              id: 'u$i',
              threadId: 't',
              role: AiMessageRole.user,
              content: 'pergunta $i',
              createdAt: DateTime(2026, 9, 1, 8, i, 0),
              turnStatus: AiTurnStatus.done,
            ).toRow(),
          )
          ..add(
            AiChatMessage(
              id: 'a$i',
              threadId: 't',
              role: AiMessageRole.assistant,
              content: 'resposta longa ' * 400,
              createdAt: DateTime(2026, 9, 1, 8, i, 1),
            ).toRow(),
          );
      }
      await repo.upsertAiChatMessages('t', rows);
      await chat.openThread('t');

      await chat.send('nova pergunta');
      await idle();
      expect(summaries, 1);
      final summary = await repo.getAiChatThreadSummary('t');
      expect(summary?['summary'], contains('Resumo'));

      await chat.send('outra pergunta');
      await idle();
      expect(summaries, 1, reason: 'no new summary until the high-water mark');

      final turns = provider.payloads
          .where(
            (p) => !'${((p['messages'] as List).first as Map)['content']}'
                .startsWith('You maintain'),
          )
          .toList();
      final a = (turns[0]['messages'] as List).cast<Map>();
      final b = (turns[1]['messages'] as List).cast<Map>();
      expect(a.first['content'], contains('<conversation_summary>'));
      expect(
        jsonEncode(b.take(a.length - 1).toList()),
        jsonEncode(a.take(a.length - 1).toList()),
      );
    },
  );

  test('a context-length error folds history away and retries once', () async {
    var calls = 0;
    await setUpChat(
      script: (p) {
        final system = '${((p['messages'] as List).first as Map)['content']}';
        if (system.startsWith('You maintain')) {
          return _Reply.text('resumo', stream: false);
        }
        calls++;
        return calls == 1
            ? const _Reply.error(
                400,
                '{"error":{"message":"maximum context length exceeded"}}',
              )
            : _Reply.text('coube');
      },
    );
    final repo = DatabaseHelper.instance.aiChatRepo;
    await repo.upsertAiChatThread(
      id: 't',
      title: 'T',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    await repo.upsertAiChatMessages('t', [
      for (var i = 0; i < 4; i++) ...[
        AiChatMessage(
          id: 'u$i',
          threadId: 't',
          role: AiMessageRole.user,
          content: 'q$i',
          createdAt: DateTime(2026, 9, 1, 8, i),
        ).toRow(),
        AiChatMessage(
          id: 'a$i',
          threadId: 't',
          role: AiMessageRole.assistant,
          content: 'a$i',
          createdAt: DateTime(2026, 9, 1, 8, i, 30),
        ).toRow(),
      ],
    ]);
    await chat.openThread('t');
    await chat.send('pergunta');
    await idle();
    final messages = await stored('t');
    expect(messages.last.content, 'coube');
    expect(chat.state.error, isNull);
  });

  test('an empty answer gets one final nudge', () async {
    var n = 0;
    await setUpChat(
      script: (p) => ++n == 1 ? _Reply.text('') : _Reply.text('agora sim'),
    );
    await chat.send('oi');
    await idle();
    expect(provider.payloads.last['tool_choice'], 'none');
    expect(
      (await stored(chat.state.activeThreadId!)).last.content,
      'agora sim',
    );
  });

  test('save_memory applies at once and reaches the next request', () async {
    await setUpChat(
      script: (p) =>
          _toolMessages(p).isEmpty &&
              !'${((p['messages'] as List).first as Map)['content']}'.contains(
                '<memory>\n- [',
              )
          ? _Reply.tools([
              _call('m1', 'save_memory', {
                'content': 'Tem dor no ombro direito.',
                'category': 'health',
              }),
            ])
          : _Reply.text('Anotado.'),
    );
    await chat.send('Tenho dor no ombro direito, lembre disso');
    await idle();
    await chat.send('ok');
    await idle();

    final system =
        '${((provider.payloads.last['messages'] as List).first as Map)['content']}';
    expect(system, contains('<memory>'));
    expect(system, contains('Tem dor no ombro direito.'));

    // Undo from the chat removes it and tells the model.
    final toolMessage = chat.state.messages.firstWhere((m) => m.isTool);
    await chat.undoMemoryChange(toolMessage.id);
    final memory = AiMemoryService(repo: AiMemoryRepository());
    expect(await memory.all(), isEmpty);
    expect(chat.state.messages.last.role, AiMessageRole.event);
  });

  test('approving a proposal records an app event for the model', () async {
    final proposals = _FakeProposals();
    await setUpChat(
      proposals: proposals,
      script: (p) =>
          _toolMessages(p).isEmpty &&
              !jsonEncode(p['messages']).contains('<app_event>{')
          ? _Reply.tools([
              _call('p1', 'propose_body_measurement', {'weight': 80}),
            ])
          : _Reply.text('Prévia pronta.'),
    );
    await chat.send('Registre 80 kg');
    await idle();
    expect(chat.state.proposals.single.status, AiProposalStatus.awaiting);

    await chat.approveProposal('prop-1');
    expect(chat.state.proposals.single.status, AiProposalStatus.applied);
    final event = chat.state.messages.last;
    expect(event.role, AiMessageRole.event);
    expect((jsonDecode(event.content!) as Map)['status'], 'applied');

    await chat.send('feito?');
    await idle();
    expect(
      jsonEncode(provider.payloads.last['messages']),
      contains('<app_event>{'),
    );
  });

  test('consent is required before the first message', () async {
    await setUpChat();
    await settings.setDataSharingAccepted(false);
    expect(await chat.send('oi'), isFalse);
    expect(chat.state.error, 'ai_error:consent_required');
    expect(provider.payloads, isEmpty);
  });

  test('disabled domains leave the catalog', () async {
    await setUpChat();
    final all = chat.toolCatalogChars();
    await settings.setDomainEnabled(AiToolDomain.sleep, false);
    expect(chat.toolCatalogChars(), lessThan(all));
  });
}

// =============================================================================
// Scripted provider
// =============================================================================

typedef _Script = _Reply Function(Map<String, dynamic> payload);

List<Map> _toolMessages(Map<String, dynamic> payload) =>
    (payload['messages'] as List)
        .cast<Map>()
        .where((m) => m['role'] == 'tool')
        .toList();

Map<String, dynamic> _call(
  String id,
  String name,
  Map<String, dynamic> args, {
  Map<String, dynamic> extras = const {},
}) => {
  'id': id,
  'type': 'function',
  'function': {'name': name, 'arguments': jsonEncode(args)},
  ...extras,
};

class _Reply {
  final int status;
  final String? text;
  final List<Map<String, dynamic>> toolCalls;
  final String? reasoning;
  final String? errorBody;
  final Future<void>? gate;
  final bool stream;

  const _Reply._({
    this.status = 200,
    this.text,
    this.toolCalls = const [],
    this.reasoning,
    this.errorBody,
    this.gate,
    this.stream = true,
  });

  factory _Reply.text(String text, {Future<void>? gate, bool stream = true}) =>
      _Reply._(text: text, gate: gate, stream: stream);

  factory _Reply.tools(List<Map<String, dynamic>> calls, {String? reasoning}) =>
      _Reply._(toolCalls: calls, reasoning: reasoning);

  const _Reply.error(int status, String body)
    : this._(status: status, errorBody: body);
}

class _Provider extends http.BaseClient {
  final _Script script;
  final List<Map<String, dynamic>> payloads = [];
  int aborted = 0;

  _Provider(this.script);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = (request as http.Request).body;
    final payload = (jsonDecode(body) as Map).cast<String, dynamic>();
    payloads.add(payload);
    final reply = script(payload);
    final abort = request is http.Abortable
        ? (request as http.Abortable).abortTrigger
        : null;
    if (reply.gate != null) {
      var wasAborted = false;
      await Future.any([
        reply.gate!,
        if (abort != null) abort.then((_) => wasAborted = true),
      ]);
      if (wasAborted) {
        aborted++;
        throw http.RequestAbortedException(request.url);
      }
    }
    if (reply.errorBody != null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(reply.errorBody!)),
        reply.status,
      );
    }
    final streamed = payload['stream'] == true && reply.stream;
    final text = streamed ? _sse(reply) : _json(reply);
    return http.StreamedResponse(Stream.value(utf8.encode(text)), 200);
  }

  String _json(_Reply reply) => jsonEncode({
    'choices': [
      {
        'message': {
          'role': 'assistant',
          'content': reply.text,
          if (reply.reasoning != null) 'reasoning_content': reply.reasoning,
          if (reply.toolCalls.isNotEmpty) 'tool_calls': reply.toolCalls,
        },
        'finish_reason': reply.toolCalls.isEmpty ? 'stop' : 'tool_calls',
      },
    ],
    'usage': {'prompt_tokens': 100, 'completion_tokens': 10},
  });

  String _sse(_Reply reply) {
    final chunks = <Map<String, dynamic>>[];
    if (reply.reasoning != null) {
      chunks.add({
        'choices': [
          {
            'delta': {'reasoning_content': reply.reasoning},
          },
        ],
      });
    }
    final text = reply.text ?? '';
    for (var i = 0; i < text.length; i += 4) {
      chunks.add({
        'choices': [
          {
            'delta': {
              'content': text.substring(
                i,
                i + 4 > text.length ? text.length : i + 4,
              ),
            },
          },
        ],
      });
    }
    for (var i = 0; i < reply.toolCalls.length; i++) {
      chunks.add({
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {...reply.toolCalls[i], 'index': i},
              ],
            },
          },
        ],
      });
    }
    chunks.add({
      'choices': [
        {
          'delta': <String, dynamic>{},
          'finish_reason': reply.toolCalls.isEmpty ? 'stop' : 'tool_calls',
        },
      ],
      'usage': {
        'prompt_tokens': 100,
        'completion_tokens': 10,
        'prompt_tokens_details': {'cached_tokens': 80},
      },
    });
    return '${chunks.map((c) => 'data: ${jsonEncode(c)}\n\n').join()}'
        'data: [DONE]\n\n';
  }
}

// =============================================================================
// Collaborators
// =============================================================================

class _FakeRegistry extends AiToolRegistry {
  @override
  List<Map<String, dynamic>> readToolsSchema({Set<AiToolDomain>? domains}) => [
    for (final (name, domain) in const [
      ('get_sleep', AiToolDomain.sleep),
      ('get_nutrition', AiToolDomain.nutrition),
    ])
      if (domains == null || domains.contains(domain))
        AiToolSpec(
          name: name,
          description: 'Test tool $name.',
          domain: domain,
          properties: {
            'days': {'type': 'integer', 'description': 'Window.'},
          },
        ).schema,
  ];

  @override
  Future<AiToolResult> executeRead({
    required String toolName,
    required Map<String, dynamic> args,
  }) async =>
      AiToolResult(ok: true, data: {'tool': toolName, 'days': args['days']});
}

class _FakeContext extends AiContextService {
  @override
  Future<String> buildSnapshot({required Set<AiToolDomain> domains}) async =>
      'today: 2026-09-30 (Wednesday)';
}

class _FakeProposals extends AiProposalService {
  AiProposal? _proposal;

  @override
  List<AiToolSpec> toolSpecs() => [
    AiToolSpec(
      name: 'propose_body_measurement',
      description: 'Propose a measurement.',
      domain: AiToolDomain.body,
      proposal: true,
    ),
  ];

  @override
  bool handles(String toolName) => toolName == 'propose_body_measurement';

  @override
  Future<AiToolResult> prepare({
    required String threadId,
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> args,
  }) async {
    _proposal = AiProposal(
      id: 'prop-1',
      threadId: threadId,
      toolCallId: toolCallId,
      kind: 'body_measurement',
      payload: args,
      preview: const {},
      status: AiProposalStatus.awaiting,
      createdAt: DateTime(2026, 9, 30),
    );
    return const AiToolResult(
      ok: true,
      data: {'proposal_id': 'prop-1', 'status': 'awaiting'},
    );
  }

  @override
  Future<AiProposal?> get(String id) async => _proposal;

  @override
  Future<List<AiProposal>> forThread(String threadId) async => [?_proposal];

  @override
  AiProposalApplyMode applyModeOf(AiProposal proposal) =>
      AiProposalApplyMode.transactional;

  @override
  Future<AiProposal> approve(String id) async =>
      _proposal = _proposal!.copyWith(status: AiProposalStatus.applied);

  @override
  Future<AiProposal> reject(String id) async =>
      _proposal = _proposal!.copyWith(status: AiProposalStatus.rejected);

  @override
  Map<String, dynamic> outcomeFacts(AiProposal proposal) => {
    'proposal_id': proposal.id,
    'kind': proposal.kind,
    'status': proposal.status.storageValue,
  };
}
