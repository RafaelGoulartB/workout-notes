import 'dart:convert';

import 'package:workout_notes/models/sleep_stage_epoch.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';

/// Minute-by-minute summary of a staged night, small enough to keep on the
/// session row (~2 KB for a full night) so the night chart can be drawn
/// without storing the 30-second epochs.
///
/// Every series has one value per [stepSeconds] from the session start.
class SleepNightTimeline {
  static const version = 1;
  static const defaultStepSeconds = 60;

  /// 64 levels per character: probabilities are quantized to 1/63, seconds
  /// per minute are stored as whole seconds (0..60).
  static const _alphabet =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_';
  static const _missing = '.';

  final int stepSeconds;
  final List<SleepStageType> stages;

  /// Model probability of being asleep; null where nothing was classified.
  final List<double?> sleepProbability;

  /// Seconds of sound attributed to the person (movement, voice) per step.
  final List<int> movementSeconds;

  /// Seconds of sound attributed to the room (birds, HVAC, traffic) per step.
  final List<int> ambientSeconds;
  final List<bool> snoring;

  const SleepNightTimeline({
    this.stepSeconds = defaultStepSeconds,
    required this.stages,
    required this.sleepProbability,
    required this.movementSeconds,
    required this.ambientSeconds,
    required this.snoring,
  });

  int get length => stages.length;

  bool get hasSnoring => snoring.any((v) => v);

  /// Buckets [epochs] into steps. Each step takes the stage covering most of
  /// it, the time-weighted mean probability of its classified part, and the
  /// share of each epoch's sound that falls inside it.
  static SleepNightTimeline? fromEpochs({
    required DateTime start,
    required DateTime end,
    required List<SleepStageEpoch> epochs,
    int stepSeconds = defaultStepSeconds,
  }) {
    final total = end.difference(start).inSeconds;
    if (total <= 0 || epochs.isEmpty || stepSeconds <= 0) return null;
    final steps = (total / stepSeconds).ceil();
    final stageSeconds = List.generate(steps, (_) => <SleepStageType, int>{});
    final pWeighted = List<double>.filled(steps, 0);
    final pSeconds = List<int>.filled(steps, 0);
    final movement = List<double>.filled(steps, 0);
    final ambient = List<double>.filled(steps, 0);
    final snore = List<bool>.filled(steps, false);
    for (final epoch in epochs) {
      final from = epoch.startedAt.difference(start).inSeconds;
      final duration = epoch.durationSeconds.clamp(1, 3600);
      final to = from + duration;
      if (to <= 0 || from >= total) continue;
      for (
        var step = (from.clamp(0, total - 1) ~/ stepSeconds);
        step < steps && step * stepSeconds < to;
        step++
      ) {
        final stepFrom = step * stepSeconds;
        final overlap =
            (to < stepFrom + stepSeconds ? to : stepFrom + stepSeconds) -
            (from > stepFrom ? from : stepFrom);
        if (overlap <= 0) continue;
        final seconds = stageSeconds[step];
        seconds[epoch.stage] = (seconds[epoch.stage] ?? 0) + overlap;
        final p = epoch.sleepingProbability;
        if (epoch.stage != SleepStageType.unknown && p != null) {
          pWeighted[step] += p * overlap;
          pSeconds[step] += overlap;
        }
        movement[step] += epoch.movementSeconds * overlap / duration;
        ambient[step] += epoch.ambientSeconds * overlap / duration;
        if (epoch.snoring) snore[step] = true;
      }
    }
    return SleepNightTimeline(
      stepSeconds: stepSeconds,
      stages: [
        for (final seconds in stageSeconds)
          seconds.isEmpty
              ? SleepStageType.unknown
              : (seconds.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value)))
                    .first
                    .key,
      ],
      sleepProbability: [
        for (var i = 0; i < steps; i++)
          pSeconds[i] == 0 ? null : pWeighted[i] / pSeconds[i],
      ],
      movementSeconds: [
        for (final v in movement) v.round().clamp(0, stepSeconds),
      ],
      ambientSeconds: [
        for (final v in ambient) v.round().clamp(0, stepSeconds),
      ],
      snoring: snore,
    );
  }

  String encode() => jsonEncode({
    'v': version,
    'step': stepSeconds,
    'stage': stages.map(_stageChar).join(),
    'p': sleepProbability
        .map(
          (p) => p == null ? _missing : _alphabet[(p.clamp(0, 1) * 63).round()],
        )
        .join(),
    'move': movementSeconds.map(_secondsChar).join(),
    'amb': ambientSeconds.map(_secondsChar).join(),
    if (hasSnoring) 'snore': snoring.map((v) => v ? '1' : '0').join(),
  });

  /// Null for missing or unreadable data; the chart is then simply hidden.
  static SleepNightTimeline? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map || map['v'] != version) return null;
      final step = map['step'];
      final stage = map['stage'];
      final p = map['p'];
      final move = map['move'];
      final amb = map['amb'];
      final snore = map['snore'] ?? '';
      if (step is! int ||
          step <= 0 ||
          stage is! String ||
          p is! String ||
          move is! String ||
          amb is! String ||
          snore is! String) {
        return null;
      }
      final n = stage.length;
      if (n == 0 ||
          p.length != n ||
          move.length != n ||
          amb.length != n ||
          (snore.isNotEmpty && snore.length != n)) {
        return null;
      }
      int level(String c) {
        final v = _alphabet.indexOf(c);
        if (v < 0) throw const FormatException('timeline level');
        return v;
      }

      return SleepNightTimeline(
        stepSeconds: step,
        stages: [for (final c in stage.split('')) _stageOf(c)],
        sleepProbability: [
          for (final c in p.split('')) c == _missing ? null : level(c) / 63,
        ],
        movementSeconds: [for (final c in move.split('')) level(c)],
        ambientSeconds: [for (final c in amb.split('')) level(c)],
        snoring: snore.isEmpty
            ? List<bool>.filled(n, false)
            : [for (final c in snore.split('')) c == '1'],
      );
    } on FormatException {
      return null;
    }
  }

  static String _secondsChar(int seconds) =>
      _alphabet[seconds.clamp(0, _alphabet.length - 1)];

  static String _stageChar(SleepStageType stage) => switch (stage) {
    SleepStageType.awake => 'a',
    SleepStageType.sleeping => 's',
    SleepStageType.deep => 'd',
    SleepStageType.unknown => 'u',
  };

  static SleepStageType _stageOf(String c) => switch (c) {
    'a' => SleepStageType.awake,
    's' => SleepStageType.sleeping,
    'd' => SleepStageType.deep,
    _ => SleepStageType.unknown,
  };
}
