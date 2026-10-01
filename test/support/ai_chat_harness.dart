import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/repositories/ai_memory_repository.dart';
import 'package:workout_notes/services/ai_context_service.dart';
import 'package:workout_notes/services/ai_memory_service.dart';
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/services/ai_tool_registry.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/state/ai_chat_service.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';

import 'test_db.dart';

/// One scripted answer of the fake provider.
class AiReply {
  final int status;
  final String? text;
  final List<Map<String, dynamic>> toolCalls;
  final String? errorBody;

  /// Streamed answers: [text] is sent at once, then the response waits for
  /// this gate and sends [rest].
  final Future<void>? gate;
  final String rest;

  /// Held open after [rest] until this completes (a still-streaming answer).
  final Future<void>? finish;

  const AiReply._({
    this.status = 200,
    this.text,
    this.toolCalls = const [],
    this.errorBody,
    this.gate,
    this.rest = '',
    this.finish,
  });

  const AiReply.text(String text) : this._(text: text);

  const AiReply.tools(List<Map<String, dynamic>> calls)
    : this._(toolCalls: calls);

  const AiReply.error(int status, String body)
    : this._(status: status, errorBody: body);

  /// Sends [first], then holds the stream open until [gate] completes (or the
  /// request is aborted), then sends [rest].
  const AiReply.held(
    String first,
    Future<void> gate, {
    String rest = '',
    Future<void>? finish,
  }) : this._(text: first, gate: gate, rest: rest, finish: finish);
}

typedef AiScript = AiReply Function(Map<String, dynamic> payload);

Map<String, dynamic> aiWireCall(
  String id,
  String name,
  Map<String, dynamic> args,
) => {
  'id': id,
  'type': 'function',
  'function': {'name': name, 'arguments': jsonEncode(args)},
};

int aiToolMessageCount(Map<String, dynamic> payload) =>
    (payload['messages'] as List)
        .cast<Map>()
        .where((m) => m['role'] == 'tool')
        .length;

/// An OpenAI-compatible endpoint that answers from a script and streams
/// Server-Sent Events.
class AiScriptedProvider extends http.BaseClient {
  AiScript script;
  final List<Map<String, dynamic>> payloads = [];
  int aborted = 0;

  AiScriptedProvider(this.script);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final payload = (jsonDecode((request as http.Request).body) as Map)
        .cast<String, dynamic>();
    payloads.add(payload);
    final reply = script(payload);
    if (reply.errorBody != null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(reply.errorBody!)),
        reply.status,
      );
    }
    final controller = StreamController<List<int>>();
    unawaited(_feed(controller, reply, request as http.Abortable, request.url));
    return http.StreamedResponse(controller.stream, 200);
  }

  Future<void> _feed(
    StreamController<List<int>> out,
    AiReply reply,
    http.Abortable request,
    Uri url,
  ) async {
    void chunk(Map<String, dynamic> body) =>
        out.add(utf8.encode('data: ${jsonEncode(body)}\n\n'));
    Map<String, dynamic> delta(Map<String, dynamic> d, {String? finish}) => {
      'choices': [
        {'delta': d, 'finish_reason': ?finish},
      ],
    };

    if (reply.text case final text?) chunk(delta({'content': text}));
    if (reply.gate != null) {
      var wasAborted = false;
      final abort = request.abortTrigger;
      await Future.any([
        reply.gate!,
        if (abort != null) abort.then((_) => wasAborted = true),
      ]);
      if (wasAborted) {
        aborted++;
        out.addError(http.RequestAbortedException(url));
        await out.close();
        return;
      }
      if (reply.rest.isNotEmpty) chunk(delta({'content': reply.rest}));
      if (reply.finish != null) await reply.finish;
    }
    for (var i = 0; i < reply.toolCalls.length; i++) {
      chunk(
        delta({
          'tool_calls': [
            {...reply.toolCalls[i], 'index': i},
          ],
        }),
      );
    }
    chunk({
      ...delta(
        <String, dynamic>{},
        finish: reply.toolCalls.isEmpty ? 'stop' : 'tool_calls',
      ),
      'usage': {'prompt_tokens': 100, 'completion_tokens': 10},
    });
    out.add(utf8.encode('data: [DONE]\n\n'));
    await out.close();
  }
}

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

/// The real [AiChatService] wired to a scripted provider and an in-memory
/// database, for widget tests of the chat screen.
///
/// Everything that talks to SQLite or the provider needs real time: run it
/// through `tester.runAsync` and wait with [until].
class AiChatHarness {
  final AiSettingsNotifier settings;
  final AiScriptedProvider provider;
  final AiChatService chat;
  final AiMemoryService memory;

  AiChatHarness._(this.settings, this.provider, this.chat, this.memory);

  static Future<AiChatHarness> start({
    AiScript? script,
    bool consent = true,
    String locale = 'en',
    bool developerMode = false,
  }) async {
    await installTestDb();
    SharedPreferences.setMockInitialValues({
      'app_locale': locale,
      'ai_providers_v1': jsonEncode([
        {
          'id': 'p1',
          'name': 'TestAI',
          'baseUrl': 'https://provider.test/v1',
          'availableModels': ['m'],
          'selectedModel': 'm',
          'createdAt': '2026-01-01T00:00:00.000',
        },
      ]),
      'ai_active_provider_id_v1': 'p1',
      'ai_data_sharing_accepted_v1': consent,
      'ai_developer_mode_v1': developerMode,
    });
    FlutterSecureStorage.setMockInitialValues({'ai_token:p1': 'secret'});
    final provider = AiScriptedProvider(
      script ?? (_) => const AiReply.text('ok'),
    );
    final service = AiService(client: provider, delay: (_) async {});
    final settings = AiSettingsNotifier(
      prefs: await SharedPreferences.getInstance(),
      service: service,
    );
    await settings.load();
    WorkoutNotesApp.aiSettings = settings;
    final memory = AiMemoryService(repo: AiMemoryRepository());
    final chat = AiChatService.instance..reset();
    chat.overrideForTest(
      service: service,
      settings: settings,
      tools: _FakeRegistry(),
      memory: memory,
      context: _FakeContext(),
    );
    return AiChatHarness._(settings, provider, chat, memory);
  }

  Future<void> dispose() async {
    AiChatService.instance.reset();
    await uninstallTestDb();
  }

  /// Waits (real time) until [condition] holds.
  Future<void> until(bool Function() condition, {String? reason}) async {
    for (var i = 0; i < 1500 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(condition(), isTrue, reason: reason ?? 'condition not reached');
  }

  /// Waits until no turn runs.
  Future<void> idle() => until(() => chat.state.turn == null, reason: 'turn');

  /// Stores a conversation and returns nothing; open it with
  /// `chat.openThread(threadId)`.
  Future<void> seedThread(
    String threadId,
    List<AiChatMessage> messages, {
    String title = 'Seeded',
  }) async {
    final repo = DatabaseHelper.instance.aiChatRepo;
    await repo.upsertAiChatThread(
      id: threadId,
      title: title,
      createdAt: messages.first.createdAt,
      updatedAt: messages.last.createdAt,
    );
    await repo.upsertAiChatMessages(threadId, [
      for (final message in messages) message.toRow(),
    ]);
  }
}
