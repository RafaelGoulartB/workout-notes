import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/services/sleep_stage_analysis_service.dart';
import 'package:workout_notes/services/sleep_stage_engine.dart';

import '../tool/validate_sleep_stages.dart' as harness;

enum _Kind { awake, sleeping, deep }

void main() {
  const engine = SleepStageEngine();

  test('a clean night clears diary accuracy and kappa thresholds', () {
    final diary = jsonDecode(
      File('test/fixtures/validation_diary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final start = DateTime.utc(2026, 1, 1, 22);
    final end = start.add(const Duration(hours: 8));
    final segments = _night(start, [
      (Duration.zero, const Duration(minutes: 20), _Kind.awake),
      (const Duration(minutes: 20), const Duration(minutes: 60), _Kind.sleeping),
      (const Duration(minutes: 60), const Duration(hours: 3), _Kind.deep),
      (const Duration(hours: 3), const Duration(hours: 7), _Kind.sleeping),
      (const Duration(hours: 7), const Duration(hours: 7, minutes: 10), _Kind.awake),
      (const Duration(hours: 7, minutes: 10), const Duration(hours: 7, minutes: 40), _Kind.sleeping),
      (const Duration(hours: 7, minutes: 40), const Duration(hours: 8), _Kind.awake),
    ]);
    final session = _session(start, end);

    final result = engine.run(
      session: session,
      segments: segments,
      onset: start.add(const Duration(minutes: 20)),
    );
    expect(result.ran, isTrue);

    final truth = harness.DiaryTruth(diary);
    final report = harness.validateAgainstDiary(result.epochs, truth, start);

    // A clean synthetic night must agree with the diary well above chance.
    expect(report.accuracy, greaterThan(0.85), reason: report.sleepWakeBlock);
    expect(report.kappa, greaterThan(0.5), reason: report.sleepWakeBlock);
    expect(report.sensitivity, greaterThan(0.9), reason: report.sleepWakeBlock);
  });

  test('rejects a night that never matches the diary', () {
    final diary = jsonDecode(
      File('test/fixtures/validation_diary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final start = DateTime.utc(2026, 1, 1, 22);
    final end = start.add(const Duration(hours: 8));
    // The whole night is awake-featured, but the diary says the user slept.
    final segments = _night(start, [
      (Duration.zero, const Duration(hours: 8), _Kind.awake),
    ]);

    final result = engine.run(
      session: _session(start, end),
      segments: segments,
      onset: start.add(const Duration(minutes: 20)),
    );
    expect(result.ran, isTrue);

    final truth = harness.DiaryTruth(diary);
    final report = harness.validateAgainstDiary(result.epochs, truth, start);
    expect(report.accuracy, lessThan(0.5), reason: report.sleepWakeBlock);
  });

  test('night-level error block reports onset minutes from the diary', () {
    final diary = jsonDecode(
      File('test/fixtures/validation_diary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final start = DateTime.utc(2026, 1, 1, 22);
    final end = start.add(const Duration(hours: 8));
    final segments = _night(start, [
      (Duration.zero, const Duration(minutes: 20), _Kind.awake),
      (const Duration(minutes: 20), const Duration(hours: 8), _Kind.sleeping),
    ]);
    final session = _session(start, end);

    final result = engine.run(
      session: session,
      segments: segments,
      onset: start.add(const Duration(minutes: 20)),
    );
    expect(result.ran, isTrue);

    final summary = const SleepStageAnalysisService().summarize(
      sessionStart: start,
      sessionEnd: end,
      epochs: result.epochs,
    );
    final truth = harness.DiaryTruth(diary);
    final block = harness.nightErrorsBlock(
      result.epochs,
      session,
      summary,
      truth,
    );

    // The diary onset (22:20 = +20 min) and the engine estimate are both
    // available, so the block must not fall back to "(no summary available)".
    expect(block, contains('Sleep onset'));
    expect(block, contains('Sleep minutes'));
    expect(block, isNot(contains('(no summary available)')));
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
  List<(Duration, Duration, _Kind)> blocks,
) {
  final segments = <SleepMonitorSegment>[];
  var index = 0;
  for (final (from, to, kind) in blocks) {
    var t = start.add(from);
    final windowEnd = start.add(to);
    while (t.isBefore(windowEnd)) {
      segments.add(_segment(start: t, kind: kind, index: index++));
      t = t.add(const Duration(seconds: 30));
    }
  }
  return segments;
}

SleepMonitorSegment _segment({
  required DateTime start,
  required _Kind kind,
  required int index,
}) {
  final (noise, bursts, bands, flatness, regularity, motion) = switch (kind) {
    _Kind.awake => (12.0, 15, [20, 30, 40, 120, 80], 0.7, 0.1, 15.0),
    _Kind.sleeping => (2.0, 1, [100, 30, 20, 5, 2], 0.3, 0.35, 0.5),
    _Kind.deep => (1.0, 0, [100, 30, 20, 5, 2], 0.05, 0.75, 0.2),
  };
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
    motionActiveSeconds: motion,
    motionMeanDeviationG: 0.02,
    motionMaxDeviationG: 0.05,
  );
}
