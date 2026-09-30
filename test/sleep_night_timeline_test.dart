import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/sleep_night_timeline.dart';
import 'package:workout_notes/models/sleep_stage_epoch.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';

void main() {
  final start = DateTime.utc(2026, 9, 30, 5, 46, 45);

  SleepStageEpoch epoch(
    int index,
    SleepStageType stage, {
    double? p,
    double movement = 0,
    double ambient = 0,
    bool snoring = false,
  }) => SleepStageEpoch(
    id: 'e$index',
    sessionId: 's',
    startedAt: start.add(Duration(seconds: index * 30)),
    durationSeconds: 30,
    stage: stage,
    confidence: 0.9,
    awakeProbability: p == null ? null : 1 - p,
    sleepingProbability: p,
    deepProbability: null,
    algorithmVersion: 'sleep-wake-bedside-v6',
    movementSeconds: movement,
    ambientSeconds: ambient,
    snoring: snoring,
  );

  test('buckets 30-second epochs into minutes', () {
    final timeline = SleepNightTimeline.fromEpochs(
      start: start,
      end: start.add(const Duration(minutes: 3)),
      epochs: [
        epoch(0, SleepStageType.awake, p: 0.1, movement: 12),
        epoch(1, SleepStageType.awake, p: 0.3, movement: 4),
        epoch(2, SleepStageType.sleeping, p: 0.8, ambient: 6),
        epoch(3, SleepStageType.sleeping, p: 1, snoring: true),
        epoch(4, SleepStageType.unknown),
        epoch(5, SleepStageType.unknown),
      ],
    )!;
    expect(timeline.length, 3);
    expect(timeline.stages, [
      SleepStageType.awake,
      SleepStageType.sleeping,
      SleepStageType.unknown,
    ]);
    expect(timeline.sleepProbability[0], closeTo(0.2, 1e-9));
    expect(timeline.sleepProbability[1], closeTo(0.9, 1e-9));
    expect(timeline.sleepProbability[2], isNull);
    expect(timeline.movementSeconds, [16, 0, 0]);
    expect(timeline.ambientSeconds, [0, 6, 0]);
    expect(timeline.snoring, [false, true, false]);
  });

  test('encodes a full night in a few kilobytes and decodes it back', () {
    final epochs = [
      for (var i = 0; i < 960; i++)
        epoch(
          i,
          i < 30 ? SleepStageType.awake : SleepStageType.sleeping,
          p: (i % 64) / 63,
          movement: (i % 7).toDouble(),
          ambient: (i % 5).toDouble(),
          snoring: i % 50 == 0,
        ),
    ];
    final timeline = SleepNightTimeline.fromEpochs(
      start: start,
      end: start.add(const Duration(hours: 8)),
      epochs: epochs,
    )!;
    final encoded = timeline.encode();
    expect(encoded.length, lessThan(2600));
    final decoded = SleepNightTimeline.decode(encoded)!;
    expect(decoded.length, 480);
    expect(decoded.stages, timeline.stages);
    expect(decoded.movementSeconds, timeline.movementSeconds);
    expect(decoded.ambientSeconds, timeline.ambientSeconds);
    expect(decoded.snoring, timeline.snoring);
    for (var i = 0; i < 480; i++) {
      expect(
        decoded.sleepProbability[i]!,
        closeTo(timeline.sleepProbability[i]!, 1 / 126 + 1e-9),
      );
    }
  });

  test('unreadable data yields no timeline instead of throwing', () {
    for (final raw in [
      null,
      '',
      'not json',
      '{"v":2,"step":60,"stage":"s","p":"0","move":"0","amb":"0"}',
      '{"v":1,"step":60,"stage":"ss","p":"0","move":"0","amb":"0"}',
      '{"v":1,"step":60,"stage":"s","p":"!","move":"0","amb":"0"}',
    ]) {
      expect(SleepNightTimeline.decode(raw), isNull, reason: raw);
    }
  });
}
