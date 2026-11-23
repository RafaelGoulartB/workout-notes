import 'dart:math' as math;

import 'package:workout_notes/models/sleep_monitor_segment.dart';

/// What one ~30-second audio/device aggregate says about the person in bed.
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

  /// Seconds of sound or phone use attributed to the person (movement, voice,
  /// active device use). Ambient sound and snoring are excluded.
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

/// Turns native bedside aggregates into [SleepAudioEvidence].
///
/// Two complementary sources answer "is the person awake/moving next to the
/// phone?":
/// 1. **Bedside device interaction (`audio-features-v6`):** event-driven screen
///    unlock duration (`device_active_seconds`) and hardware significant-motion
///    triggers paired with a screen wake (`phone_pickup_count` +
///    `screen_on_seconds`). A lockscreen notification alone is ignored (and a
///    12 s grace filters notification wakes without a real unlock from a locked
///    keyguard), Android dreams / screen savers stop device interaction, and an
///    unlocked screen sitting motionless for more than 45 minutes (autoplay /
///    stay-awake while charging) stops overriding audio.
/// 2. **Broadband acoustic evidence (`v3`–`v6`):** a body moving in bed,
///    bedding, a voice or a hand on the phone raises **every** frequency band
///    at once, while birds (>1.5 kHz), traffic (<200 Hz) or a dove (mid-band)
///    only raise some.
///    - On `audio-features-v6`, `broadband_active_seconds` is measured natively
///      on every 125 ms FFT frame against a rolling 5-minute per-band floor, so
///      brief 1–2 s movements are not diluted by 30-second averaging and a bird
///      chirp at t=4 s never overlaps a truck at t=22 s.
///    - On `audio-features-v3`–`v5`, each band's 30-second level is compared in
///      dB with its recent quiet floor ([_floor]) and scored by its
///      second-smallest band excess, with a scale-invariant dB tilt filter
///      ([rumbleTiltDb]) for passing trucks/thunder.
///
/// What this cannot do, by construction:
/// - Quiet wakefulness with the screen off still looks like sleep; the HMM's
///   transition priors assume sleep a few minutes after the last movement.
/// - A sound with an even level for five minutes while the screen is off
///   (radio, TV across the room, steady talk) becomes the room.
/// - A gusty storm with >8 dB broadband gusts can still look like a person.
/// - Low-pitched periodic sound at a breathing rate for a minute or more reads
///   as snoring whoever makes it (a bed partner), and no recorded night has
///   snoring yet.
/// - The dB thresholds were validated on recorded bedside nights from one
///   phone/bedroom plus synthetic audio fixtures.
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

  /// Active use of the unlocked phone: strong evidence of wakefulness even in
  /// silence or steady video audio.
  static const deviceInteractionLikelihood = [0.45, 0.02, 0.005];

  /// Loud, periodic, low-frequency sound: people snore asleep.
  static const snoringLikelihood = [0.02, 0.04, 0.10];

  /// Device interaction thresholds (`audio-features-v6`).
  static const minimumDeviceActiveSeconds = 5.0;
  static const minimumPickupScreenSeconds = 1.0;
  static const motionlessUnlockedSeconds = 25.0;

  /// After 45 minutes (90 windows) of an unlocked screen with zero motion
  /// triggers, stop overriding audio so stay-awake / autoplay never ruins an
  /// entire night while still covering long bedtime reading or scrolling.
  static const maximumMotionlessUnlockedWindows = 90;

  /// Per-frame broadband burst thresholds (`audio-features-v6`).
  static const faintBroadbandBurstSeconds = 0.375;
  static const minimumBroadbandBurstSeconds = 1.0;
  static const strongBroadbandBurstSeconds = 4.0;

  /// An unbroken broadband rise still active at the end of a window for at
  /// least [stepOnsetTailSeconds] with < [stepOnsetMaxPriorSeconds] earlier
  /// in the window is a step onset (AC/fan switching on), not a person burst.
  static const stepOnsetTailSeconds = 5.0;
  static const stepOnsetMaxPriorSeconds = 0.5;

  /// Persistent v6 broadband activity (present in at least
  /// [roomAdaptedPersistenceWindows] of the last [recentFloorWindows] windows
  /// once the 5-minute floor is full) whose 30-second spectrum stays within
  /// [roomAdaptedFloorExcessDb] of the floor has become the room (bedtime
  /// podcast, TV, gusty storm, dripping/ticking).
  static const roomAdaptedPersistenceWindows = 8;
  static const roomAdaptedFloorExcessDb = 4.0;

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
  /// above the native 5-minute level baseline (legacy `v3`–`v5` path).
  static const minimumBurstSeconds = 1.0;

  /// Low-frequency rumble (passing truck, thunder, distant door slam) requires
  /// both a steep sub-200 Hz dB rise over >1.5 kHz ([rumbleTiltDb], keeping
  /// uniform movements over a fan floor from being rejected) and a tiny share
  /// of added linear energy above 1.5 kHz ([rumbleHighShare], keeping close
  /// movements while birds mask the high-band floor from being rejected).
  static const rumbleTiltDb = 15.0;
  static const rumbleHighShare = 0.03;

  /// A constant loud source (fan, AC, steady rain) before the baseline absorbs
  /// it.
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

  /// Whether each of the last [recentFloorWindows] windows had v6 broadband
  /// activity.
  final List<bool> _recentBroadbandActive = [];
  bool _previousSnoreLike = false;
  int _motionlessUnlockedWindows = 0;
  bool _previousHadPickup = false;
  bool _previousHadScreenOn = false;

  static const invalid = SleepAudioEvidence(
    reason: 'invalid_capture',
    validSignal: false,
    likelihoods: null,
  );

  /// Windows are missing before the next one: runs do not continue across gaps.
  void interrupt() {
    _previousSnoreLike = false;
    _motionlessUnlockedWindows = 0;
    _previousHadPickup = false;
    _previousHadScreenOn = false;
    _recentBroadbandActive.clear();
  }

  /// [segment] is judged over its own duration, whatever part of it the
  /// caller labels.
  SleepAudioEvidence evaluate(
    SleepMonitorSegment segment, {
    required String sessionId,
  }) {
    final seconds = segment.durationSeconds;
    if (segment.sessionId != sessionId || seconds <= 0 || seconds > 60) {
      _previousSnoreLike = false;
      _motionlessUnlockedWindows = 0;
      _previousHadPickup = false;
      _previousHadScreenOn = false;
      _recentBroadbandActive.clear();
      return invalid;
    }

    final level = _bandLevels(segment, sessionId: sessionId);
    final priorFloorCount = _levels.length;
    final floor = level == null ? null : _floor();
    if (level != null) {
      _levels.add(level);
      if (_levels.length > floorWindows) _levels.removeAt(0);
    }
    final snoreLikeBefore = _previousSnoreLike;
    _previousSnoreLike = false;

    final rawActivity = segment.noiseActiveSeconds;
    final activeOrZero =
        rawActivity != null && rawActivity.isFinite && rawActivity >= 0
        ? rawActivity.clamp(0, seconds).toDouble()
        : 0.0;

    // Bedside device signals (audio-features-v6): evaluated even when another
    // app temporarily silences the mic or while the acoustic floor calibrates.
    final deviceActive = _clampPositive(segment.deviceActiveSeconds, seconds);
    final screenOn = _clampPositive(segment.screenOnSeconds, seconds);
    final pickups = (segment.phonePickupCount ?? 0).clamp(0, 1000);
    final hadPickup = pickups >= 1;
    final hadScreenOn = screenOn >= minimumPickupScreenSeconds;
    final prevPickup = _previousHadPickup;
    final prevScreenOn = _previousHadScreenOn;
    _previousHadPickup = hadPickup;
    _previousHadScreenOn = hadScreenOn;

    if (deviceActive >= motionlessUnlockedSeconds && pickups == 0) {
      _motionlessUnlockedWindows++;
    } else {
      _motionlessUnlockedWindows = 0;
    }
    if (deviceActive >= minimumDeviceActiveSeconds &&
        _motionlessUnlockedWindows <= maximumMotionlessUnlockedWindows) {
      // Clear pickup carry-over once active use is credited so a pickup during
      // an unlocked window cannot fire phone_pickup on the next window.
      _previousHadPickup = false;
      _previousHadScreenOn = false;
      _recentBroadbandActive.clear();
      return SleepAudioEvidence(
        reason: 'device_interaction',
        validSignal: true,
        likelihoods: deviceInteractionLikelihood,
        movementSeconds: math.max(activeOrZero, deviceActive),
      );
    }
    if ((hadPickup && (hadScreenOn || prevScreenOn)) ||
        (prevPickup && hadScreenOn)) {
      // Clear carry-over once credited so one pickup cannot trigger two windows.
      _previousHadPickup = false;
      _previousHadScreenOn = false;
      _recentBroadbandActive.clear();
      return SleepAudioEvidence(
        reason: 'phone_pickup',
        validSignal: true,
        likelihoods: _groups(3),
        movementSeconds: math
            .max(activeOrZero, hadScreenOn ? screenOn : 1.0)
            .clamp(1.0, seconds.toDouble()),
      );
    }

    if (level == null) return invalid;
    if (rawActivity == null || !rawActivity.isFinite || rawActivity < 0) {
      return const SleepAudioEvidence(
        reason: 'no_activity_measure',
        validSignal: true,
        likelihoods: null,
      );
    }
    final active = activeOrZero;
    final levelStddev = segment.audioLevelStddevDb;
    final steadyLevel =
        levelStddev == null ||
        !levelStddev.isFinite ||
        levelStddev < minimumVariableLevelStddevDb;

    final bbActiveRaw = segment.broadbandActiveSeconds;
    final hasFrameBroadband =
        bbActiveRaw != null && bbActiveRaw.isFinite && bbActiveRaw >= 0;
    final bbActive = hasFrameBroadband
        ? bbActiveRaw.clamp(0, seconds).toDouble()
        : 0.0;

    if (!hasFrameBroadband && floor == null) {
      return const SleepAudioEvidence(
        reason: 'calibrating',
        validSignal: true,
        likelihoods: null,
      );
    }
    if ((active / seconds >= stationaryActiveFraction ||
            (hasFrameBroadband &&
                bbActive / seconds >= stationaryActiveFraction)) &&
        steadyLevel) {
      if (hasFrameBroadband) _recordRecentBroadbandActive(false);
      return const SleepAudioEvidence(
        reason: 'steady_background',
        validSignal: true,
        likelihoods: null,
      );
    }

    final burst = active >= minimumBurstSeconds;

    if (hasFrameBroadband) {
      final isBroadbandActive = bbActive >= minimumBroadbandBurstSeconds;
      final snoreLike =
          burst &&
          segment.noiseScore! >= snoringNoiseDb &&
          _periodic(segment) &&
          _lowShare(level) >= snoringLowShare;
      _previousSnoreLike = snoreLike;
      if (snoreLike && snoreLikeBefore) {
        _recordRecentBroadbandActive(false);
        return const SleepAudioEvidence(
          reason: 'snoring',
          validSignal: true,
          likelihoods: snoringLikelihood,
          snoring: true,
        );
      }
      final recentActiveCount = _recentBroadbandActive.where((v) => v).length;
      _recordRecentBroadbandActive(isBroadbandActive);
      final bbStrong = _clampPositive(segment.broadbandStrongSeconds, seconds);
      final bbTail = _clampPositive(segment.broadbandTailSeconds, seconds);
      final bbPeak =
          segment.broadbandPeakDb != null && segment.broadbandPeakDb!.isFinite
          ? segment.broadbandPeakDb!
          : 0.0;
      if (isBroadbandActive) {
        // An unbroken rise still running at window end (AC/fan switching on
        // mid-window) is treated as neutral sustained sound rather than a
        // sudden movement burst.
        if (bbTail >= stepOnsetTailSeconds &&
            bbActive - bbTail < stepOnsetMaxPriorSeconds) {
          return SleepAudioEvidence(
            reason: 'sustained_sound',
            validSignal: true,
            likelihoods: _groups(1),
          );
        }
        // After a full 5-minute floor (10 windows), persistent broadband
        // activity in >= 8 of the last 10 windows whose 30-second spectrum
        // stays within 4 dB of the room floor has become the room (podcast,
        // TV, gusty storm, recurring clicks/dripping).
        if (floor != null &&
            priorFloorCount >= recentFloorWindows &&
            recentActiveCount >= roomAdaptedPersistenceWindows) {
          final silent = _decibels(0);
          final excess30s = [
            for (var band = 0; band < 5; band++)
              if (floor[band] > silent) level[band] - floor[band],
          ]..sort();
          if (excess30s.length >= minimumScoredBands &&
              excess30s[1] < roomAdaptedFloorExcessDb) {
            return SleepAudioEvidence(
              reason: 'environmental_sound',
              validSignal: true,
              likelihoods: _groups(0),
              ambientSeconds: burst ? active : 0,
            );
          }
        }
        final strong =
            bbStrong >= minimumBroadbandBurstSeconds ||
            bbActive >= strongBroadbandBurstSeconds ||
            (bbPeak >= strongMovementScoreDb && bbActive >= 2.0);
        final bin = strong ? 3 : 2;
        return SleepAudioEvidence(
          reason: bin == 2 ? 'movement' : 'strong_movement',
          validSignal: true,
          likelihoods: _groups(bin),
          movementSeconds: bbActive,
        );
      }
      if (bbActive >= faintBroadbandBurstSeconds) {
        return SleepAudioEvidence(
          reason: 'faint_sound',
          validSignal: true,
          likelihoods: _groups(1),
        );
      }
      return SleepAudioEvidence(
        reason: burst ? 'environmental_sound' : 'quiet_audio',
        validSignal: true,
        likelihoods: _groups(0),
        ambientSeconds: burst ? active : 0,
      );
    }

    // Legacy 30-second spectral path (audio-features-v3/v4/v5).
    final silent = _decibels(0);
    final rawExcess = <double?>[
      for (var band = 0; band < 5; band++)
        floor![band] > silent ? level[band] - floor[band] : null,
    ];
    final excess = [for (final value in rawExcess) ?value]..sort();
    if (excess.length < minimumScoredBands) {
      return const SleepAudioEvidence(
        reason: 'silent_bands',
        validSignal: true,
        likelihoods: null,
      );
    }
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
        ambientSeconds: bin == 0 && burst ? active : 0,
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
    if (_isLowRumble(level, floor!, rawExcess)) {
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

  static double _clampPositive(double? value, int maxSeconds) =>
      value != null && value.isFinite && value > 0
      ? value.clamp(0, maxSeconds).toDouble()
      : 0.0;

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

  /// True when band 0 (<200 Hz) rose at least [rumbleTiltDb] more than either
  /// band above 1.5 kHz AND less than [rumbleHighShare] of the added energy
  /// lies above 1.5 kHz. Requiring both keeps uniform movements on a fan floor
  /// and close-range movements during loud birdsong from being misclassified.
  static bool _isLowRumble(
    List<double> level,
    List<double> floor,
    List<double?> rawExcess,
  ) {
    final low = rawExcess[0];
    if (low == null) return false;
    final b3 = rawExcess[3];
    final b4 = rawExcess[4];
    final double? high;
    if (b3 != null && b4 != null) {
      high = math.max(b3, b4);
    } else {
      high = b3 ?? b4;
    }
    if (high == null || low - high < rumbleTiltDb) return false;
    return _addedHighShare(level, floor) < rumbleHighShare;
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

  void _recordRecentBroadbandActive(bool active) {
    _recentBroadbandActive.add(active);
    if (_recentBroadbandActive.length > recentFloorWindows) {
      _recentBroadbandActive.removeAt(0);
    }
  }
}
