import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/models/sleep_inference.dart';
import 'package:workout_notes/models/sleep_monitor_diagnostics.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/services/sleep_inference_service.dart';

void main() {
  const service = SleepInferenceService();

  test('blocks a technically complete night made of digital silence', () {
    final fixture = _night(scoreAtMinute: (_) => 0, digitalSilence: true);
    final diagnostics = SleepMonitorDiagnostics.fromSession(
      fixture.session,
      fixture.segments,
    );
    final result = service.analyze(
      session: fixture.session,
      segments: fixture.segments,
      diagnostics: diagnostics,
    );

    expect(diagnostics.digitalSilenceFraction, 1);
    expect(diagnostics.isSuitableForInference, isFalse);
    expect(diagnostics.inferenceBlockers, contains('digital_silence'));
    expect(result.status, SleepInferenceStatus.insufficientData);
  });

  test('finds sustained quiet and assigns medium onset confidence', () {
    final fixture = _night(scoreAtMinute: (minute) => minute < 20 ? 16 : 2);
    final result = _analyze(service, fixture);

    expect(result.status, SleepInferenceStatus.available);
    expect(
      result.sleepOnsetAt,
      fixture.session.startedAt.add(const Duration(minutes: 20)),
    );
    expect(result.settlingSeconds, 15 * 60);
    expect(result.confidence, SleepInferenceConfidence.medium);
  });

  test('groups activity, detects awakening and ignores a transient peak', () {
    final fixture = _night(
      scoreAtMinute: (minute) {
        if (minute < 20) return 16;
        if (minute >= 90 && minute < 95) return 18;
        if (minute >= 120 && minute < 120.5) return 22;
        return 2;
      },
    );
    final result = _analyze(service, fixture);

    expect(result.awakenings, hasLength(1));
    expect(
      result.awakenings.single.startedAt,
      fixture.session.startedAt.add(const Duration(minutes: 90)),
    );
    expect(
      result.events.where(
        (event) => event.type == SleepInferenceEventType.transientActivity,
      ),
      hasLength(1),
    );
    expect(result.estimatedSleepSeconds, 3 * 3600 + 35 * 60);
  });

  test('merges envelopes separated by sixty seconds', () {
    final fixture = _night(
      scoreAtMinute: (minute) {
        if (minute < 20) return 16;
        if (minute >= 60 && minute < 62) return 18;
        if (minute >= 63 && minute < 64) return 18;
        return 2;
      },
    );
    final result = _analyze(service, fixture);
    final merged = result.events.firstWhere(
      (event) =>
          event.startedAt ==
          fixture.session.startedAt.add(const Duration(minutes: 60)),
    );

    expect(merged.durationSeconds, 4 * 60);
    expect(merged.activeSeconds, 3 * 60);
    expect(merged.type, SleepInferenceEventType.awakening);
  });

  test('does not bridge activity across invalid signal gaps', () {
    final fixture = _night(
      scoreAtMinute: (minute) {
        if (minute < 20) return 16;
        if (minute >= 60 && minute < 62) return 18;
        if (minute >= 63 && minute < 64) return 18;
        return 2;
      },
      invalidAtMinute: (minute) => minute >= 62 && minute < 63,
    );
    final result = _analyze(service, fixture);
    final afterOnset = result.events.where(
      (event) =>
          event.startedAt.isAfter(
            fixture.session.startedAt.add(const Duration(minutes: 20)),
          ) &&
          event.type == SleepInferenceEventType.transientActivity,
    );

    expect(afterOnset, hasLength(2));
    expect(result.awakenings, isEmpty);
  });

  test('marks sustained activity in final ten minutes without awakening', () {
    final fixture = _night(
      scoreAtMinute: (minute) {
        if (minute < 20) return 16;
        if (minute >= 235) return 18;
        return 2;
      },
    );
    final result = _analyze(service, fixture);

    expect(result.awakenings, isEmpty);
    expect(
      result.events.singleWhere(
        (event) => event.type == SleepInferenceEventType.finalActivity,
      ),
      isNotNull,
    );
  });

  test('does not invent onset when the whole night remains active', () {
    final fixture = _night(scoreAtMinute: (_) => 16);
    final result = _analyze(service, fixture);

    expect(result.status, SleepInferenceStatus.available);
    expect(result.sleepOnsetAt, isNull);
    expect(result.estimatedSleepSeconds, isNull);
    expect(result.confidence, SleepInferenceConfidence.low);
  });
}

SleepInferenceResult _analyze(
  SleepInferenceService service,
  _NightFixture fixture,
) {
  final diagnostics = SleepMonitorDiagnostics.fromSession(
    fixture.session,
    fixture.segments,
  );
  expect(diagnostics.isSuitableForInference, isTrue);
  return service.analyze(
    session: fixture.session,
    segments: fixture.segments,
    diagnostics: diagnostics,
  );
}

_NightFixture _night({
  required double Function(double minute) scoreAtMinute,
  bool digitalSilence = false,
  bool Function(double minute)? invalidAtMinute,
}) {
  final start = DateTime.utc(2026, 7, 29, 5);
  const segmentSeconds = 30;
  const totalSeconds = 4 * 60 * 60;
  final segments = List.generate(totalSeconds ~/ segmentSeconds, (index) {
    final offsetSeconds = index * segmentSeconds;
    final minute = offsetSeconds / 60;
    final score = scoreAtMinute(minute);
    final invalid = invalidAtMinute?.call(minute) ?? false;
    return SleepMonitorSegment(
      id: 'segment-$index',
      sessionId: 'session-1',
      startedAt: start.add(Duration(seconds: offsetSeconds)),
      durationSeconds: segmentSeconds,
      audioRmsDbfs: digitalSilence ? -120 : -82 + score,
      audioPeakDbfs: digitalSilence ? -120 : -62 + score,
      noiseScore: invalid ? null : score,
      classification: invalid ? 'invalid' : (score >= 10 ? 'noise' : 'quiet'),
      validFraction: invalid ? 0 : 1,
      noiseBurstCount: score >= 10 ? 10 : 0,
    );
  });
  final session = SleepMonitorSession(
    id: 'session-1',
    sleepEntryId: null,
    status: SleepMonitorSession.completed,
    startedAt: start,
    endedAt: start.add(const Duration(seconds: totalSeconds)),
    utcOffsetStartMinutes: -180,
    utcOffsetEndMinutes: -180,
    sensorMode: 'audio',
    algorithmVersion: SleepMonitorSession.defaultAlgorithmVersion,
    timeInBedMinutes: 240,
    quietMinutes: null,
    noisyMinutes: null,
    estimatedSleepMinutes: null,
    noiseEventCount: 0,
    signalQualityScore: 1,
    endReason: SleepMonitorSession.endUser,
    createdAt: start,
  );
  return _NightFixture(session, segments);
}

class _NightFixture {
  final SleepMonitorSession session;
  final List<SleepMonitorSegment> segments;

  const _NightFixture(this.session, this.segments);
}
