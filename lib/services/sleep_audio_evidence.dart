import 'dart:math' as math;

import 'package:workout_notes/models/sleep_monitor_segment.dart';

/// What one ~30-second audio aggregate says about the person in bed.
///
/// [likelihoods] holds the probability of the window under the three emission
/// groups of [SleepWakeModel] (active wake, quiet wake, sleep). It is null
/// when the window carries no evidence either way (capture failure, a steady
/// loud background, a missing activity measure).
class SleepAudioEvidence {
  final String reason;
  final bool validSignal;
  final List<double>? likelihoods;

  /// Seconds of sound attributed to the person (movement, voice). Ambient
  /// sound and snoring are excluded.
  final double movementSeconds;
  final bool snoring;

  const SleepAudioEvidence({
    required this.reason,
    required this.validSignal,
    required this.likelihoods,
    this.movementSeconds = 0,
    this.snoring = false,
  });

  bool get informative => likelihoods != null;
}

/// Turns native aggregates into [SleepAudioEvidence].
///
/// Stateful only through a small causal estimate of the room's quiet spectrum
/// (a low percentile of the recent windows per band), so every window is
/// judged by how its sound differs from this room's own background rather
/// than by absolute band fractions that depend on the phone's microphone.
class SleepAudioEvidenceExtractor {
  static const minimumValidFraction = 0.8;
  static const maximumZeroSampleFraction = 0.98;

  /// Upper edges (seconds of activity per 30 s) of the activity bins.
  static const activityBinEdges = [1.0, 3.0, 10.0, 20.0];

  /// P(activity bin | emission group). Sleep has occasional short sounds
  /// (turning over); quiet wake is almost as silent; active wake is what
  /// produces sustained sound.
  static const activeWakeActivity = [0.20, 0.12, 0.25, 0.20, 0.23];
  static const quietWakeActivity = [0.785, 0.105, 0.08, 0.02, 0.01];
  static const sleepActivity = [0.80, 0.10, 0.07, 0.02, 0.01];

  /// Relative likelihood of audible periodic breathing in a quiet window.
  static const periodicBreathing = [0.06, 0.12, 0.15];
  static const _periodicBaseline = 0.12;

  /// Snoring happens asleep; awake people practically never snore.
  static const snoringLikelihood = [0.002, 0.002, 0.05];

  static const minimumRegularity = 0.45;
  static const minimumRateHz = 0.15;
  static const maximumRateHz = 0.65;
  static const maximumFlatness = 0.65;
  static const loudActivityNoiseDb = 10.0;
  static const stationaryActiveFraction = 0.8;
  static const minimumVariableLevelStddevDb = 3.0;
  static const snoringLowShare = 0.6;

  /// Ambient sound: narrowband near the floor (absolute rule, v3 onwards) or
  /// a soft window (less than 10x the room floor's energy, RMS under +15 dB)
  /// whose excess is almost all above 1.5 kHz (birds, insects, electronics)
  /// or below 200 Hz (HVAC, traffic rumble). A person moving or speaking next
  /// to the phone is louder and adds energy below 1.5 kHz.
  static const environmentalLowBandFraction = 0.9;
  static const environmentalHighBandFraction = 0.7;
  static const maximumEnvironmentalProminenceDb = 30.0;
  static const maximumEnvironmentalExcessRatio = 10.0;
  static const maximumEnvironmentalNoiseDb = 15.0;
  static const minimumForegroundExcessRatio = 0.5;
  static const environmentalHighExcessShare = 0.8;
  static const environmentalRumbleExcessShare = 0.9;

  static const floorWindows = 40;
  static const minimumFloorWindows = 10;
  static const floorPercentile = 0.2;

  /// audio-features-v5 measures breathing on a 150-2000 Hz envelope, so the
  /// microphone hiss above 4 kHz can no longer fake or mask periodicity.
  final bool bandLimitedBreathing;
  final List<List<double>> _floorHistory = [];

  SleepAudioEvidenceExtractor({this.bandLimitedBreathing = false});

  static const invalid = SleepAudioEvidence(
    reason: 'invalid_capture',
    validSignal: false,
    likelihoods: null,
  );

  SleepAudioEvidence evaluate(
    SleepMonitorSegment segment, {
    required String sessionId,
    required int seconds,
  }) {
    final noise = segment.noiseScore;
    final bands = [
      segment.spectralBandEnergy0,
      segment.spectralBandEnergy1,
      segment.spectralBandEnergy2,
      segment.spectralBandEnergy3,
      segment.spectralBandEnergy4,
    ];
    final zeros = segment.digitalSilenceFraction;
    final valid =
        segment.sessionId == sessionId &&
        seconds > 0 &&
        seconds <= 60 &&
        !segment.isInvalid &&
        segment.validFraction.isFinite &&
        segment.validFraction >= minimumValidFraction &&
        segment.validFraction <= 1 &&
        segment.audioCalibrated != false &&
        // Individual zero-valued PCM samples, not time without capture: quiet
        // quantized audio has many valid zeros. Only near-total digital
        // silence is a capture failure.
        (zeros == null ||
            (zeros.isFinite &&
                zeros >= 0 &&
                zeros < maximumZeroSampleFraction)) &&
        noise != null &&
        noise.isFinite &&
        noise >= 0 &&
        bands.every((v) => v != null && v.isFinite && v >= 0);
    if (!valid) return invalid;
    final energy = [for (final v in bands) v! / seconds];
    final total = energy.fold<double>(0, (sum, v) => sum + v);
    if (!total.isFinite || total <= 0) return invalid;

    final excess = _excessOverFloor(energy);
    _remember(energy);

    final activity = segment.noiseActiveSeconds;
    if (activity == null || !activity.isFinite || activity < 0) {
      return const SleepAudioEvidence(
        reason: 'no_activity_measure',
        validSignal: true,
        likelihoods: null,
      );
    }
    final active = activity.clamp(0, seconds).toDouble();
    final per30 = active * 30 / seconds;
    final bin = _bin(per30);
    final high = (energy[3] + energy[4]) / total;
    final regularity = segment.breathingRegularity;
    final rate = segment.breathingRateHz;
    final flatness = segment.spectralFlatness;
    final periodic =
        regularity != null &&
        regularity.isFinite &&
        regularity >= minimumRegularity &&
        regularity <= 1 &&
        rate != null &&
        rate.isFinite &&
        rate >= minimumRateHz &&
        rate <= maximumRateHz &&
        flatness != null &&
        flatness.isFinite &&
        flatness >= 0 &&
        flatness < maximumFlatness;

    if (bin == 0) {
      final quiet = _groups(0);
      // v3/v4 breathing comes from a full-band envelope, which hiss-dominated
      // windows can fake; v5 already excludes that band.
      if (periodic && (bandLimitedBreathing || high < 0.4)) {
        return SleepAudioEvidence(
          reason: 'periodic_breathing',
          validSignal: true,
          likelihoods: [
            for (var g = 0; g < 3; g++)
              quiet[g] * periodicBreathing[g] / _periodicBaseline,
          ],
        );
      }
      return SleepAudioEvidence(
        reason: 'quiet_audio',
        validSignal: true,
        likelihoods: quiet,
      );
    }

    if (_isEnvironmental(segment, energy, total, excess)) {
      return SleepAudioEvidence(
        reason: 'environmental_sound',
        validSignal: true,
        likelihoods: [for (final v in _groups(0)) math.sqrt(v)],
      );
    }
    final levelStddev = segment.audioLevelStddevDb;
    if (active / seconds >= stationaryActiveFraction &&
        (levelStddev == null ||
            !levelStddev.isFinite ||
            levelStddev < minimumVariableLevelStddevDb)) {
      // A constant loud source (fan, AC) says nothing about the person.
      return const SleepAudioEvidence(
        reason: 'steady_background',
        validSignal: true,
        likelihoods: null,
      );
    }
    final lowShare = excess != null && excess.total > 0
        ? (excess.bands[0] + excess.bands[1]) / excess.total
        : (energy[0] + energy[1]) / total;
    if (periodic && noise >= loudActivityNoiseDb && lowShare >= snoringLowShare) {
      return const SleepAudioEvidence(
        reason: 'snoring',
        validSignal: true,
        likelihoods: snoringLikelihood,
        snoring: true,
      );
    }
    final likelihoods = _groups(bin);
    if (noise >= loudActivityNoiseDb) {
      return SleepAudioEvidence(
        reason: 'audio_activity',
        validSignal: true,
        likelihoods: likelihoods,
        movementSeconds: active,
      );
    }
    // Sound barely above the room level: same shape, half the weight.
    return SleepAudioEvidence(
      reason: 'soft_audio_activity',
      validSignal: true,
      likelihoods: [for (final v in likelihoods) math.sqrt(v)],
      movementSeconds: active,
    );
  }

  static int _bin(double activeSecondsPer30) {
    for (var i = 0; i < activityBinEdges.length; i++) {
      if (activeSecondsPer30 < activityBinEdges[i]) return i;
    }
    return activityBinEdges.length;
  }

  static List<double> _groups(int bin) => [
    activeWakeActivity[bin],
    quietWakeActivity[bin],
    sleepActivity[bin],
  ];

  bool _isEnvironmental(
    SleepMonitorSegment segment,
    List<double> energy,
    double total,
    _Excess? excess,
  ) {
    final peak = segment.audioPeakDbfs;
    final floor = segment.audioBaselineDbfs;
    if (peak != null &&
        floor != null &&
        peak.isFinite &&
        floor.isFinite &&
        peak - floor < maximumEnvironmentalProminenceDb &&
        (energy[0] / total >= environmentalLowBandFraction ||
            (energy[3] + energy[4]) / total >=
                environmentalHighBandFraction)) {
      return true;
    }
    if (excess == null || segment.noiseScore! >= maximumEnvironmentalNoiseDb) {
      return false;
    }
    // Spectrally the same as the last quarter hour of this room: a sound
    // that has been going on long enough to become the background.
    if (excess.ratio < minimumForegroundExcessRatio) return true;
    if (excess.ratio >= maximumEnvironmentalExcessRatio) return false;
    return (excess.bands[3] + excess.bands[4]) / excess.total >=
            environmentalHighExcessShare ||
        excess.bands[0] / excess.total >= environmentalRumbleExcessShare;
  }

  _Excess? _excessOverFloor(List<double> energy) {
    if (_floorHistory.length < minimumFloorWindows) return null;
    final floor = List<double>.filled(5, 0);
    for (var band = 0; band < 5; band++) {
      final values = [for (final w in _floorHistory) w[band]]..sort();
      floor[band] = values[(values.length * floorPercentile).floor()];
    }
    final floorTotal = floor.fold<double>(0, (sum, v) => sum + v);
    if (floorTotal <= 0) return null;
    final bands = [
      for (var band = 0; band < 5; band++)
        math.max(0.0, energy[band] - floor[band]),
    ];
    final total = bands.fold<double>(0, (sum, v) => sum + v);
    return _Excess(bands, total, total / floorTotal);
  }

  void _remember(List<double> energy) {
    _floorHistory.add(energy);
    if (_floorHistory.length > floorWindows) _floorHistory.removeAt(0);
  }
}

class _Excess {
  final List<double> bands;
  final double total;

  /// Excess energy relative to the whole floor spectrum.
  final double ratio;

  const _Excess(this.bands, this.total, this.ratio);
}
