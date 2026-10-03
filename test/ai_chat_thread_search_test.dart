import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_chat_thread.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/state/ai_chat_service.dart';

import 'support/ai_test_db.dart';

void main() {
  setUp(installAiTestDb);
  tearDown(uninstallAiTestDb);

  Future<void> seedThreads(int count) async {
    final repo = DatabaseHelper.instance.aiChatRepo;
    final base = DateTime.utc(2026, 1, 1);
    for (var i = 0; i < count; i++) {
      await repo.upsertAiChatThread(
        id: 't$i',
        title: 'Conversa $i',
        createdAt: base,
        updatedAt: base.add(Duration(minutes: i)),
      );
    }
  }

  test('search finds a thread beyond the first page by title', () async {
    await seedThreads(130);
    final service = AiChatService.instance;
    await service.refreshThreads();

    // t0 is the oldest: it is outside the first loaded page of 100.
    expect(service.state.threads.any((t) => t.id == 't0'), isFalse);
    expect(service.state.totalThreadCount, 130);

    final page = await service.searchThreads('Conversa 0');
    expect(page.threads.map((t) => t.id), contains('t0'));
    expect(page.total, page.threads.length);
  });

  test('search matches message text and pages its results', () async {
    await seedThreads(120);
    final repo = DatabaseHelper.instance.aiChatRepo;
    await repo.upsertAiChatMessages('t1', [
      AiChatMessage(
        id: 'm1',
        threadId: 't1',
        role: AiMessageRole.user,
        content: 'Quanto de creatina devo tomar?',
        createdAt: DateTime.utc(2026, 1, 1),
      ).toRow(),
    ]);
    await repo.upsertAiChatMessages('t2', [
      AiChatMessage(
        id: 'm2',
        threadId: 't2',
        role: AiMessageRole.tool,
        content: '{"note":"creatina in a tool payload"}',
        createdAt: DateTime.utc(2026, 1, 1),
      ).toRow(),
    ]);

    final service = AiChatService.instance;
    final byMessage = await service.searchThreads('CREATINA');
    expect(byMessage.threads.map((t) => t.id), ['t1']);

    final first = await service.searchThreads('Conversa', limit: 50);
    expect(first.threads, hasLength(50));
    expect(first.hasMore, isTrue);
    expect(first.total, 120);
    final second = await service.searchThreads(
      'Conversa',
      offset: 50,
      limit: 50,
    );
    expect(second.threads.first.id, isNot(first.threads.first.id));
    expect(second.total, isNull);
    final ids = {...first.threads, ...second.threads}.map((t) => t.id);
    expect(ids, hasLength(100));
  });

  test('search is literal for LIKE wildcards and keeps pinned first', () async {
    final repo = DatabaseHelper.instance.aiChatRepo;
    final base = DateTime.utc(2026, 2, 1);
    await repo.upsertAiChatThread(
      id: 'a',
      title: '100% focus',
      createdAt: base,
      updatedAt: base,
    );
    await repo.upsertAiChatThread(
      id: 'b',
      title: '1000 focus',
      createdAt: base,
      updatedAt: base.add(const Duration(days: 1)),
    );
    await repo.upsertAiChatThread(
      id: 'c',
      title: 'under_score 100% x',
      createdAt: base,
      updatedAt: base.subtract(const Duration(days: 1)),
      isPinned: true,
    );

    final rows = await repo.searchAiChatThreadsPage(query: '100%', limit: 10);
    expect(rows.map((r) => r['id']), ['c', 'a']);
    final underscore = await repo.searchAiChatThreadsPage(
      query: '_score',
      limit: 10,
    );
    expect(underscore.single['id'], 'c');
    expect(await repo.countAiChatThreads(query: '100%'), 2);
    expect(await repo.countAiChatThreads(), 3);
    expect(
      await repo.searchAiChatThreadsPage(query: "x' OR 1=1 --", limit: 10),
      isEmpty,
    );
  });

  test('search is case- and accent-insensitive', () async {
    final repo = DatabaseHelper.instance.aiChatRepo;
    final base = DateTime.utc(2026, 3, 1);
    await repo.upsertAiChatThread(
      id: 'a',
      title: 'Plano de AÇÃO',
      createdAt: base,
      updatedAt: base,
    );
    await repo.upsertAiChatThread(
      id: 'b',
      title: 'Outra',
      createdAt: base,
      updatedAt: base,
    );
    await repo.upsertAiChatMessages('b', [
      AiChatMessage(
        id: 'm',
        threadId: 'b',
        role: AiMessageRole.assistant,
        content: 'Sua recuperação está ótima',
        createdAt: base,
      ).toRow(),
    ]);
    final service = AiChatService.instance;
    expect(
      (await service.searchThreads('plano de acao')).threads.map((t) => t.id),
      ['a'],
    );
    expect(
      (await service.searchThreads('RECUPERACAO')).threads.map((t) => t.id),
      ['b'],
    );
  });

  test('untitled threads are recognised without changing written titles', () {
    AiChatThread thread(String title) => AiChatThread(
      id: 'x',
      title: title,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    expect(thread(AiChatThread.genericTitle).hasGenericTitle, isTrue);
    expect(thread('Nova conversa').hasGenericTitle, isTrue);
    expect(thread('Conversa').hasGenericTitle, isTrue);
    expect(thread('Minha conversa sobre treino').hasGenericTitle, isFalse);
    expect(thread('Leg day').displayTitle('New conversation'), 'Leg day');
    expect(thread('').displayTitle('New conversation'), 'New conversation');
  });
}
