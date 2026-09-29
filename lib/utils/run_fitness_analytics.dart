import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/utils/run_analytics_dates.dart';

/// Fitness from running efforts: the VDOT estimate, race predictions and the
/// monthly fitness curve.
///
/// Works on already-loaded [RunActivity] lists so it can be unit-tested without
/// a database. Fitness numbers are estimates (Daniels' VDOT model) and are
/// never more precise than the effort data feeding them.
abstract final class RunFitnessAnalytics {
  /// Fixed race distances for the predictor table.
  static const List<double> raceDistances = [
    RunPaceCalculator.fiveKMeters,
    RunPaceCalculator.tenKMeters,
    RunPaceCalculator.halfMeters,
    RunPaceCalculator.marathonMeters,
  ];

  /// Best-effort samples usable for a VDOT estimate. 1 km is left out: the
  /// model overrates sub-4-minute efforts.
  static List<RunEffortSample> effortsOf(RunActivity a) {
    if (!a.isRun) return const [];
    final date = a.startedAt.toLocal();
    RunEffortSample? sample(double meters, int? seconds) =>
        seconds == null || seconds <= 0
        ? null
        : RunEffortSample(
            activityId: a.id,
            date: date,
            distanceMeters: meters,
            timeSeconds: seconds,
          );
    return [
      ?sample(3000, a.bestEffort3kSec),
      ?sample(RunPaceCalculator.fiveKMeters, a.bestEffort5kSec),
      ?sample(RunPaceCalculator.tenKMeters, a.bestEffort10kSec),
      ?sample(RunPaceCalculator.halfMeters, a.bestEffortHalfSec),
      ?sample(RunPaceCalculator.marathonMeters, a.bestEffortMarathonSec),
    ];
  }

  /// Whole-run sample for activities with no usable best effort. A training
  /// run is rarely a maximal effort, so this only ever underestimates.
  static RunEffortSample? trainingRunSample(RunActivity a) {
    if (!a.isRun) return null;
    final seconds = a.movingTimeSeconds > 0
        ? a.movingTimeSeconds
        : a.durationSeconds;
    if (a.distanceMeters < 3000 || seconds <= 0) return null;
    if (!RunPaceCalculator.isPlausibleRace(
      distanceMeters: a.distanceMeters,
      timeSeconds: seconds,
    )) {
      return null;
    }
    return RunEffortSample(
      activityId: a.id,
      date: a.startedAt.toLocal(),
      distanceMeters: a.distanceMeters,
      timeSeconds: seconds,
    );
  }

  static double vdotOf(RunEffortSample sample) => RunPaceCalculator.vdotFor(
    distanceMeters: sample.distanceMeters,
    timeSeconds: sample.timeSeconds,
  );

  /// Current fitness from the best recent effort. Looks at the last
  /// [windowDays] days first, then the last year (flagged [RunFitnessEstimate.isStale]),
  /// and only falls back to plain training runs when no effort exists.
  static RunFitnessEstimate? estimate(
    List<RunActivity> activities, {
    DateTime? now,
    int windowDays = 90,
  }) {
    final today = RunAnalyticsDates.day(now ?? DateTime.now());
    final runs = activities.where(RunAnalyticsDates.completedRun).toList();

    RunEffortSample? best(Iterable<RunEffortSample> samples, int days) {
      final from = today.subtract(Duration(days: days));
      RunEffortSample? top;
      var topVdot = 0.0;
      for (final s in samples) {
        if (RunAnalyticsDates.day(s.date).isBefore(from) ||
            RunAnalyticsDates.day(s.date).isAfter(today)) {
          continue;
        }
        final v = vdotOf(s);
        if (v > topVdot) {
          topVdot = v;
          top = s;
        }
      }
      return top;
    }

    final efforts = [for (final a in runs) ...effortsOf(a)];
    var source = best(efforts, windowDays);
    var stale = false;
    var fromTraining = false;
    if (source == null) {
      source = best(efforts, 365);
      stale = source != null;
    }
    if (source == null) {
      final training = <RunEffortSample>[
        for (final a in runs) ?trainingRunSample(a),
      ];
      source = best(training, windowDays);
      fromTraining = source != null;
    }
    if (source == null) return null;
    final vdot = vdotOf(source);
    if (!vdot.isFinite || vdot < 15 || vdot > 90) return null;
    return RunFitnessEstimate(
      vdot: vdot,
      source: source,
      isStale: stale,
      fromTrainingRuns: fromTraining,
      paces: RunPaceCalculator.fromVdot(vdot),
      predictions: predictRaces(vdot),
    );
  }

  static List<RunRacePrediction> predictRaces(double vdot) => [
    for (final meters in raceDistances)
      () {
        final pace = RunPaceCalculator.racePaceFor(vdot, meters);
        return RunRacePrediction(
          distanceMeters: meters,
          paceSecPerKm: pace,
          timeSeconds: (pace * meters / 1000).round(),
        );
      }(),
  ];

  /// Best VDOT per calendar month over the last [months] months, oldest
  /// first. Months without data are skipped. Uses best efforts; when the
  /// range has none at all it falls back to whole training runs.
  static List<RunVdotPoint> vdotByMonth(
    List<RunActivity> activities, {
    int months = 12,
    DateTime? now,
  }) {
    final today = RunAnalyticsDates.day(now ?? DateTime.now());
    final firstMonth = DateTime(today.year, today.month - (months - 1));
    final runs = activities.where(RunAnalyticsDates.completedRun).where((a) {
      final d = a.startedAt.toLocal();
      return !d.isBefore(firstMonth) &&
          !RunAnalyticsDates.day(d).isAfter(today);
    }).toList();

    var samples = [for (final a in runs) ...effortsOf(a)];
    if (samples.isEmpty) {
      samples = [for (final a in runs) ?trainingRunSample(a)];
    }
    final byMonth = <DateTime, double>{};
    for (final s in samples) {
      final key = DateTime(s.date.year, s.date.month);
      final v = vdotOf(s);
      if (!v.isFinite || v < 15 || v > 90) continue;
      if (v > (byMonth[key] ?? 0)) byMonth[key] = v;
    }
    final keys = byMonth.keys.toList()..sort();
    return [for (final k in keys) RunVdotPoint(month: k, vdot: byMonth[k]!)];
  }
}

/// A distance/time pair that can be turned into a VDOT.
class RunEffortSample {
  final String activityId;
  final DateTime date;
  final double distanceMeters;
  final int timeSeconds;

  const RunEffortSample({
    required this.activityId,
    required this.date,
    required this.distanceMeters,
    required this.timeSeconds,
  });
}

class RunFitnessEstimate {
  final double vdot;

  /// The effort the estimate comes from.
  final RunEffortSample source;

  /// Best effort is older than the recent window (up to a year old).
  final bool isStale;

  /// No best effort was available; estimated from an ordinary training run,
  /// so the real fitness is likely higher.
  final bool fromTrainingRuns;
  final RunPaces paces;
  final List<RunRacePrediction> predictions;

  const RunFitnessEstimate({
    required this.vdot,
    required this.source,
    required this.isStale,
    required this.fromTrainingRuns,
    required this.paces,
    required this.predictions,
  });

  RunZoneBounds get zones => RunZoneBounds.fromPaces(paces);
}

class RunVdotPoint {
  final DateTime month;
  final double vdot;

  const RunVdotPoint({required this.month, required this.vdot});
}

class RunRacePrediction {
  final double distanceMeters;
  final int timeSeconds;
  final double paceSecPerKm;

  const RunRacePrediction({
    required this.distanceMeters,
    required this.timeSeconds,
    required this.paceSecPerKm,
  });
}

/// Pace zones from a fitness index. Boundaries are slower-than pace limits:
/// easy pace (~66% VO2max), marathon pace, threshold (T) and interval (I).
enum RunZone { z1, z2, z3, z4, z5 }

class RunZoneBounds {
  final double easySecPerKm;
  final double marathonSecPerKm;
  final double tempoSecPerKm;
  final double intervalSecPerKm;

  const RunZoneBounds({
    required this.easySecPerKm,
    required this.marathonSecPerKm,
    required this.tempoSecPerKm,
    required this.intervalSecPerKm,
  });

  factory RunZoneBounds.fromPaces(RunPaces paces) => RunZoneBounds(
    easySecPerKm: paces.easySecPerKm,
    marathonSecPerKm: paces.marathonSecPerKm,
    tempoSecPerKm: paces.tempoSecPerKm,
    intervalSecPerKm: paces.intervalSecPerKm,
  );

  RunZone zoneFor(double paceSecPerKm) {
    if (paceSecPerKm >= easySecPerKm) return RunZone.z1;
    if (paceSecPerKm >= marathonSecPerKm) return RunZone.z2;
    if (paceSecPerKm >= tempoSecPerKm) return RunZone.z3;
    if (paceSecPerKm >= intervalSecPerKm) return RunZone.z4;
    return RunZone.z5;
  }

  /// Slowest and fastest pace of [zone] in sec/km; the open ends are null.
  (double? slowest, double? fastest) rangeOf(RunZone zone) => switch (zone) {
    RunZone.z1 => (null, easySecPerKm),
    RunZone.z2 => (easySecPerKm, marathonSecPerKm),
    RunZone.z3 => (marathonSecPerKm, tempoSecPerKm),
    RunZone.z4 => (tempoSecPerKm, intervalSecPerKm),
    RunZone.z5 => (intervalSecPerKm, null),
  };
}
