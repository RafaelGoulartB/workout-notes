import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/repositories/workout_repository.dart';

/// The "Strength for runners" routine a running plan points at.
///
/// Two short sessions built from seeded exercises that need little or no
/// equipment: single-leg strength, posterior chain, calves and trunk — the
/// structures that absorb running impact. The routine lives in the ordinary
/// strength module, so it is logged, edited and progressed like any other.
class RunnerStrengthRoutine {
  static const settingKey = 'runner_strength_routine_id';

  final RoutineRepository _routines;
  final SettingsRepository _settings;
  final WorkoutRepository _workouts;

  RunnerStrengthRoutine({
    RoutineRepository? routines,
    SettingsRepository? settings,
    WorkoutRepository? workouts,
  }) : _routines = routines ?? RoutineRepository(),
       _settings = settings ?? SettingsRepository(),
       _workouts = workouts ?? WorkoutRepository();

  /// Seeded exercise id, reps (or seconds for holds) per set, sets.
  static const _dayA = [
    ('goblet_squat', 10, 3, false),
    ('reverse_lunge', 8, 3, false),
    ('calf_raise', 15, 3, false),
    ('glute_bridge', 12, 3, false),
    ('plank', 40, 3, true),
  ];
  static const _dayB = [
    ('step_up', 8, 3, false),
    ('romanian_dl', 10, 3, false),
    ('seated_calf', 15, 3, false),
    ('dead_bug', 10, 3, false),
    ('side_plank', 30, 3, true),
  ];

  /// Id of the routine, creating it on first use. A routine the user
  /// deleted is recreated; one they edited is left alone.
  Future<String> ensure({required bool pt}) async {
    final stored = await _settings.getSetting(settingKey);
    if (stored != null && await _routines.getRoutine(stored) != null) {
      return stored;
    }
    final id = await _routines.createRoutine(
      pt ? 'Força para corredores' : 'Strength for runners',
      notes: pt
          ? 'Duas sessões curtas (~25 min) por semana, nos dias que o plano de '
                'corrida indicar. Carga moderada: termine cada série com 2–3 '
                'repetições sobrando.'
          : 'Two short sessions (~25 min) a week, on the days your running '
                'plan suggests. Moderate load: finish each set with 2–3 reps '
                'in reserve.',
    );
    for (final (label, exercises) in [('A', _dayA), ('B', _dayB)]) {
      final day = await _routines.addRoutineDay(
        id,
        pt ? 'Força $label' : 'Strength $label',
      );
      for (final (exerciseId, amount, sets, timed) in exercises) {
        if (!await _exerciseExists(exerciseId)) continue;
        final entry = await _routines.addRoutineExercise(
          day,
          exerciseId,
          restTimeSeconds: 60,
        );
        for (var i = 0; i < sets; i++) {
          await _routines.addPredefinedSet(
            entry,
            reps: timed ? null : amount,
            timeSeconds: timed ? amount : null,
          );
        }
      }
    }
    await _settings.setSetting(settingKey, id);
    return id;
  }

  /// Starts today's strength workout from day A or B of the routine and
  /// returns the new workout id.
  Future<String> startWorkout({
    required bool pt,
    required int sessionIndex,
    DateTime? date,
  }) async {
    final routineId = await ensure(pt: pt);
    final days = await _routines.getRoutineDays(routineId);
    final workoutId = await _workouts.createWorkout(
      date: date,
      routineId: routineId,
    );
    if (days.isNotEmpty) {
      final day = days[sessionIndex % days.length];
      await _workouts.importRoutineDayToWorkout(workoutId, day['id'] as String);
    }
    return workoutId;
  }

  /// Days in [from]..[to] with a finished workout from this routine.
  Future<Set<DateTime>> completedDays(DateTime from, DateTime to) async {
    final routineId = await _settings.getSetting(settingKey);
    if (routineId == null) return const {};
    final db = await _routines.db;
    final rows = await db.query(
      'workouts',
      columns: ['date'],
      where:
          'routine_id = ? AND end_time IS NOT NULL AND date >= ? AND date <= ?',
      whereArgs: [routineId, _date(from), _date(to)],
    );
    return {
      for (final row in rows)
        if (DateTime.tryParse(row['date'] as String? ?? '') case final d?)
          DateTime(d.year, d.month, d.day),
    };
  }

  Future<bool> _exerciseExists(String id) async {
    final db = await _routines.db;
    final rows = await db.query(
      'exercises',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static String _date(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String().substring(0, 10);
}
