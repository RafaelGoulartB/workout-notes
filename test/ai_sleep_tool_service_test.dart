import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/services/ai_sleep_tool_service.dart';
import 'package:workout_notes/services/ai_tool_result_shaper.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/date_utils.dart';

import 'support/ai_heavy_user_fixture.dart';
import 'support/test_db.dart';

void main() {
  late Database database;
  late AiSleepToolService service;
  final now = DateTime(2026, 8, 13, 12);

  setUp(() async {
    database = await installTestDb();
    service = AiSleepToolService(now: () => now);
  });

  tearDown(uninstallTestDb);

  group('AiSleepNight resolver', () {
    test(
      'duration priority is actual, monitor, entry estimate, recorded',
      () async {
        await _entry(
          database,
          id: 'a',
          date: '2026-08-12',
          recorded: 470,
          actual: 430,
          estimated: 445,
          timeInBed: 480,
        );
        await _session(
          database,
          entryId: 'a',
          estimated: 440,
          efficiency: null,
        );
        await _entry(
          database,
          id: 'b',
          date: '2026-08-11',
          recorded: 470,
          estimated: 445,
          timeInBed: 480,
        );
        await _session(database, id: 's-b', entryId: 'b', estimated: 440);
        await _entry(
          database,
          id: 'c',
          date: '2026-08-10',
          recorded: 470,
          estimated: 445,
        );
        await _entry(database, id: 'd', date: '2026-08-09', recorded: 470);

        final nights = await AiSleepNight.load(
          DatabaseHelper.instance,
          startKey: '2026-08-09',
          endKey: '2026-08-12',
        );

        expect(nights.map((n) => n.date), [
          '2026-08-12',
          '2026-08-11',
          '2026-08-10',
          '2026-08-09',
        ]);
        expect(nights.map((n) => n.minutes), [430, 440, 445, 470]);
        expect(nights.map((n) => n.durationSource), [
          AiSleepDurationSource.actual,
          AiSleepDurationSource.monitorEstimate,
          AiSleepDurationSource.entryEstimate,
          AiSleepDurationSource.recorded,
        ]);
      },
    );

    test(
      'efficiency prefers the monitor value, else minutes / time in bed',
      () async {
        await _entry(
          database,
          id: 'a',
          date: '2026-08-12',
          recorded: 480,
          actual: 400,
          timeInBed: 500,
        );
        await _session(database, entryId: 'a', efficiency: 91.5);
        await _entry(
          database,
          id: 'b',
          date: '2026-08-11',
          recorded: 480,
          actual: 400,
          timeInBed: 500,
        );
        await _entry(
          database,
          id: 'c',
          date: '2026-08-10',
          recorded: 480,
          actual: 600,
          timeInBed: 500,
        );
        await _entry(database, id: 'd', date: '2026-08-09', recorded: 480);

        final nights = await AiSleepNight.load(
          DatabaseHelper.instance,
          startKey: '2026-08-09',
          endKey: '2026-08-12',
        );

        expect(nights[0].efficiencyPct, 91.5);
        expect(nights[1].efficiencyPct, closeTo(80, 0.001));
        expect(nights[2].efficiencyPct, 100); // clamped
        expect(nights[3].efficiencyPct, isNull); // no time in bed
      },
    );

    test('uses the latest monitor session of an entry', () async {
      await _entry(database, id: 'a', date: '2026-08-12', recorded: 480);
      await _session(
        database,
        id: 'old',
        entryId: 'a',
        estimated: 300,
        startedAt: '2026-08-11T22:00:00.000',
      );
      await _session(
        database,
        id: 'new',
        entryId: 'a',
        estimated: 410,
        startedAt: '2026-08-11T23:00:00.000',
      );

      final night = await AiSleepNight.loadDate(
        DatabaseHelper.instance,
        '2026-08-12',
      );

      expect(night!.minutes, 410);
    });
  });

  group('get_sleep_night_detail', () {
    test(
      'returns one resolved duration, stages, monitoring and alarm outcome',
      () async {
        await _entry(
          database,
          id: 'night-1',
          date: '2026-08-12',
          recorded: 470,
          actual: 430,
          estimated: 445,
          source: 'monitored',
          comment: 'Acordei cansado',
          timeInBed: 480,
          bedtime: 1380,
          wake: 420,
        );
        await _session(
          database,
          entryId: 'night-1',
          estimated: 440,
          alarmTrigger: 'awake',
          smartWindow: 30,
          wakeFeeling: 3,
        );

        final data = _shaped(await service.nightDetail(date: '2026-08-12'));

        expect(data['date'], '2026-08-12');
        expect(data['id'], 'night-1');
        expect(data['source'], 'monitored');
        expect(data['comment'], 'Acordei cansado');
        final duration = data['duration'] as Map;
        expect(duration['minutes'], 430);
        expect(duration['source'], 'actual');
        expect(duration['recorded_min'], 470);
        expect(duration['monitor_estimate_min'], 440);
        expect(duration['entry_estimate_min'], 445);
        expect(duration, isNot(contains('actual_min')));
        expect(data['efficiency_pct'], 89.5); // session value wins
        expect(data['bedtime'], '23:00');
        expect(data['wake'], '07:00');
        expect(data['time_in_bed_min'], 480);
        expect(data['sleep_latency_min'], 20);
        expect(data['sleep_onset_at'], isNotNull);
        final stages = data['stages'] as Map;
        expect(stages['awake_min'], 30);
        expect(stages['sleeping_min'], 440);
        expect(stages['awakenings'], 3);
        expect(stages['confidence_pct'], closeTo(74, 0.001));
        expect(stages['algorithm_version'], 'sleep-wake-bedside-v6');
        final monitoring = data['monitoring'] as Map;
        expect(monitoring['session_id'], 'sess-1');
        expect(monitoring['signal_quality_pct'], closeTo(86, 0.001));
        expect(monitoring['noise_events'], 7);
        final alarm = data['alarm'] as Map;
        expect(alarm['smart_window_minutes'], 30);
        expect(alarm['alarm_trigger'], 'awake');
        expect(alarm['alarm_fired_at'], isNotNull);
        expect(alarm['wake_feeling'], 'refreshed');

        final json = jsonEncode(data);
        expect(json, isNot(contains('deep')));
        expect(json, isNot(contains('mission_type')));
      },
    );

    test('a manual night has no stages, monitoring or alarm', () async {
      await _entry(database, id: 'm', date: '2026-08-12', recorded: 450);

      final data = _shaped(await service.nightDetail(date: '2026-08-12'));

      expect(data['duration'], {'minutes': 450, 'source': 'recorded'});
      expect(data, isNot(contains('stages')));
      expect(data, isNot(contains('monitoring')));
      expect(data, isNot(contains('alarm')));
      expect(data, isNot(contains('efficiency_pct')));
    });

    test(
      'defaults to today and reports a missing night as not_found',
      () async {
        await expectLater(
          service.nightDetail(),
          throwsA(
            isA<AiToolNotFoundException>()
                .having(
                  (e) => e.message,
                  'message',
                  'no sleep recorded for 2026-08-13',
                )
                .having((e) => e.hint, 'hint', contains('detail=nightly')),
          ),
        );
        await _entry(database, id: 'today', date: '2026-08-13', recorded: 400);
        expect((await service.nightDetail())['date'], '2026-08-13');
      },
    );

    test('rejects an invalid date with invalid_args', () async {
      await expectLater(
        service.nightDetail(date: '13/08/2026'),
        throwsA(isA<AiToolArgException>()),
      );
      await expectLater(
        service.nightDetail(date: '2026-02-30'),
        throwsA(isA<AiToolArgException>()),
      );
    });
  });

  group('get_sleep', () {
    Future<void> seedWeek() async {
      for (var i = 0; i < 7; i++) {
        final date = dateKey(addDays(now, -i));
        await _entry(
          database,
          id: 'e$i',
          date: date,
          recorded: 500,
          actual: 420 + i * 10,
          timeInBed: 480,
          bedtime: 1380,
          wake: 420,
          source: i == 0 ? 'manual' : 'monitored',
        );
        if (i != 0) {
          await _session(
            database,
            id: 's$i',
            entryId: 'e$i',
            efficiency: 80,
            alarm: i <= 3,
            alarmTrigger: i == 1
                ? 'awake'
                : i == 2
                ? 'stirring'
                : i == 3
                ? 'deadline'
                : null,
            smartWindow: i <= 3 ? 20 : null,
            wakeFeeling: i == 1
                ? 3
                : i == 2
                ? 1
                : null,
          );
        }
      }
    }

    test(
      'summary aggregates, compares with the goal and counts alarm outcomes',
      () async {
        await seedWeek();
        await database.insert('app_settings', {
          'key': 'sleep_goal_minutes',
          'value': '450',
        });

        final data = _shaped(await service.sleep(days: 7));

        final applied = data['applied'] as Map;
        expect(applied['start_date'], '2026-08-07');
        expect(applied['end_date'], '2026-08-13');
        expect(applied['detail'], 'summary');
        expect(data['recorded_nights'], 7);
        expect(data['coverage_pct'], 100);
        expect(data['avg_sleep_min'], 450); // 420..480
        expect(data['min_sleep_min'], 420);
        expect(data['max_sleep_min'], 480);
        expect(
          data['avg_efficiency_pct'],
          closeTo(81.1, 0.001),
        ); // 6 sessions + 87.5 computed
        expect(data['regularity_score'], 100);
        expect(data['avg_bedtime'], '23:00');
        expect(data['avg_wake'], '07:00');
        expect(data['goal_min'], 450);
        expect(data['avg_vs_goal_min'], 0);
        expect(data['goal_achievement_pct'], 100);
        expect(data['nights_meeting_goal'], 4); // 450, 460, 470, 480
        expect(data['manual_nights'], 1);
        expect(data['monitored_nights'], 6);
        expect(data['duration_sources'], {'actual': 7});
        final alarm = data['alarm'] as Map;
        expect(alarm['nights'], 3);
        expect(alarm['smart_window_nights'], 3);
        expect(alarm['triggered_awake'], 1);
        expect(alarm['triggered_stirring'], 1);
        expect(alarm['triggered_deadline'], 1);
        expect(alarm['wake_feeling_nights'], {'tired': 1, 'refreshed': 1});
        expect(jsonEncode(data), isNot(contains('deep')));
      },
    );

    test(
      'summary uses the default goal and omits what is not recorded',
      () async {
        await _entry(database, id: 'a', date: '2026-08-12', recorded: 360);

        final data = _shaped(await service.sleep(days: 14));

        expect(data['goal_min'], 480);
        expect(data['avg_vs_goal_min'], -120);
        expect(data['nights_meeting_goal'], 0);
        expect(data['coverage_pct'], 7.1);
        expect(data['avg_efficiency_pct'], isNull);
        expect(data['regularity_score'], isNull);
        expect(data['avg_bedtime'], isNull);
        expect(data['alarm'], isNull);
        expect(data['avg_awakenings'], isNull);
      },
    );

    test('an end_date in the future is clamped to today', () async {
      await seedWeek();
      final result = await service.sleep(
        days: 7,
        endDate: dateKey(addDays(now, 5)),
      );
      expect((result['applied'] as Map)['end_date'], dateKey(now));
      expect(result['coverage_pct'], closeTo(100, 1e-9));
    });

    test('summary of an empty window only echoes the window', () async {
      final data = _shaped(await service.sleep());

      expect(data['recorded_nights'], 0);
      expect(data, isNot(contains('avg_sleep_min')));
      expect((data['applied'] as Map)['days'], 14);
    });

    test(
      'nightly lists newest first and pages back with next_end_date',
      () async {
        await seedWeek();
        // Older nights outside the first window.
        await _entry(database, id: 'old', date: '2026-07-20', recorded: 400);

        final first = await service.sleep(days: 3, detail: 'nightly');
        final rows = first['nights'] as List;
        expect(rows.map((r) => (r as Map)['date']), [
          '2026-08-13',
          '2026-08-12',
          '2026-08-11',
        ]);
        expect((rows.first as Map)['duration_min'], 420);
        expect((rows.first as Map)['bedtime'], '23:00');
        expect((rows.first as Map)['source'], 'manual');
        expect(first['has_more'], isTrue);
        expect(first['next_end_date'], '2026-08-10');

        final second = await service.sleep(
          days: 4,
          endDate: first['next_end_date'] as String,
          detail: 'nightly',
        );
        expect((second['nights'] as List).map((r) => (r as Map)['date']), [
          '2026-08-10',
          '2026-08-09',
          '2026-08-08',
          '2026-08-07',
        ]);
        expect(second['next_end_date'], '2026-08-06');

        final last = await service.sleep(
          days: 30,
          endDate: '2026-08-06',
          detail: 'nightly',
        );
        expect(((last['nights'] as List).single as Map)['date'], '2026-07-20');
        expect(last, isNot(contains('has_more')));
        expect(last, isNot(contains('next_end_date')));
      },
    );

    test('rejects a bad end_date or detail', () async {
      await expectLater(
        service.sleep(endDate: 'yesterday'),
        throwsA(isA<AiToolArgException>()),
      );
      await expectLater(
        service.sleep(detail: 'full'),
        throwsA(isA<AiToolArgException>()),
      );
    });
  });

  group('result size on the heavy user', () {
    late DateTime today;
    late HeavyUserFixture fixture;

    setUp(() async {
      await uninstallTestDb();
      database = await installTestDb(seed: true);
      today = DateTime(2026, 9, 30, 12);
      fixture = await seedHeavyUser(database, now: today);
      service = AiSleepToolService(now: () => today);
    });

    int shapedLength(Map<String, dynamic> result) =>
        jsonEncode(const AiToolResultShaper().shape(result)).length;

    test('every sleep call fits in 6000 chars', () async {
      final calls = <String, Map<String, dynamic>>{
        'summary default': await service.sleep(),
        'summary 90': await service.sleep(days: 90),
        'nightly default': await service.sleep(detail: 'nightly'),
        'nightly 90': await service.sleep(days: 90, detail: 'nightly'),
        'night detail': await service.nightDetail(date: fixture.sleepNightDate),
      };
      final sizes = {
        for (final e in calls.entries) e.key: shapedLength(e.value),
      };
      // ignore: avoid_print
      print('sleep tool sizes: $sizes');
      for (final entry in sizes.entries) {
        expect(entry.value, lessThanOrEqualTo(6000), reason: entry.key);
      }
      final shaped = const AiToolResultShaper().shape(calls['nightly 90']!);
      expect(shaped, isNot(contains('truncated_rows')));
      expect(shaped['next_end_date'], isNull);
    });
  });
}

Map<String, dynamic> _shaped(Map<String, dynamic> result) =>
    const AiToolResultShaper().shape(result);

Future<void> _entry(
  Database database, {
  required String id,
  required String date,
  required int recorded,
  int? actual,
  int? estimated,
  int? timeInBed,
  int? bedtime,
  int? wake,
  String source = 'manual',
  String? comment,
}) => database.insert('sleep_entries', {
  'id': id,
  'date': date,
  'sleep_minutes': recorded,
  'actual_sleep_minutes': actual,
  'estimated_sleep_minutes': estimated,
  'time_in_bed_minutes': timeInBed,
  'bedtime_minutes': bedtime,
  'wake_time_minutes': wake,
  'source': source,
  'comment': comment,
  'created_at': '2026-08-13T07:00:00.000',
});

Future<void> _session(
  Database database, {
  String? id,
  required String entryId,
  int? estimated,
  double? efficiency = 89.5,
  String startedAt = '2026-08-11T23:00:00.000',
  bool alarm = true,
  String? alarmTrigger,
  int? smartWindow,
  int? wakeFeeling,
}) => database.insert('sleep_monitor_sessions', {
  'id': id ?? 'sess-${entryId.replaceFirst('night-', '')}',
  'sleep_entry_id': entryId,
  'status': 'completed',
  'started_at': startedAt,
  'ended_at': '2026-08-12T07:00:00.000',
  'alarm_at': alarm ? '2026-08-12T07:10:00.000' : null,
  'monitor_mode': 'alarm_without_mission',
  'utc_offset_start_minutes': -180,
  'sensor_mode': 'audio',
  'algorithm_version': 'audio-features-v5',
  'time_in_bed_minutes': 480,
  'quiet_minutes': 440,
  'noisy_minutes': 40,
  'estimated_sleep_minutes': estimated,
  'noise_event_count': 7,
  'signal_quality_score': 0.86,
  'analysis_status': 'available',
  'sleep_onset_at': '2026-08-11T23:20:00.000',
  'final_wake_at': '2026-08-12T06:55:00.000',
  'sleep_latency_minutes': 20,
  'awake_minutes': 30,
  'sleeping_minutes': 440,
  'unknown_minutes': 10,
  'restless_sleep_minutes': 25,
  'snore_minutes': 12,
  'awakening_count': 3,
  'sleep_efficiency': efficiency,
  'stage_confidence': 0.74,
  'stage_algorithm_version': 'sleep-wake-bedside-v6',
  'smart_window_minutes': smartWindow,
  'alarm_fired_at': alarmTrigger == null ? null : '2026-08-12T06:50:00.000',
  'alarm_trigger': alarmTrigger,
  'wake_feeling': wakeFeeling,
  'created_at': startedAt,
});
