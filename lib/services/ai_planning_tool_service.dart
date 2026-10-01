// Read-only queries built for the AI Coach may run SQL directly (a documented
// exception to the repository-only rule); writes never happen in this file.
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Read-only access to the periodization plan: current phase, the day's
/// targets, the template week and the weekly review numbers.
class AiPlanningToolService {
  final DatabaseHelper db;
  final PeriodizationRepository periodization;
  final DateTime Function() _now;

  AiPlanningToolService({
    DatabaseHelper? db,
    PeriodizationRepository? periodization,
    DateTime Function()? now,
  }) : db = db ?? DatabaseHelper.instance,
       periodization =
           periodization ?? (db ?? DatabaseHelper.instance).periodizationRepo,
       _now = now ?? DateTime.now;

  /// The injected clock, so spec handlers resolve dates like the queries.
  DateTime now() => dayOf(_now());

  /// What the active plan expects on [date]: the plan and its phases, the
  /// current phase and week, the day's training/rest type and nutrition
  /// target, the template week, the routine day and run planned next. With
  /// [review] (`week` or `phase`) it adds the metrics of that week or phase.
  Future<Map<String, dynamic>> trainingPlan({
    required DateTime date,
    String? review,
  }) async {
    final day = dayOf(date);
    final plan = await periodization.getActivePlan();
    if (plan == null) {
      return {'date': dateKey(day), 'active_plan': false};
    }
    final phases = await periodization.getPhases(plan.id);
    final dayPlan = await periodization.getDayPlan(day);
    final routine = await periodization.getRoutineSuggestion(day);
    final run = await periodization.getRunSuggestion(day);
    final current = dayPlan?.phase;
    final target = dayPlan?.target;
    final planned = dayPlan?.day;
    return {
      'date': dateKey(day),
      'weekday': day.weekday,
      'plan': _planMap(plan),
      'phases': [
        for (final phase in phases)
          {
            'id': phase.id,
            'name': phase.name,
            'kind': phase.templateKey,
            'start_date': dateKey(phase.startDate),
            'end_date': dateKey(phase.endDate),
            'weeks': phase.totalWeeks,
            'current': phase.id == current?.id ? true : null,
          },
      ],
      'in_plan': current != null,
      'phase': current == null
          ? null
          : {
              'name': current.name,
              'kind': current.templateKey,
              'intent': current.intent,
              'week': dayPlan!.weekNumber,
              'total_weeks': dayPlan.totalWeeks,
              'week_label': target?.weekLabel,
            },
      'targets': _targetMap(target),
      'review': current == null || review == null
          ? null
          : await _review(day, current, review),
      'day': planned == null
          ? null
          : {
              'training_day': dayPlan!.trainingDay,
              'strength_planned': planned.strength,
              'run_planned': planned.run,
              'calories': planned.calories,
              'protein_g': planned.proteinG,
              'carbs_g': planned.carbsG,
              'fat_g': planned.fatG,
            },
      'week_template': dayPlan == null || !(target?.hasTemplateWeek ?? false)
          ? null
          : [
              for (final entry in dayPlan.week)
                {
                  'weekday': entry.weekday,
                  'strength': entry.strength ? true : null,
                  'run': entry.run ? true : null,
                  'calories': entry.calories,
                },
            ],
      'next_routine_day': routine == null
          ? null
          : {
              'routine_id': routine.routineId,
              'routine': routine.routineName,
              'day_id': routine.routineDayId,
              'day': routine.routineDayName,
              'day_number': routine.routineDayIndex + 1,
              'days': routine.routineDayCount,
            },
      'planned_run': run == null
          ? null
          : {
              'plan_id': run.runPlanId,
              'plan': run.runPlanName,
              'week': run.weekIndex + 1,
              'session_id': run.workout.id,
              'name': run.workout.name,
              'kind': run.workout.kind.value,
              'distance_m': run.workout.targetDistanceMeters,
              'duration_s': run.workout.targetDurationSeconds,
              'pace_s_km': run.workout.targetPaceSecPerKm,
              'status': run.scheduled?.status.value,
              'runs_done_this_week': run.completedRunsThisWeek,
            },
    };
  }

  /// Metrics of the plan week (or the whole phase) containing [day] and the
  /// weekly check-in(s) the user filled.
  Future<Map<String, dynamic>> _review(
    DateTime day,
    PeriodizationPhase phase,
    String scope,
  ) async {
    final weekStart = mondayOf(day);
    final isWeek = scope == 'week';
    final metrics = isWeek
        ? await periodization.getWeekMetrics(phase, weekStart)
        : await periodization.getPhaseMetrics(phase);
    final snapshot = Map<String, dynamic>.from(metrics.toSnapshot())
      ..remove('start_date')
      ..remove('end_date');
    // The plan's strength metrics only count workouts of the routines the
    // plan links; say so, and add every finished workout of the range so the
    // model never reads "2 workouts" as the user's whole training.
    for (final key in const ['workout_count', 'completed_sets', 'volume']) {
      if (snapshot.containsKey(key)) {
        snapshot['plan_routine_$key'] = snapshot.remove(key);
      }
    }
    final database = await periodization.db;
    final all = await database.rawQuery(
      '''
      SELECT COUNT(*) AS n FROM workouts
      WHERE end_time IS NOT NULL AND date >= ? AND date <= ?
      ''',
      [dateKey(metrics.startDate), dateKey(metrics.endDate)],
    );
    snapshot['all_finished_workout_count'] =
        (all.first['n'] as num?)?.toInt() ?? 0;
    final checkins = await periodization.getCheckins(phase.id);
    return {
      'scope': scope,
      'start_date': dateKey(metrics.startDate),
      'end_date': dateKey(metrics.endDate),
      'metrics': snapshot,
      if (isWeek)
        'checkin': _checkin(
          checkins
              .where((c) => dateKey(c.weekStart) == dateKey(weekStart))
              .firstOrNull,
        ),
      if (!isWeek)
        'checkins': [
          for (final checkin in checkins.take(12))
            {
              'week_start': dateKey(checkin.weekStart),
              'energy': checkin.energy,
              'hunger': checkin.hunger,
              'recovery': checkin.recovery,
              'performance': checkin.performance,
              'decision': checkin.decision.value,
            },
        ],
    };
  }

  Map<String, dynamic>? _checkin(PeriodizationCheckin? checkin) {
    if (checkin == null) return null;
    return {
      'energy': checkin.energy,
      'hunger': checkin.hunger,
      'recovery': checkin.recovery,
      'performance': checkin.performance,
      'decision': checkin.decision.value,
      'notes': checkin.notes,
    };
  }

  Map<String, dynamic> _planMap(PeriodizationPlan plan) => {
    'id': plan.id,
    'name': plan.name,
    'start_date': dateKey(plan.startDate),
    'end_date': dateKey(plan.endDate),
    'status': plan.status.value,
    'notes': plan.notes,
  };

  Map<String, dynamic>? _targetMap(PeriodizationTarget? target) {
    if (target == null) return null;
    return {
      'calories': target.calories,
      'protein_g': target.proteinG,
      'carbs_g': target.carbsG,
      'fat_g': target.fatG,
      'rest_day_calories': target.restCalories,
      'workouts_per_week': target.workoutsPerWeek,
      'sets_per_week_min': target.minSetsPerWeek,
      'sets_per_week_max': target.maxSetsPerWeek,
      'rpe_min': target.minRpe,
      'rpe_max': target.maxRpe,
      'run_sessions_per_week': target.runSessionsPerWeek,
      'run_weekly_distance_m': target.runWeeklyDistanceMeters,
      'long_run_m': target.longRunDistanceMeters,
      'quality_runs_per_week': target.qualitySessionsPerWeek,
      'target_weight_kg': target.targetWeightKg,
      'weekly_weight_change_pct': target.weeklyWeightChangePercent,
      'sleep_hours': target.sleepHours,
      'strength_days': target.strengthDays.isEmpty ? null : target.strengthDays,
      'run_days': target.runDays.isEmpty ? null : target.runDays,
      'valid_from': dateKey(target.validFrom),
    };
  }
}
