import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/utils/sql_helpers.dart';

/// Edits the `training_json` column of `phase_targets`.
///
/// Weekly periodization targets keep references to routines and running plans
/// inside that JSON, so deleting the referenced row has to rewrite the
/// targets that mention it (there is no foreign key to cascade).
abstract final class PhaseTargetTraining {
  /// Runs [edit] on the decoded `training_json` of every target whose JSON
  /// contains [mentions], and writes back the ones for which it returns `true`.
  ///
  /// Returns how many targets were rewritten. [db] should be the transaction
  /// of the delete that made the references dangling.
  static Future<int> rewriteMentioning(
    DatabaseExecutor db, {
    required String mentions,
    required bool Function(Map<String, dynamic> training) edit,
  }) async {
    final rows = await db.query(
      'phase_targets',
      columns: ['id', 'training_json'],
      where: "training_json LIKE ? ESCAPE '\\'",
      whereArgs: ['%${escapeLike(mentions)}%'],
    );
    var rewritten = 0;
    for (final row in rows) {
      final raw = row['training_json'] as String?;
      if (raw == null || raw.isEmpty) continue;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) continue;
      final training = Map<String, dynamic>.from(decoded);
      if (!edit(training)) continue;
      await db.update(
        'phase_targets',
        {'training_json': jsonEncode(training)},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      rewritten++;
    }
    return rewritten;
  }

  /// Removes [routineId] from `routine_id` / `routine_ids`.
  static Future<int> removeRoutine(DatabaseExecutor db, String routineId) =>
      rewriteMentioning(
        db,
        mentions: routineId,
        edit: (training) {
          var changed = false;
          final ids = training['routine_ids'];
          if (ids is List && ids.contains(routineId)) {
            final remaining = ids
                .whereType<String>()
                .where((id) => id != routineId)
                .toList();
            if (remaining.isEmpty) {
              training.remove('routine_ids');
            } else {
              training['routine_ids'] = remaining;
            }
            changed = true;
          }
          final remainingIds = training['routine_ids'];
          if (training['routine_id'] == routineId) {
            // The single-id key mirrors the first of the list.
            if (remainingIds is List && remainingIds.isNotEmpty) {
              training['routine_id'] = remainingIds.first;
            } else {
              training.remove('routine_id');
            }
            changed = true;
          }
          return changed;
        },
      );

  /// Removes [planId] from `run.run_plan_ids`.
  static Future<int> removeRunPlan(DatabaseExecutor db, String planId) =>
      rewriteMentioning(
        db,
        mentions: planId,
        edit: (training) {
          final run = training['run'];
          if (run is! Map) return false;
          final original = run['run_plan_ids'];
          if (original is! List || !original.contains(planId)) return false;
          final ids = original
              .whereType<String>()
              .where((id) => id != planId)
              .toList();
          final updatedRun = Map<String, dynamic>.from(run);
          if (ids.isEmpty) {
            updatedRun.remove('run_plan_ids');
          } else {
            updatedRun['run_plan_ids'] = ids;
          }
          training['run'] = updatedRun;
          return true;
        },
      );
}
