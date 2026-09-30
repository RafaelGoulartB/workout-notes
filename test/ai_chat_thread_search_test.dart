import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_chat_thread.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_routine_proposal.dart';
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

  test('saving the open thread reorders the loaded list in memory', () async {
    final repo = DatabaseHelper.instance.aiChatRepo;
    final base = DateTime.utc(2026, 3, 1);
    await repo.upsertAiChatThread(
      id: 'pinned',
      title: 'Pinned',
      createdAt: base,
      updatedAt: base,
      isPinned: true,
    );
    await repo.upsertAiChatThread(
      id: 'old',
      title: 'Old one',
      createdAt: base,
      updatedAt: base.add(const Duration(days: 1)),
    );
    await repo.upsertAiChatThread(
      id: 'other',
      title: 'Other',
      createdAt: base,
      updatedAt: base.add(const Duration(days: 2)),
    );
    final service = AiChatService.instance;
    await service.newChat();
    await service.refreshThreads();
    expect(service.state.threads.map((t) => t.id), ['pinned', 'other', 'old']);

    await service.openThread('old');
    await service.persistCurrentThreadForTest();

    expect(service.state.threads.map((t) => t.id), ['pinned', 'old', 'other']);
    expect(service.state.threads[1].title, 'Old one');
    expect((await repo.getAiChatThread('old'))!['title'], 'Old one');
    await service.newChat();
  });

  test('saving a thread outside the loaded pages keeps its title', () async {
    await seedThreads(130);
    final service = AiChatService.instance;
    await service.newChat();
    await service.refreshThreads();
    expect(service.state.threads.any((t) => t.id == 't0'), isFalse);

    await service.openThread('t0');
    await service.persistCurrentThreadForTest();

    expect(service.state.threads.first.id, 't0');
    expect(service.state.threads.first.title, 'Conversa 0');
    final repo = DatabaseHelper.instance.aiChatRepo;
    expect((await repo.getAiChatThread('t0'))!['title'], 'Conversa 0');
    await service.newChat();
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

  test('applied-proposal summary follows the app language', () {
    final proposal = AiRoutineProposal(
      id: 'p',
      threadId: 't',
      toolCallId: 'c',
      action: AiRoutineProposalAction.create,
      target: const {'name': 'Push'},
      diff: const {},
      status: AiRoutineProposalStatus.applied,
      createdAt: DateTime.utc(2026),
    );
    final en = appliedProposalEventPrompt(proposal, languageCode: 'en');
    final pt = appliedProposalEventPrompt(proposal, languageCode: 'pt');
    expect(en, contains('em inglês'));
    expect(en, isNot(contains('português brasileiro')));
    expect(pt, contains('em português brasileiro'));
    expect(en, contains('"routineName":"Push"'));
  });
}
