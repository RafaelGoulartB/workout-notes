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
import 'package:workout_notes/models/ai_tool_call.dart';
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
    String? utilityModel,
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
          'utilityModel': ?utilityModel,
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

  test('reasoning extras and tool-call signatures are echoed inside the turn '
      'and dropped after it', () async {
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
    expect(
      (nextTurn['tool_calls'] as List).first,
      isNot(contains('extra_content')),
    );
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
    'compaction is hysteretic: one compaction, then a stable prefix',
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
      // The dropped range is long, so it is folded in successive chunks.
      expect(summaries, greaterThanOrEqualTo(1));
      final afterCompaction = summaries;
      final summary = await repo.getAiChatThreadSummary('t');
      expect(summary?['summary'], contains('Resumo'));

      await chat.send('outra pergunta');
      await idle();
      expect(
        summaries,
        afterCompaction,
        reason: 'no new summary until the high-water mark',
      );

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

  test('stubbing old tool results without a summary cut is saved, so the '
      'next turn sends the same prefix', () async {
    var summaries = 0;
    await setUpChat(
      script: (p) {
        final system = '${((p['messages'] as List).first as Map)['content']}';
        if (system.startsWith('You maintain')) {
          summaries++;
          return _Reply.text('resumo', stream: false);
        }
        return _Reply.text('ok');
      },
    );
    final repo = DatabaseHelper.instance.aiChatRepo;
    await repo.upsertAiChatThread(
      id: 't',
      title: 'T',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    final big = '{"ok":true,"data":{"t":"${'x' * 11500}"}}';
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < 4; i++) {
      final at = DateTime(2026, 9, 1, 8, i);
      rows.addAll([
        AiChatMessage(
          id: 'u$i',
          threadId: 't',
          role: AiMessageRole.user,
          content: 'q$i',
          createdAt: at,
        ).toRow(),
        AiChatMessage(
          id: 'a$i',
          threadId: 't',
          role: AiMessageRole.assistant,
          toolCalls: [
            AiToolCall(id: 'c${i}a', name: 'get_sleep', arguments: const {}),
            AiToolCall(
              id: 'c${i}b',
              name: 'get_nutrition',
              arguments: const {},
            ),
          ],
          createdAt: at.add(const Duration(seconds: 1)),
        ).toRow(),
        for (final suffix in ['a', 'b'])
          AiChatMessage(
            id: 'r$i$suffix',
            threadId: 't',
            role: AiMessageRole.tool,
            toolCallId: 'c$i$suffix',
            toolName: 'get_sleep',
            content: big,
            createdAt: at.add(const Duration(seconds: 2)),
          ).toRow(),
        AiChatMessage(
          id: 'f$i',
          threadId: 't',
          role: AiMessageRole.assistant,
          content: 'a$i',
          createdAt: at.add(const Duration(seconds: 3)),
        ).toRow(),
      ]);
    }
    await repo.upsertAiChatMessages('t', rows);
    await chat.openThread('t');

    await chat.send('nova');
    await idle();
    expect(summaries, 0, reason: 'stubs alone were enough');
    final saved = await repo.getAiChatThreadSummary('t');
    expect(saved?['through_message_id'], '');
    expect(saved?['tools_through_message_id'], isNotNull);

    await chat.send('outra');
    await idle();
    final a = (provider.payloads[0]['messages'] as List).cast<Map>();
    final b = (provider.payloads[1]['messages'] as List).cast<Map>();
    expect(
      jsonEncode(b.take(a.length - 1).toList()),
      jsonEncode(a.take(a.length - 1).toList()),
    );
    final stubs = a.where(
      (m) => m['role'] == 'tool' && '${m['content']}'.contains('omitted'),
    );
    expect(stubs, isNotEmpty);
  });

  /// A conversation of [turns] user/assistant pairs (`u<i>`, `a<i>`), each
  /// answer long enough that the whole thread is far over the history budget.
  Future<void> seedLongThread(int turns, {String id = 't'}) async {
    final repo = DatabaseHelper.instance.aiChatRepo;
    await repo.upsertAiChatThread(
      id: id,
      title: 'Long',
      createdAt: DateTime(2026, 9, 1),
      updatedAt: DateTime(2026, 9, 1),
    );
    await repo.upsertAiChatMessages(id, [
      for (var i = 0; i < turns; i++) ...[
        AiChatMessage(
          id: 'u$i',
          threadId: id,
          role: AiMessageRole.user,
          content: 'pergunta $i',
          createdAt: DateTime(2026, 9, 1, 8, i, 0),
          turnStatus: AiTurnStatus.done,
        ).toRow(),
        AiChatMessage(
          id: 'a$i',
          threadId: id,
          role: AiMessageRole.assistant,
          content: 'resposta longa ' * 400,
          createdAt: DateTime(2026, 9, 1, 8, i, 1),
        ).toRow(),
      ],
    ]);
    await chat.openThread(id);
  }

  String? summaryInput(Map<String, dynamic> payload) {
    final messages = (payload['messages'] as List).cast<Map>();
    if (!'${messages.first['content']}'.startsWith('You maintain')) return null;
    return '${messages.last['content']}';
  }

  test(
    'a long dropped range is folded in chunks, nothing is cut unread',
    () async {
      final inputs = <String>[];
      await setUpChat(
        script: (p) {
          final input = summaryInput(p);
          if (input == null) return _Reply.text('ok');
          inputs.add(input);
          return _Reply.text('Resumo ${inputs.length}', stream: false);
        },
      );
      await seedLongThread(40);

      await chat.send('nova pergunta');
      await idle();

      expect(inputs.length, greaterThan(1), reason: 'more than one chunk');
      expect(inputs.first, isNot(contains('Current summary')));
      for (var i = 1; i < inputs.length; i++) {
        expect(inputs[i], startsWith('Current summary:\nResumo $i\n'));
      }
      final allInput = inputs.join('\n');
      expect(allInput, contains('User: pergunta 0\n'));
      final saved = await DatabaseHelper.instance.aiChatRepo
          .getAiChatThreadSummary('t');
      expect(saved?['summary'], 'Resumo ${inputs.length}');
      // Every question before the cut went through some chunk.
      final cutIndex = int.parse(
        (saved?['through_message_id'] as String).substring(1),
      );
      for (var i = 0; i <= cutIndex; i++) {
        expect(allInput, contains('User: pergunta $i\n'));
      }
      expect(allInput, isNot(contains('omitted for length')));
    },
  );

  test('a failed summary keeps the full history and moves no cut', () async {
    await setUpChat(
      script: (p) => summaryInput(p) != null
          ? const _Reply.error(400, '{"error":{"message":"boom"}}')
          : _Reply.text('ok'),
    );
    await seedLongThread(40);
    final repo = DatabaseHelper.instance.aiChatRepo;
    await repo.upsertAiChatMessages('t', [
      AiChatMessage(
        id: 'tool-old',
        threadId: 't',
        role: AiMessageRole.tool,
        toolCallId: 'x',
        toolName: 'get_sleep',
        content: '{"ok":true,"data":{"t":"${'y' * 3000}"}}',
        createdAt: DateTime(2026, 9, 1, 8, 0, 2),
      ).toRow(),
    ]);

    await chat.send('nova pergunta');
    await idle();

    // The answer was still requested, with the whole history in it.
    final turn = provider.payloads.where((p) => summaryInput(p) == null).last;
    final wire = jsonEncode(turn['messages']);
    expect(wire, contains('pergunta 0'));
    expect(wire, contains('pergunta 39'));
    expect(wire, isNot(contains('could not be summarized')));
    expect(wire, isNot(contains('<conversation_summary>')));
    expect(chat.state.messages.last.content, 'ok');
    // No cut, nothing archived.
    expect(await repo.getAiChatThreadSummary('t'), isNull);
    final tool = await repo.getAiChatMessage('tool-old');
    expect(tool?['content'], contains('yyyy'));
  });

  test('a failing utility model falls back to the chat model', () async {
    final models = <String>[];
    await setUpChat(
      utilityModel: 'u',
      script: (p) {
        if (summaryInput(p) == null) return _Reply.text('ok');
        models.add('${p['model']}');
        return p['model'] == 'u'
            ? const _Reply.error(404, '{"error":{"message":"no model"}}')
            : _Reply.text('Resumo', stream: false);
      },
    );
    await seedLongThread(40);

    await chat.send('nova pergunta');
    await idle();

    expect(models.take(2), ['u', 'm']);
    final saved = await DatabaseHelper.instance.aiChatRepo
        .getAiChatThreadSummary('t');
    expect(saved?['summary'], startsWith('Resumo'));
  });

  test('a partial summary moves the cut only past the folded turns', () async {
    var calls = 0;
    await setUpChat(
      script: (p) {
        if (summaryInput(p) == null) return _Reply.text('ok');
        calls++;
        return calls == 1
            ? _Reply.text('Resumo parcial', stream: false)
            : const _Reply.error(400, '{"error":{"message":"boom"}}');
      },
    );
    await seedLongThread(40);

    await chat.send('nova pergunta');
    await idle();

    final repo = DatabaseHelper.instance.aiChatRepo;
    final saved = await repo.getAiChatThreadSummary('t');
    final cut = saved?['through_message_id'] as String;
    expect(cut, startsWith('a'), reason: 'a turn boundary');
    expect(saved?['summary'], 'Resumo parcial');
    final cutIndex = int.parse(cut.substring(1));
    // Turns after the cut that no summary covers are still sent.
    final turn = provider.payloads.where((p) => summaryInput(p) == null).last;
    final wire = jsonEncode(turn['messages']);
    expect(wire, contains('Resumo parcial'));
    expect(wire, isNot(contains('pergunta $cutIndex"')));
    expect(wire, contains('pergunta ${cutIndex + 1}'));
    expect(wire, contains('pergunta 39'));
  });

  for (final (label, reply) in [
    ('the output limit', _Reply.text('Resposta curta', finishReason: 'length')),
    (
      'a content filter',
      _Reply.text('Resposta curta', finishReason: 'content_filter'),
    ),
    ('a stream without its end', _Reply.text('Resposta curta', cutOff: true)),
  ]) {
    test(
      'an answer cut by $label is kept, flagged, not re-requested',
      () async {
        await setUpChat(script: (_) => reply);
        await chat.send('pergunta');
        await idle();

        expect(provider.payloads, hasLength(1), reason: 'no automatic re-POST');
        final answer = chat.state.messages.last;
        expect(answer.content, 'Resposta curta');
        expect(answer.isCutOff, isTrue);
        expect(
          (await stored(chat.state.activeThreadId!)).last.isCutOff,
          isTrue,
        );
        expect(chat.state.messages.first.turnStatus, AiTurnStatus.done);
      },
    );
  }

  test('the cut-off flag is app-side: never sent to a provider', () async {
    var first = true;
    await setUpChat(
      script: (_) {
        final reply = first
            ? _Reply.text('Pela metade', finishReason: 'length')
            : _Reply.text('ok');
        first = false;
        return reply;
      },
    );
    await chat.send('pergunta');
    await idle();
    await chat.send('e agora?');
    await idle();
    final wire = jsonEncode(provider.payloads.last['messages']);
    expect(wire, contains('Pela metade'));
    expect(wire, isNot(contains(kAiCutOffExtra)));
  });

  test('a complete answer is not flagged', () async {
    await setUpChat(script: (_) => _Reply.text('Inteira'));
    await chat.send('pergunta');
    await idle();
    expect(chat.state.messages.last.isCutOff, isFalse);
  });

  test('retry is refused when the turn holds an approved proposal', () async {
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
    final threadId = chat.state.activeThreadId!;
    await chat.approveProposal('prop-1');
    final before = await stored(threadId);
    final user = before.first;
    final requests = provider.payloads.length;

    await chat.retryTurn(user.id);

    expect(chat.state.error, 'ai_error:retry_resolved_proposal');
    expect(chat.state.turn, isNull);
    expect(provider.payloads.length, requests, reason: 'nothing was sent');
    expect(
      (await stored(threadId)).map((m) => m.id),
      before.map((m) => m.id),
      reason: 'messages, tool results and the outcome event all stay',
    );
    expect(chat.state.proposals.single.status, AiProposalStatus.applied);
  });

  test('retry still works while the proposal awaits approval', () async {
    final proposals = _FakeProposals();
    var n = 0;
    await setUpChat(
      proposals: proposals,
      script: (p) {
        n++;
        return _toolMessages(p).isEmpty && n < 3
            ? _Reply.tools([
                _call('p$n', 'propose_body_measurement', {'weight': 80}),
              ])
            : _Reply.text('Prévia pronta.');
      },
    );
    await chat.send('Registre 80 kg');
    await idle();
    final user = (await stored(chat.state.activeThreadId!)).first;

    await chat.retryTurn(user.id);
    await idle();

    expect(chat.state.error, isNull);
    expect(chat.state.messages.first.id, user.id);
  });

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

  test('a failed proposal is final: no retry offered, approving again adds '
      'no duplicate event', () async {
    final proposals = _FakeProposals()..approveTo = AiProposalStatus.failed;
    await setUpChat(
      proposals: proposals,
      script: (p) => _toolMessages(p).isEmpty
          ? _Reply.tools([
              _call('p1', 'propose_body_measurement', {'weight': 80}),
            ])
          : _Reply.text('Prévia pronta.'),
    );
    await chat.send('Registre 80 kg');
    await idle();

    await chat.approveProposal('prop-1');
    expect(chat.state.proposals.single.status, AiProposalStatus.failed);
    expect(chat.state.error, 'ai_error:proposal_apply_failed');
    expect(chat.state.errorAction.name, 'none');

    await chat.approveProposal('prop-1');
    await chat.rejectProposal('prop-1');
    final events = chat.state.messages.where((m) => m.isEvent).toList();
    expect(events, hasLength(1));
  });

  test('consent is required before the first message', () async {
    await setUpChat();
    await settings.setDataSharingAccepted(false);
    expect(await chat.send('oi'), isFalse);
    expect(chat.state.error, 'ai_error:consent_required');
    expect(provider.payloads, isEmpty);
  });

  test('repeated or missing tool-call ids are made unique, so results and '
      'proposals never pair with an older call', () async {
    var round = 0;
    await setUpChat(
      script: (p) {
        round++;
        if (round <= 3) {
          // A server that reuses "call_0" every round.
          return _Reply.tools([
            _call('call_0', 'get_sleep', {'days': round}),
          ]);
        }
        if (round == 4) return _Reply.text('ok');
        // Next turn: a server that sends no id at all.
        if (round <= 6) {
          return _Reply.tools([
            {
              ..._call('', 'get_sleep', {'days': 10 + round}),
            }..remove('id'),
          ]);
        }
        return _Reply.text('ok');
      },
    );
    await chat.send('um');
    await idle();
    await chat.send('dois');
    await idle();

    final messages = await stored(chat.state.activeThreadId!);
    final ids = [
      for (final m in messages)
        for (final c in m.toolCalls) c.id,
    ];
    expect(ids, hasLength(5));
    expect(ids.toSet(), hasLength(5), reason: 'ids: $ids');
    // Each result belongs to its own call (days 1, 2, 3, 15, 16).
    final days = [
      for (final m in messages)
        if (m.isTool) ((jsonDecode(m.content!) as Map)['data'] as Map)['days'],
    ];
    expect(days, [1, 2, 3, 15, 16]);
    for (final m in messages.where((m) => m.isTool)) {
      expect(ids, contains(m.toolCallId));
    }
  });

  test('a switched-off domain cannot be read or proposed by calling its tool '
      'by name', () async {
    _FakeRegistry.executed.clear();
    final proposals = _FakeProposals();
    await setUpChat(
      proposals: proposals,
      script: (p) => _toolMessages(p).isEmpty
          ? _Reply.tools([
              _call('s1', 'get_sleep', {'days': 7}),
              _call('n1', 'get_nutrition', {'days': 7}),
              _call('b1', 'propose_body_measurement', {'weight': 80}),
            ])
          : _Reply.text('ok'),
    );
    await settings.setDomainEnabled(AiToolDomain.sleep, false);
    await settings.setDomainEnabled(AiToolDomain.body, false);
    await chat.send('Como dormi? E registre 80 kg');
    await idle();

    expect(_FakeRegistry.executed, ['get_nutrition']);
    expect(chat.state.proposals, isEmpty);
    final results = {
      for (final m in await stored(chat.state.activeThreadId!))
        if (m.isTool) m.toolName: jsonDecode(m.content!) as Map,
    };
    expect(results['get_sleep']!['code'], 'tool_not_available');
    expect(results['propose_body_measurement']!['code'], 'tool_not_available');
    expect(results['get_nutrition']!['ok'], isTrue);
    final tools = [
      for (final t in provider.payloads.first['tools'] as List)
        ((t as Map)['function'] as Map)['name'],
    ];
    expect(tools, isNot(contains('get_sleep')));
    expect(tools, isNot(contains('propose_body_measurement')));
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

  /// Finish reason reported instead of `stop` (`length`, `content_filter`).
  final String? finishReason;

  /// The stream ends right after the text: no finish reason and no `[DONE]`.
  final bool cutOff;

  const _Reply._({
    this.status = 200,
    this.text,
    this.toolCalls = const [],
    this.reasoning,
    this.errorBody,
    this.gate,
    this.stream = true,
    this.finishReason,
    this.cutOff = false,
  });

  factory _Reply.text(
    String text, {
    Future<void>? gate,
    bool stream = true,
    String? finishReason,
    bool cutOff = false,
  }) => _Reply._(
    text: text,
    gate: gate,
    stream: stream,
    finishReason: finishReason,
    cutOff: cutOff,
  );

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
        'finish_reason':
            reply.finishReason ??
            (reply.toolCalls.isEmpty ? 'stop' : 'tool_calls'),
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
    if (reply.cutOff) {
      return chunks.map((c) => 'data: ${jsonEncode(c)}\n\n').join();
    }
    chunks.add({
      'choices': [
        {
          'delta': <String, dynamic>{},
          'finish_reason':
              reply.finishReason ??
              (reply.toolCalls.isEmpty ? 'stop' : 'tool_calls'),
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
  static final List<String> executed = [];

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
  }) async {
    executed.add(toolName);
    return AiToolResult(
      ok: true,
      data: {'tool': toolName, 'days': args['days']},
    );
  }
}

class _FakeContext extends AiContextService {
  @override
  Future<String> buildSnapshot({required Set<AiToolDomain> domains}) async =>
      'today: 2026-09-30 (Wednesday)';
}

class _FakeProposals extends AiProposalService {
  AiProposal? _proposal;
  AiProposalStatus approveTo = AiProposalStatus.applied;

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
  Future<AiProposal> approve(String id) async {
    if (!_proposal!.isPending) return _proposal!;
    return _proposal = _proposal!.copyWith(
      status: approveTo,
      errorCode: approveTo == AiProposalStatus.failed ? 'apply_failed' : null,
    );
  }

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
