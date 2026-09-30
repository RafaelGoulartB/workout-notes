import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_epoch.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_audio_evidence.dart';
import 'package:workout_notes/services/sleep_wake_model.dart';

/// Audio-only sleep/wake estimate for a phone on a bedside table.
///
/// Each window becomes evidence ([SleepAudioEvidenceExtractor]) for a hidden
/// Markov model ([SleepWakeModel]). [SleepWakeCursor] runs the causal forward
/// filter and drives the live UI. A completed session is replayed through the
/// same cursor and then smoothed with the backward pass, so each window is
/// judged with the whole night as context: a sleep onset lands where the
/// silence began instead of where it was confirmed, a wake starts at the
/// first sustained sound, and short holes inside sleep are bridged.
///
/// Quiet wakefulness still cannot be told apart from sleep with these
/// signals; the model assumes it lasts a few minutes after the last sound of
/// a person. Probabilities are model probabilities, not calibrated ones.
class SleepWakeEngine {
  static const algorithmVersion = 'sleep-wake-bedside-v6';
  static const source = 'bedside_heuristic';
  static const featureVersions = {
    'audio-features-v3',
    'audio-features-v4',
    'audio-features-v5',
  };

  /// What the native recorder shipped with this build produces.
  static const currentFeatureVersion = 'audio-features-v5';

  /// Feature versions whose breathing envelope is band-limited.
  static const bandLimitedBreathingVersions = {'audio-features-v5'};
  static const alignmentToleranceMilliseconds = 1000;

  /// Live labels fall back to unknown after this long without evidence.
  static const liveEvidenceHoldSeconds = 2 * 60;

  /// Offline, a run of windows without evidence up to this long is labelled
  /// from its context; longer runs stay unknown.
  static const maximumBridgeSeconds = 20 * 60;
  static const parameters = <String, num>{
    'minimum_valid_fraction': SleepAudioEvidenceExtractor.minimumValidFraction,
    'maximum_zero_sample_fraction':
        SleepAudioEvidenceExtractor.maximumZeroSampleFraction,
    'minimum_regularity': SleepAudioEvidenceExtractor.minimumRegularity,
    'minimum_rate_hz': SleepAudioEvidenceExtractor.minimumRateHz,
    'maximum_rate_hz': SleepAudioEvidenceExtractor.maximumRateHz,
    'loud_activity_noise_db': SleepAudioEvidenceExtractor.loudActivityNoiseDb,
    'stationary_active_fraction':
        SleepAudioEvidenceExtractor.stationaryActiveFraction,
    'minimum_variable_level_stddev_db':
        SleepAudioEvidenceExtractor.minimumVariableLevelStddevDb,
    'snoring_low_share': SleepAudioEvidenceExtractor.snoringLowShare,
    'environmental_low_band_fraction':
        SleepAudioEvidenceExtractor.environmentalLowBandFraction,
    'environmental_high_band_fraction':
        SleepAudioEvidenceExtractor.environmentalHighBandFraction,
    'maximum_environmental_prominence_db':
        SleepAudioEvidenceExtractor.maximumEnvironmentalProminenceDb,
    'maximum_environmental_excess_ratio':
        SleepAudioEvidenceExtractor.maximumEnvironmentalExcessRatio,
    'maximum_environmental_noise_db':
        SleepAudioEvidenceExtractor.maximumEnvironmentalNoiseDb,
    'minimum_foreground_excess_ratio':
        SleepAudioEvidenceExtractor.minimumForegroundExcessRatio,
    'environmental_high_excess_share':
        SleepAudioEvidenceExtractor.environmentalHighExcessShare,
    'environmental_rumble_excess_share':
        SleepAudioEvidenceExtractor.environmentalRumbleExcessShare,
    'floor_windows': SleepAudioEvidenceExtractor.floorWindows,
    'floor_percentile': SleepAudioEvidenceExtractor.floorPercentile,
    'settling_quiet_to_sleep': 0.03,
    'wake_quiet_to_sleep': 0.10,
    'sleep_to_wake': 0.014,
    'live_evidence_hold_seconds': liveEvidenceHoldSeconds,
    'maximum_bridge_seconds': maximumBridgeSeconds,
    'alignment_tolerance_ms': alignmentToleranceMilliseconds,
  };

  const SleepWakeEngine();

  static bool supports(SleepMonitorSession session) =>
      featureVersions.contains(session.algorithmVersion);

  /// [smooth] applies the offline backward pass; `false` returns the causal
  /// labels exactly as the live cursor emitted them.
  SleepStageEngineResult run({
    required SleepMonitorSession session,
    required List<SleepMonitorSegment> segments,
    bool smooth = true,
  }) {
    final end = session.endedAt;
    if (end == null || !end.isAfter(session.startedAt) || segments.isEmpty) {
      return const SleepStageEngineResult(ran: false, blockers: ['no_data']);
    }
    final cursor = SleepWakeCursor(
      sessionId: session.id,
      startsAwake: true,
      featureVersion: session.algorithmVersion,
    );
    final decisions = <SleepWakeDecision>[];
    final ordered = [...segments]
      ..sort((a, b) {
        final time = a.startedAt.compareTo(b.startedAt);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    var position = session.startedAt;

    void gap(DateTime until) {
      while (position.isBefore(until)) {
        final seconds = until.difference(position).inSeconds.clamp(0, 30);
        if (seconds == 0) break;
        decisions.add(cursor.missing(position, seconds));
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
      // Native timestamps are whole seconds while the session start keeps
      // milliseconds, so the first window routinely starts <1 s off. That is
      // the same window, not a gap (and not an overlap below).
      if (segment.startedAt.difference(position).inMilliseconds >
          alignmentToleranceMilliseconds) {
        gap(segment.startedAt);
      }
      final clippedStart = position;
      final seconds = clippedEnd.difference(clippedStart).inSeconds;
      if (seconds <= 0) continue;
      final overlapMs = clippedStart
          .difference(segment.startedAt)
          .inMilliseconds;
      // Aggregates from an overlapping/oversized window cannot be attributed
      // to its remaining fragment. Preserve that time as unknown.
      if (overlapMs > alignmentToleranceMilliseconds ||
          segment.durationSeconds > 60) {
        gap(clippedEnd);
        continue;
      }
      decisions.add(
        cursor.add(segment, startedAt: clippedStart, durationSeconds: seconds),
      );
      position = clippedEnd;
    }
    if (position.isBefore(end)) gap(end);

    final epochs = smooth
        ? _smooth(decisions)
        : [for (final d in decisions) d.epoch];
    final reasons = <String, String>{
      for (final d in decisions) d.epoch.id: d.reason,
    };
    final total = end.difference(session.startedAt).inSeconds;
    final knownSeconds = epochs
        .where((e) => e.stage != SleepStageType.unknown)
        .fold<int>(0, (sum, e) => sum + e.durationSeconds);
    return SleepStageEngineResult(
      ran: true,
      epochs: List.unmodifiable(epochs),
      validEpochs: decisions.where((d) => d.validSignal).length,
      unknownEpochs: epochs
          .where((e) => e.stage == SleepStageType.unknown)
          .length,
      coverage: total == 0 ? 0 : knownSeconds / total,
      window: SleepWindow(
        onsetAt: epochs.where((e) => e.isSleep).firstOrNull?.startedAt,
      ),
      decisionReasons: Map.unmodifiable(reasons),
    );
  }

  /// Forward-backward smoothing over the cursor's filtered probabilities.
  static List<SleepStageEpoch> _smooth(List<SleepWakeDecision> decisions) {
    final n = decisions.length;
    if (n == 0) return const [];
    final beta = List<List<double>>.filled(n, const []);
    beta[n - 1] = List<double>.filled(SleepWakeModel.stateCount, 1);
    for (var t = n - 2; t >= 0; t--) {
      beta[t] = SleepWakeModel.backward(
        beta[t + 1],
        decisions[t + 1].likelihoods,
      );
    }
    // Windows without evidence are labelled from context only inside short
    // runs; a long capture failure or steady background stays unknown.
    final bridgeable = List<bool>.filled(n, true);
    var t = 0;
    while (t < n) {
      if (decisions[t].likelihoods != null) {
        t++;
        continue;
      }
      var j = t;
      var seconds = 0;
      while (j < n && decisions[j].likelihoods == null) {
        seconds += decisions[j].epoch.durationSeconds;
        j++;
      }
      if (seconds > maximumBridgeSeconds) {
        for (var k = t; k < j; k++) {
          bridgeable[k] = false;
        }
      }
      t = j;
    }
    return [
      for (var i = 0; i < n; i++)
        _label(
          decisions[i],
          SleepWakeModel.normalize([
            for (var s = 0; s < SleepWakeModel.stateCount; s++)
              decisions[i].probabilities[s] * beta[i][s],
          ]),
          known: decisions[i].validSignal && bridgeable[i],
        ),
    ];
  }

  static SleepStageEpoch _label(
    SleepWakeDecision decision,
    List<double> probabilities, {
    required bool known,
  }) {
    final e = decision.epoch;
    final sleep = SleepWakeModel.sleepProbability(probabilities);
    final stage = !known
        ? SleepStageType.unknown
        : sleep >= 0.5
        ? SleepStageType.sleeping
        : SleepStageType.awake;
    return SleepStageEpoch(
      id: e.id,
      sessionId: e.sessionId,
      startedAt: e.startedAt,
      durationSeconds: e.durationSeconds,
      stage: stage,
      confidence: stage == SleepStageType.unknown
          ? 0
          : (sleep >= 0.5 ? sleep : 1 - sleep),
      awakeProbability: 1 - sleep,
      sleepingProbability: sleep,
      deepProbability: null,
      algorithmVersion: e.algorithmVersion,
      source: e.source,
      movementSeconds: e.movementSeconds,
      snoring: e.snoring,
    );
  }
}

class SleepWakeDecision {
  final SleepStageEpoch epoch;
  final String reason;
  final bool validSignal;

  /// Emission-group likelihoods of the window, null without evidence.
  final List<double>? likelihoods;

  /// Filtered state probabilities after this window.
  final List<double> probabilities;

  const SleepWakeDecision(
    this.epoch,
    this.reason,
    this.validSignal, {
    this.likelihoods,
    this.probabilities = const [],
  });
}

/// Causal forward filter, shared by live UI updates and completed-session
/// replay. Constant space: the state distribution, the room floor spectrum
/// and a counter. Previously emitted epochs are never rewritten.
class SleepWakeCursor {
  final String sessionId;
  final SleepAudioEvidenceExtractor _evidence;
  DateTime? _expectedStart;
  List<double>? _probabilities;
  final List<double> _startProbabilities;
  int _secondsWithoutEvidence = 0;

  /// [startsAwake] is for a cursor that begins at the moment the user started
  /// recording. [featureVersion] is the session's native feature version.
  SleepWakeCursor({
    required this.sessionId,
    bool startsAwake = false,
    String? featureVersion,
  }) : _evidence = SleepAudioEvidenceExtractor(
         bandLimitedBreathing: SleepWakeEngine.bandLimitedBreathingVersions
             .contains(featureVersion),
       ),
       _startProbabilities = startsAwake
           ? SleepWakeModel.startAwake
           : SleepWakeModel.startUnknown;

  /// Current probability that the person is asleep, null before any window.
  double? get sleepProbability => _probabilities == null
      ? null
      : SleepWakeModel.sleepProbability(_probabilities!);

  SleepStageEpoch unknown(DateTime start, int seconds) =>
      _epoch(start, seconds, SleepStageType.unknown, 0, null);

  /// Advances the model through time without capture and labels it unknown.
  SleepWakeDecision missing(DateTime start, int seconds) {
    _step(null);
    _expectedStart = start.add(Duration(seconds: seconds));
    _secondsWithoutEvidence += seconds;
    return SleepWakeDecision(
      unknown(start, seconds),
      'missing_capture',
      false,
      probabilities: _probabilities!,
    );
  }

  SleepWakeDecision add(
    SleepMonitorSegment segment, {
    DateTime? startedAt,
    int? durationSeconds,
  }) {
    final start = startedAt ?? segment.startedAt;
    final seconds = durationSeconds ?? segment.durationSeconds;
    final expected = _expectedStart;
    if (expected != null) {
      final gapMs = start.difference(expected).inMilliseconds;
      if (gapMs > SleepWakeEngine.alignmentToleranceMilliseconds) {
        // Live windows that never arrived: let the model drift through them.
        final steps = (gapMs / 30000).round().clamp(1, 480);
        for (var i = 0; i < steps; i++) {
          _step(null);
        }
        _secondsWithoutEvidence += gapMs ~/ 1000;
      }
    }
    _expectedStart = start.add(Duration(seconds: seconds));
    final evidence = _evidence.evaluate(
      segment,
      sessionId: sessionId,
      seconds: seconds,
    );
    _step(evidence.likelihoods);
    if (evidence.informative) {
      _secondsWithoutEvidence = 0;
    } else {
      _secondsWithoutEvidence += seconds;
    }
    final sleep = SleepWakeModel.sleepProbability(_probabilities!);
    final stage =
        !evidence.validSignal ||
            _secondsWithoutEvidence > SleepWakeEngine.liveEvidenceHoldSeconds
        ? SleepStageType.unknown
        : sleep >= 0.5
        ? SleepStageType.sleeping
        : SleepStageType.awake;
    return SleepWakeDecision(
      _epoch(
        start,
        evidence.validSignal ? seconds : seconds.clamp(1, 60),
        stage,
        sleep,
        evidence,
      ),
      evidence.reason,
      evidence.validSignal,
      likelihoods: evidence.likelihoods,
      probabilities: _probabilities!,
    );
  }

  void _step(List<double>? likelihoods) {
    final prior = _probabilities == null
        ? _startProbabilities
        : SleepWakeModel.predict(_probabilities!);
    _probabilities = SleepWakeModel.update(prior, likelihoods);
  }

  SleepStageEpoch _epoch(
    DateTime start,
    int seconds,
    SleepStageType stage,
    double sleepProbability,
    SleepAudioEvidence? evidence,
  ) {
    final known = stage != SleepStageType.unknown;
    return SleepStageEpoch(
      id: '$sessionId:${start.microsecondsSinceEpoch}',
      sessionId: sessionId,
      startedAt: start,
      durationSeconds: seconds,
      stage: stage,
      confidence: !known
          ? 0
          : (sleepProbability >= 0.5 ? sleepProbability : 1 - sleepProbability),
      awakeProbability: known ? 1 - sleepProbability : null,
      sleepingProbability: known ? sleepProbability : null,
      deepProbability: null,
      algorithmVersion: SleepWakeEngine.algorithmVersion,
      source: SleepWakeEngine.source,
      movementSeconds: evidence?.movementSeconds ?? 0,
      snoring: evidence?.snoring ?? false,
    );
  }
}

/// Result of a staging pass: the labelled epochs plus coverage counters.
class SleepStageEngineResult {
  final Map<String, String> decisionReasons;
  final bool ran;
  final List<SleepStageEpoch> epochs;
  final List<String> blockers;
  final int validEpochs;
  final int unknownEpochs;
  final double coverage;
  final SleepWindow window;

  const SleepStageEngineResult({
    this.decisionReasons = const {},
    required this.ran,
    this.epochs = const [],
    this.blockers = const [],
    this.validEpochs = 0,
    this.unknownEpochs = 0,
    this.coverage = 0,
    this.window = const SleepWindow(),
  });
}

/// The detected sleep period: [onsetAt] is the start of the first sleep.
class SleepWindow {
  final DateTime? onsetAt;

  const SleepWindow({this.onsetAt});
}
