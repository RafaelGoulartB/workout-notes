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

  group('bedside summaries', () {
    final start = DateTime.utc(2026, 8, 1, 22);

    List<SleepStageEpoch> night(
      List<(SleepStageType, int)> parts, {
      bool Function(int index)? moving,
      bool Function(int index)? snoring,
    }) {
      final epochs = <SleepStageEpoch>[];
      for (final (stage, count) in parts) {
        for (var i = 0; i < count; i++) {
          final index = epochs.length;
          epochs.add(
            SleepStageEpoch(
              id: 'e$index',
              sessionId: 's',
              startedAt: start.add(Duration(seconds: index * 30)),
              durationSeconds: 30,
              stage: stage,
              confidence: 0.9,
              awakeProbability: null,
              sleepingProbability: null,
              deepProbability: null,
              algorithmVersion: 'sleep-wake-bedside-v6',
              source: 'bedside_heuristic',
              movementSeconds: moving?.call(index) ?? false ? 4 : 0,
              snoring: snoring?.call(index) ?? false,
            ),
          );
        }
      }
      return epochs;
    }

    test('restless sleep needs repeated movement nearby', () {
      // 60 min asleep; movement every other window from minute 20 to 30.
      final epochs = night([
        (SleepStageType.sleeping, 120),
      ], moving: (i) => i >= 40 && i < 60 && i.isEven);
      final summary = service.summarize(
        sessionStart: start,
        sessionEnd: start.add(const Duration(minutes: 60)),
        epochs: epochs,
      )!;
      // The busy 10 minutes plus the edges of the 5-minute neighbourhood.
      expect(summary.restlessSleepMinutes, inInclusiveRange(10, 18));
      final isolated = service.summarize(
        sessionStart: start,
        sessionEnd: start.add(const Duration(minutes: 60)),
        epochs: night([
          (SleepStageType.sleeping, 120),
        ], moving: (i) => i % 20 == 0),
      )!;
      expect(isolated.restlessSleepMinutes, 0);
    });

    test('snoring minutes count only snoring while asleep', () {
      final summary = service.summarize(
        sessionStart: start,
        sessionEnd: start.add(const Duration(minutes: 30)),
        epochs: night([
          (SleepStageType.awake, 20),
          (SleepStageType.sleeping, 40),
        ], snoring: (i) => i % 2 == 0),
      )!;
      expect(summary.snoreMinutes, 10);
    });

    test('unknown time neither splits an awakening nor counts as wake', () {
      final summary = service.summarize(
        sessionStart: start,
        sessionEnd: start.add(const Duration(minutes: 60)),
        epochs: night([
          (SleepStageType.awake, 10),
          (SleepStageType.sleeping, 40),
          (SleepStageType.awake, 4),
          (SleepStageType.unknown, 2),
          (SleepStageType.awake, 4),
          (SleepStageType.sleeping, 60),
        ]),
      )!;
      expect(summary.awakeningCount, 1);
      expect(summary.unknownMinutes, 1);
      // Efficiency over the classified 59 minutes, not the 60 in bed.
      expect(summary.sleepEfficiency, closeTo(50 / 59 * 100, 0.01));
    });
  });
}
