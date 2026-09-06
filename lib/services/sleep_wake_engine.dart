import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_epoch.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_stage_engine.dart'
    show SleepStageEngineResult, SleepWindow;

/// Causal audio-only estimate for a phone on a bedside table.
/// Sustained low activity is a fallback when breathing is not audible; quiet
/// wakefulness cannot be distinguished reliably with these signals alone.
/// Scores are evidence strength, not calibrated physiological probabilities.
/// No clock-of-night, terminal wake rule, deep-sleep prior or motion reward.
class SleepWakeEngine {
  static const algorithmVersion = 'sleep-wake-bedside-v2';
  static const source = 'bedside_heuristic';
  static const sleepConfirmationSeconds = 10 * 60;
  static const quietConfirmationSeconds = 20 * 60;
  static const wakeConfirmationSeconds = 60;
  static const evidenceHoldSeconds = 2 * 60;
  static const parameters = <String, num>{
    'sleep_confirmation_seconds': sleepConfirmationSeconds,
    'quiet_confirmation_seconds': quietConfirmationSeconds,
    'wake_confirmation_seconds': wakeConfirmationSeconds,
    'evidence_hold_seconds': evidenceHoldSeconds,
    'minimum_valid_fraction': 0.8,
    'minimum_regularity': 0.45,
    'minimum_rate_hz': 0.15,
    'maximum_rate_hz': 0.65,
    'maximum_sleep_noise': 6,
    'minimum_wake_noise': 10,
    'minimum_wake_active_fraction': 0.1,
    'stationary_active_fraction': 0.8,
    'minimum_variable_level_stddev_db': 3,
  };

  const SleepWakeEngine();

  static bool supports(SleepMonitorSession session) =>
      session.algorithmVersion == 'audio-features-v3';

  SleepStageEngineResult run({
    required SleepMonitorSession session,
    required List<SleepMonitorSegment> segments,
  }) {
    final end = session.endedAt;
    if (end == null || !end.isAfter(session.startedAt) || segments.isEmpty) {
      return const SleepStageEngineResult(ran: false, blockers: ['no_data']);
    }
    final cursor = SleepWakeCursor(sessionId: session.id);
    final epochs = <SleepStageEpoch>[];
    final reasons = <String, String>{};
    final ordered = [...segments]
      ..sort((a, b) {
        final time = a.startedAt.compareTo(b.startedAt);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    var position = session.startedAt;
    var validEpochs = 0;
    var knownSeconds = 0;

    void append(SleepStageEpoch epoch, String reason) {
      epochs.add(epoch);
      reasons[epoch.id] = reason;
      if (epoch.stage != SleepStageType.unknown) {
        knownSeconds += epoch.durationSeconds;
      }
    }

    void gap(DateTime until) {
      cursor.reset();
      while (position.isBefore(until)) {
        final seconds = until.difference(position).inSeconds.clamp(0, 30);
        if (seconds == 0) break;
        append(cursor.unknown(position, seconds), 'missing_capture');
        position = position.add(Duration(seconds: seconds));
      }
      position = until;
    }

    for (final segment in ordered) {
      if (segment.sessionId != session.id || segment.durationSeconds <= 0) {
        continue;
      }
      final rawEnd = segment.startedAt.add(
        Duration(seconds: segment.durationSeconds),
      );
      if (!rawEnd.isAfter(position) || !segment.startedAt.isBefore(end)) {
        continue;
      }
      final clippedEnd = rawEnd.isAfter(end) ? end : rawEnd;
      if (segment.startedAt.isAfter(position)) gap(segment.startedAt);
      final clippedStart = position;
      final seconds = clippedEnd.difference(clippedStart).inSeconds;
      if (seconds <= 0) continue;
      // Aggregates from an overlapping/oversized window cannot be attributed
      // to its remaining fragment. Preserve that time as unknown.
      if (segment.startedAt.isBefore(clippedStart) ||
          segment.durationSeconds > 60) {
        gap(clippedEnd);
        continue;
      }
      final decision = cursor.add(segment, durationSeconds: seconds);
      if (decision.validSignal) validEpochs++;
      append(decision.epoch, decision.reason);
      position = clippedEnd;
    }
    if (position.isBefore(end)) gap(end);
    final total = end.difference(session.startedAt).inSeconds;
    DateTime? onset;
    for (final epoch in epochs) {
      if (epoch.isSleep) {
        onset = epoch.startedAt;
        break;
      }
    }
    return SleepStageEngineResult(
      ran: true,
      epochs: List.unmodifiable(epochs),
      validEpochs: validEpochs,
      unknownEpochs: epochs
          .where((e) => e.stage == SleepStageType.unknown)
          .length,
      coverage: total == 0 ? 0 : knownSeconds / total,
      window: SleepWindow(onsetAt: onset),
      decisionReasons: Map.unmodifiable(reasons),
    );
  }
}

class SleepWakeDecision {
  final SleepStageEpoch epoch;
  final String reason;
  final bool validSignal;
  const SleepWakeDecision(this.epoch, this.reason, this.validSignal);
}

/// Constant-space state, shared by live UI updates and completed-session replay.
/// A gap resets evidence. Previously emitted epochs are never rewritten.
class SleepWakeCursor {
  final String sessionId;
  DateTime? _expectedStart;
  SleepStageType _state = SleepStageType.unknown;
  int _sleepSeconds = 0;
  int _quietSeconds = 0;
  int _wakeSeconds = 0;
  int _uncertainSeconds = 0;

  SleepWakeCursor({required this.sessionId});

  void reset() {
    _expectedStart = null;
    _state = SleepStageType.unknown;
    _sleepSeconds = _quietSeconds = _wakeSeconds = _uncertainSeconds = 0;
  }

  SleepStageEpoch unknown(DateTime start, int seconds) =>
      _epoch(start, seconds, SleepStageType.unknown, 0);

  SleepWakeDecision add(SleepMonitorSegment segment, {int? durationSeconds}) {
    final seconds = durationSeconds ?? segment.durationSeconds;
    final expected = _expectedStart;
    if (expected != null &&
        segment.startedAt.difference(expected).inMilliseconds.abs() > 1000) {
      reset();
    }
    _expectedStart = segment.startedAt.add(Duration(seconds: seconds));
    final noise = segment.noiseScore;
    final bands = [
      segment.spectralBandEnergy0,
      segment.spectralBandEnergy1,
      segment.spectralBandEnergy2,
      segment.spectralBandEnergy3,
      segment.spectralBandEnergy4,
    ];
    final bandTotal = bands.fold<double>(0, (sum, v) => sum + (v ?? 0));
    final valid =
        segment.sessionId == sessionId &&
        seconds > 0 &&
        seconds <= 60 &&
        !segment.isInvalid &&
        segment.validFraction.isFinite &&
        segment.validFraction >= 0.8 &&
        segment.validFraction <= 1 &&
        segment.audioCalibrated != false &&
        (segment.digitalSilenceFraction ?? 0) < 0.2 &&
        noise != null &&
        noise.isFinite &&
        noise >= 0 &&
        bands.every((v) => v != null && v.isFinite && v >= 0) &&
        bandTotal.isFinite &&
        bandTotal > 0;
    if (!valid) {
      reset();
      return SleepWakeDecision(
        unknown(segment.startedAt, seconds.clamp(1, 60)),
        'invalid_capture',
        false,
      );
    }
    final total = bands.fold<double>(0, (sum, v) => sum + v!);
    final high = (bands[3]! + bands[4]!) / total;
    final activity = segment.noiseActiveSeconds;
    final levelVariation = segment.audioLevelStddevDb;
    final regularity = segment.breathingRegularity;
    final rate = segment.breathingRateHz;
    final flatness = segment.spectralFlatness;
    // This is evidence from a valid recording, not missing audio or lack of
    // phone motion. A bedside microphone need not resolve periodic breathing.
    final quietEvidence =
        noise < 6 &&
        activity != null &&
        activity.isFinite &&
        activity >= 0 &&
        activity / seconds < 0.1;
    final sleepEvidence =
        quietEvidence &&
        regularity != null &&
        regularity.isFinite &&
        regularity >= 0.45 &&
        regularity <= 1 &&
        rate != null &&
        rate.isFinite &&
        rate >= 0.15 &&
        rate <= 0.65 &&
        high < 0.4 &&
        flatness != null &&
        flatness.isFinite &&
        flatness >= 0 &&
        flatness < 0.65;
    final wakeEvidence =
        activity != null &&
        activity.isFinite &&
        activity <= seconds + 1 &&
        activity / seconds >= 0.1 &&
        (activity / seconds < 0.8 ||
            (levelVariation != null &&
                levelVariation.isFinite &&
                levelVariation >= 3)) &&
        noise >= 10;
    String reason;
    double strength;
    if (wakeEvidence) {
      _wakeSeconds += seconds;
      // A single short sound reduces pending support; only sustained activity
      // restarts confirmation. This avoids a full reset for every bed turn.
      _sleepSeconds = (_sleepSeconds - seconds).clamp(
        0,
        SleepWakeEngine.sleepConfirmationSeconds,
      );
      _quietSeconds = (_quietSeconds - seconds).clamp(
        0,
        SleepWakeEngine.quietConfirmationSeconds,
      );
      _uncertainSeconds += seconds;
      if (_wakeSeconds >= SleepWakeEngine.wakeConfirmationSeconds) {
        _state = SleepStageType.awake;
        _sleepSeconds = _quietSeconds = 0;
        _uncertainSeconds = 0;
      }
      reason = _state == SleepStageType.awake
          ? 'sustained_audio_activity'
          : 'activity_pending';
      strength = _state == SleepStageType.awake ? 0.6 : 0.3;
    } else if (quietEvidence) {
      _quietSeconds = (_quietSeconds + seconds).clamp(
        0,
        SleepWakeEngine.quietConfirmationSeconds,
      );
      _sleepSeconds = sleepEvidence
          ? (_sleepSeconds + seconds).clamp(
              0,
              SleepWakeEngine.sleepConfirmationSeconds,
            )
          : 0;
      _wakeSeconds = 0;
      // During a transition, do not indefinitely retain the previous wake state.
      _uncertainSeconds = _state == SleepStageType.sleeping
          ? 0
          : _uncertainSeconds + seconds;
      if (_sleepSeconds >= SleepWakeEngine.sleepConfirmationSeconds ||
          _quietSeconds >= SleepWakeEngine.quietConfirmationSeconds) {
        _state = SleepStageType.sleeping;
        _uncertainSeconds = 0;
      }
      reason = _state == SleepStageType.sleeping
          ? (sleepEvidence
                ? 'sustained_periodic_audio'
                : 'sustained_low_audio_activity')
          : 'sleep_pending';
      strength = _state == SleepStageType.sleeping
          ? (sleepEvidence ? 0.6 : 0.4)
          : 0.3;
    } else {
      _wakeSeconds = _sleepSeconds = 0;
      _quietSeconds = (_quietSeconds - seconds).clamp(
        0,
        SleepWakeEngine.quietConfirmationSeconds,
      );
      _uncertainSeconds += seconds;
      reason = 'ambiguous_audio';
      strength = 0.3;
    }
    if (_uncertainSeconds > SleepWakeEngine.evidenceHoldSeconds) {
      _state = SleepStageType.unknown;
    }
    if (_state == SleepStageType.unknown) strength = 0;
    return SleepWakeDecision(
      _epoch(segment.startedAt, seconds, _state, strength),
      reason,
      true,
    );
  }

  SleepStageEpoch _epoch(
    DateTime start,
    int seconds,
    SleepStageType stage,
    double strength,
  ) => SleepStageEpoch(
    id: '$sessionId:${start.microsecondsSinceEpoch}',
    sessionId: sessionId,
    startedAt: start,
    durationSeconds: seconds,
    stage: stage,
    confidence: strength,
    awakeProbability: null,
    sleepingProbability: null,
    deepProbability: null,
    algorithmVersion: SleepWakeEngine.algorithmVersion,
    source: SleepWakeEngine.source,
  );
}
