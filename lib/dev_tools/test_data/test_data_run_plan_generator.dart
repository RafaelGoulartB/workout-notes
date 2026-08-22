import 'test_data_context.dart';

class RunPlanGenerationResult {
  final int plans;
  final int completedPlans;

  const RunPlanGenerationResult({
    required this.plans,
    required this.completedPlans,
  });
}

/// Creates explicit plan-progress scenarios for visual and interaction tests.
/// The completed ledger rows are test-only links; recorded run activities are
/// never duplicated or modified.
class TestDataRunPlanGenerator {
  TestDataRunPlanGenerator(this.context);

  final TestDataContext context;

  Future<RunPlanGenerationResult> generate() async {
    await _insertPlan(
      key: 'completed-5k',
      name: '5 km — concluído',
      goal: '5k',
      weeks: 4,
      completedWeeks: 4,
      completionCount: 1,
      baseDistanceKm: 4,
    );
    await _insertPlan(
      key: 'completed-10k',
      name: '10 km — concluído',
      goal: '10k',
      weeks: 6,
      completedWeeks: 6,
      completionCount: 2,
      baseDistanceKm: 6,
    );
    await _insertPlan(
      key: 'active-half',
      name: 'Meia maratona — em andamento',
      goal: 'half',
      weeks: 6,
      completedWeeks: 1,
      baseDistanceKm: 8,
      active: true,
    );
    return const RunPlanGenerationResult(plans: 3, completedPlans: 2);
  }

  Future<void> _insertPlan({
    required String key,
    required String name,
    required String goal,
    required int weeks,
    required int completedWeeks,
    int completionCount = 0,
    required double baseDistanceKm,
    bool active = false,
  }) async {
    final db = context.database;
    final planId = context.id('run_plan', key);
    final nowIso = context.now.toIso8601String();
    final monday = DateTime(
      context.now.year,
      context.now.month,
      context.now.day,
    ).subtract(Duration(days: context.now.weekday - 1));

    await db.insert('run_plans', {
      'id': planId,
      'name': name,
      'notes': active
          ? 'Cenário de teste com a primeira semana concluída.'
          : 'Cenário de teste finalizado em 100%.',
      'goal_kind': goal,
      'race_date': null,
      'weeks': weeks,
      'status': 'active',
      'completion_count': completionCount,
      'activated_at': active ? context.date(context.now) : null,
      'created_at': context.start.toIso8601String(),
      'updated_at': nowIso,
    });

    const days = [2, 5, 7];
    const kinds = ['easy', 'tempo', 'long'];
    const labels = ['Rodagem leve', 'Ritmo controlado', 'Longão leve'];
    for (var week = 0; week < weeks; week++) {
      for (var session = 0; session < days.length; session++) {
        final workoutId = context.id('run_plan_workout', '$key:$week:$session');
        final distanceKm = baseDistanceKm + week * .5 + session * 1.5;
        await db.insert('run_plan_workouts', {
          'id': workoutId,
          'run_plan_id': planId,
          'week_index': week,
          'day_of_week': days[session],
          'order_index': session,
          'kind': kinds[session],
          'name': labels[session],
          'notes': 'Treino gerado para validar estados do plano.',
          'target_distance_meters': distanceKm * 1000,
          'target_duration_seconds': null,
          'target_pace_sec_per_km': null,
          'effort_zone': session == 1 ? 'RPE 7' : 'Z2 / RPE 3–4',
          'created_at': nowIso,
        });

        final completed = week < completedWeeks;
        final date = active
            ? monday.add(Duration(days: week * 7 + days[session] - 1))
            : context.now.subtract(
                Duration(days: (weeks - week) * 7 - days[session]),
              );
        await db.insert('scheduled_runs', {
          'id': context.id('scheduled_run', '$key:$week:$session'),
          'date': context.date(date),
          'run_plan_id': planId,
          'run_plan_workout_id': workoutId,
          'status': completed ? 'completed' : 'planned',
          'notes': completed ? 'Concluído no cenário de teste' : null,
          'run_activity_id': null,
          'created_at': nowIso,
          'updated_at': nowIso,
        });
      }
    }
  }
}
