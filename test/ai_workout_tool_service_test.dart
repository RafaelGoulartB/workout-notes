import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/services/ai_tool_registry.dart';
import 'package:workout_notes/services/ai_workout_tool_service.dart';

import 'support/ai_test_db.dart';

void main() {
  late Database db;
  late AiWorkoutToolService service;

  setUp(() async {
    db = await installAiTestDb();
    service = AiWorkoutToolService();
    await _seedExercises(db);
  });

  tearDown(uninstallAiTestDb);

  test('history is paginated and distinguishes every workout status', () async {
    await _workout(db, 'done', '2026-08-10', status: 'completed');
    await _workout(db, 'active', '2026-08-11', status: 'in_progress');
    await _workout(db, 'planned', '2026-08-12', status: 'planned');

    final first = await service.history(page: 1, pageSize: 2);
    expect((first['pagination'] as Map)['totalItems'], 3);
    expect((first['pagination'] as Map)['hasMore'], isTrue);
    expect((first['workouts'] as List).map((row) => (row as Map)['status']), [
      'planned',
      'in_progress',
    ]);

    final completed = await service.history(status: 'completed');
    expect(completed['workouts'], hasLength(1));
    expect(((completed['workouts'] as List).single as Map)['id'], 'done');
  });

  test(
    'workout detail preserves metadata but totals only performed sets',
    () async {
      await _workout(db, 'detail', '2026-08-10', status: 'completed');
      await db.insert('exercise_entries', {
        'id': 'entry',
        'workout_id': 'detail',
        'exercise_id': 'bench',
        'order_index': 0,
        'superset_group_id': 'super-a',
        'notes': 'Controle a descida',
        'rest_time_seconds': 90,
      });
      await _set(db, 'performed', 'entry', weight: 50, reps: 10, rpe: 8);
      await _set(db, 'warmup', 'entry', weight: 20, reps: 20, warmup: true);
      await _set(
        db,
        'pending',
        'entry',
        weight: 100,
        reps: 10,
        complete: false,
      );

      final detail = (await service.workoutDetail('detail'))!;
      final totals = detail['performedTotals'] as Map;
      expect(detail['status'], 'completed');
      expect(totals['completedSets'], 1);
      expect(totals['volumeKg'], 500);
      expect(totals['averageRpe'], 8);
      final exercise = (detail['exercises'] as List).single as Map;
      expect(exercise['exerciseName'], 'Supino');
      expect(exercise['equipment'], 'Barra');
      expect(exercise['notes'], 'Controle a descida');
      expect(exercise['supersetGroupId'], 'super-a');
      expect(exercise['sets'], hasLength(3));
    },
  );

  test(
    'exercise profile, history and records cover strength and cardio',
    () async {
      await _workout(db, 'same-day-a', '2026-08-10', status: 'completed');
      await _workout(db, 'same-day-b', '2026-08-10', status: 'completed');
      await _entryWithSet(db, 'a', 'same-day-a', 'bench', weight: 60, reps: 10);
      await _entryWithSet(db, 'b', 'same-day-b', 'bench', weight: 70, reps: 5);
      await _entryWithSet(
        db,
        'run',
        'same-day-b',
        'running',
        distance: 5,
        seconds: 1500,
      );

      final profile = (await service.exerciseDetail('bench'))!;
      expect(profile['equipment'], 'Barra');
      expect(profile['defaultRestTimeSeconds'], 120);
      expect((profile['usage'] as Map)['completedWorkouts'], 2);

      final history = await service.exerciseHistory('bench');
      expect(
        history['sessionCount'],
        2,
        reason: 'dois treinos no mesmo dia não podem ser mesclados',
      );
      expect(history['totalSets'], 2);

      final records = await service.exerciseRecords('running');
      final byMetric = {
        for (final row in records['records'] as List)
          (row as Map)['metric']: row,
      };
      expect((byMetric['max_distance'] as Map)['value'], 5);
      expect((byMetric['longest_duration'] as Map)['value'], 1500);
      expect((byMetric['best_pace'] as Map)['value'], 300);
    },
  );

  test('training summary ignores warm-up and incomplete work', () async {
    await _workout(db, 'done', '2026-08-10', status: 'completed');
    await _workout(db, 'planned', '2026-08-11', status: 'planned');
    await _entryWithSet(
      db,
      'done-entry',
      'done',
      'bench',
      weight: 40,
      reps: 10,
      rpe: 7,
    );
    await _entryWithSet(
      db,
      'planned-entry',
      'planned',
      'bench',
      weight: 200,
      reps: 10,
      complete: false,
    );

    final summary = await service.trainingSummary(
      startDate: '2026-08-01',
      endDate: '2026-08-31',
    );
    expect((summary['workouts'] as Map)['completed'], 1);
    expect((summary['workouts'] as Map)['planned'], 1);
    final totals = summary['performedTotals'] as Map;
    expect(totals['completedSets'], 1);
    expect(totals['volumeKg'], 400);
    expect(totals['averageRpe'], 7);
    expect(totals['volumePerMinute'], closeTo(6.6667, 0.001));
  });

  test('progress and weekly volume honor their real date windows', () async {
    final today = DateTime.now();
    final todayText = today.toIso8601String().substring(0, 10);
    final oldText = today
        .subtract(const Duration(days: 90))
        .toIso8601String()
        .substring(0, 10);
    await _workout(db, 'current', todayText, status: 'completed');
    await _workout(db, 'old', oldText, status: 'completed');
    await _entryWithSet(
      db,
      'current-entry',
      'current',
      'bench',
      weight: 50,
      reps: 10,
    );
    await _entryWithSet(db, 'old-entry', 'old', 'bench', weight: 200, reps: 10);

    final progress = await service.progressTrend('bench', weeks: 2);
    expect(progress['sessionCount'], 1);
    expect(
      ((progress['dataPoints'] as List).single as Map)['workoutId'],
      'current',
    );

    final weekly = await service.weeklyVolume(weeks: 2);
    expect(weekly['weeks'], hasLength(2));
    final currentWeek = (weekly['weeks'] as List).last as Map;
    final category = (currentWeek['categories'] as List).single as Map;
    expect(category['volumeKg'], 500);
  });

  test('cardio includes time-only completed sessions', () async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await _workout(db, 'cardio', today, status: 'completed');
    await _entryWithSet(db, 'time-only', 'cardio', 'running', seconds: 1800);
    await _entryWithSet(
      db,
      'incomplete-distance',
      'cardio',
      'running',
      distance: 50,
      complete: false,
    );

    final result = await service.cardioSummary(weeks: 4);
    expect(result['sessions'], hasLength(1));
    final modality = (result['byModality'] as List).single as Map;
    expect(modality['totalTimeSeconds'], 1800);
    expect(modality['totalDistance'], 0);
  });

  test(
    'routing recognizes period, analysis and exercise metadata vocabulary',
    () {
      final registry = AiToolRegistry();
      expect(
        registry.toolNamesForQuery('Meu histórico de treinos no período'),
        containsAll(['get_workout_history', 'get_workout_detail']),
      );
      expect(
        registry.toolNamesForQuery('Analise o RPE e a densidade do treino'),
        contains('get_training_summary'),
      );
      expect(
        registry.toolNamesForQuery(
          'Qual equipamento e descanso padrão do exercício?',
        ),
        containsAll(['list_exercises', 'get_exercise_detail']),
      );
    },
  );
}

Future<void> _seedExercises(Database db) async {
  await db.insert('exercise_categories', {
    'id': 'strength',
    'name': 'Peito',
    'color': 1,
    'order_index': 0,
    'energy_system': 'anaerobic',
  });
  await db.insert('exercise_categories', {
    'id': 'aerobic',
    'name': 'Corrida',
    'color': 2,
    'order_index': 1,
    'energy_system': 'aerobic',
  });
  await db.insert('exercises', {
    'id': 'bench',
    'name': 'Supino',
    'category_id': 'strength',
    'type': 'weightReps',
    'notes': 'Peitoral com barra',
    'equipment': 'Barra',
    'is_favorite': 1,
    'default_rest_time': 120,
    'weight_increment': 2.5,
    'created_at': '2026-01-01T00:00:00',
  });
  await db.insert('exercises', {
    'id': 'running',
    'name': 'Corrida',
    'category_id': 'aerobic',
    'type': 'distanceTime',
    'is_favorite': 0,
    'created_at': '2026-01-01T00:00:00',
  });
}

Future<void> _workout(
  Database db,
  String id,
  String date, {
  required String status,
}) async {
  await db.insert('workouts', {
    'id': id,
    'date': date,
    'start_time': status == 'planned' ? null : '${date}T10:00:00',
    'end_time': status == 'completed' ? '${date}T11:00:00' : null,
    'duration_seconds': status == 'completed' ? 3600 : null,
    'estimated_calories': status == 'completed' ? 300 : null,
    'feeling_rating': status == 'completed' ? 4 : null,
    'comment': 'Treino $id',
    'is_from_routine': 0,
    'created_at': '${date}T09:00:00',
  });
}

Future<void> _entryWithSet(
  Database db,
  String id,
  String workoutId,
  String exerciseId, {
  double? weight,
  int? reps,
  double? distance,
  int? seconds,
  double? rpe,
  bool complete = true,
}) async {
  await db.insert('exercise_entries', {
    'id': id,
    'workout_id': workoutId,
    'exercise_id': exerciseId,
    'order_index': 0,
  });
  await _set(
    db,
    '$id-set',
    id,
    weight: weight,
    reps: reps,
    distance: distance,
    seconds: seconds,
    rpe: rpe,
    complete: complete,
  );
}

Future<void> _set(
  Database db,
  String id,
  String entryId, {
  double? weight,
  int? reps,
  double? distance,
  int? seconds,
  double? rpe,
  bool complete = true,
  bool warmup = false,
}) => db.insert('sets', {
  'id': id,
  'exercise_entry_id': entryId,
  'weight': weight,
  'reps': reps,
  'distance': distance,
  'time_seconds': seconds,
  'is_complete': complete ? 1 : 0,
  'is_warmup': warmup ? 1 : 0,
  'rpe': rpe,
  'order_index': 0,
});
