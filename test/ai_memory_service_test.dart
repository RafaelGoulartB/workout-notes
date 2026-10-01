import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/ai_memory.dart';
import 'package:workout_notes/repositories/ai_memory_repository.dart';
import 'package:workout_notes/services/ai_memory_service.dart';

import 'support/test_db.dart';

void main() {
  late AiMemoryService memory;

  setUp(() async {
    await installTestDb();
    memory = AiMemoryService(repo: AiMemoryRepository());
    final repo = AiMemoryRepository();
    final at = DateTime(2026, 9, 1);
    for (final (id, content) in const [
      ('aaaaaaaa-1111-4000-8000-000000000001', 'Joelho esquerdo dolorido.'),
      ('aaaaaaab-2222-4000-8000-000000000002', 'Treina em casa.'),
    ]) {
      await repo.upsert(
        AiMemory(
          id: id,
          content: content,
          category: AiMemoryCategory.health,
          createdAt: at,
          updatedAt: at,
        ),
      );
    }
  });

  tearDown(uninstallTestDb);

  Future<Map<String, dynamic>> delete(String id) async => (await memory.execute(
    toolName: 'delete_memory',
    args: {'id': id},
  )).toMap();

  test('empty, short or ambiguous ids never match a memory', () async {
    for (final id in ['', '  ', '[]', 'aaaa', 'aaaaaaa']) {
      expect((await delete(id))['code'], 'not_found', reason: '"$id"');
    }
    expect(await memory.all(), hasLength(2));
  });

  test('the short id shown in <memory> and the full id both work', () async {
    expect((await delete('[aaaaaaab]'))['ok'], isTrue);
    expect(
      (await delete('aaaaaaaa-1111-4000-8000-000000000001'))['ok'],
      isTrue,
    );
    expect(await memory.all(), isEmpty);
  });

  test('replaces_id with a truncated id does not overwrite anything', () async {
    final result = await memory.execute(
      toolName: 'save_memory',
      args: {'content': 'Novo fato.', 'category': 'other', 'replaces_id': 'a'},
    );
    expect(result.toMap()['code'], 'not_found');
    expect((await memory.all()).map((m) => m.content), [
      'Joelho esquerdo dolorido.',
      'Treina em casa.',
    ]);
  });
}
