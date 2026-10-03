import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/services/ai_tool_math.dart';
import 'package:workout_notes/services/ai_tool_result_shaper.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/services/ai_workout_tool_service.dart';
import 'package:workout_notes/utils/ai_revision.dart';

import 'support/ai_test_db.dart';
import 'support/strength_workout_seed.dart';

void main() {
  late Database db;
  late AiWorkoutToolService service;
  final today = DateTime(2026, 8, 20, 12);

  setUp(() async {
    db = await installAiTestDb();
    service = AiWorkoutToolService(now: () => today);
    await seedStrengthBasics(db);
  });

  tearDown(uninstallAiTestDb);

  Future<void> workout(
    String id,
    String date, {
    bool finished = true,
    bool started = true,
    String? routineId,
    String? dayId,
    String? comment,
    List<(String, List<(double, int, {bool warmup, bool done})>)> exercises =
        const [],
  }) async {
    await seedWorkout(
      db,
      id,
      date: date,
      finished: finished,
      routineId: routineId,
      dayId: dayId,
      comment: comment,
      exercises: exercises,
    );
    if (!started) {
      await db.update(
        'workouts',
        {'start_time': null},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Map<String, dynamic> shaped(Map<String, dynamic> data) =>
      const AiToolResultShaper().shape(data);

  group('get_workout_history', () {
    test(
      'newest first, paged, with the totals of performed work only',
      () async {
        await workout(
          'w1',
          '2026-08-10',
          exercises: [
            ('bench', [seedSet(50, 10), seedSet(20, 20, warmup: true)]),
          ],
        );
        await workout(
          'w2',
          '2026-08-12',
          comment: 'Treino ótimo',
          exercises: [
            ('bench', [seedSet(60, 8), seedSet(100, 5, done: false)]),
          ],
        );
        await workout('w3', '2026-08-14');

        final first = await service.history(limit: 2, page: 1);
        final rows = (first['workouts'] as List).cast<Map<String, dynamic>>();
        expect(rows.map((r) => r['id']), ['w3', 'w2']);
        expect(first['total'], 3);
        expect(first['has_more'], isTrue);
        expect(first['next_page'], 2);
        expect(rows.last['sets'], 1);
        expect(rows.last['volume_kg'], 480);
        expect(rows.last['planned_sets'], 1);
        expect(rows.last['comment'], 'Treino ótimo');
        expect(
          rows.last['status'],
          isNull,
          reason: 'the status filter already says completed',
        );

        final second = await service.history(limit: 2, page: 2);
        expect(((second['workouts'] as List).single as Map)['id'], 'w1');
        expect(second['has_more'], isFalse);
        expect(second['next_page'], isNull);
        expect(
          ((second['workouts'] as List).single as Map)['volume_kg'],
          500,
          reason: 'warm-up sets do not count',
        );
      },
    );

    test(
      'status and date filters tell completed, running and planned apart',
      () async {
        await workout('done', '2026-08-10');
        await workout('active', '2026-08-11', finished: false);
        await workout('planned', '2026-08-25', finished: false, started: false);

        final all = await service.history(status: 'all');
        final byId = {
          for (final row in (all['workouts'] as List).cast<Map>())
            row['id']: row['status'],
        };
        expect(byId, {
          'planned': 'planned',
          'active': 'in_progress',
          'done': 'completed',
        });
        expect(
          ((await service.history(status: 'planned'))['workouts'] as List).map(
            (r) => (r as Map)['id'],
          ),
          ['planned'],
        );
        expect(
          ((await service.history(status: 'in_progress'))['workouts'] as List)
              .map((r) => (r as Map)['id']),
          ['active'],
        );
        final windowed = await service.history(
          status: 'all',
          startDate: '2026-08-11',
          endDate: '2026-08-11',
        );
        expect(((windowed['workouts'] as List).single as Map)['id'], 'active');
      },
    );
  });

  group('get_workout_detail', () {
    test('lists sets compactly: performed, warm-up and open apart', () async {
      await workout(
        'detail',
        '2026-08-10',
        routineId: 'ppl',
        dayId: 'push',
        exercises: [
          (
            'bench',
            [
              seedSet(20, 12, warmup: true),
              seedSet(60, 10),
              seedSet(62.5, 8),
              seedSet(70, 5, done: false),
            ],
          ),
        ],
      );
      await db.update(
        'sets',
        {'rpe': 8.0},
        where: 'id = ?',
        whereArgs: ['detail-e0-s1'],
      );

      final detail = await service.workoutDetail('detail');
      expect(detail['status'], 'completed');
      expect(detail['routine'], 'Push Pull Legs');
      final totals = detail['totals'] as Map;
      expect(totals['sets'], 2);
      expect(totals['volume_kg'], 60 * 10 + 62.5 * 8);
      expect(totals['avg_rpe'], 8);
      final exercise = (detail['exercises'] as List).single as Map;
      expect(exercise['name'], 'Bench Press');
      expect(exercise['type'], 'weightReps');
      expect(exercise['sets'], '60x10@8, 62.5x8');
      expect(exercise['warmup'], '20x12');
      expect(exercise['open'], '70x5');
      // Compact output: no per-set maps and no ids of sets.
      expect(jsonEncode(shaped(detail)), isNot(contains('detail-e0-s1')));
    });

    test('a planned workout has no totals; records and comparison come from '
        'finished workouts', () async {
      await workout(
        'old',
        '2026-08-01',
        routineId: 'ppl',
        dayId: 'push',
        exercises: [
          ('bench', [seedSet(60, 5), seedSet(60, 5)]),
        ],
      );
      await workout(
        'new',
        '2026-08-08',
        routineId: 'ppl',
        dayId: 'push',
        exercises: [
          ('bench', [seedSet(70, 5), seedSet(70, 5), seedSet(70, 5)]),
        ],
      );
      await workout(
        'plan',
        '2026-08-25',
        finished: false,
        started: false,
        exercises: [
          ('bench', [seedSet(70, 5, done: false)]),
        ],
      );

      final fresh = await service.workoutDetail('new');
      final comparison = fresh['comparison'] as Map;
      expect(comparison['workout_id'], 'old');
      expect(comparison['basis'], 'same_routine_day');
      expect(comparison['sets_change'], 1);
      expect(comparison['volume_change_pct'], closeTo(75, 0.01));
      final records = (fresh['records'] as List).cast<Map>();
      expect(records.map((r) => r['kind']), containsAll(['e1rm', 'weight']));
      expect(records.first['previous_kg'], isNotNull);

      final planned = await service.workoutDetail('plan');
      expect(planned['status'], 'planned');
      expect(planned['totals'], isNull);
      expect(planned['comparison'], isNull);
      expect(((planned['exercises'] as List).single as Map)['open'], '70x5');
    });

    test('unknown id is not_found with a hint', () async {
      await expectLater(
        service.workoutDetail('nope'),
        throwsA(
          isA<AiToolNotFoundException>().having(
            (e) => e.hint,
            'hint',
            'call get_workout_history to get valid ids',
          ),
        ),
      );
    });
  });

  group('list_exercises', () {
    test(
      'search matches stored, English and Portuguese names ignoring accents',
      () async {
        await db.insert('exercises', {
          'id': 'bench_press',
          'name': 'Supino Reto',
          'locale_key': 'bench_press',
          'category_id': 'chest',
          'type': 'weightReps',
          'created_at': '2026-01-01',
        });
        await db.insert('exercises', {
          'id': 'custom',
          'name': 'Flexão Arqueiro',
          'category_id': 'chest',
          'type': 'weightReps',
          'created_at': '2026-01-01',
        });
        Future<List<Object?>> ids(String search) async =>
            ((await service.listExercises(search: search))['exercises'] as List)
                .map((row) => (row as Map)['id'])
                .toList();

        expect(
          await ids('bench press'),
          contains('bench_press'),
          reason: 'English catalog name',
        );
        expect(
          await ids('SUPINO'),
          contains('bench_press'),
          reason: 'stored Portuguese name',
        );
        expect(await ids('flexao'), ['custom'], reason: 'accent-insensitive');
        final result = await service.listExercises(search: 'bench');
        final row = (result['exercises'] as List).cast<Map>().firstWhere(
          (r) => r['id'] == 'bench_press',
        );
        expect(row['name'], 'Supino Reto');
        expect(row['name_en'], 'Bench Press');
        expect(result['categories'], {'chest': 'Chest'});
      },
    );

    test('sort by recency exposes what has not been trained lately', () async {
      await workout(
        'a',
        '2026-07-01',
        exercises: [
          ('bench', [seedSet(50, 5)]),
        ],
      );
      await workout(
        'b',
        '2026-08-15',
        exercises: [
          ('row', [seedSet(50, 5)]),
        ],
      );

      List<Object?> order(Map<String, dynamic> result) =>
          (result['exercises'] as List).map((r) => (r as Map)['id']).toList();

      final stale = await service.listExercises(sort: 'least_recent');
      expect(order(stale), [
        'bench',
        'row',
        'treadmill',
      ], reason: 'never trained last');
      final fresh = await service.listExercises(sort: 'most_recent');
      expect(order(fresh), ['row', 'bench', 'treadmill']);
      final rows = (stale['exercises'] as List).cast<Map>();
      expect(rows.first['last_trained'], '2026-07-01');
      expect(rows.first['days_since'], 50);
      expect(rows.first['sessions'], 1);
      expect(rows.last['last_trained'], isNull);
      final limited = await service.listExercises(limit: 1);
      expect(limited['has_more'], isTrue);
      expect(limited['total'], 3);
    });
  });

  group('get_exercise_history', () {
    test('profile, newest sessions and a real progress trend', () async {
      // reps == 1 makes the estimated 1RM equal to the weight.
      await workout(
        'w1',
        '2026-07-01',
        exercises: [
          ('bench', [seedSet(100, 1)]),
        ],
      );
      await workout(
        'w2',
        '2026-07-08',
        exercises: [
          ('bench', [seedSet(102.5, 1), seedSet(60, 10, warmup: true)]),
        ],
      );
      await workout(
        'w3',
        '2026-07-15',
        exercises: [
          ('bench', [seedSet(105, 1)]),
        ],
      );
      await workout(
        'open',
        '2026-07-22',
        finished: false,
        exercises: [
          ('bench', [seedSet(200, 1)]),
        ],
      );

      final history = await service.exerciseHistory('bench', limit: 2);
      expect(history['name'], 'Bench Press');
      expect(history['total_sessions'], 3);
      expect(history['first_trained'], '2026-07-01');
      expect(history['last_trained'], '2026-07-15');
      expect(history['session_count'], 3);
      final sessions = (history['sessions'] as List).cast<Map>();
      expect(sessions.map((s) => s['date']), ['2026-07-15', '2026-07-08']);
      expect(sessions.first['sets'], '105x1');
      expect(sessions.last['sets'], '102.5x1', reason: 'warm-ups are left out');
      final trend = history['trend'] as Map;
      expect(trend['first_e1rm_kg'], 100);
      expect(trend['last_e1rm_kg'], 105);
      expect(trend['best_e1rm_kg'], 105);
      expect(trend['e1rm_change_pct'], closeTo(5, 0.001));
      expect(trend['e1rm_slope_kg_per_week'], closeTo(2.5, 0.001));
      expect(trend['top_weight_best_kg'], 105);
    });

    test(
      'a date window limits sessions and trend; unknown id is not_found',
      () async {
        await workout(
          'w1',
          '2026-07-01',
          exercises: [
            ('bench', [seedSet(100, 1)]),
          ],
        );
        await workout(
          'w2',
          '2026-08-01',
          exercises: [
            ('bench', [seedSet(110, 1)]),
          ],
        );
        final windowed = await service.exerciseHistory(
          'bench',
          startDate: '2026-07-20',
        );
        expect(windowed['session_count'], 1);
        expect((windowed['trend'] as Map)['first_e1rm_kg'], 110);
        await expectLater(
          service.exerciseHistory('nope'),
          throwsA(isA<AiToolNotFoundException>()),
        );
      },
    );
  });

  group('get_personal_records', () {
    test('feed across exercises and the bests of one exercise', () async {
      await workout(
        'w1',
        '2026-08-01',
        exercises: [
          ('bench', [seedSet(60, 5)]),
        ],
      );
      await workout(
        'w2',
        '2026-08-10',
        exercises: [
          ('bench', [seedSet(70, 5)]),
        ],
      );
      await workout(
        'w3',
        '2026-08-15',
        exercises: [
          ('bench', [seedSet(70, 8)]),
          ('row', [seedSet(50, 5)]),
        ],
      );
      final window = AiToolMath.window(
        today: today,
        days: 30,
        defaultDays: 30,
        maxDays: 366,
      );

      final feed = await service.personalRecords(window: window);
      final records = (feed['records'] as List).cast<Map>();
      expect(records.first['date'], '2026-08-15', reason: 'newest first');
      expect(
        records.every((r) => r['exercise_id'] == 'bench'),
        isTrue,
        reason: 'the first session of an exercise is only a baseline',
      );
      expect(records.map((r) => r['workout_id']).toSet(), {'w2', 'w3'});

      final one = await service.personalRecords(
        exerciseId: 'bench',
        window: window,
      );
      final best = {
        for (final row in (one['best'] as List).cast<Map>()) row['metric']: row,
      };
      expect(best['max_weight_kg']!['value'], 70);
      expect(best['max_reps']!['value'], 8);
      expect(best['best_e1rm_kg']!['value'], closeTo(70 * (1 + 8 / 30), 0.001));
      expect(best['best_session_volume_kg']!['value'], 70 * 8);
      await expectLater(
        service.personalRecords(exerciseId: 'nope', window: window),
        throwsA(isA<AiToolNotFoundException>()),
      );
    });
  });

  group('get_training_summary', () {
    test(
      'counts only finished work inside the window and compares periods',
      () async {
        await workout(
          'p1',
          '2026-07-25',
          exercises: [
            ('bench', [seedSet(50, 10)]),
          ],
        );
        await workout(
          'c1',
          '2026-08-05',
          exercises: [
            ('bench', [seedSet(50, 10), seedSet(20, 20, warmup: true)]),
          ],
        );
        await workout(
          'c2',
          '2026-08-12',
          exercises: [
            ('row', [seedSet(40, 10), seedSet(90, 10, done: false)]),
          ],
        );
        await workout('active', '2026-08-18', finished: false);
        await workout('missed', '2026-08-06', finished: false, started: false);
        await workout(
          'upcoming',
          '2026-08-25',
          finished: false,
          started: false,
        );
        await workout(
          'outside',
          '2026-09-30',
          exercises: [
            ('bench', [seedSet(500, 10)]),
          ],
        );

        final window = AiToolMath.window(
          today: today,
          days: 20,
          defaultDays: 30,
          maxDays: 366,
        );
        final summary = await service.trainingSummary(window: window);
        expect((summary['applied'] as Map)['start_date'], '2026-08-01');
        final workouts = summary['workouts'] as Map;
        expect(workouts['completed'], 2);
        expect(workouts['in_progress'], 1);
        expect(workouts['missed'], 1);
        expect(
          workouts['planned_upcoming'],
          0,
          reason: 'the upcoming workout is after the window',
        );
        final totals = summary['totals'] as Map;
        expect(totals['sets'], 2);
        expect(totals['volume_kg'], 50 * 10 + 40 * 10);
        final previous = summary['previous_period'] as Map;
        expect(previous['start_date'], '2026-07-12');
        expect(previous['end_date'], '2026-07-31');
        expect(previous['workouts'], 1);
        expect(previous['volume_kg'], 500);
        expect(previous['volume_change_pct'], closeTo(80, 0.001));
        expect(previous['workouts_change'], 1);
      },
    );

    test('group_by week is newest first and flags partial weeks', () async {
      await workout(
        'a',
        '2026-08-04',
        exercises: [
          ('bench', [seedSet(50, 10)]),
        ],
      );
      await workout(
        'b',
        '2026-08-11',
        exercises: [
          ('bench', [seedSet(50, 10)]),
        ],
      );
      await workout(
        'c',
        '2026-08-12',
        exercises: [
          ('bench', [seedSet(50, 10)]),
        ],
      );
      final window = AiToolMath.window(
        today: today,
        startDate: '2026-08-03',
        endDate: '2026-08-20',
        defaultDays: 30,
        maxDays: 366,
      );
      final summary = await service.trainingSummary(
        window: window,
        groupBy: 'week',
      );
      final weeks = (summary['by_week'] as List).cast<Map>();
      expect(weeks.map((w) => w['week_start']), [
        '2026-08-17',
        '2026-08-10',
        '2026-08-03',
      ]);
      expect(weeks[0]['partial'], isTrue, reason: 'the current week is open');
      expect(weeks[1]['workouts'], 2);
      expect(weeks[1]['partial'], isNull);
      expect(weeks[2]['workouts'], 1);
    });

    test(
      'group_by category lists untouched categories with last trained',
      () async {
        await workout(
          'old',
          '2026-05-01',
          exercises: [
            ('row', [seedSet(50, 10)]),
          ],
        );
        await workout(
          'new',
          '2026-08-10',
          exercises: [
            ('bench', [seedSet(50, 10)]),
          ],
        );
        final window = AiToolMath.window(
          today: today,
          days: 30,
          defaultDays: 30,
          maxDays: 366,
        );
        final summary = await service.trainingSummary(
          window: window,
          groupBy: 'category',
        );
        final rows = {
          for (final row in (summary['by_category'] as List).cast<Map>())
            row['category_id']: row,
        };
        expect(rows['chest']!['sets'], 1);
        expect(rows['back']!['sets'], 0);
        expect(rows['back']!['last_trained'], '2026-05-01');
        expect(rows['back']!['days_since'], 111);
        expect(rows['cardio']!['last_trained'], isNull);
      },
    );

    test(
      'a window over a DST change counts exactly the requested days',
      () async {
        final march = AiWorkoutToolService(
          now: () => DateTime(2026, 3, 10, 12),
        );
        await workout(
          'x',
          '2026-03-05',
          exercises: [
            ('bench', [seedSet(50, 10)]),
          ],
        );
        final window = AiToolMath.window(
          today: DateTime(2026, 3, 10),
          startDate: '2026-03-01',
          endDate: '2026-03-10',
          defaultDays: 30,
          maxDays: 366,
        );
        final summary = await march.trainingSummary(window: window);
        expect((summary['applied'] as Map)['days'], 10);
        expect((summary['workouts'] as Map)['per_week'], closeTo(0.7, 0.001));
      },
    );
  });

  group('routines', () {
    test('list shows counts and last used', () async {
      await workout('w', '2026-08-10', routineId: 'ppl');
      final result = await service.listRoutines();
      final routine = (result['routines'] as List).single as Map;
      expect(routine['name'], 'Push Pull Legs');
      expect(routine['days'], 2);
      expect(routine['last_used'], '2026-08-10');
      expect(
        ((await service.listRoutines(nameContains: 'zzz'))['routines'] as List),
        isEmpty,
      );
    });

    test(
      'detail returns names, types, source ids once and the revision',
      () async {
        await db.insert('routine_exercises', {
          'id': 're1',
          'routine_day_id': 'push',
          'exercise_id': 'bench',
          'order_index': 0,
          'rest_time_seconds': 90,
        });
        for (var i = 0; i < 3; i++) {
          await db.insert('predefined_sets', {
            'id': 'ps$i',
            'routine_exercise_id': 're1',
            'weight': 60.0,
            'reps': 8 + i,
            'is_warmup': i == 0 ? 1 : 0,
            'order_index': i,
          });
        }
        final detail = await service.routineDetail('ppl');
        expect(detail['revision'], await routineRevision(db, 'ppl'));
        final days = (detail['days'] as List).cast<Map>();
        expect(days.map((d) => d['source_day_id']), ['push', 'pull']);
        final exercise = (days.first['exercises'] as List).single as Map;
        expect(exercise['source_routine_exercise_id'], 're1');
        expect(exercise['exercise_id'], 'bench');
        expect(exercise['name'], 'Bench Press');
        expect(exercise['type'], 'weightReps');
        expect(exercise['rest_s'], 90);
        final sets = (exercise['sets'] as List).cast<Map>();
        expect(sets.map((s) => s['source_set_id']), ['ps0', 'ps1', 'ps2']);
        expect(sets.first['warmup'], isTrue);

        final encoded = jsonEncode(shaped(detail));
        for (final id in ['re1', 'ps0', 'ps1', 'ps2', 'push']) {
          expect(
            RegExp('"$id"').allMatches(encoded).length,
            1,
            reason: '$id appears exactly once',
          );
        }

        final day = await service.routineDetail('ppl', dayId: 'pull');
        expect(((day['days'] as List).single as Map)['source_day_id'], 'pull');
        await expectLater(
          service.routineDetail('ppl', dayId: 'nope'),
          throwsA(isA<AiToolNotFoundException>()),
        );
        await expectLater(
          service.routineDetail('nope'),
          throwsA(
            isA<AiToolNotFoundException>().having(
              (e) => e.hint,
              'hint',
              'call list_routines to get valid ids',
            ),
          ),
        );
      },
    );

    test('a big routine returns the first days and lists the rest', () async {
      for (var d = 0; d < 6; d++) {
        final dayId = 'big-d$d';
        await db.insert('routine_days', {
          'id': dayId,
          'routine_id': 'ppl',
          'name': 'Extra $d',
          'order_index': 10 + d,
        });
        for (var e = 0; e < 6; e++) {
          final reId = '$dayId-e$e';
          await db.insert('routine_exercises', {
            'id': reId,
            'routine_day_id': dayId,
            'exercise_id': e.isEven ? 'bench' : 'row',
            'order_index': e,
          });
          for (var s = 0; s < 4; s++) {
            await db.insert('predefined_sets', {
              'id': '$reId-s$s',
              'routine_exercise_id': reId,
              'weight': 50.0,
              'reps': 8,
              'order_index': s,
            });
          }
        }
      }
      final detail = await service.routineDetail('ppl');
      expect(jsonEncode(shaped(detail)).length, lessThanOrEqualTo(6000));
      expect(detail.containsKey('truncated_rows'), isFalse);
      final more = (detail['more_days'] as List).cast<Map>();
      expect(more, isNotEmpty);
      expect(detail['has_more'], isTrue);
      final shown = (detail['days'] as List).length;
      expect(shown + more.length, 8);
      final nextDay = await service.routineDetail(
        'ppl',
        dayId: more.first['source_day_id'] as String,
      );
      expect(
        ((nextDay['days'] as List).single as Map)['source_day_id'],
        more.first['source_day_id'],
      );
    });
  });
}
