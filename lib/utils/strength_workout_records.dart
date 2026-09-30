import 'package:workout_notes/repositories/strength_records_repository.dart';

/// A set of a workout that can carry a record mark.
class StrengthMarkableSet {
  final String id;
  final double weight;
  final int reps;
  final bool isWarmup;
  final bool isComplete;

  const StrengthMarkableSet({
    required this.id,
    required this.weight,
    required this.reps,
    this.isWarmup = false,
    this.isComplete = true,
  });
}

/// Pure helpers around records set inside one workout.
abstract final class StrengthWorkoutRecords {
  /// Records set by [workoutId] when it is not saved yet (an active workout):
  /// [history] is every earlier finished set, [session] the sets of the
  /// running workout (its samples must carry [workoutId]).
  static List<StrengthRecordEvent> sessionEvents({
    required List<StrengthSetSample> history,
    required List<StrengthSetSample> session,
    required String workoutId,
  }) {
    final earlier = history.where((s) => s.workoutId != workoutId);
    final events = StrengthRecordsCalculator.events([...earlier, ...session]);
    return events.where((e) => e.workoutId == workoutId).toList();
  }

  /// Exercises whose session volume beat every earlier session, as
  /// exerciseId -> (volume, previous best). The first session of an exercise is
  /// a baseline, never a record.
  static Map<String, ({double volume, double previous})> volumeRecords({
    required List<StrengthSetSample> history,
    required List<StrengthSetSample> session,
    required String workoutId,
  }) {
    final best = <String, double>{};
    final perSession = <String, Map<String, double>>{};
    for (final s in history) {
      if (s.workoutId == workoutId) continue;
      final sessions = perSession.putIfAbsent(s.exerciseId, () => {});
      sessions[s.workoutId] = (sessions[s.workoutId] ?? 0) + s.volume;
    }
    perSession.forEach((exerciseId, sessions) {
      best[exerciseId] = sessions.values.reduce((a, b) => a > b ? a : b);
    });
    final current = <String, double>{};
    for (final s in session) {
      current[s.exerciseId] = (current[s.exerciseId] ?? 0) + s.volume;
    }
    final result = <String, ({double volume, double previous})>{};
    current.forEach((exerciseId, volume) {
      final previous = best[exerciseId];
      if (previous != null && previous > 0 && volume > previous + 0.01) {
        result[exerciseId] = (volume: volume, previous: previous);
      }
    });
    return result;
  }

  /// Which sets of one exercise carry a record: the set that produced each
  /// event (matching load and reps). Returns set id -> kinds.
  static Map<String, Set<StrengthRecordKind>> markSets({
    required List<StrengthRecordEvent> events,
    required String exerciseId,
    required List<StrengthMarkableSet> sets,
  }) {
    final marks = <String, Set<StrengthRecordKind>>{};
    for (final event in events) {
      if (event.exerciseId != exerciseId) continue;
      for (final set in sets) {
        if (set.isWarmup || !set.isComplete) continue;
        if ((set.weight - event.weight).abs() < 0.001 &&
            set.reps == event.reps) {
          marks.putIfAbsent(set.id, () => {}).add(event.kind);
          break;
        }
      }
    }
    return marks;
  }

  /// Distinct exercises with at least one record, per workout.
  static Map<String, int> exerciseCountByWorkout(
    List<StrengthRecordEvent> events,
  ) {
    final exercises = <String, Set<String>>{};
    for (final e in events) {
      exercises.putIfAbsent(e.workoutId, () => {}).add(e.exerciseId);
    }
    return {
      for (final entry in exercises.entries) entry.key: entry.value.length,
    };
  }
}
