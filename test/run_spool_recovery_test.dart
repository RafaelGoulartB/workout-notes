import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/utils/run_spool_recovery.dart';

void main() {
  test('finalizeInterruptedActivity uses last point end and clamps moving time', () {
    final activity = <String, dynamic>{
      'status': 'recording',
      'started_at': '2026-08-18T10:00:00.000Z',
      'duration_seconds': 600,
      'moving_time_seconds': 580,
      'distance_meters': 2000.0,
    };
    final points = [
      {
        'recorded_at': '2026-08-18T10:05:00.000Z',
      },
      {
        'recorded_at': '2026-08-18T10:10:00.000Z',
      },
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
  });

  test('finalizeInterruptedActivity raises stale duration to last-point wall time', () {
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
  });
}
