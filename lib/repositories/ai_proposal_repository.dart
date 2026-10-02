import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/repositories/base_repository.dart';

/// SQL behind `ai_proposals`. Every method that takes a [DatabaseExecutor]
/// can run inside the approval transaction; the status transitions are
/// compare-and-set (`WHERE status = ?`) so two concurrent approvals can never
/// both win.
class AiProposalRepository extends BaseRepository {
  Future<void> insert(AiProposal proposal, {DatabaseExecutor? executor}) async {
    final database = executor ?? await db;
    await database.insert('ai_proposals', proposal.toRow());
  }

  Future<AiProposal?> get(String id, {DatabaseExecutor? executor}) async {
    final database = executor ?? await db;
    final rows = await database.query(
      'ai_proposals',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : AiProposal.fromRow(rows.first);
  }

  /// Proposals of a conversation, oldest first.
  Future<List<AiProposal>> forThread(String threadId) async {
    final database = await db;
    final rows = await database.query(
      'ai_proposals',
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'created_at ASC, id ASC',
    );
    return [for (final row in rows) AiProposal.fromRow(row)];
  }

  /// The proposal a tool call already produced, if any (a retried call must
  /// not create a second card).
  Future<AiProposal?> byToolCall(String threadId, String toolCallId) async {
    final database = await db;
    final rows = await database.query(
      'ai_proposals',
      where: 'thread_id = ? AND tool_call_id = ?',
      whereArgs: [threadId, toolCallId],
      orderBy: 'created_at ASC',
      limit: 1,
    );
    return rows.isEmpty ? null : AiProposal.fromRow(rows.first);
  }

  /// Proposals of [kind] still awaiting an answer in a conversation.
  Future<List<AiProposal>> awaitingOfKind(String threadId, String kind) async {
    final database = await db;
    final rows = await database.query(
      'ai_proposals',
      where: 'thread_id = ? AND kind = ? AND status = ?',
      whereArgs: [threadId, kind, AiProposalStatus.awaiting.storageValue],
      orderBy: 'created_at ASC',
    );
    return [for (final row in rows) AiProposal.fromRow(row)];
  }

  /// Moves a proposal from [from] to [to]. Returns the number of rows
  /// changed: 0 means another actor already resolved it.
  Future<int> transition(
    DatabaseExecutor executor,
    String id, {
    required AiProposalStatus from,
    required AiProposalStatus to,
    required DateTime at,
    String? errorCode,
    Map<String, dynamic>? result,
  }) => executor.update(
    'ai_proposals',
    {
      'status': to.storageValue,
      'resolved_at': at.toIso8601String(),
      'error_code': errorCode,
      if (result != null) 'result_json': jsonEncode(result),
    },
    where: 'id = ? AND status = ?',
    whereArgs: [id, from.storageValue],
  );

  /// Stores the result of an applied proposal.
  Future<int> setResult(
    DatabaseExecutor executor,
    String id,
    Map<String, dynamic> result,
  ) => executor.update(
    'ai_proposals',
    {'result_json': jsonEncode(result)},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Replaces the stored preview (older proposals rebuilt by their handler).
  Future<void> updatePreview(
    String id,
    Map<String, dynamic> preview, {
    DatabaseExecutor? executor,
  }) async {
    final database = executor ?? await db;
    await database.update(
      'ai_proposals',
      {'preview_json': jsonEncode(preview)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Expires every proposal still awaiting an answer that was created before
  /// [cutoff]. Returns how many were expired.
  Future<int> expireAwaitingBefore(
    DateTime cutoff, {
    required DateTime now,
    DatabaseExecutor? executor,
  }) async {
    final database = executor ?? await db;
    return database.update(
      'ai_proposals',
      {
        'status': AiProposalStatus.expired.storageValue,
        'resolved_at': now.toIso8601String(),
        'error_code': 'expired',
      },
      where: 'status = ? AND created_at < ?',
      whereArgs: [
        AiProposalStatus.awaiting.storageValue,
        cutoff.toIso8601String(),
      ],
    );
  }
}
