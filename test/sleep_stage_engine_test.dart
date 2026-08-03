import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_stage_engine.dart';

enum _Kind { awake, sleeping, deep }

void main() {
  const engine = SleepStageEngine();

  test('stages a clear night into awake, light and deep epochs', () {
    final start = DateTime.utc(2026, 8, 1, 22);
    final end = start.add(const Duration(hours: 8));
    final segments = _night(start, [
      (Duration.zero, const Duration(minutes: 30), _Kind.awake),
      (const Duration(minutes: 30), const Duration(minutes: 60), _Kind.sleeping),
      (const Duration(minutes: 60), const Duration(hours: 3), _Kind.deep),
      (const Duration(hours: 3), const Duration(hours: 4, minutes: 30), _Kind.sleeping),
      (const Duration(hours: 4, minutes: 30), const Duration(hours: 4, minutes: 40), _Kind.awake),
      (const Duration(hours: 4, minutes: 40), const Duration(hours: 7, minutes: 40), _Kind.sleeping),
      (const Duration(hours: 7, minutes: 40), const Duration(hours: 8), _Kind.awake),
    ]);

    final result = engine.run(
      session: _session(start, end),
      segments: segments,
      onset: start.add(const Duration(minutes: 30)),
    );

    expect(result.ran, isTrue);
    expect(result.blockers, isEmpty);
    expect(result.epochs.length, segments.length);
    expect(result.epochs.first.algorithmVersion, SleepStageEngine.algorithmVersion);
    expect(result.epochs.first.source, SleepStageEngine.source);

    expect(
      _fraction(result, SleepStageType.awake,
          start, start.add(const Duration(minutes: 30))),
      greaterThan(0.8),
      reason: 'initial awake window',
    );
    expect(
      _fraction(result, SleepStageType.deep,
          start.add(const Duration(hours: 1)), start.add(const Duration(hours: 3))),
      greaterThan(0.8),
      reason: 'deep block in first half',
    );
    expect(
      _fraction(result, SleepStageType.awake,
          start.add(const Duration(hours: 4, minutes: 30)),
          start.add(const Duration(hours: 4, minutes: 40))),
      greaterThan(0.7),
      reason: 'mid-night awakening',
    );
    expect(
      _fraction(result, SleepStageType.awake,
          start.add(const Duration(hours: 7, minutes: 40)), end),
      greaterThan(0.7),
      reason: 'final wake',
    );
  });

  test('never labels deep before the post-onset gate', () {
    final start = DateTime.utc(2026, 8, 1, 22);
    final end = start.add(const Duration(hours: 2));
    // Deep-like features appear right after lights-out; the whole block ends
    // before onset+20min, so deep must not be produced there.
    final onset = start.add(const Duration(minutes: 30));
    final segments = _night(start, [
      (Duration.zero, const Duration(minutes: 30), _Kind.sleeping),
      (const Duration(minutes: 30), const Duration(minutes: 50), _Kind.deep),
      (const Duration(minutes: 50), const Duration(hours: 2), _Kind.sleeping),
    ]);

    final result = engine.run(
      session: _session(start, end),
      segments: segments,
      onset: onset,
    );

    expect(result.ran, isTrue);
    expect(
      _fraction(result, SleepStageType.deep,
          onset, start.add(const Duration(minutes: 50))),
      lessThan(0.2),
      reason: 'deep is forbidden before onset+20min',
    );
  });

  test('motion spike during quiet sleep relabels the window awake', () {
    final start = DateTime.utc(2026, 8, 1, 22);
    final end = start.add(const Duration(hours: 2));
    // Sleeping features except for a motion burst.
    final segments = <SleepMonitorSegment>[];
    var index = 0;
    var t = start;
    while (t.isBefore(end)) {
      final inSpike =
          !t.isBefore(start.add(const Duration(minutes: 60))) &&
          t.isBefore(start.add(const Duration(minutes: 70)));
      segments.add(
        _segment(
          start: t,
          kind: _Kind.sleeping,
          index: index++,
          motionOverride: inSpike ? 18.0 : null,
        ),
      );
      t = t.add(const Duration(seconds: 30));
    }

    final result = engine.run(
      session: _session(start, end),
      segments: segments,
      onset: start.add(const Duration(minutes: 15)),
    );

    expect(result.ran, isTrue);
    expect(
      _fraction(result, SleepStageType.awake,
          start.add(const Duration(minutes: 60)),
          start.add(const Duration(minutes: 70))),
      greaterThan(0.6),
      reason: 'sustained motion should wake the sleeper',
    );
  });

  test('audio-only recordings still stage when motion is absent', () {
    final start = DateTime.utc(2026, 8, 1, 22);
    final end = start.add(const Duration(hours: 4));
    final segments = _night(start, [
      (Duration.zero, const Duration(minutes: 30), _Kind.sleeping),
      (const Duration(minutes: 30), const Duration(hours: 2), _Kind.deep),
      (const Duration(hours: 2), const Duration(hours: 4), _Kind.sleeping),
    ], withMotion: false);

    final result = engine.run(
      session: _session(start, end),
      segments: segments,
      onset: start.add(const Duration(minutes: 10)),
    );

    expect(result.ran, isTrue);
    expect(
      result.epochs.where((e) => e.stage == SleepStageType.unknown),
      isEmpty,
    );
    expect(
      _fraction(result, SleepStageType.deep,
          start.add(const Duration(minutes: 30)), start.add(const Duration(hours: 2))),
      greaterThan(0.7),
      reason: 'deep still detected from spectral features alone',
    );
  });

  test('marks invalid and digital-silence windows unknown with zero confidence', () {
    final start = DateTime.utc(2026, 8, 1, 22);
    final end = start.add(const Duration(hours: 1));
    final segments = <SleepMonitorSegment>[];
    var index = 0;
    var t = start;
    while (t.isBefore(end)) {
      final position = index;
      final segment = _segment(
        start: t,
        kind: _Kind.sleeping,
        index: index++,
      );
      if (position >= 20 && position < 30) {
        segments.add(_silence(segment, index));
      } else if (position >= 40 && position < 50) {
        segments.add(_invalid(segment, index));
      } else {
        segments.add(segment);
      }
      t = t.add(const Duration(seconds: 30));
    }

    final result = engine.run(
      session: _session(start, end),
      segments: segments,
      onset: start.add(const Duration(minutes: 5)),
    );

    expect(result.ran, isTrue);
    final silenceEpochs = result.epochs
        .where((e) =>
            !e.startedAt.isBefore(start.add(const Duration(minutes: 10))) &&
            e.startedAt.isBefore(start.add(const Duration(minutes: 15))))
        .toList();
    expect(silenceEpochs, isNotEmpty);
    for (final epoch in silenceEpochs) {
      expect(epoch.stage, SleepStageType.unknown);
      expect(epoch.confidence, 0);
    }
  });

  test('returns a legacy blocker for pre-feature recordings', () {
    final start = DateTime.utc(2026, 8, 1, 22);
    final end = start.add(const Duration(hours: 2));
    final segments = <SleepMonitorSegment>[];
    var t = start;
    var index = 0;
    while (t.isBefore(end)) {
      segments.add(
        SleepMonitorSegment(
          id: 'seg-$index',
          sessionId: 'session-1',
          startedAt: t,
          durationSeconds: 30,
          audioRmsDbfs: -30,
          audioPeakDbfs: -20,
          noiseScore: 2,
          classification: 'quiet',
          validFraction: 0.95,
          noiseBurstCount: 0,
        ),
      );
      t = t.add(const Duration(seconds: 30));
      index++;
    }

    final result = engine.run(
      session: _session(start, end),
      segments: segments,
    );

    expect(result.ran, isFalse);
    expect(result.blockers, contains('legacy_recording'));
    expect(result.epochs, isEmpty);
  });

  test('emits in-range confidence and normalized probabilities', () {
    final start = DateTime.utc(2026, 8, 1, 22);
    final end = start.add(const Duration(hours: 4));
    final segments = _night(start, [
      (Duration.zero, const Duration(minutes: 30), _Kind.awake),
      (const Duration(minutes: 30), const Duration(hours: 2), _Kind.sleeping),
      (const Duration(hours: 2), const Duration(hours: 3, minutes: 30), _Kind.deep),
      (const Duration(hours: 3, minutes: 30), const Duration(hours: 4), _Kind.sleeping),
    ]);

    final result = engine.run(
      session: _session(start, end),
      segments: segments,
      onset: start.add(const Duration(minutes: 30)),
    );

    for (final epoch in result.epochs) {
      expect(epoch.confidence, inInclusiveRange(0, 1));
      final sum = (epoch.awakeProbability ?? 0) +
          (epoch.sleepingProbability ?? 0) +
          (epoch.deepProbability ?? 0);
      expect(sum, closeTo(1, 0.001), reason: 'epoch at ${epoch.startedAt}');
    }
  });
}

SleepMonitorSession _session(DateTime start, DateTime end) {
  return SleepMonitorSession(
    id: 'session-1',
    sleepEntryId: null,
    status: SleepMonitorSession.completed,
    startedAt: start,
    endedAt: end,
    utcOffsetStartMinutes: 0,
    utcOffsetEndMinutes: 0,
    sensorMode: 'audio',
    algorithmVersion: 'audio-features-v2',
    timeInBedMinutes: end.difference(start).inMinutes,
    quietMinutes: null,
    noisyMinutes: null,
    estimatedSleepMinutes: null,
    noiseEventCount: 0,
    signalQualityScore: null,
    endReason: SleepMonitorSession.endUser,
    createdAt: start,
  );
}

List<SleepMonitorSegment> _night(
  DateTime start,
  List<(Duration, Duration, _Kind)> blocks, {
  bool withMotion = true,
}) {
  final segments = <SleepMonitorSegment>[];
  var index = 0;
  for (final (from, to, kind) in blocks) {
    var t = start.add(from);
    final windowEnd = start.add(to);
    while (t.isBefore(windowEnd)) {
      segments.add(
        _segment(start: t, kind: kind, index: index++, withMotion: withMotion),
      );
      t = t.add(const Duration(seconds: 30));
    }
  }
  return segments;
}

SleepMonitorSegment _segment({
  required DateTime start,
  required _Kind kind,
  required int index,
  bool withMotion = true,
  double? motionOverride,
}) {
  final (noise, bursts, bands, flatness, regularity, motion) = switch (kind) {
    _Kind.awake => (12.0, 15, [20, 30, 40, 120, 80], 0.7, 0.1, 15.0),
    _Kind.sleeping => (2.0, 1, [100, 30, 20, 5, 2], 0.3, 0.35, 0.5),
    _Kind.deep => (1.0, 0, [100, 30, 20, 5, 2], 0.05, 0.75, 0.2),
  };
  final motionValue = motionOverride ?? motion;
  return SleepMonitorSegment(
    id: 'seg-$index',
    sessionId: 'session-1',
    startedAt: start,
    durationSeconds: 30,
    audioRmsDbfs: -30,
    audioPeakDbfs: -20,
    noiseScore: noise,
    classification: noise >= 10 ? 'noise' : 'quiet',
    validFraction: 0.95,
    noiseBurstCount: bursts,
    spectralBandEnergy0: bands[0].toDouble(),
    spectralBandEnergy1: bands[1].toDouble(),
    spectralBandEnergy2: bands[2].toDouble(),
    spectralBandEnergy3: bands[3].toDouble(),
    spectralBandEnergy4: bands[4].toDouble(),
    spectralFlatness: flatness,
    spectralCentroidHz: 1000,
    breathingRegularity: regularity,
    breathingRateHz: 0.25,
    motionActiveSeconds: withMotion ? motionValue : null,
    motionMeanDeviationG: withMotion ? 0.02 : null,
    motionMaxDeviationG: withMotion ? 0.05 : null,
  );
}

SleepMonitorSegment _silence(SleepMonitorSegment source, int index) {
  return SleepMonitorSegment(
    id: 'silence-$index',
    sessionId: source.sessionId,
    startedAt: source.startedAt,
    durationSeconds: source.durationSeconds,
    audioRmsDbfs: -120,
    audioPeakDbfs: -120,
    noiseScore: 0,
    classification: 'quiet',
    validFraction: 0.98,
    noiseBurstCount: 0,
  );
}

SleepMonitorSegment _invalid(SleepMonitorSegment source, int index) {
  return SleepMonitorSegment(
    id: 'invalid-$index',
    sessionId: source.sessionId,
    startedAt: source.startedAt,
    durationSeconds: source.durationSeconds,
    audioRmsDbfs: source.audioRmsDbfs,
    audioPeakDbfs: source.audioPeakDbfs,
    noiseScore: source.noiseScore,
    classification: 'invalid',
    validFraction: 0.2,
    noiseBurstCount: source.noiseBurstCount,
    spectralBandEnergy0: source.spectralBandEnergy0,
    spectralBandEnergy1: source.spectralBandEnergy1,
    spectralBandEnergy2: source.spectralBandEnergy2,
    spectralBandEnergy3: source.spectralBandEnergy3,
    spectralBandEnergy4: source.spectralBandEnergy4,
    spectralFlatness: source.spectralFlatness,
    spectralCentroidHz: source.spectralCentroidHz,
    breathingRegularity: source.breathingRegularity,
    breathingRateHz: source.breathingRateHz,
    motionActiveSeconds: source.motionActiveSeconds,
    motionMeanDeviationG: source.motionMeanDeviationG,
    motionMaxDeviationG: source.motionMaxDeviationG,
  );
}

double _fraction(
  SleepStageEngineResult result,
  SleepStageType stage,
  DateTime from,
  DateTime to,
) {
  final relevant = result.epochs
      .where((e) => !e.startedAt.isBefore(from) && e.startedAt.isBefore(to))
      .toList();
  if (relevant.isEmpty) return 0;
  return relevant.where((e) => e.stage == stage).length / relevant.length;
}
