import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/services/ai_run_tool_service.dart';
import 'package:workout_notes/services/ai_tool_result_shaper.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/date_utils.dart';

import 'support/ai_heavy_user_fixture.dart';
import 'support/run_route_fixture.dart';
import 'support/test_db.dart';

/// Wednesday 2026-09-30, so the current week starts on Monday 2026-09-28.
final _now = DateTime(2026, 9, 30, 12);

void main() {
  late Database db;
  late AiRunToolService service;

  setUp(() async {
    db = await installTestDb(seed: true);
    service = AiRunToolService(now: () => _now);
  });

  tearDown(uninstallTestDb);

  group('list_run_activities', () {
    setUp(() async {
      await _insertActivity(
        db,
        id: 'run-a',
        startedAt: DateTime(2026, 9, 29, 7),
      );
      await _insertActivity(
        db,
        id: 'run-b',
        startedAt: DateTime(2026, 9, 28, 23, 30),
      );
      await _insertActivity(
        db,
        id: 'run-c',
        startedAt: DateTime(2026, 9, 20, 7),
      );
      await _insertActivity(
        db,
        id: 'bike-a',
        type: 'stationary_bike',
        startedAt: DateTime(2026, 9, 25, 18),
        distanceMeters: 12000,
        movingSeconds: 1800,
      );
      await _insertActivity(
        db,
        id: 'tread-a',
        type: 'treadmill',
        startedAt: DateTime(2026, 9, 10, 18),
      );
      await _insertActivity(
        db,
        id: 'run-aborted',
        startedAt: DateTime(2026, 9, 29, 9),
        status: 'recording',
      );
    });

    test('defaults to running, newest first, completed only', () async {
      final result = await service.listActivities();
      final rows = result['activities'] as List;
      expect(rows.map((r) => (r as Map)['id']), [
        'run-a',
        'run-b',
        'run-c',
        'tread-a',
      ]);
      expect(result['total'], 4);
      expect(result['has_more'], isFalse);
      expect(result.containsKey('next_page'), isFalse);
      expect((result['applied'] as Map)['activity_type'], 'running');
      final first = rows.first as Map;
      expect(first['pace_s_km'], 300);
      expect(first.containsKey('speed_kmh'), isFalse);
    });

    test('filters by type', () async {
      final bikes = await service.listActivities(
        activityType: 'stationary_bike',
      );
      final row = (bikes['activities'] as List).single as Map;
      expect(row['id'], 'bike-a');
      expect(row['speed_kmh'], closeTo(24, 0.01));
      expect(row.containsKey('pace_s_km'), isFalse);

      final all = await service.listActivities(activityType: 'all');
      expect(all['total'], 5);
    });

    test('date window includes the whole end day and nothing after', () async {
      final result = await service.listActivities(
        startDate: '2026-09-28',
        endDate: '2026-09-28',
      );
      expect((result['activities'] as List).map((r) => (r as Map)['id']), [
        'run-b',
      ]);
    });

    test('pages with has_more and next_page', () async {
      final first = await service.listActivities(limit: 3);
      expect(first['has_more'], isTrue);
      expect(first['next_page'], 2);
      expect(first['limit'], 3);
      final second = await service.listActivities(limit: 3, page: 2);
      expect((second['activities'] as List).map((r) => (r as Map)['id']), [
        'tread-a',
      ]);
      expect(second['has_more'], isFalse);
    });

    test('rejects bad arguments', () async {
      expect(
        () => service.listActivities(startDate: '28/09/2026'),
        throwsA(
          isA<AiToolArgException>().having(
            (e) => e.param,
            'param',
            'start_date',
          ),
        ),
      );
      expect(
        () => service.listActivities(
          startDate: '2026-09-29',
          endDate: '2026-09-01',
        ),
        throwsA(isA<AiToolArgException>()),
      );
      expect(
        () => service.listActivities(activityType: 'swim'),
        throwsA(
          isA<AiToolArgException>().having(
            (e) => e.param,
            'param',
            'activity_type',
          ),
        ),
      );
    });
  });

  group('get_run_activity_detail', () {
    test('unknown id is not_found with a hint', () async {
      await expectLater(
        service.activityDetail('missing'),
        throwsA(
          isA<AiToolNotFoundException>().having(
            (e) => e.hint,
            'hint',
            contains('list_run_activities'),
          ),
        ),
      );
    });

    test(
      'exposes splits, laps, gear, plan link and planned vs actual steps',
      () async {
        await _insertPlanTree(db);
        await db.insert('run_gear', {
          'id': 'gear-1',
          'name': 'Pegasus',
          'initial_distance_meters': 100000.0,
          'retire_distance_meters': 700000.0,
          'created_at': '2026-01-01T00:00:00',
          'updated_at': '2026-01-01T00:00:00',
        });
        await _insertActivity(
          db,
          id: 'run-detail',
          startedAt: DateTime(2026, 9, 29, 7),
          distanceMeters: 2500,
          movingSeconds: 800,
          planWorkoutId: 'w-interval-0',
          gearId: 'gear-1',
          elevationGain: 12,
          bestEffort1kSec: 310,
        );
        await _insertActivity(
          db,
          id: 'run-other',
          startedAt: DateTime(2026, 9, 1, 7),
          distanceMeters: 10000,
          movingSeconds: 3000,
          gearId: 'gear-1',
        );
        await _insertScheduled(
          db,
          id: 'sr-detail',
          date: '2026-09-29',
          workoutId: 'w-interval-0',
          status: 'completed',
          activityId: 'run-detail',
        );
        for (var i = 1; i <= 3; i++) {
          await db.insert('run_splits', {
            'activity_id': 'run-detail',
            'split_index': i,
            'distance_meters': i == 3 ? 500.0 : 1000.0,
            'duration_seconds': i == 3 ? 160 : 320,
            'pace_sec_per_km': 320.0,
            'is_partial': i == 3 ? 1 : 0,
          });
        }
        await db.insert('run_laps', {
          'activity_id': 'run-detail',
          'lap_index': 1,
          'start_distance_meters': 0.0,
          'distance_meters': 1200.0,
          'duration_seconds': 400,
          'pace_sec_per_km': 333.0,
        });
        await db.insert('run_activity_steps', {
          'id': 'ras-1',
          'run_activity_id': 'run-detail',
          'order_index': 0,
          'role': 'work',
          'rep_index': 1,
          'planned_metric': 'distance',
          'planned_value': 400,
          'planned_pace_sec_per_km': 290.0,
          'actual_distance_meters': 400.0,
          'actual_duration_seconds': 114,
          'actual_pace_sec_per_km': 285.0,
        });

        final detail = await service.activityDetail('run-detail');
        expect(detail['id'], 'run-detail');
        expect(detail['pace_s_km'], closeTo(320, 0.01));
        expect(detail['elevation_gain_m'], 12);
        expect((detail['best_efforts_s'] as Map)['1k'], 310);
        expect(detail['gear'], containsPair('name', 'Pegasus'));
        expect((detail['gear'] as Map)['total_km'], closeTo(112.5, 0.001));
        expect((detail['plan'] as Map)['name'], 'Plano 10K');
        expect((detail['scheduled_run'] as Map)['status'], 'completed');
        final session = detail['planned_session'] as Map;
        expect(session['name'], 'Tiros');
        expect(
          session['steps'],
          '1200m warmup | 2x(400m work @4:40-5:00, 200m recovery) | 1000m cooldown',
        );
        final steps = detail['step_results'] as List;
        expect((steps.single as Map)['pace_delta_s_km'], -5);
        final splits = detail['splits'] as List;
        expect(splits, hasLength(3));
        expect((splits.last as Map)['partial'], isTrue);
        expect((splits.last as Map)['distance_m'], 500);
        expect(((detail['laps'] as List).single as Map)['lap'], 1);
        // One id each: no run id repeated for the same activity.
        expect(RegExp('"run-detail"').allMatches(jsonEncode(detail)).length, 1);
      },
    );

    test('route summary and bike detail without splits', () async {
      await _insertActivity(
        db,
        id: 'run-route',
        startedAt: DateTime(2026, 9, 29, 7),
        distanceMeters: 1500,
        movingSeconds: 480,
        routeQuality: 'good',
      );
      await insertCompactRoute(db, 'run-route', [
        RunTrackPoint(
          id: 'p1',
          activityId: 'run-route',
          seq: 0,
          lat: -23.0,
          lng: -46.0,
          altitude: 100,
          accuracy: null,
          speed: null,
          recordedAt: DateTime(2026, 9, 29, 7),
        ),
        RunTrackPoint(
          id: 'p2',
          activityId: 'run-route',
          seq: 1,
          lat: -23.02,
          lng: -46.0,
          altitude: 110,
          accuracy: null,
          speed: null,
          recordedAt: DateTime(2026, 9, 29, 7, 8),
        ),
      ]);
      await _insertActivity(
        db,
        id: 'bike-1',
        type: 'stationary_bike',
        startedAt: DateTime(2026, 9, 28, 18),
        distanceMeters: 10000,
        movingSeconds: 1800,
      );
      final run = await service.activityDetail('run-route');
      expect((run['route'] as Map)['quality'], 'good');
      final bike = await service.activityDetail('bike-1');
      expect(bike['speed_kmh'], closeTo(20, 0.01));
      expect(bike.containsKey('splits'), isFalse);
      expect(bike.containsKey('route'), isFalse);
      expect(bike['gear'], isNull);
    });
  });

  group('get_run_progress', () {
    setUp(() async {
      await _insertActivity(
        db,
        id: 'this-week',
        startedAt: DateTime(2026, 9, 29, 7),
        pace: 300,
      );
      await _insertActivity(
        db,
        id: 'last-week',
        startedAt: DateTime(2026, 9, 22, 7),
        distanceMeters: 10000,
        movingSeconds: 3200,
        pace: 320,
      );
      await _insertActivity(
        db,
        id: 'in-window',
        startedAt: DateTime(2026, 9, 10, 7),
        pace: 330,
      );
      await _insertActivity(
        db,
        id: 'previous',
        startedAt: DateTime(2026, 8, 20, 7),
        distanceMeters: 16000,
        movingSeconds: 5440,
        pace: 340,
      );
      await _insertActivity(
        db,
        id: 'ancient',
        startedAt: DateTime(2026, 7, 1, 7),
        pace: 400,
      );
      await _insertActivity(
        db,
        id: 'bike',
        type: 'stationary_bike',
        startedAt: DateTime(2026, 9, 29, 18),
        distanceMeters: 20000,
        movingSeconds: 2400,
      );
    });

    test(
      'distance change is a real percentage and runs are windowed',
      () async {
        final result = await service.progress(period: '4_weeks');
        expect(result['run_count'], 3);
        expect(result['distance_m'], 20000);
        final vs = result['vs_previous_period'] as Map;
        expect(vs['distance_m'], 16000);
        expect(vs['distance_change_pct'], closeTo(25, 0.001));
        expect(vs['pace_change_s_km'], closeTo(317.5 - 340, 0.01));
        expect(result['avg_pace_s_km'], closeTo(317.5, 0.01));
        expect(result.containsKey('distanceRatioVsPreviousPeriod'), isFalse);
      },
    );

    test('longest and fastest run are compact references', () async {
      final result = await service.progress(period: '4_weeks');
      final longest = result['longest_run'] as Map;
      expect(longest['activity_id'], 'last-week');
      expect(longest['date'], '2026-09-22');
      expect(longest['distance_m'], 10000);
      expect(longest.containsKey('title'), isFalse);
      expect((result['fastest_run'] as Map)['activity_id'], 'this-week');
    });

    test('weekly trend is newest first and flags the partial week', () async {
      final result = await service.progress(period: '4_weeks');
      final trend = result['trend'] as List;
      expect(trend, hasLength(4));
      expect((trend.first as Map)['start'], '2026-09-28');
      expect((trend.first as Map)['partial'], isTrue);
      expect((trend[1] as Map)['partial'], isNull);
      expect((trend[1] as Map)['distance_m'], 10000);
      expect(result['trend_unit'], 'week');
      expect((result['this_week'] as Map)['distance_m'], 5000);
      final paceTrend = result['pace_trend'] as List;
      expect((paceTrend.first as Map)['date'], '2026-09-29');
    });

    test('pace trend is capped and all-time has no comparison', () async {
      for (var i = 0; i < 40; i++) {
        await _insertActivity(
          db,
          id: 'bulk-$i',
          startedAt: addDays(
            DateTime(2026, 9, 1),
            -i * 2,
          ).add(const Duration(hours: 6)),
          pace: 330,
        );
      }
      final all = await service.progress(period: 'all');
      expect((all['pace_trend'] as List).length, lessThanOrEqualTo(16));
      expect(all.containsKey('vs_previous_period'), isFalse);
      expect(all['run_count'], 45);
    });

    test('rejects an unknown period', () async {
      expect(
        () => service.progress(period: 'decade'),
        throwsA(isA<AiToolArgException>()),
      );
    });
  });

  group('review fixes', () {
    test(
      'week_streak counts all history, not only the loaded period',
      () async {
        for (var week = 0; week < 10; week++) {
          await _insertActivity(
            db,
            id: 'streak-$week',
            startedAt: DateTime(2026, 9, 29 - 7 * week, 7),
          );
        }
        final result = await service.progress(period: '4_weeks');
        expect(result['week_streak'], 10);
      },
    );

    test('get_run_schedule with only a past end_date looks back', () async {
      final result = await service.schedule(endDate: '2026-09-10');
      expect((result['applied'] as Map)['start_date'], '2026-08-14');
      expect((result['applied'] as Map)['end_date'], '2026-09-10');
    });
  });

  group('get_cardio_summary', () {
    setUp(() async {
      await _insertActivity(
        db,
        id: 'run-1',
        startedAt: DateTime(2026, 9, 29, 7),
      );
      await _insertActivity(
        db,
        id: 'run-2',
        startedAt: DateTime(2026, 9, 22, 7),
        distanceMeters: 10000,
        movingSeconds: 3200,
      );
      await _insertActivity(
        db,
        id: 'bike-1',
        type: 'stationary_bike',
        startedAt: DateTime(2026, 9, 24, 18),
        distanceMeters: 12000,
        movingSeconds: 1800,
      );
      await _insertActivity(
        db,
        id: 'run-old',
        startedAt: DateTime(2026, 9, 1, 7),
      );
      await _insertGymCardio(db, 'gym-done', '2026-09-25', finished: true);
      await _insertGymCardio(db, 'gym-open', '2026-09-26', finished: false);
      await _insertGymCardio(db, 'gym-future', '2026-10-05', finished: true);
    });

    test('totals by type, recent ids and full weeks only', () async {
      final result = await service.cardioSummary();
      expect((result['applied'] as Map)['start_date'], '2026-09-03');
      expect((result['applied'] as Map)['end_date'], '2026-09-30');
      expect(result['total_sessions'], 3);
      final types = {
        for (final row in (result['by_type'] as List).cast<Map>())
          row['activity_type'] as String: row,
      };
      expect(types['running']!['sessions'], 2);
      expect(types['running']!['distance_m'], 15000);
      expect(types['stationary_bike']!['avg_speed_kmh'], closeTo(24, 0.01));
      expect(result['recent_activity_ids'], ['run-1', 'bike-1', 'run-2']);
      final weekly = result['weekly'] as List;
      final week = weekly.single as Map;
      expect(week['week_start'], '2026-09-21');
      expect(week['run_sessions'], 1);
      expect(week['bike_sessions'], 1);
    });

    test('gym cardio counts finished, non-future workouts only', () async {
      final gym = (await service.cardioSummary())['gym_cardio'] as Map;
      expect(gym['workout_ids'], ['gym-done']);
      final modality = (gym['by_modality'] as List).single as Map;
      expect(modality['workouts'], 1);
      expect(modality['distance_km'], 5);
      expect(modality['duration_s'], 1500);
    });

    test('window follows days and omits gym cardio when empty', () async {
      final short = await service.cardioSummary(days: 7);
      expect((short['applied'] as Map)['days'], 7);
      expect(short['total_sessions'], 2);
      await db.delete('workouts');
      expect((await service.cardioSummary())['gym_cardio'], isNull);
    });
  });

  group('get_run_achievements', () {
    test('podium rows carry kind, place, activity id and raw value', () async {
      await _insertActivity(
        db,
        id: 'fast',
        startedAt: DateTime(2026, 9, 29, 7),
        pace: 285,
        bestEffort5kSec: 1500,
      );
      await _insertActivity(
        db,
        id: 'long',
        startedAt: DateTime(2026, 9, 20, 7),
        distanceMeters: 10000,
        movingSeconds: 3300,
        pace: 330,
        bestEffort5kSec: 1600,
      );
      final result = await service.achievements();
      final rows = (result['podium'] as List).cast<Map>();
      final distance = rows
          .where((r) => r['kind'] == 'longest_distance')
          .toList();
      expect(distance.first['place'], 1);
      expect(distance.first['activity_id'], 'long');
      expect(distance.first['value'], 10000);
      final effort = rows.where((r) => r['kind'] == 'best_effort_5k').toList();
      expect(effort.first['activity_id'], 'fast');
      expect(effort.first['value'], 1500);
      expect((result['units'] as Map)['best_avg_pace'], 's_km');
    });
  });

  group('plans', () {
    setUp(() async {
      await _insertPlanTree(db);
      await db.insert('run_plans', {
        'id': 'plan-old',
        'name': 'Plano antigo',
        'goal_kind': 'base',
        'weeks': 2,
        'status': 'archived',
        'completion_count': 1,
        'created_at': '2026-01-01T00:00:00',
        'updated_at': '2026-01-01T00:00:00',
      });
    });

    test('list_run_plans: compact rows with batched progress', () async {
      await _insertActivity(
        db,
        id: 'done-1',
        startedAt: DateTime(2026, 9, 22, 7),
        distanceMeters: 4500,
        movingSeconds: 1500,
      );
      await _insertScheduled(
        db,
        id: 'sr-1',
        date: '2026-09-22',
        workoutId: 'w-easy-0',
        status: 'completed',
        activityId: 'done-1',
      );
      await _insertScheduled(
        db,
        id: 'sr-2',
        date: '2026-09-24',
        workoutId: 'w-interval-0',
        status: 'skipped',
      );
      final result = await service.listPlans();
      final rows = result['plans'] as List;
      final plan = rows.single as Map;
      expect(plan['id'], 'plan-1');
      expect(plan['current_week'], 2);
      expect(plan['is_activated'], isTrue);
      expect(plan['sessions_completed'], 1);
      expect(plan['sessions_skipped'], 1);
      expect(plan['sessions_total'], 6);
      expect(plan['completion_pct'], closeTo(100 / 6, 0.001));

      final withArchived = await service.listPlans(includeArchived: true);
      expect(withArchived['total'], 2);
    });

    test(
      'get_run_plan: no id lists every plan and details the followed one',
      () async {
        final result = await service.plan();
        final plans = (result['plans'] as List).cast<Map>();
        expect(plans.map((p) => p['id']), containsAll(['plan-1', 'plan-old']));
        expect(
          plans.firstWhere((p) => p['id'] == 'plan-old')['status'],
          'archived',
        );
        final detail = result['plan'] as Map;
        expect(
          detail['id'],
          'plan-1',
          reason: 'the activated plan is followed',
        );
        expect(result['sessions'], isNotNull);
        final explicit = await service.plan(planId: 'plan-old');
        expect(
          explicit.containsKey('plans'),
          isFalse,
          reason: 'an explicit id returns only that plan',
        );
        expect((explicit['plan'] as Map)['id'], 'plan-old');
        await db.delete('run_plans');
        expect((await service.plan())['plans'], isEmpty);
      },
    );

    test('get_run_plan_detail: unknown id and out-of-range week', () async {
      await expectLater(
        service.planDetail('nope'),
        throwsA(isA<AiToolNotFoundException>()),
      );
      await expectLater(
        service.planDetail('plan-1', fromWeek: 9),
        throwsA(
          isA<AiToolArgException>().having(
            (e) => e.param,
            'param',
            'from_week',
          ),
        ),
      );
    });

    test(
      'get_run_plan_detail: window of weeks, has_more and next_from_week',
      () async {
        final first = await service.planDetail('plan-1', fromWeek: 1, weeks: 1);
        expect((first['applied'] as Map)['from_week'], 1);
        expect(first['has_more'], isTrue);
        expect(first['next_from_week'], 2);
        final sessions = (first['sessions'] as List).cast<Map>();
        expect(sessions.map((s) => s['week']).toSet(), {1});
        expect(sessions, hasLength(3));
        expect(
          sessions.firstWhere((s) => s['kind'] == 'interval')['steps'],
          contains('2x('),
        );
        expect(first['week_overview'], hasLength(2));

        // Default: from the current week (2), two weeks, which is the end.
        final current = await service.planDetail('plan-1');
        expect((current['applied'] as Map)['from_week'], 2);
        expect(current['has_more'], isFalse);
        expect(current.containsKey('next_from_week'), isFalse);
        expect(((current['plan'] as Map))['current_week'], 2);
      },
    );

    test('get_run_plan_detail: adherence and adaptations history', () async {
      await _insertActivity(
        db,
        id: 'done-easy',
        startedAt: DateTime(2026, 9, 22, 7),
        distanceMeters: 4500,
        movingSeconds: 1500,
      );
      await _insertScheduled(
        db,
        id: 'sr-easy',
        date: '2026-09-22',
        workoutId: 'w-easy-0',
        status: 'completed',
        activityId: 'done-easy',
      );
      for (var i = 0; i < 8; i++) {
        await db.insert('run_plan_adaptations', {
          'id': 'ad-$i',
          'run_plan_id': 'plan-1',
          'week_index': i,
          'kind': i.isEven ? 'hold' : 'stepBack',
          'status': 'applied',
          'payload_json': jsonEncode({
            'fromWeek': i + 1,
            'doneKm': 18.5,
            'plannedKm': 21,
            'missedWeeks': 0,
          }),
          'created_at': '2026-09-${10 + i}T08:00:00',
        });
      }
      final detail = await service.planDetail('plan-1');
      final adherence = detail['adherence'] as Map;
      expect(adherence['planned_distance_m'], 5000);
      expect(adherence['performed_distance_m'], 4500);
      expect(adherence['distance_adherence_pct'], closeTo(90, 0.001));
      final adaptations = (detail['adaptations'] as List).cast<Map>();
      expect(adaptations, hasLength(6));
      expect(adaptations.first['week'], 8);
      expect(adaptations.first['from_week'], 9);
      expect(adaptations.first['done_km'], 18.5);
      final sessionRows = (detail['sessions'] as List).cast<Map>();
      final done = sessionRows.where((s) => s['status'] == 'completed');
      expect(done, isEmpty, reason: 'week 1 is outside the default window');
      final week1 = await service.planDetail('plan-1', fromWeek: 1, weeks: 1);
      final easy = (week1['sessions'] as List).cast<Map>().firstWhere(
        (s) => s['id'] == 'w-easy-0',
      );
      expect(easy['status'], 'completed');
      expect(easy['activity_id'], 'done-easy');
    });

    test(
      'get_run_schedule: ascending, paged, one legend for plan names',
      () async {
        await _insertActivity(
          db,
          id: 'done-1',
          startedAt: DateTime(2026, 9, 29, 7),
          distanceMeters: 4800,
          movingSeconds: 1500,
        );
        await _insertScheduled(
          db,
          id: 'sr-a',
          date: '2026-09-29',
          workoutId: 'w-easy-1',
          status: 'completed',
          activityId: 'done-1',
        );
        await _insertScheduled(
          db,
          id: 'sr-b',
          date: '2026-10-01',
          workoutId: 'w-interval-1',
          status: 'planned',
        );
        await _insertScheduled(
          db,
          id: 'sr-c',
          date: '2026-10-03',
          workoutId: 'w-long-1',
          status: 'planned',
        );
        await _insertScheduled(
          db,
          id: 'sr-before',
          date: '2026-09-29',
          workoutId: null,
          status: 'planned',
          createdAt: '2026-09-29T09:00:00',
        );
        // Starts today by default: the 29th is before the window.
        final result = await service.schedule();
        expect((result['applied'] as Map)['start_date'], '2026-09-30');
        expect((result['applied'] as Map)['end_date'], '2026-10-27');
        expect((result['runs'] as List).map((r) => (r as Map)['id']), [
          'sr-b',
          'sr-c',
        ]);

        final first = await service.schedule(
          startDate: '2026-09-29',
          endDate: '2026-10-05',
          limit: 2,
        );
        expect(first['total'], 4);
        expect(first['has_more'], isTrue);
        expect(first['next_page'], 2);
        final rows = (first['runs'] as List).cast<Map>();
        expect(rows.map((r) => r['id']), ['sr-a', 'sr-before']);
        expect(rows.first['activity_id'], 'done-1');
        expect(rows.first['actual_distance_m'], 4800);
        expect(rows.first['session'], 'Rodagem');
        expect((first['plans'] as List).single, {
          'plan_id': 'plan-1',
          'name': 'Plano 10K',
        });
        final second = await service.schedule(
          startDate: '2026-09-29',
          endDate: '2026-10-05',
          limit: 2,
          page: 2,
        );
        expect((second['runs'] as List).map((r) => (r as Map)['id']), [
          'sr-b',
          'sr-c',
        ]);
        expect(second['has_more'], isFalse);
        final interval = (second['runs'] as List).cast<Map>().first;
        expect(interval['kind'], 'interval');
        expect(interval['distance_m'], 3400);
      },
    );

    test('get_run_schedule rejects bad dates', () async {
      expect(
        () => service.schedule(endDate: 'tomorrow'),
        throwsA(
          isA<AiToolArgException>().having((e) => e.param, 'param', 'end_date'),
        ),
      );
      expect(
        () => service.schedule(startDate: '2026-10-05', endDate: '2026-10-01'),
        throwsA(isA<AiToolArgException>()),
      );
    });
  });

  group('result size on the heavy user', () {
    test('every default call fits in 6000 characters', () async {
      final fixture = await seedHeavyUser(db);
      final heavy = AiRunToolService();
      const shaper = AiToolResultShaper();
      final calls = <String, Future<Map<String, dynamic>>>{
        'list_run_activities': heavy.listActivities(),
        'list_run_activities(all, 40)': heavy.listActivities(
          activityType: 'all',
          limit: 40,
        ),
        'get_run_activity_detail': heavy.activityDetail(fixture.runActivityId),
        'get_run_progress(12_weeks)': heavy.progress(),
        'get_run_progress(year)': heavy.progress(period: 'year'),
        'get_run_progress(all)': heavy.progress(period: 'all'),
        'get_cardio_summary': heavy.cardioSummary(),
        'get_cardio_summary(366)': heavy.cardioSummary(days: 366),
        'get_run_achievements': heavy.achievements(),
        'list_run_plans': heavy.listPlans(),
        'get_run_plan_detail': heavy.planDetail(fixture.runPlanId),
        'get_run_plan_detail(6 weeks)': heavy.planDetail(
          fixture.runPlanId,
          fromWeek: 1,
          weeks: 6,
        ),
        'get_run_schedule': heavy.schedule(),
        'get_run_schedule(40)': heavy.schedule(limit: 40),
      };
      for (final entry in calls.entries) {
        final shaped = shaper.shape(await entry.value);
        final size = jsonEncode(shaped).length;
        // ignore: avoid_print
        print('${entry.key}: $size chars');
        expect(size, lessThanOrEqualTo(6000), reason: entry.key);
      }
      // Defaults must not rely on the shaper's row trimming.
      final defaults = [
        await heavy.listActivities(),
        await heavy.progress(),
        await heavy.cardioSummary(),
        await heavy.planDetail(fixture.runPlanId),
        await heavy.schedule(),
      ];
      for (final result in defaults) {
        final shaped = shaper.shape(result);
        expect(shaped.containsKey('truncated_rows'), isFalse);
      }
    });

    test('heavy detail and plan results are unambiguous', () async {
      final fixture = await seedHeavyUser(db);
      final heavy = AiRunToolService();
      final detail = await heavy.activityDetail(fixture.runActivityId);
      expect(detail['splits'], isNotEmpty);
      expect(detail['laps'], hasLength(4));
      final plan = await heavy.planDetail(fixture.runPlanId);
      expect((plan['plan'] as Map)['current_week'], 6);
      expect((plan['week_overview'] as List), hasLength(12));
      final sessions = (plan['sessions'] as List).cast<Map>();
      expect(
        sessions.firstWhere((s) => s['kind'] == 'interval')['steps'],
        '1200m warmup | 6x(400m work @4:40-5:00, 200m recovery) | 1000m cooldown',
      );
    });
  });
}

Future<void> _insertActivity(
  Database db, {
  required String id,
  required DateTime startedAt,
  double distanceMeters = 5000,
  int movingSeconds = 1500,
  String type = 'running',
  String status = 'completed',
  double? pace,
  double? rpe,
  int? bestEffort5kSec,
  int? bestEffort1kSec,
  String? planWorkoutId,
  String? gearId,
  double? elevationGain,
  String? routeQuality,
}) async {
  final isBike = type == 'stationary_bike';
  await db.insert('run_activities', {
    'id': id,
    'activity_type': type,
    'started_at': startedAt.toIso8601String(),
    'ended_at': startedAt
        .add(Duration(seconds: movingSeconds))
        .toIso8601String(),
    'duration_seconds': movingSeconds,
    'moving_time_seconds': movingSeconds,
    'distance_meters': distanceMeters,
    'avg_pace_sec_per_km': isBike
        ? null
        : (pace ?? movingSeconds / (distanceMeters / 1000)),
    'calories': 300,
    'rpe': rpe,
    'feeling_rating': 4,
    'status': status,
    'created_at': startedAt.toIso8601String(),
    'updated_at': startedAt.toIso8601String(),
    'best_split_pace_sec_per_km': isBike ? null : 285.0,
    'best_effort_1k_sec': bestEffort1kSec,
    'best_effort_5k_sec': bestEffort5kSec,
    'efforts_computed': 1,
    'plan_workout_id': planWorkoutId,
    'gear_id': gearId,
    'elevation_gain_meters': elevationGain,
    'route_quality': routeQuality,
  });
}

/// A 2-week plan activated on Monday 2026-09-21 (so 2026-09-30 is week 2) with
/// an easy run, an interval session and a long run each week.
Future<void> _insertPlanTree(Database db) async {
  const created = '2026-09-01T00:00:00';
  await db.insert('run_plans', {
    'id': 'plan-1',
    'name': 'Plano 10K',
    'goal_kind': '10k',
    'weeks': 2,
    'status': 'active',
    'activated_at': '2026-09-21',
    'completion_count': 0,
    'created_at': created,
    'updated_at': created,
  });
  for (var week = 0; week < 2; week++) {
    await db.insert('run_plan_workouts', {
      'id': 'w-easy-$week',
      'run_plan_id': 'plan-1',
      'week_index': week,
      'day_of_week': 2,
      'order_index': 0,
      'kind': 'easy',
      'name': 'Rodagem',
      'target_distance_meters': 5000.0,
      'target_pace_sec_per_km': 340.0,
      'effort_zone': 'Z2',
      'created_at': created,
    });
    await db.insert('run_plan_workouts', {
      'id': 'w-interval-$week',
      'run_plan_id': 'plan-1',
      'week_index': week,
      'day_of_week': 4,
      'order_index': 1,
      'kind': 'interval',
      'name': 'Tiros',
      'created_at': created,
    });
    await db.insert('run_plan_workouts', {
      'id': 'w-long-$week',
      'run_plan_id': 'plan-1',
      'week_index': week,
      'day_of_week': 6,
      'order_index': 2,
      'kind': 'long',
      'name': 'Longão',
      'target_distance_meters': 8000.0,
      'created_at': created,
    });
    final intervalId = 'w-interval-$week';
    final steps = <(String, int, int?, int)>[
      ('warmup', 1200, null, 1),
      ('work', 400, 1, 2),
      ('recovery', 200, 1, 2),
      ('cooldown', 1000, null, 1),
    ];
    for (var i = 0; i < steps.length; i++) {
      await db.insert('run_workout_steps', {
        'id': '$intervalId-st$i',
        'run_plan_workout_id': intervalId,
        'order_index': i,
        'role': steps[i].$1,
        'metric': 'distance',
        'value': steps[i].$2,
        'repeat_group': steps[i].$3,
        'repeat_count': steps[i].$4,
        'target_pace_min_sec_per_km': steps[i].$1 == 'work' ? 280.0 : null,
        'target_pace_max_sec_per_km': steps[i].$1 == 'work' ? 300.0 : null,
      });
    }
  }
}

Future<void> _insertScheduled(
  Database db, {
  required String id,
  required String date,
  required String? workoutId,
  required String status,
  String? activityId,
  String createdAt = '2026-09-01T00:00:00',
}) async {
  await db.insert('scheduled_runs', {
    'id': id,
    'date': date,
    'run_plan_id': workoutId == null ? null : 'plan-1',
    'run_plan_workout_id': workoutId,
    'status': status,
    'run_activity_id': activityId,
    'created_at': createdAt,
    'updated_at': createdAt,
  });
}

Future<void> _insertGymCardio(
  Database db,
  String id,
  String date, {
  required bool finished,
}) async {
  await db.insert('workouts', {
    'id': id,
    'date': date,
    'start_time': '${date}T18:00:00',
    'end_time': finished ? '${date}T19:00:00' : null,
    'is_from_routine': 0,
    'created_at': '${date}T18:00:00',
  });
  await db.insert('exercise_entries', {
    'id': '$id-entry',
    'workout_id': id,
    'exercise_id': 'cycling',
    'order_index': 0,
  });
  await db.insert('sets', {
    'id': '$id-set',
    'exercise_entry_id': '$id-entry',
    'distance': 5.0,
    'time_seconds': 1500,
    'is_complete': 1,
    'is_warmup': 0,
    'order_index': 0,
  });
}
