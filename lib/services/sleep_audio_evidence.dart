import 'dart:math' as math;

import 'package:workout_notes/models/sleep_monitor_segment.dart';

/// What one ~30-second audio aggregate says about the person in bed.
///
/// [likelihoods] holds the probability of the window under the three emission
/// groups of [SleepWakeModel] (active wake, quiet wake, sleep). It is null
/// when the window carries no evidence either way (capture failure, a steady
/// loud background, no room floor yet, digitally silent bands, a missing
/// activity measure).
class SleepAudioEvidence {
  final String reason;
  final bool validSignal;
  final List<double>? likelihoods;

  /// Seconds of sound attributed to the person (movement, voice). Ambient
  /// sound and snoring are excluded.
  final double movementSeconds;

  /// Seconds of sound attributed to the room (birds, traffic, HVAC).
  final double ambientSeconds;
  final bool snoring;

  const SleepAudioEvidence({
    required this.reason,
    required this.validSignal,
    required this.likelihoods,
    this.movementSeconds = 0,
    this.ambientSeconds = 0,
    this.snoring = false,
  });

  bool get informative => likelihoods != null;
}

/// Turns native aggregates into [SleepAudioEvidence].
///
/// The question it answers is "did a person next to the phone make a sound
/// in this window?", and the answer rests on one physical difference. A body
/// moving in bed, bedding, a voice or a hand on the phone is close to the
/// microphone and raises **every** frequency band at once. Sound from
/// outside the room is coloured by its source and by the walls: birds and
/// insects only reach the bands above 1.5 kHz, traffic and thunder mostly the
/// one below 200 Hz, a dove or a distant voice the middle.
///
/// So each band is compared, in dB, with this room's own recent quiet level
/// ([_floor]) and the window is scored by its **second-smallest** band
/// excess: at least four of the five bands must have risen by that much. One
/// band may stay masked by the ambient sound of the moment.
///
/// What this cannot do, by construction:
/// - A sound whose 30-second level stays within a few dB for five minutes
///   becomes the room, whoever makes it: a video, a conversation at an even
///   level, a crying baby next to the phone. At the very start of a night,
///   with no quiet to compare with, that takes a minute and a half. Someone
///   watching a video reads as still, exactly like someone who fell asleep
///   to a podcast; only what stands out of it counts. A person whose sound
///   comes and goes (every real wake recorded so far) is not affected.
/// - Bursty sound that stays in a few bands counts as a still person
///   (`environmental_sound`), not as missing evidence. That is what lets a
///   morning of birds and traffic be sleep, and it rests on a movement still
///   standing out of that sound, which holds while the room is not much
///   louder than a movement.
/// - Broadband, bursty, strongly varying room sound (a storm with gusts)
///   looks like a person.
/// - Low-pitched sound at a breathing rate for a minute or more reads as
///   snoring, whoever makes it (a snoring bed partner, heavy breathing while
///   awake), and a movement inside a snoring run is labelled snoring too.
///   Snoring that stops every other window is still scored as movement. No
///   recorded night has snoring.
/// - The dB thresholds are relative to the microphone's own noise floor and
///   were set on one phone in one bedroom.
class SleepAudioEvidenceExtractor {
  static const minimumValidFraction = 0.8;
  static const maximumZeroSampleFraction = 0.98;

  /// Upper edges (dB of broadband excess) of the score bins: still, faint,
  /// movement, strong movement.
  static const faintScoreDb = 4.0;
  static const movementScoreDb = 8.0;
  static const strongMovementScoreDb = 14.0;
  static const scoreBinEdges = [
    faintScoreDb,
    movementScoreDb,
    strongMovementScoreDb,
  ];

  /// P(score bin | emission group). Someone awake and active is silent in
  /// some windows; a sleeper turns over now and then, and a little ambient
  /// sound always leaks into the score. A faint score is equally likely in
  /// every group: it carries no evidence, and neither does a broadband sound
  /// the rules below attribute to the room. Quiet wake must never be less
  /// likely to move than sleep, or silence would favour lying awake.
  static const activeWakeScore = [0.42, 0.10, 0.15, 0.33];
  static const quietWakeScore = [0.84, 0.10, 0.045, 0.015];
  static const sleepScore = [0.86, 0.10, 0.03, 0.01];

  /// Loud, periodic, low-frequency sound: people snore asleep.
  static const snoringLikelihood = [0.02, 0.04, 0.10];

  /// The floor of a band is the 20th percentile of the last 20 minutes: a
  /// person's sounds are intermittent at that scale and never reach it.
  static const floorWindows = 40;
  static const minimumFloorWindows = 3;
  static const floorPercentile = 0.2;

  /// ...or the lowest level of the last five minutes when that is higher: a
  /// band that has not dropped once in five minutes holds a new room sound
  /// (rain starting, a dawn chorus), which would otherwise read as movement
  /// for the quarter of an hour the percentile needs.
  static const recentFloorWindows = 10;

  /// Band energies at or below this are digital silence in that band. A band
  /// whose floor is silent has no level to rise from and is left out of the
  /// score; the score needs [minimumScoredBands] of them.
  static const minimumBandEnergy = 1e-18;
  static const minimumScoredBands = 4;

  /// A movement is a burst: at least this much of the window stood 10 dB
  /// above the native 5-minute level baseline. A broadband rise without any
  /// burst is a sound that has been going on for minutes (rain, a fan).
  static const minimumBurstSeconds = 1.0;

  /// Less than this share of the energy added over the floor lies above
  /// 1.5 kHz: a vehicle, thunder or a door slammed somewhere else, whose
  /// rumble is loud enough to leak into every band. A person next to the
  /// phone always adds more (measured on added energy, not on the dB excess,
  /// so it still holds while birdsong masks the high bands).
  static const rumbleHighShare = 0.02;

  /// A constant loud source (fan, AC) before the native baseline absorbs it.
  static const stationaryActiveFraction = 0.8;
  static const minimumVariableLevelStddevDb = 3.0;

  /// Snoring: a loud window, mostly below 600 Hz, modulated at a breathing
  /// rate, and the second such window in a row (snoring goes on; a single
  /// window can be periodic by chance). It is judged before the score, as
  /// loud snoring next to the phone reaches every band.
  static const minimumRegularity = 0.45;
  static const minimumRateHz = 0.15;
  static const maximumRateHz = 0.5;
  static const maximumFlatness = 0.65;
  static const snoringNoiseDb = 10.0;
  static const snoringLowShare = 0.6;

  /// Recent band levels in dB, oldest first.
  final List<List<double>> _levels = [];
  bool _previousSnoreLike = false;

  static const invalid = SleepAudioEvidence(
    reason: 'invalid_capture',
    validSignal: false,
    likelihoods: null,
  );

  /// Windows are missing before the next one: a run of snoring does not
  /// continue across them.
  void interrupt() => _previousSnoreLike = false;

  /// [segment] is judged over its own duration, whatever part of it the
  /// caller labels.
  SleepAudioEvidence evaluate(
    SleepMonitorSegment segment, {
    required String sessionId,
  }) {
    final seconds = segment.durationSeconds;
    final level = _bandLevels(segment, sessionId: sessionId);
    if (level == null) {
      _previousSnoreLike = false;
      return invalid;
    }
    final floor = _floor();
    _levels.add(level);
    if (_levels.length > floorWindows) _levels.removeAt(0);
    final snoreLikeBefore = _previousSnoreLike;
    _previousSnoreLike = false;

    final activity = segment.noiseActiveSeconds;
    if (activity == null || !activity.isFinite || activity < 0) {
      return const SleepAudioEvidence(
        reason: 'no_activity_measure',
        validSignal: true,
        likelihoods: null,
      );
    }
    final active = activity.clamp(0, seconds).toDouble();
    if (floor == null) {
      return const SleepAudioEvidence(
        reason: 'calibrating',
        validSignal: true,
        likelihoods: null,
      );
    }
    final levelStddev = segment.audioLevelStddevDb;
    if (active / seconds >= stationaryActiveFraction &&
        (levelStddev == null ||
            !levelStddev.isFinite ||
            levelStddev < minimumVariableLevelStddevDb)) {
      return const SleepAudioEvidence(
        reason: 'steady_background',
        validSignal: true,
        likelihoods: null,
      );
    }

    final silent = _decibels(0);
    final excess = [
      for (var band = 0; band < 5; band++)
        if (floor[band] > silent) level[band] - floor[band],
    ]..sort();
    if (excess.length < minimumScoredBands) {
      return const SleepAudioEvidence(
        reason: 'silent_bands',
        validSignal: true,
        likelihoods: null,
      );
    }
    final burst = active >= minimumBurstSeconds;
    final snoreLike =
        burst &&
        segment.noiseScore! >= snoringNoiseDb &&
        _periodic(segment) &&
        _lowShare(level) >= snoringLowShare;
    _previousSnoreLike = snoreLike;
    if (snoreLike && snoreLikeBefore) {
      return const SleepAudioEvidence(
        reason: 'snoring',
        validSignal: true,
        likelihoods: snoringLikelihood,
        snoring: true,
      );
    }
    final bin = _bin(excess[1]);
    if (bin < 2) {
      return SleepAudioEvidence(
        reason: bin == 1
            ? 'faint_sound'
            : burst
            ? 'environmental_sound'
            : 'quiet_audio',
        validSignal: true,
        likelihoods: _groups(bin),
        ambientSeconds: burst ? active : 0,
      );
    }
    // Every band rose, but not the way a person next to the phone does it.
    // Neither says anything about the person: both weigh like a faint sound.
    if (!burst) {
      return SleepAudioEvidence(
        reason: 'sustained_sound',
        validSignal: true,
        likelihoods: _groups(1),
      );
    }
    if (_addedHighShare(level, floor) < rumbleHighShare) {
      return SleepAudioEvidence(
        reason: 'low_rumble',
        validSignal: true,
        likelihoods: _groups(1),
        ambientSeconds: active,
      );
    }
    return SleepAudioEvidence(
      reason: bin == 2 ? 'movement' : 'strong_movement',
      validSignal: true,
      likelihoods: _groups(bin),
      movementSeconds: active,
    );
  }

  static double _decibels(double energy) =>
      10 * math.log(math.max(energy, minimumBandEnergy)) / math.ln10;

  static int _bin(double score) {
    for (var i = 0; i < scoreBinEdges.length; i++) {
      if (score < scoreBinEdges[i]) return i;
    }
    return scoreBinEdges.length;
  }

  static List<double> _groups(int bin) => [
    activeWakeScore[bin],
    quietWakeScore[bin],
    sleepScore[bin],
  ];

  static bool _periodic(SleepMonitorSegment segment) {
    final regularity = segment.breathingRegularity;
    final rate = segment.breathingRateHz;
    final flatness = segment.spectralFlatness;
    return regularity != null &&
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
  }

  /// Share of the energy above the room floor that lies above 1.5 kHz.
  static double _addedHighShare(List<double> level, List<double> floor) {
    var high = 0.0;
    var all = 0.0;
    for (var band = 0; band < 5; band++) {
      final added = math.max(
        0.0,
        math.pow(10, level[band] / 10) - math.pow(10, floor[band] / 10),
      );
      all += added;
      if (band >= 3) high += added;
    }
    return all > 0 ? high / all : 1;
  }

  /// Share of the window's energy below 600 Hz.
  static double _lowShare(List<double> level) {
    final energy = [for (final v in level) math.pow(10, v / 10)];
    final total = energy.fold<double>(0, (sum, v) => sum + v);
    return total > 0 ? (energy[0] + energy[1]) / total : 0;
  }

  /// Band levels in dB of a usable window, null for a capture failure.
  static List<double>? _bandLevels(
    SleepMonitorSegment segment, {
    required String sessionId,
  }) {
    final seconds = segment.durationSeconds;
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
    if (!valid) return null;
    final energy = [for (final v in bands) v! / seconds];
    final total = energy.fold<double>(0, (sum, v) => sum + v);
    if (!total.isFinite || total <= 0) return null;
    return [for (final v in energy) _decibels(v)];
  }

  /// The room's quiet level per band, from the windows before this one.
  List<double>? _floor() {
    final count = _levels.length;
    if (count < minimumFloorWindows) return null;
    final index = (count * floorPercentile).floor();
    final recent = count < recentFloorWindows
        ? null
        : _levels.sublist(count - recentFloorWindows);
    return [
      for (var band = 0; band < 5; band++)
        math.max(
          ([for (final window in _levels) window[band]]..sort())[index],
          recent == null
              ? double.negativeInfinity
              : recent.map((window) => window[band]).reduce(math.min),
        ),
    ];
  }
}
