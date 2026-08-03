import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/models/sleep_stage_epoch.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_stage_analysis_service.dart';

void main() {
  const service = SleepStageAnalysisService();

  test('calculates onset, final wake, phases and internal awakenings', () {
    final start = DateTime.utc(2026, 8, 1, 22);
    final epochs = <SleepStageEpoch>[];
    var index = 0;

    void add(SleepStageType stage, int minutes, {double confidence = 0.8}) {
      for (var halfMinute = 0; halfMinute < minutes * 2; halfMinute++) {
        epochs.add(
          SleepStageEpoch(
            id: 'epoch-${index++}',
            sessionId: 'session-1',
            startedAt: start.add(Duration(seconds: (index - 1) * 30)),
            durationSeconds: 30,
            stage: stage,
            confidence: confidence,
            awakeProbability: stage == SleepStageType.awake ? 0.9 : 0.05,
            sleepingProbability: stage == SleepStageType.sleeping ? 0.9 : 0.05,
            deepProbability: stage == SleepStageType.deep ? 0.9 : 0.05,
            algorithmVersion: 'acoustic-staging-test',
          ),
        );
      }
    }

    add(SleepStageType.awake, 2);
    add(SleepStageType.sleeping, 8);
    add(SleepStageType.deep, 3);
    add(SleepStageType.awake, 2);
    add(SleepStageType.sleeping, 2);
    add(SleepStageType.awake, 5);

    final summary = service.summarize(
      sessionStart: start,
      sessionEnd: start.add(const Duration(minutes: 22)),
      epochs: epochs,
    )!;

    expect(summary.sleepOnsetAt, start.add(const Duration(minutes: 2)));
    expect(summary.finalWakeAt, start.add(const Duration(minutes: 17)));
    expect(summary.sleepingMinutes, 10);
    expect(summary.deepSleepMinutes, 3);
    expect(summary.awakeMinutes, 9);
    expect(summary.sleepLatencyMinutes, 2);
    expect(summary.awakeningCount, 1);
    expect(summary.estimatedSleepMinutes, 13);
    expect(summary.sleepEfficiency, closeTo(13 / 22 * 100, 0.01));
  });

  test('does not turn unknown epochs into sleep stages', () {
    final start = DateTime.utc(2026, 8, 1, 22);
    final result = service.summarize(
      sessionStart: start,
      sessionEnd: start.add(const Duration(minutes: 1)),
      epochs: [
        SleepStageEpoch(
          id: 'unknown',
          sessionId: 'session-1',
          startedAt: start,
          durationSeconds: 60,
          stage: SleepStageType.unknown,
          confidence: 0,
          awakeProbability: 0,
          sleepingProbability: 0,
          deepProbability: 0,
          algorithmVersion: 'acoustic-staging-test',
        ),
      ],
    );

    expect(result, isNull);
  });
}
