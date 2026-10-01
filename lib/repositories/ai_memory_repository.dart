import 'package:workout_notes/models/ai_memory.dart';
import 'package:workout_notes/repositories/base_repository.dart';

/// Long-term facts the AI Coach keeps about the user (`ai_memories`).
class AiMemoryRepository extends BaseRepository {
  Future<List<AiMemory>> getAll() async {
    final db = await this.db;
    final rows = await db.query(
      'ai_memories',
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(AiMemory.fromRow).toList();
  }

  Future<AiMemory?> getById(String id) async {
    final db = await this.db;
    final rows = await db.query(
      'ai_memories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : AiMemory.fromRow(rows.first);
  }

  Future<void> upsert(AiMemory memory) async {
    final db = await this.db;
    final updated = await db.update(
      'ai_memories',
      memory.toRow()..remove('id'),
      where: 'id = ?',
      whereArgs: [memory.id],
    );
    if (updated == 0) await db.insert('ai_memories', memory.toRow());
  }

  Future<bool> delete(String id) async {
    final db = await this.db;
    return await db.delete('ai_memories', where: 'id = ?', whereArgs: [id]) >
        0;
  }

  Future<void> deleteAll() async {
    final db = await this.db;
    await db.delete('ai_memories');
  }
}
