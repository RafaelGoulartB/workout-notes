import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_tracking_state.dart';

void main() {
  test('parses auto-pause and manual laps from the native state', () {
    final state = RunTrackingState.fromMap({
      'status': 'recording',
      'auto_paused': true,
      'distance_meters': 2400.0,
      'moving_time_seconds': 700,
      'laps': [
        {
          'lap_index': 1,
          'start_distance_meters': 0.0,
          'distance_meters': 1000.0,
          'duration_seconds': 300,
          'pace_sec_per_km': 300.0,
        },
      ],
      'current_lap': {
        'lap_index': 2,
        'start_distance_meters': 1000.0,
        'distance_meters': 1400.0,
        'duration_seconds': 400,
        'pace_sec_per_km': 285.7,
      },
    });

    expect(state.isRecording, isTrue);
    expect(state.isAutoPaused, isTrue);
    expect(state.isClockRunning, isFalse);
    expect(state.isActive, isTrue);
    expect(state.laps.single.index, 1);
    expect(state.currentLap!.index, 2);
    expect(state.currentLap!.distanceMeters, 1400);
  });

  test('a normal recording has a running clock and no laps', () {
    final state = RunTrackingState.fromMap({'status': 'recording'});
    expect(state.isClockRunning, isTrue);
    expect(state.isAutoPaused, isFalse);
    expect(state.laps, isEmpty);
    expect(state.currentLap, isNull);
  });

  test('auto-pause only exists while recording', () {
    final paused = RunTrackingState.fromMap({
      'status': 'paused',
      'auto_paused': true,
    });
    expect(paused.isAutoPaused, isFalse);
    expect(paused.isPaused, isTrue);
  });

  test('copyWith keeps laps and auto-pause unless replaced', () {
    final state = RunTrackingState.fromMap({
      'status': 'recording',
      'auto_paused': true,
      'laps': [
        {'lap_index': 1},
      ],
    });
    final copy = state.copyWith(distanceMeters: 10);
    expect(copy.autoPaused, isTrue);
    expect(copy.laps, hasLength(1));
    expect(copy.copyWith(autoPaused: false).autoPaused, isFalse);
  });
}
