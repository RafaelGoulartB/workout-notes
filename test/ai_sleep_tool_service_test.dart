import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/services/ai_sleep_tool_service.dart';
import 'package:workout_notes/services/ai_tool_registry.dart';

import 'support/ai_test_db.dart';

void main() {
  late Database database;
  late AiToolRegistry registry;
  final now = DateTime(2026, 8, 13, 12);

  setUp(() async {
    database = await installAiTestDb();
    registry = AiToolRegistry(sleep: AiSleepToolService(now: () => now));
  });

  tearDown(uninstallAiTestDb);

  test(
    'night detail exposes entry, session, stages and signal summary',
    () async {
      await _insertEntry(
        database,
        id: 'night-1',
        date: '2026-08-12',
        recorded: 470,
        actual: 430,
        estimated: 445,
        source: 'monitored',
        comment: 'Acordei cansado',
      );
      await _insertSession(database, entryId: 'night-1');
      await _insertEpochs(database);

      final result = await registry.executeRead(
        toolName: 'get_sleep_night_detail',
        args: const {'date': '2026-08-12'},
      );

      expect(result.ok, isTrue);
      final data = (result.data as Map).cast<String, dynamic>();
      expect(data['found'], isTrue);
      expect(data['source'], 'monitored');
      expect(data['comment'], 'Acordei cansado');
      final duration = data['duration'] as Map;
      expect(duration['recordedMinutes'], 470);
      expect(duration['actualMinutes'], 430);
      expect(duration['estimatedMinutes'], 445);
      expect(duration['monitorEstimatedMinutes'], 440);
      expect(duration['effectiveMinutes'], 430);
      expect(duration['effectiveSource'], 'actual_sleep_minutes');
      final schedule = data['schedule'] as Map;
      expect(schedule['bedtimeLocal'], '23:00');
      expect(schedule['wakeTimeLocal'], '07:00');
      expect(schedule['sleepLatencyMinutes'], 20);
      final stages = data['stages'] as Map;
      expect(stages['available'], isTrue);
      expect(stages['deepSleepMinutes'], 95);
      expect(stages['awakeningCount'], 3);
      final epochs = stages['epochSummary'] as Map;
      expect(epochs['epochCount'], 4);
      expect(epochs['knownEpochCount'], 3);
      expect(epochs['coveragePct'], 75.0);
      expect(epochs['deepSleepMinutes'], 0.5);
      final monitoring = data['monitoring'] as Map;
      expect(monitoring['signalQualityScore'], 0.86);
      expect((monitoring['noise'] as Map)['eventCount'], 7);
      expect(monitoring, isNot(contains('missionType')));
      expect(monitoring, isNot(contains('alarmDismissMethod')));
    },
  );

  test(
    'night detail reports a missing date without inventing zeroes',
    () async {
      final result = await registry.executeRead(
        toolName: 'get_sleep_night_detail',
        args: const {'date': '2026-08-11'},
      );

      expect(result.ok, isTrue);
      expect((result.data as Map)['found'], isFalse);
    },
  );

  test(
    'history paginates by end date and preserves every recorded night',
    () async {
      for (var day = 6; day <= 12; day++) {
        await _insertEntry(
          database,
          id: 'night-$day',
          date: '2026-08-${day.toString().padLeft(2, '0')}',
          recorded: 400 + day,
          actual: day.isEven ? 380 + day : null,
          estimated: day.isOdd ? 390 + day : null,
          source: day.isEven ? 'manual' : 'monitored',
        );
      }

      final result = await registry.executeRead(
        toolName: 'get_sleep_history',
        args: const {'days': 3, 'end_date': '2026-08-10'},
      );

      expect(result.ok, isTrue);
      final data = result.data as Map;
      expect(data['startDate'], '2026-08-08');
      expect(data['endDate'], '2026-08-10');
      expect(data['recordedNights'], 3);
      expect(data['previousEndDate'], '2026-08-07');
      final nights = (data['nights'] as List).cast<Map>();
      expect(nights.map((night) => night['date']), [
        '2026-08-08',
        '2026-08-09',
        '2026-08-10',
      ]);
      expect(
        (nights[1]['duration'] as Map)['effectiveSource'],
        'estimated_sleep_minutes',
      );
    },
  );

  test(
    'sleep profile exposes goal, monitoring counts and stage coverage',
    () async {
      await database.insert('app_settings', {
        'key': 'sleep_goal_minutes',
        'value': '450',
      });
      await database.insert('app_settings', {
        'key': 'sleep_monitor_default_mode',
        'value': 'monitoring_only',
      });
      await _insertEntry(
        database,
        id: 'manual',
        date: '2026-08-12',
        recorded: 420,
        actual: 420,
        source: 'manual',
      );
      await _insertEntry(
        database,
        id: 'monitored',
        date: '2026-08-13',
        recorded: 480,
        estimated: 480,
        source: 'monitored',
      );
      await _insertSession(database, entryId: 'monitored');

      final result = await registry.executeRead(
        toolName: 'get_sleep_profile',
        args: const {},
      );

      expect(result.ok, isTrue);
      final data = result.data as Map;
      expect(data['dailyGoalMinutes'], 450);
      expect(data['goalSource'], 'user_setting');
      expect(data['defaultMonitorMode'], 'monitoring_only');
      final last30 = data['last30Days'] as Map;
      expect(last30['recordedNights'], 2);
      expect(last30['manualNights'], 1);
      expect(last30['monitoredNights'], 1);
      expect(last30['stageAvailableNights'], 1);
      expect(last30['stageCoveragePct'], 100.0);
      expect(last30['averageSleepMinutes'], 450.0);
      expect(last30['differenceFromGoalMinutes'], 0.0);
      expect(data.toString(), isNot(contains('barcode_hash')));
    },
  );
}

Future<void> _insertEntry(
  Database database, {
  required String id,
  required String date,
  required int recorded,
  int? actual,
  int? estimated,
  required String source,
  String? comment,
}) => database.insert('sleep_entries', {
  'id': id,
  'date': date,
  'sleep_minutes': recorded,
  'actual_sleep_minutes': actual,
  'bedtime_minutes': 23 * 60,
  'wake_time_minutes': 7 * 60,
  'comment': comment,
  'source': source,
  'time_in_bed_minutes': 480,
  'estimated_sleep_minutes': estimated,
  'created_at': '${date}T07:00:00.000',
});

Future<void> _insertSession(Database database, {required String entryId}) =>
    database.insert('sleep_monitor_sessions', {
      'id': 'session-$entryId',
      'sleep_entry_id': entryId,
      'status': 'completed',
      'started_at': '2026-08-11T23:00:00.000',
      'ended_at': '2026-08-12T07:00:00.000',
      'monitor_mode': 'monitoring_only',
      'utc_offset_start_minutes': -180,
      'utc_offset_end_minutes': -180,
      'sensor_mode': 'audio_motion',
      'algorithm_version': 'audio-features-v2',
      'time_in_bed_minutes': 480,
      'quiet_minutes': 410,
      'noisy_minutes': 70,
      'estimated_sleep_minutes': 440,
      'noise_event_count': 7,
      'signal_quality_score': 0.86,
      'analysis_status': 'available',
      'sleep_onset_at': '2026-08-11T23:20:00.000',
      'final_wake_at': '2026-08-12T06:55:00.000',
      'sleep_latency_minutes': 20,
      'awake_minutes': 40,
      'sleeping_minutes': 305,
      'deep_sleep_minutes': 95,
      'unknown_minutes': 40,
      'awakening_count': 3,
      'sleep_efficiency': 91.7,
      'stage_confidence': 0.79,
      'stage_algorithm_version': 'sleep-stage-v2',
      'end_reason': 'user',
      'created_at': '2026-08-12T07:00:00.000',
    });

Future<void> _insertEpochs(Database database) async {
  const stages = ['awake', 'sleeping', 'deep', 'unknown'];
  for (var index = 0; index < stages.length; index++) {
    await database.insert('sleep_stage_epochs', {
      'id': 'epoch-$index',
      'session_id': 'session-night-1',
      'started_at': '2026-08-11T23:${index.toString().padLeft(2, '0')}:00.000',
      'duration_seconds': 30,
      'stage': stages[index],
      'confidence': 0.8,
      'awake_probability': stages[index] == 'awake' ? 0.8 : 0.1,
      'sleeping_probability': stages[index] == 'sleeping' ? 0.8 : 0.1,
      'deep_probability': stages[index] == 'deep' ? 0.8 : 0.1,
      'algorithm_version': 'sleep-stage-v2',
      'source': 'acoustic_model',
    });
  }
}
