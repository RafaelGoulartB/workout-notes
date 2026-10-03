import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/exercise_with_sets.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/repositories/workout_repository.dart';
import 'package:workout_notes/utils/app_number_format.dart';
import 'package:workout_notes/utils/strength_workout_format.dart';
import 'package:workout_notes/utils/strength_workout_records.dart';
import 'package:workout_notes/utils/workout_estimator.dart';
import 'package:workout_notes/widgets/workout/finish_workout_sheet.dart';

/// Builds the summary shown when finishing a workout: duration, volume, sets,
/// cardio totals, estimated calories and the personal records the session
/// set. No [BuildContext]; the totals and strength records are pure
/// ([totals], [strengthRecords]) and the rest reads through the repositories.
class WorkoutSummaryService {
  final WorkoutRepository _workoutRepo;
  final BodyMeasurementRepository _bodyRepo;
  final StrengthRecordsRepository _recordsRepo;

  WorkoutSummaryService({
    WorkoutRepository? workoutRepo,
    BodyMeasurementRepository? bodyRepo,
    StrengthRecordsRepository? recordsRepo,
  }) : _workoutRepo = workoutRepo ?? DatabaseHelper.instance.workoutRepo,
       _bodyRepo = bodyRepo ?? DatabaseHelper.instance.bodyMeasurementRepo,
       _recordsRepo =
           recordsRepo ?? DatabaseHelper.instance.strengthRecordsRepo;

  /// Duration, volume, sets, distance/time and PRs of the running workout.
  ///
  /// [workoutId] null skips the record detection (nothing to compare).
  /// [cardioExerciseIds] are the aerobic exercises: they never count for
  /// strength records.
  Future<WorkoutSummary> compute({
    required AppLocalizations loc,
    required String? workoutId,
    required List<ExerciseWithSets> exercises,
    required Set<String> cardioExerciseIds,
    DateTime? timerStart,
    DateTime? timerEnd,
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    var durationSeconds = 0;
    if (timerStart != null) {
      final end = timerEnd ?? clock;
      durationSeconds = end.difference(timerStart).inSeconds;
    }
    final calorieDurationSeconds = durationSeconds > 0
        ? durationSeconds
        : estimateDurationSeconds(exercises);
    final bodyWeightKg = await _bodyRepo.getLatestWeightKg();
    final estimatedCalories = WorkoutEstimateCalculator.estimateCalories(
      durationSeconds: calorieDurationSeconds,
      bodyWeightKg: bodyWeightKg,
    );

    final totals = WorkoutSummaryService.totals(exercises, loc);

    final prs = <PR>[];
    if (workoutId != null) {
      // Strength records: compare this session's sets with every earlier
      // finished workout (best e1RM, heaviest load, session volume).
      final history = await _recordsRepo.loadSets();
      prs.addAll(
        strengthRecords(
          loc: loc,
          workoutId: workoutId,
          exercises: exercises,
          cardioExerciseIds: cardioExerciseIds,
          history: history,
          now: clock,
        ),
      );
      prs.addAll(await _cardioRecords(workoutId, totals.cardioByExercise));
    }

    return WorkoutSummary(
      durationSeconds: durationSeconds,
      totalVolume: totals.totalVolume,
      totalSets: totals.totalSets,
      completedSets: totals.completedSets,
      totalDistance: totals.totalDistance,
      totalCardioTime: totals.totalCardioTime,
      estimatedCalories: estimatedCalories,
      prs: prs,
    );
  }

  /// Planned duration of the exercises as they stand (sets, reps, rests).
  static int estimateDurationSeconds(List<ExerciseWithSets> exercises) {
    final estimateExercises = exercises.map(
      (exercise) => WorkoutEstimateExercise(
        restTimeSeconds: exercise.restTimeSeconds,
        sets: exercise.sets
            .map(
              (set) => WorkoutEstimateSet(
                reps: (set['reps'] as num?)?.toInt(),
                timeSeconds: (set['time_seconds'] as num?)?.toInt(),
              ),
            )
            .toList(),
      ),
    );
    return WorkoutEstimateCalculator.estimateDurationSeconds(estimateExercises);
  }

  /// Working-set totals. Warm-up sets count for nothing; volume only for
  /// completed sets; distance and time for every working set.
  static WorkoutSummaryTotals totals(
    List<ExerciseWithSets> exercises,
    AppLocalizations loc,
  ) {
    var totalVolume = 0.0;
    var totalSets = 0;
    var completedSets = 0;
    var totalDistance = 0.0;
    var totalCardioTime = 0;
    final cardio = <String, CardioBests>{};

    for (final ex in exercises) {
      var exerciseDistance = 0.0;
      var exerciseTime = 0;

      for (final s in ex.sets) {
        final isComplete = (s['is_complete'] as int?) == 1;
        final isWarmup = (s['is_warmup'] as int?) == 1;
        if (isWarmup) continue;

        totalSets++;
        final dist = (s['distance'] as num?)?.toDouble() ?? 0;
        final time = (s['time_seconds'] as int?) ?? 0;
        if (dist > 0) {
          exerciseDistance += dist;
          totalDistance += dist;
        }
        if (time > 0) {
          exerciseTime += time;
          totalCardioTime += time;
        }
        if (isComplete) {
          completedSets++;
          final weight = (s['weight'] as num?)?.toDouble() ?? 0;
          final reps = (s['reps'] as int?) ?? 0;
          totalVolume += weight * reps;
        }
      }

      // Track cardio bests (longest distance, best pace).
      if (exerciseDistance > 0 && exerciseTime > 0) {
        cardio[ex.exerciseId] = CardioBests(
          name: ex.localizedName(loc),
          distance: exerciseDistance,
          timeSeconds: exerciseTime,
        );
      }
    }

    return WorkoutSummaryTotals(
      totalVolume: totalVolume,
      totalSets: totalSets,
      completedSets: completedSets,
      totalDistance: totalDistance,
      totalCardioTime: totalCardioTime,
      cardioByExercise: cardio,
    );
  }

  /// Records set by the running workout, computed with the same rules as the
  /// records screen (completed, non-warm-up, weighted strength sets) against
  /// the [history] of finished workouts.
  static List<PR> strengthRecords({
    required AppLocalizations loc,
    required String workoutId,
    required List<ExerciseWithSets> exercises,
    required Set<String> cardioExerciseIds,
    required List<StrengthSetSample> history,
    required DateTime now,
  }) {
    final session = <StrengthSetSample>[];
    for (final ex in exercises) {
      if (cardioExerciseIds.contains(ex.exerciseId)) continue;
      for (final s in ex.sets) {
        if ((s['is_warmup'] as int?) == 1 || (s['is_complete'] as int?) != 1) {
          continue;
        }
        final weight = (s['weight'] as num?)?.toDouble() ?? 0;
        final reps = (s['reps'] as num?)?.toInt() ?? 0;
        if (weight <= 0 || reps <= 0) continue;
        session.add(
          StrengthSetSample(
            workoutId: workoutId,
            date: now,
            exerciseId: ex.exerciseId,
            exerciseName: ex.name,
            exerciseLocaleKey: ex.localeKey,
            categoryId: ex.categoryId ?? '',
            weight: weight,
            reps: reps,
          ),
        );
      }
    }
    if (session.isEmpty) return const [];

    final events = StrengthWorkoutRecords.sessionEvents(
      history: history,
      session: session,
      workoutId: workoutId,
    );
    final volumes = StrengthWorkoutRecords.volumeRecords(
      history: history,
      session: session,
      workoutId: workoutId,
    );

    final prs = <PR>[];
    for (final ex in exercises) {
      final name = ex.localizedName(loc);
      for (final e in events.where((e) => e.exerciseId == ex.exerciseId)) {
        final set = StrengthWorkoutFormat.setLabel(e.weight, e.reps);
        prs.add(
          PR(
            exerciseName: name,
            type: e.kind == StrengthRecordKind.e1rm ? 'e1rm' : 'weight',
            value: e.kind == StrengthRecordKind.e1rm
                ? '${StrengthWorkoutFormat.weightKg(e.value)} ($set)'
                : set,
            previous: e.previous == null
                ? ''
                : StrengthWorkoutFormat.weightKg(e.previous!),
          ),
        );
      }
      final volume = volumes[ex.exerciseId];
      if (volume != null) {
        prs.add(
          PR(
            exerciseName: name,
            type: 'volume',
            value: StrengthWorkoutFormat.volume(volume.volume),
            previous: StrengthWorkoutFormat.volume(volume.previous),
          ),
        );
      }
    }
    return prs;
  }

  /// Longest-distance records of the cardio exercises: only beating an
  /// earlier best counts (a first session is a baseline).
  Future<List<PR>> _cardioRecords(
    String workoutId,
    Map<String, CardioBests> current,
  ) async {
    final prs = <PR>[];
    for (final entry in current.entries) {
      final bests = entry.value;
      final bestDistance = await _workoutRepo.getBestPreviousDistance(
        entry.key,
        excludeWorkoutId: workoutId,
      );
      if (bestDistance > 0 && bests.distance > bestDistance) {
        prs.add(
          PR(
            exerciseName: bests.name,
            type: 'distance',
            value: '${AppNumberFormat.decimal(bests.distance, 1)} km',
            previous: '${AppNumberFormat.decimal(bestDistance, 1)} km',
          ),
        );
      }
    }
    return prs;
  }
}

/// Working-set totals of a workout (see [WorkoutSummaryService.totals]).
class WorkoutSummaryTotals {
  final double totalVolume;
  final int totalSets;
  final int completedSets;
  final double totalDistance;
  final int totalCardioTime;

  /// Distance and time per cardio exercise id.
  final Map<String, CardioBests> cardioByExercise;

  const WorkoutSummaryTotals({
    required this.totalVolume,
    required this.totalSets,
    required this.completedSets,
    required this.totalDistance,
    required this.totalCardioTime,
    required this.cardioByExercise,
  });
}
