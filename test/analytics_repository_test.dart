import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/repositories/analytics_repository.dart';

import 'support/ai_test_db.dart';

Future<void> _workout(
  Database db,
  String id,
  String date, {
  bool finished = true,
  int? duration,
}) => db.insert('workouts', {
  'id': id,
  'date': date,
  'start_time': '${date}T10:00:00.000',
  'end_time': finished ? '${date}T11:00:00.000' : null,
  'duration_seconds': duration,
});

var _seq = 0;

Future<void> _sets(
  Database db,
  String workoutId,
  String exerciseId,
  List<(double, int, {bool done, bool warmup})> sets,
) async {
  final entryId = 'ee${_seq++}';
  await db.insert('exercise_entries', {
    'id': entryId,
    'workout_id': workoutId,
    'exercise_id': exerciseId,
    'order_index': 0,
  });
  for (final (i, s) in sets.indexed) {
    await db.insert('sets', {
      'id': 's${_seq++}',
      'exercise_entry_id': entryId,
      'weight': s.$1,
      'reps': s.$2,
      'is_complete': s.done ? 1 : 0,
      'is_warmup': s.warmup ? 1 : 0,
      'order_index': i,
    });
  }
}

(double, int, {bool done, bool warmup}) _set(
  double w,
  int r, {
  bool done = true,
  bool warmup = false,
}) => (w, r, done: done, warmup: warmup);

void main() {
  late Database db;
  final repo = AnalyticsRepository();

  setUp(() async {
    db = await installAiTestDb();
    await db.insert('exercise_categories', {
      'id': 'chest',
      'name': 'Chest',
      'color': 0xFF2196F3,
      'order_index': 0,
      'energy_system': 'anaerobic',
    });
    await db.insert('exercises', {
      'id': 'bench',
      'name': 'Bench',
      'category_id': 'chest',
    });
    await _workout(db, 'w1', '2026-09-01', duration: 3600);
    await _workout(db, 'w2', '2026-09-08', finished: false);
  });

  tearDown(uninstallAiTestDb);

  test(
    'history ignores planned sets, warm-ups and unfinished workouts',
    () async {
      await _sets(db, 'w1', 'bench', [
        _set(100, 1),
        _set(90, 8),
        _set(200, 10, done: false),
        _set(20, 15, warmup: true),
      ]);
      await _sets(db, 'w2', 'bench', [_set(150, 5)]);

      final data = await repo.getExerciseHistory('bench');
      final history = data['history'] as List;
      expect(history, hasLength(1));
      final session = history.single as Map<String, dynamic>;
      expect(session['total_sets'], 2);
      expect(session['max_weight'], 100.0);
      expect(session['total_volume'], 100 * 1 + 90 * 8);
      // 90 x 8 -> 114 beats the single at 100 (heaviest set).
      expect(session['estimated_1rm'], closeTo(114, 0.01));
      expect(data['best_1rm'], closeTo(114, 0.01));
      expect(data['best_weight'], 100.0);
      expect((session['best_set'] as Map)['reps'], 8);
    },
  );

  test('history keeps two workouts of the same day apart', () async {
    await _workout(db, 'w3', '2026-09-01');
    await _sets(db, 'w1', 'bench', [_set(80, 5)]);
    await _sets(db, 'w3', 'bench', [_set(85, 5)]);
    final data = await repo.getExerciseHistory('bench');
    expect(data['history'] as List, hasLength(2));
  });

  test(
    'overview counts finished workouts and completed sets only',
    () async {
      await _sets(db, 'w1', 'bench', [
        _set(100, 10),
        _set(50, 10, done: false),
      ]);
      await _sets(db, 'w2', 'bench', [_set(100, 10)]);

      final overview = await DatabaseHelper.instance.analyticsRepo
          .getWorkoutOverviewStats();
      expect(overview['total_workouts'], 1);
      expect(overview['total_sets'], 1);
    },
  );
}
