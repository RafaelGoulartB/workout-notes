import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/repositories/phase_target_training.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/sql_helpers.dart';

import 'support/test_db.dart';

void main() {
  setUpAll(initSqfliteFfiForTests);

  group('date_utils', () {
    test('dayOf drops the time of day', () {
      expect(dayOf(DateTime(2026, 8, 1, 23, 59, 59)), DateTime(2026, 8, 1));
    });

    test('addDays crosses months, years and negative offsets', () {
      expect(addDays(DateTime(2026, 1, 31, 15), 1), DateTime(2026, 2, 1));
      expect(addDays(DateTime(2026, 12, 31), 1), DateTime(2027, 1, 1));
      expect(addDays(DateTime(2026, 3, 1), -1), DateTime(2026, 2, 28));
    });

    test('mondayOf returns the Monday of the ISO week', () {
      // 2026-08-05 is a Wednesday.
      expect(mondayOf(DateTime(2026, 8, 5, 18)), DateTime(2026, 8, 3));
      expect(mondayOf(DateTime(2026, 8, 3)), DateTime(2026, 8, 3));
      expect(mondayOf(DateTime(2026, 8, 9, 23, 59)), DateTime(2026, 8, 3));
      // Crosses the month/year boundary.
      expect(mondayOf(DateTime(2027, 1, 1)), DateTime(2026, 12, 28));
    });

    test('dateKey pads to yyyy-MM-dd from the calendar date', () {
      expect(dateKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
      expect(dateKey(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('sql_helpers', () {
    test('escapeLike escapes the wildcard and escape characters', () {
      expect(escapeLike(r'50%_off\deal'), r'50\%\_off\\deal');
      expect(escapeLike('plain'), 'plain');
    });

    test('optionalText trims and turns blank into null', () {
      expect(optionalText('  hi  '), 'hi');
      expect(optionalText('   '), isNull);
      expect(optionalText(''), isNull);
      expect(optionalText(null), isNull);
    });
  });

  group('phase target training references', () {
    late Database db;

    setUp(() async {
      db = await installTestDb();
      const now = '2026-08-01T08:00:00.000';
      await db.insert('periodization_plans', {
        'id': 'plan',
        'name': 'Plan',
        'start_date': '2026-08-03',
        'end_date': '2026-09-27',
        'created_at': now,
        'updated_at': now,
      });
      await db.insert('periodization_phases', {
        'id': 'phase',
        'plan_id': 'plan',
        'name': 'Phase',
        'color': 1,
        'start_date': '2026-08-03',
        'end_date': '2026-09-27',
        'created_at': now,
        'updated_at': now,
      });
      for (final routineId in ['gone', 'kept']) {
        await db.insert('routines', {
          'id': routineId,
          'name': routineId,
          'created_at': now,
        });
      }
    });

    tearDown(uninstallTestDb);

    Future<void> target(
      String id,
      Map<String, Object?> training,
      int version,
    ) => db.insert('phase_targets', {
      'id': id,
      'phase_id': 'phase',
      'training_json': jsonEncode(training),
      'version': version,
      'valid_from': '2026-08-03',
      'created_at': '2026-08-01T08:00:00.000',
    });

    Future<Map<String, dynamic>> training(String id) async {
      final row = (await db.query(
        'phase_targets',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
      return jsonDecode(row['training_json'] as String) as Map<String, dynamic>;
    }

    test('deleting a routine clears it from every target', () async {
      await target('single', {'routine_id': 'gone'}, 1);
      await target('list', {
        'routine_ids': ['gone', 'kept'],
        'routine_id': 'gone',
      }, 2);
      await target('other', {'routine_id': 'kept', 'workouts': 3}, 3);

      await RoutineRepository().deleteRoutine('gone');

      expect(await training('single'), isEmpty);
      expect(await training('list'), {
        'routine_ids': ['kept'],
        'routine_id': 'kept',
      });
      expect(await training('other'), {'routine_id': 'kept', 'workouts': 3});
      expect(await db.query('routines'), hasLength(1));
    });

    test('deleting a run plan clears it from targets', () async {
      const now = '2026-08-01T08:00:00.000';
      for (final id in ['plan-a', 'plan-b']) {
        await db.insert('run_plans', {
          'id': id,
          'name': id,
          'created_at': now,
          'updated_at': now,
        });
      }
      await target('both', {
        'run': {
          'run_plan_ids': ['plan-a', 'plan-b'],
          'weekly': 3,
        },
      }, 1);
      await target('only-a', {
        'run': {
          'run_plan_ids': ['plan-a'],
        },
      }, 2);
      await target('none', {
        'strength_days': [1, 3],
      }, 3);

      await RunPlanRepository().deletePlan('plan-a');

      expect(await training('both'), {
        'run': {
          'run_plan_ids': ['plan-b'],
          'weekly': 3,
        },
      });
      expect(await training('only-a'), {'run': <String, dynamic>{}});
      expect(await training('none'), {
        'strength_days': [1, 3],
      });
    });

    test(
      'rewriteMentioning only touches targets that mention the id',
      () async {
        await target('a', {'note': 'has needle'}, 1);
        await target('b', {'note': 'nothing'}, 2);

        final rewritten = await PhaseTargetTraining.rewriteMentioning(
          db,
          mentions: 'needle',
          edit: (training) {
            training['note'] = 'edited';
            return true;
          },
        );

        expect(rewritten, 1);
        expect((await training('a'))['note'], 'edited');
        expect((await training('b'))['note'], 'nothing');
      },
    );
  });
}
