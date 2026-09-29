import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/utils/run_spool_recovery.dart';

void main() {
  test(
    'finalizeInterruptedActivity uses last point end and clamps moving time',
    () {
      final activity = <String, dynamic>{
        'status': 'recording',
        'started_at': '2026-08-18T10:00:00.000Z',
        'duration_seconds': 600,
        'moving_time_seconds': 580,
        'distance_meters': 2000.0,
      };
      final points = [
        {'recorded_at': '2026-08-18T10:05:00.000Z'},
        {'recorded_at': '2026-08-18T10:10:00.000Z'},
      ];

      RunSpoolRecovery.finalizeInterruptedActivity(
        activity,
        points: points.map((e) => Map<String, dynamic>.from(e)).toList(),
        now: DateTime.parse('2026-08-18T12:00:00.000Z'),
      );

      expect(activity['status'], 'completed');
      expect(activity['ended_at'], '2026-08-18T10:10:00.000Z');
      // 10 minutes wall from start to last point > stored 600? equal 600
      expect(activity['duration_seconds'], 600);
      expect(activity['moving_time_seconds'], 580);
      expect(activity['avg_pace_sec_per_km'], closeTo(290.0, 0.01));
    },
  );

  test(
    'finalizeInterruptedActivity raises stale duration to last-point wall time',
    () {
      final activity = <String, dynamic>{
        'status': 'paused',
        'started_at': '2026-08-18T10:00:00.000Z',
        'duration_seconds': 60,
        'moving_time_seconds': 50,
        'distance_meters': 400.0,
      };
      final points = [
        {'recorded_at': '2026-08-18T10:08:00.000Z'},
      ];

      RunSpoolRecovery.finalizeInterruptedActivity(
        activity,
        points: points.map((e) => Map<String, dynamic>.from(e)).toList(),
      );

      expect(activity['duration_seconds'], 480);
      expect(activity['moving_time_seconds'], 50);
      expect(activity['ended_at'], '2026-08-18T10:08:00.000Z');
    },
  );

  test('finalizeInterruptedActivity closes the open lap after manual laps', () {
    final activity = <String, dynamic>{
      'status': 'recording',
      'started_at': '2026-08-18T10:00:00.000Z',
      'duration_seconds': 1200,
      'moving_time_seconds': 1100,
      'distance_meters': 3500.0,
      'laps': [
        {
          'lap_index': 1,
          'start_distance_meters': 0.0,
          'distance_meters': 1000.0,
          'duration_seconds': 320,
          'pace_sec_per_km': 320.0,
        },
      ],
      'lap_start_distance_meters': 1000.0,
      'lap_start_moving_seconds': 320,
    };

    RunSpoolRecovery.finalizeInterruptedActivity(
      activity,
      now: DateTime.parse('2026-08-18T10:20:00.000Z'),
    );

    final laps = activity['laps'] as List;
    expect(laps, hasLength(2));
    final last = laps.last as Map;
    expect(last['lap_index'], 2);
    expect(last['distance_meters'], 2500.0);
    expect(last['duration_seconds'], 780);
    expect(last['pace_sec_per_km'], closeTo(312, 0.01));
  });

  test('finalizeInterruptedActivity leaves lap-less runs alone', () {
    final activity = <String, dynamic>{
      'status': 'recording',
      'started_at': '2026-08-18T10:00:00.000Z',
      'duration_seconds': 600,
      'moving_time_seconds': 600,
      'distance_meters': 1000.0,
    };
    RunSpoolRecovery.finalizeInterruptedActivity(
      activity,
      now: DateTime.parse('2026-08-18T10:10:00.000Z'),
    );
    expect(activity.containsKey('laps'), isFalse);
  });
}
