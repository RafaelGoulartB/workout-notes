/// Hidden Markov model of a night in bed, one step per ~30-second window.
///
/// Five states: settling wake (before the first sleep) and wake after sleep
/// onset, each split into an active state (sound of a person) and a quiet
/// state (lying still), plus sleep. Settling and later wake are separate
/// because they behave differently: falling asleep the first time usually
/// takes longer than falling back asleep after a short arousal.
///
/// A bedside microphone cannot tell quiet wake from sleep, so their
/// emissions are nearly equal and the transition priors decide how long a
/// silent stretch stays "awake" after the last sound of a person. The
/// probabilities are model probabilities, not calibrated against
/// polysomnography.
class SleepWakeModel {
  static const settlingActive = 0;
  static const settlingQuiet = 1;
  static const wakeActive = 2;
  static const wakeQuiet = 3;
  static const asleep = 4;
  static const stateCount = 5;

  /// Emission group of each state: 0 active wake, 1 quiet wake, 2 sleep.
  static const emissionGroup = [0, 1, 0, 1, 2];

  /// Row = from, column = to, per 30-second step.
  static const transitions = <List<double>>[
    // Settling: ~7 min of silence after the last movement before sleep.
    [0.85, 0.14, 0, 0, 0.01],
    [0.02, 0.95, 0, 0, 0.03],
    // After sleep onset: falling back asleep takes ~3 min of silence.
    [0, 0, 0.85, 0.13, 0.02],
    [0, 0, 0.04, 0.86, 0.10],
    // Sleep: an arousal every ~35 min on average, most of them brief.
    [0, 0, 0.010, 0.004, 0.986],
  ];

  /// Starting a recording is itself evidence the user is awake.
  static const startAwake = [0.7, 0.3, 0.0, 0.0, 0.0];

  /// A cursor joining an ongoing night knows nothing about it.
  static const startUnknown = [0.15, 0.15, 0.1, 0.1, 0.5];

  static List<double> predict(List<double> p) {
    final out = List<double>.filled(stateCount, 0);
    for (var i = 0; i < stateCount; i++) {
      if (p[i] == 0) continue;
      final row = transitions[i];
      for (var j = 0; j < stateCount; j++) {
        out[j] += p[i] * row[j];
      }
    }
    return out;
  }

  /// Bayes update with the likelihood of the window under each emission
  /// group; `null` (no evidence) keeps the prediction.
  static List<double> update(List<double> predicted, List<double>? groups) {
    final out = [
      for (var i = 0; i < stateCount; i++)
        predicted[i] * (groups == null ? 1 : groups[emissionGroup[i]]),
    ];
    return normalize(out);
  }

  /// One backward step: `beta_t` from `beta_{t+1}` and the evidence of t+1.
  static List<double> backward(List<double> next, List<double>? groups) {
    final out = List<double>.filled(stateCount, 0);
    for (var i = 0; i < stateCount; i++) {
      final row = transitions[i];
      var sum = 0.0;
      for (var j = 0; j < stateCount; j++) {
        if (row[j] == 0) continue;
        sum +=
            row[j] *
            (groups == null ? 1 : groups[emissionGroup[j]]) *
            next[j];
      }
      out[i] = sum;
    }
    return normalize(out);
  }

  static List<double> normalize(List<double> p) {
    final total = p.fold<double>(0, (sum, v) => sum + v);
    if (!total.isFinite || total <= 0) {
      return List<double>.filled(stateCount, 1 / stateCount);
    }
    return [for (final v in p) v / total];
  }

  static double sleepProbability(List<double> p) => p[asleep];
}
