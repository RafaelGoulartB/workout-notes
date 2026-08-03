import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../models/sleep_monitor_segment.dart';
import '../models/sleep_monitor_session.dart';
import '../models/sleep_stage_epoch.dart';
import '../models/sleep_stage_type.dart';

/// Heuristic sleep-stage estimator that fuses spectral audio features with
/// actigraphy into 30-second epochs (awake / sleeping / deep).
///
/// This is a deliberately transparent, privacy-preserving engine: it consumes
/// only the per-window aggregates the Android monitor already persists (band
/// energies, spectral flatness, breathing regularity, motion), applies a small
/// linear feature scorer, then smooths the label sequence with a 3-state
/// Viterbi pass that encodes sleep-architecture priors (no deep right after
/// onset, deep concentrated in the first half of the night, realistic dwell
/// times). It never looks at raw audio.
///
/// The emitted epochs feed [SleepStageAnalysisService.summarize] unchanged.
class SleepStageEngine {
  static const algorithmVersion = 'dart-heuristic-fusion-v1';
  static const source = 'heuristic_fusion';

  // Feature normalization denominators.
  static const noiseNormalizer = 15.0;
  static const burstNormalizer = 20.0;
  static const motionNormalizer = 20.0;

  // Scoring weights.
  static const awakeNoiseWeight = 1.2;
  static const awakeBurstWeight = 1.6;
  static const awakeHfWeight = 1.4;
  static const awakeMotionWeight = 2.2;
  static const awakeRegWeight = 0.8;

  // Deep sleep requires clearly regular slow breathing; applying the weight to
  // regularity^2 makes light sleep (reg ~0.3) fall well short while deep sleep
  // (reg >= 0.7) crosses the threshold.
  static const deepRegWeight = 2.4;
  static const deepLfWeight = 0.7;
  static const deepToneWeight = 0.8;
  static const deepMotionWeight = 1.0;
  static const deepBurstWeight = 1.2;
  static const deepNoiseWeight = 0.8;
  static const deepHfWeight = 0.5;

  static const sleepMotionWeight = 1.4;
  static const sleepBurstWeight = 0.9;
  static const sleepNoiseWeight = 0.3;
  static const sleepBias = 0.4;

  // Sleep-architecture priors.
  static const deepGateMinutes = 20;
  static const deepGateLogit = -5.0;
  static const deepPriorStart = 0.8;

  // Confidence blending.
  static const confidencePosteriorWeight = 0.55;
  static const confidenceMarginWeight = 0.25;
  static const confidenceQualityWeight = 0.20;

  // Eligibility.
  static const minScorableEpochs = 10;

  static const parameters = <String, num>{
    'noise_normalizer': noiseNormalizer,
    'burst_normalizer': burstNormalizer,
    'motion_normalizer': motionNormalizer,
    'awake_noise_weight': awakeNoiseWeight,
    'awake_burst_weight': awakeBurstWeight,
    'awake_hf_weight': awakeHfWeight,
    'awake_motion_weight': awakeMotionWeight,
    'awake_reg_weight': awakeRegWeight,
    'deep_reg_weight': deepRegWeight,
    'deep_lf_weight': deepLfWeight,
    'deep_tone_weight': deepToneWeight,
    'deep_motion_weight': deepMotionWeight,
    'deep_burst_weight': deepBurstWeight,
    'deep_noise_weight': deepNoiseWeight,
    'deep_hf_weight': deepHfWeight,
    'sleep_motion_weight': sleepMotionWeight,
    'sleep_burst_weight': sleepBurstWeight,
    'sleep_noise_weight': sleepNoiseWeight,
    'sleep_bias': sleepBias,
    'deep_gate_minutes': deepGateMinutes,
    'deep_prior_start': deepPriorStart,
    'confidence_posterior_weight': confidencePosteriorWeight,
    'confidence_margin_weight': confidenceMarginWeight,
    'confidence_quality_weight': confidenceQualityWeight,
    'min_scorable_epochs': minScorableEpochs,
  };

  const SleepStageEngine();

  SleepStageEngineResult run({
    required SleepMonitorSession session,
    required List<SleepMonitorSegment> segments,
    DateTime? onset,
  }) {
    final blockers = <String>[];
    final ordered = [...segments]
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final sessionEnd = session.endedAt ?? session.startedAt;
    if (ordered.isEmpty || !sessionEnd.isAfter(session.startedAt)) {
      blockers.add('no_data');
      return SleepStageEngineResult(ran: false, blockers: blockers);
    }
    if (!ordered.any((segment) => segment.hasSpectralFeatures)) {
      blockers.add('legacy_recording');
      return SleepStageEngineResult(ran: false, blockers: blockers);
    }

    // Per-window features. Windows that cannot be scored (invalid, digital
    // silence, or missing spectral signal) stay null and become unknown epochs.
    final windowFeatures = <_WindowFeatures?>[
      for (final segment in ordered) _featuresOf(segment),
    ];
    final scorable = <int>[
      for (var i = 0; i < ordered.length; i++)
        if (windowFeatures[i] != null) i,
    ];
    if (scorable.length < minScorableEpochs) {
      blockers.add('insufficient_spectral_data');
      return SleepStageEngineResult(ran: false, blockers: blockers);
    }
    final scorableIndexBySegment = <int, int>{
      for (var k = 0; k < scorable.length; k++) scorable[k]: k,
    };

    final viterbi = _ViterbiPass(
      [for (final index in scorable) windowFeatures[index]!],
      session,
      sessionEnd,
      onset,
    ).run();

    final epochs = <SleepStageEpoch>[];
    final uuid = const Uuid();
    for (var i = 0; i < ordered.length; i++) {
      final segment = ordered[i];
      final feature = windowFeatures[i];
      final scorableIndex = feature == null ? null : scorableIndexBySegment[i];
      final (stage, confidence, probs) = scorableIndex == null
          ? (
              SleepStageType.unknown,
              0.0,
              _zeroProbs,
            )
          : viterbi.epochAt(scorableIndex);
      epochs.add(
        SleepStageEpoch(
          id: uuid.v4(),
          sessionId: session.id,
          startedAt: segment.startedAt,
          durationSeconds: segment.durationSeconds,
          stage: stage,
          confidence: confidence,
          awakeProbability: probs.awake,
          sleepingProbability: probs.sleeping,
          deepProbability: probs.deep,
          algorithmVersion: algorithmVersion,
          source: source,
        ),
      );
    }

    final known = epochs.where((e) => e.stage != SleepStageType.unknown).length;
    return SleepStageEngineResult(
      ran: true,
      epochs: List.unmodifiable(epochs),
      blockers: blockers,
      validEpochs: scorable.length,
      unknownEpochs: epochs.length - known,
      coverage: epochs.isEmpty ? 0 : known / epochs.length,
    );
  }

  /// Returns normalized features for a scorable window, or null when the
  /// window cannot be staged (invalid, digital silence, missing signal).
  _WindowFeatures? _featuresOf(SleepMonitorSegment segment) {
    if (segment.isInvalid || segment.validFraction < 0.5) return null;
    if (segment.noiseScore == null || !segment.hasSpectralFeatures) return null;
    final flatness = segment.spectralFlatness;
    if (flatness == null || !flatness.isFinite || flatness < 0) return null;
    final totalBand =
        (segment.spectralBandEnergy0 ?? 0) +
        (segment.spectralBandEnergy1 ?? 0) +
        (segment.spectralBandEnergy2 ?? 0) +
        (segment.spectralBandEnergy3 ?? 0) +
        (segment.spectralBandEnergy4 ?? 0);
    if (totalBand <= 0) return null;

    final highFreq =
        (segment.spectralBandEnergy3 ?? 0) + (segment.spectralBandEnergy4 ?? 0);
    final lowFreq = (segment.spectralBandEnergy0 ?? 0) +
        (segment.spectralBandEnergy1 ?? 0);
    final regularity = segment.breathingRegularity ?? 0;
    final motionSeconds = segment.motionActiveSeconds ?? 0;

    return _WindowFeatures(
      startedAt: segment.startedAt,
      nNoise: (segment.noiseScore! / noiseNormalizer).clamp(0.0, 1.0),
      nBurst: (segment.noiseBurstCount / burstNormalizer).clamp(0.0, 1.0),
      highFreqFraction: (highFreq / totalBand).clamp(0.0, 1.0),
      lowFreqFraction: (lowFreq / totalBand).clamp(0.0, 1.0),
      tone: (1 - flatness).clamp(0.0, 1.0),
      regularity: regularity.clamp(0.0, 1.0),
      motion: (motionSeconds / motionNormalizer).clamp(0.0, 1.0),
      signalQuality: segment.validFraction.clamp(0.0, 1.0),
    );
  }
}

/// Result of a heuristic staging pass.
class SleepStageEngineResult {
  final bool ran;
  final List<SleepStageEpoch> epochs;
  final List<String> blockers;
  final int validEpochs;
  final int unknownEpochs;
  final double coverage;

  const SleepStageEngineResult({
    required this.ran,
    this.epochs = const [],
    this.blockers = const [],
    this.validEpochs = 0,
    this.unknownEpochs = 0,
    this.coverage = 0,
  });
}

/// Probability triple for an epoch. Zeros when the window is unknown.
class _EpochProbs {
  final double awake;
  final double sleeping;
  final double deep;

  const _EpochProbs(this.awake, this.sleeping, this.deep);
}

const _zeroProbs = _EpochProbs(0, 0, 0);

class _WindowFeatures {
  final DateTime startedAt;
  final double nNoise;
  final double nBurst;
  final double highFreqFraction;
  final double lowFreqFraction;
  final double tone;
  final double regularity;
  final double motion;
  final double signalQuality;

  const _WindowFeatures({
    required this.startedAt,
    required this.nNoise,
    required this.nBurst,
    required this.highFreqFraction,
    required this.lowFreqFraction,
    required this.tone,
    required this.regularity,
    required this.motion,
    required this.signalQuality,
  });
}

/// A single (startedAt, endedAt) pair preserved for position-based priors.
class _ViterbiPass {
  static const _states = 3;
  static const _awake = 0;
  static const _sleeping = 1;
  static const _deep = 2;

  static const _transition = <List<double>>[
    [0.90, 0.10, 0.00], // awake -> sleeping is the only exit
    [0.03, 0.94, 0.03], // sleeping -> deep and -> awake
    [0.01, 0.07, 0.92], // deep stays long
  ];
  static const _initial = [0.6, 0.3, 0.1];

  final List<_WindowFeatures> _features;
  final SleepMonitorSession _session;
  final DateTime _sessionEnd;
  final DateTime? _onset;
  late final List<List<double>> _logT;
  late final List<double> _logPi;

  _ViterbiPass(
    this._features,
    this._session,
    this._sessionEnd,
    this._onset,
  ) {
    _logT = [
      for (final row in _transition)
        [for (final value in row) value <= 0 ? double.negativeInfinity : math.log(value)],
    ];
    _logPi = [for (final value in _initial) math.log(value)];
  }

  _ViterbiResult run() {
    final n = _features.length;
    // Viterbi in log space.
    final dp = List.generate(n, (_) => List.filled(_states, double.negativeInfinity));
    final back = List.generate(n, (_) => List.filled(_states, 0));
    for (var s = 0; s < _states; s++) {
      dp[0][s] = _logPi[s] + math.log(_emission(s, 0));
    }
    for (var i = 1; i < n; i++) {
      for (var s = 0; s < _states; s++) {
        var best = double.negativeInfinity;
        var bestPrev = 0;
        for (var p = 0; p < _states; p++) {
          if (_logT[p][s] == double.negativeInfinity) continue;
          final score = dp[i - 1][p] + _logT[p][s];
          if (score > best) {
            best = score;
            bestPrev = p;
          }
        }
        dp[i][s] = best + math.log(_emission(s, i));
        back[i][s] = bestPrev;
      }
    }
    var lastState = 0;
    var lastBest = double.negativeInfinity;
    for (var s = 0; s < _states; s++) {
      if (dp[n - 1][s] > lastBest) {
        lastBest = dp[n - 1][s];
        lastState = s;
      }
    }
    final path = List.filled(n, 0);
    path[n - 1] = lastState;
    for (var i = n - 1; i > 0; i--) {
      path[i - 1] = back[i][path[i]];
    }

    // Forward-backward for posterior marginals, in log space to avoid
    // underflow over a full night.
    final lAlpha = List.generate(n, (_) => List.filled(_states, double.negativeInfinity));
    final lBeta = List.generate(n, (_) => List.filled(_states, double.negativeInfinity));
    for (var s = 0; s < _states; s++) {
      lAlpha[0][s] = _logPi[s] + math.log(_emission(s, 0));
    }
    for (var i = 1; i < n; i++) {
      for (var s = 0; s < _states; s++) {
        lAlpha[i][s] = _logSumExp([
          for (var p = 0; p < _states; p++)
            if (_logT[p][s] != double.negativeInfinity)
              lAlpha[i - 1][p] + _logT[p][s],
        ]) + math.log(_emission(s, i));
      }
    }
    for (var s = 0; s < _states; s++) {
      lBeta[n - 1][s] = 0.0;
    }
    for (var i = n - 2; i >= 0; i--) {
      for (var s = 0; s < _states; s++) {
        lBeta[i][s] = _logSumExp([
          for (var s2 = 0; s2 < _states; s2++)
            if (_logT[s][s2] != double.negativeInfinity)
              _logT[s][s2] + math.log(_emission(s2, i + 1)) + lBeta[i + 1][s2],
        ]);
      }
    }

    final labels = List<_EpochLabel>.generate(n, (i) {
      final state = path[i];
      final maxPosterior = _posteriorMax(i, lAlpha, lBeta);
      final confidence = _confidence(i, state, maxPosterior);
      final probs = _posteriorProbs(i, lAlpha, lBeta);
      return _EpochLabel(
        stage: switch (state) {
          _awake => SleepStageType.awake,
          _sleeping => SleepStageType.sleeping,
          _ => SleepStageType.deep,
        },
        confidence: confidence,
        probs: probs,
      );
    });

    return _ViterbiResult(labels);
  }

  double _emission(int state, int index) {
    final f = _features[index];
    final logits = _logits(f);
    final awake = math.exp(logits.awake - _logMax(logits));
    final sleeping = math.exp(logits.sleeping - _logMax(logits));
    final deep = math.exp(logits.deep - _logMax(logits));
    final sum = awake + sleeping + deep;
    return switch (state) {
      _awake => awake / sum,
      _sleeping => sleeping / sum,
      _ => deep / sum,
    };
  }

  _Logits _logits(_WindowFeatures f) {
    final deepPrior = _deepPrior(f);
    final regSquared = f.regularity * f.regularity;
    return _Logits(
      awake: SleepStageEngine.awakeNoiseWeight * f.nNoise +
          SleepStageEngine.awakeBurstWeight * f.nBurst +
          SleepStageEngine.awakeHfWeight * f.highFreqFraction +
          SleepStageEngine.awakeMotionWeight * f.motion -
          SleepStageEngine.awakeRegWeight * f.regularity,
      sleeping: SleepStageEngine.sleepMotionWeight * (1 - f.motion) +
          SleepStageEngine.sleepBurstWeight * (1 - f.nBurst) +
          SleepStageEngine.sleepNoiseWeight * (1 - f.nNoise) +
          SleepStageEngine.sleepBias,
      deep: SleepStageEngine.deepRegWeight * regSquared +
          SleepStageEngine.deepLfWeight * f.lowFreqFraction +
          SleepStageEngine.deepToneWeight * f.tone -
          SleepStageEngine.deepMotionWeight * f.motion -
          SleepStageEngine.deepBurstWeight * f.nBurst -
          SleepStageEngine.deepNoiseWeight * f.nNoise -
          SleepStageEngine.deepHfWeight * f.highFreqFraction +
          deepPrior,
    );
  }

  /// Deep is structurally unlikely right after sleep onset and, across the
  /// night, concentrated in the first half.
  double _deepPrior(_WindowFeatures f) {
    final gate = (_onset ?? _session.startedAt.add(const Duration(minutes: 5)))
        .add(const Duration(minutes: SleepStageEngine.deepGateMinutes));
    if (f.startedAt.isBefore(gate)) {
      return SleepStageEngine.deepGateLogit;
    }
    final totalSeconds = _sessionEnd.difference(_session.startedAt).inSeconds;
    if (totalSeconds <= 0) return 0.0;
    final progress =
        (f.startedAt.difference(_session.startedAt).inSeconds / totalSeconds)
            .clamp(0.0, 1.0);
    return SleepStageEngine.deepPriorStart *
        math.max(0.0, (1.2 - progress) / 0.6);
  }

  double _posteriorMax(
    int index,
    List<List<double>> lAlpha,
    List<List<double>> lBeta,
  ) {
    final probs = _posteriorProbs(index, lAlpha, lBeta);
    return math.max(probs.awake, math.max(probs.sleeping, probs.deep));
  }

  _EpochProbs _posteriorProbs(
    int index,
    List<List<double>> lAlpha,
    List<List<double>> lBeta,
  ) {
    final logZ = _logSumExp([
      for (var s = 0; s < _states; s++) lAlpha[index][s] + lBeta[index][s],
    ]);
    final probs = <double>[
      for (var s = 0; s < _states; s++) math.exp(lAlpha[index][s] + lBeta[index][s] - logZ),
    ];
    return _EpochProbs(probs[_awake], probs[_sleeping], probs[_deep]);
  }

  double _confidence(int index, int state, double maxPosterior) {
    final f = _features[index];
    final logits = _logits(f);
    final sorted = [logits.awake, logits.sleeping, logits.deep]..sort((a, b) => b.compareTo(a));
    final featureMargin = ((sorted[0] - sorted[1]) / 4).clamp(0.0, 1.0);
    final confidence =
        SleepStageEngine.confidencePosteriorWeight * maxPosterior +
        SleepStageEngine.confidenceMarginWeight * featureMargin +
        SleepStageEngine.confidenceQualityWeight * f.signalQuality;
    return confidence.clamp(0.0, 1.0);
  }

  double _logMax(_Logits logits) => math.max(
    logits.awake,
    math.max(logits.sleeping, logits.deep),
  );

  double _logSumExp(List<double> values) {
    if (values.isEmpty) return double.negativeInfinity;
    var maxValue = values.first;
    for (final value in values.skip(1)) {
      if (value > maxValue) maxValue = value;
    }
    var sum = 0.0;
    for (final value in values) {
      sum += math.exp(value - maxValue);
    }
    return maxValue + math.log(sum);
  }
}

class _Logits {
  final double awake;
  final double sleeping;
  final double deep;

  const _Logits({
    required this.awake,
    required this.sleeping,
    required this.deep,
  });
}

class _EpochLabel {
  final SleepStageType stage;
  final double confidence;
  final _EpochProbs probs;

  const _EpochLabel({
    required this.stage,
    required this.confidence,
    required this.probs,
  });
}

class _ViterbiResult {
  final List<_EpochLabel> labels;

  const _ViterbiResult(this.labels);

  (SleepStageType, double, _EpochProbs) epochAt(int index) {
    final label = labels[index];
    return (label.stage, label.confidence, label.probs);
  }
}
