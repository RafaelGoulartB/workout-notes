import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';

/// Shared seed data for the AI proposal tests.
abstract final class AiProposalFixtures {
  static const threadId = 'thread_1';

  static String get now => DateTime.now().toIso8601String();

  /// A conversation plus the exercise library the routine tests use:
  /// `bench` and `squat` (weight/reps), `run` (distance/time).
  static Future<void> seedThreadAndExercises(Database db) async {
    await seedThread(db);
    await db.insert('exercise_categories', {
      'id': 'chest',
      'name': 'Chest',
      'color': 1,
      'order_index': 0,
      'energy_system': 'anaerobic',
    });
    for (final (id, name, type) in [
      ('bench', 'Bench press', 'weightReps'),
      ('squat', 'Squat', 'weightReps'),
      ('run', 'Run', 'distanceTime'),
      ('plank', 'Plank', 'timeOnly'),
    ]) {
      await db.insert('exercises', {
        'id': id,
        'name': name,
        'category_id': 'chest',
        'type': type,
        'is_favorite': 0,
        'created_at': now,
      });
    }
  }

  static Future<void> seedThread(Database db, {String id = threadId}) async {
    await db.insert('ai_chat_threads', {
      'id': id,
      'title': 'Test',
      'created_at': now,
      'updated_at': now,
    });
  }
}

/// Prepares a proposal and returns its id, failing the test when the call was
/// refused.
Future<String> prepareProposal(
  AiProposalService service,
  String toolName,
  Map<String, dynamic> args, {
  String threadId = AiProposalFixtures.threadId,
  String toolCallId = 'call_1',
}) async {
  final result = await service.prepare(
    threadId: threadId,
    toolCallId: toolCallId,
    toolName: toolName,
    args: args,
  );
  if (!result.ok) {
    throw StateError('prepare failed: ${result.toMap()}');
  }
  return (result.data as Map)['proposal_id'] as String;
}

extension AiProposalStatusX on AiProposal {
  String get statusName => status.storageValue;
}

/// Reads a nested JSON value by path: `dig(preview, 'items.0.calories')`.
/// Map keys and list indexes are separated by dots; null when absent.
Object? dig(Object? root, String path) {
  Object? current = root;
  for (final part in path.split('.')) {
    if (current is Map) {
      current = current[part];
    } else if (current is List) {
      final index = int.tryParse(part);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
  }
  return current;
}

/// The `code` of every warning in a preview's `warnings` list.
List<Object?> codes(Object? warnings) => [
  for (final warning in (warnings as List? ?? const []))
    if (warning is Map) warning['code'],
];
