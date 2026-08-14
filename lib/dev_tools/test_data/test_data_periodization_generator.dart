import 'dart:math' as math;

import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';

import 'test_data_context.dart';

class PeriodizationGenerationResult {
  final int plans;
  final int phases;
  final int checkins;

  const PeriodizationGenerationResult({
    required this.plans,
    required this.phases,
    required this.checkins,
  });
}

/// Generates two complementary, realistic periodization stories.
///
/// The first plan is a completed strength cycle. The second is a current
/// hybrid running/body-composition plan with past, current, and future phases.
/// It deliberately includes target revisions, routine links, and weekly
/// check-ins so every manual periodization screen has meaningful data.
class TestDataPeriodizationGenerator {
  final TestDataContext context;

  TestDataPeriodizationGenerator(this.context);

  Future<PeriodizationGenerationResult> generate() async {
    final today = _day(context.now);
    final routineRows = await context.database.query(
      'routines',
      columns: ['id'],
      where: 'id LIKE ?',
      whereArgs: ['$devDataPrefix%'],
      orderBy: 'id ASC',
    );
    final routineIds = routineRows
        .map((row) => row['id'] as String)
        .toList(growable: false);
    final userActive = await context.database.query(
      'periodization_plans',
      columns: ['id'],
      where: "status = 'active' AND id NOT LIKE ?",
      whereArgs: ['$devDataPrefix%'],
      limit: 1,
    );

    final completedStart = today.subtract(const Duration(days: 112));
    final completed = _PlanSeed(
      id: context.id('periodization_plan', 'strength'),
      name: 'Ciclo de força e pico',
      startDate: completedStart,
      status: PeriodizationPlanStatus.completed,
      notes:
          'Bloco concluído com base técnica, intensificação progressiva e pico de força.',
      phases: [
        _PhaseSeed(
          key: 'strength-base',
          name: 'Base técnica',
          templateKey: 'base',
          color: 0xFF3F51B5,
          startDate: completedStart,
          days: 21,
          intent: 'Consolidar técnica e capacidade de trabalho',
          target: _target(
            calories: 2600,
            protein: 170,
            workouts: 3,
            setsMin: 40,
            setsMax: 50,
            rpeMin: 6.5,
            rpeMax: 8,
            weight: 80.5,
            sleep: 7.5,
          ),
          routineIndex: 0,
        ),
        _PhaseSeed(
          key: 'strength-intensification',
          name: 'Intensificação',
          templateKey: 'intensification',
          color: 0xFFF57C00,
          startDate: completedStart.add(const Duration(days: 21)),
          days: 21,
          intent: 'Elevar intensidade mantendo a execução consistente',
          target: _target(
            calories: 2700,
            protein: 175,
            workouts: 4,
            setsMin: 36,
            setsMax: 46,
            rpeMin: 7.5,
            rpeMax: 9,
            weight: 80,
            sleep: 8,
          ),
          revisedTarget: _target(
            calories: 2800,
            protein: 180,
            workouts: 4,
            setsMin: 34,
            setsMax: 42,
            rpeMin: 7.5,
            rpeMax: 9,
            weight: 79.8,
            sleep: 8,
          ),
          revisionDay: 14,
          routineIndex: 0,
        ),
        _PhaseSeed(
          key: 'strength-peak',
          name: 'Pico e testes',
          templateKey: 'peak',
          color: 0xFFD32F2F,
          startDate: completedStart.add(const Duration(days: 42)),
          days: 14,
          intent: 'Reduzir volume e expressar força máxima',
          target: _target(
            calories: 2800,
            protein: 180,
            workouts: 3,
            setsMin: 22,
            setsMax: 30,
            rpeMin: 8,
            rpeMax: 9.5,
            weight: 79.5,
            sleep: 8,
          ),
          routineIndex: 0,
        ),
      ],
    );

    final activeStart = today.subtract(const Duration(days: 56));
    final active = _PlanSeed(
      id: context.id('periodization_plan', 'hybrid'),
      name: 'Recomposição e corrida de 10 km',
      startDate: activeStart,
      status: userActive.isEmpty
          ? PeriodizationPlanStatus.active
          : PeriodizationPlanStatus.draft,
      notes:
          'Plano híbrido atual: reduzir gordura sem perder força e preparar uma prova de 10 km.',
      phases: [
        _PhaseSeed(
          key: 'hybrid-cutting',
          name: 'Cutting gradual',
          templateKey: 'cutting',
          color: 0xFF00897B,
          startDate: activeStart,
          days: 28,
          intent: 'Reduzir gordura preservando desempenho e massa magra',
          target: _target(
            calories: 2250,
            protein: 180,
            carbs: 225,
            fat: 70,
            workouts: 4,
            setsMin: 36,
            setsMax: 48,
            rpeMin: 6.5,
            rpeMax: 8.5,
            weight: 77.8,
            weeklyWeightChange: -0.4,
            sleep: 7.5,
          ),
          revisedTarget: _target(
            calories: 2350,
            protein: 180,
            carbs: 245,
            fat: 72,
            workouts: 4,
            setsMin: 34,
            setsMax: 44,
            rpeMin: 6.5,
            rpeMax: 8.5,
            weight: 78.2,
            weeklyWeightChange: -0.3,
            sleep: 7.5,
          ),
          revisionDay: 14,
          routineIndex: 0,
        ),
        _PhaseSeed(
          key: 'hybrid-deload',
          name: 'Deload e manutenção',
          templateKey: 'deload',
          color: 0xFF78909C,
          startDate: activeStart.add(const Duration(days: 28)),
          days: 7,
          intent: 'Dissipar fadiga e estabilizar o peso',
          target: _target(
            calories: 2500,
            protein: 175,
            workouts: 3,
            setsMin: 20,
            setsMax: 28,
            rpeMin: 5.5,
            rpeMax: 7,
            weight: 78,
            sleep: 8,
          ),
          routineIndex: 0,
        ),
        _PhaseSeed(
          key: 'hybrid-build',
          name: 'Construção específica 10 km',
          templateKey: 'build',
          color: 0xFF1976D2,
          startDate: activeStart.add(const Duration(days: 35)),
          days: 35,
          intent: 'Aumentar volume de corrida sem abandonar a força',
          target: _target(
            calories: 2550,
            protein: 170,
            carbs: 310,
            fat: 68,
            workouts: 5,
            setsMin: 30,
            setsMax: 42,
            rpeMin: 6,
            rpeMax: 8.5,
            weight: 77.8,
            sleep: 7.5,
          ),
          splitRoutines: true,
        ),
        _PhaseSeed(
          key: 'hybrid-taper',
          name: 'Polimento e prova',
          templateKey: 'taper',
          color: 0xFF7B1FA2,
          startDate: activeStart.add(const Duration(days: 70)),
          days: 14,
          intent: 'Reduzir fadiga e chegar descansado à prova',
          target: _target(
            calories: 2650,
            protein: 165,
            carbs: 340,
            fat: 70,
            workouts: 4,
            setsMin: 20,
            setsMax: 30,
            rpeMin: 5.5,
            rpeMax: 8,
            weight: 77.5,
            sleep: 8,
          ),
          routineIndex: 1,
        ),
      ],
    );

    var phases = 0;
    var checkins = 0;
    for (final plan in [completed, active]) {
      final result = await _insertPlan(plan, routineIds, today);
      phases += result.$1;
      checkins += result.$2;
    }
    return PeriodizationGenerationResult(
      plans: 2,
      phases: phases,
      checkins: checkins,
    );
  }

  Future<(int, int)> _insertPlan(
    _PlanSeed seed,
    List<String> routineIds,
    DateTime today,
  ) async {
    final endDate = seed.phases.last.endDate;
    final createdAt = seed.startDate.subtract(const Duration(days: 4));
    final plan = PeriodizationPlan(
      id: seed.id,
      name: seed.name,
      startDate: seed.startDate,
      endDate: endDate,
      status: seed.status,
      notes: seed.notes,
      createdAt: createdAt,
      updatedAt: seed.status == PeriodizationPlanStatus.completed
          ? endDate.add(const Duration(hours: 20))
          : context.now,
    );
    await context.database.insert('periodization_plans', plan.toMap());

    var checkinCount = 0;
    for (var index = 0; index < seed.phases.length; index++) {
      final phaseSeed = seed.phases[index];
      final phase = PeriodizationPhase(
        id: context.id('periodization_phase', phaseSeed.key),
        planId: seed.id,
        name: phaseSeed.name,
        templateKey: phaseSeed.templateKey,
        color: phaseSeed.color,
        startDate: phaseSeed.startDate,
        endDate: phaseSeed.endDate,
        intent: phaseSeed.intent,
        orderIndex: index,
        createdAt: createdAt,
        updatedAt: context.now,
      );
      await context.database.insert('periodization_phases', phase.toMap());

      final targets = <PeriodizationTarget>[
        _materializeTarget(phase, phaseSeed.target, version: 1),
      ];
      if (phaseSeed.revisedTarget != null) {
        targets.add(
          _materializeTarget(
            phase,
            phaseSeed.revisedTarget!,
            version: 2,
            validFrom: phase.startDate.add(
              Duration(days: phaseSeed.revisionDay ?? 7),
            ),
          ),
        );
      }
      for (final target in targets) {
        await context.database.insert('phase_targets', target.toMap());
      }
      await _linkRoutines(phase, phaseSeed, routineIds, createdAt);
      checkinCount += await _insertCheckins(phase, targets, today);
    }
    return (seed.phases.length, checkinCount);
  }

  PeriodizationTarget _materializeTarget(
    PeriodizationPhase phase,
    PeriodizationTarget seed, {
    required int version,
    DateTime? validFrom,
  }) => PeriodizationTarget(
    id: context.id('periodization_target', '${phase.id}:$version'),
    phaseId: phase.id,
    version: version,
    validFrom: validFrom ?? phase.startDate,
    calories: seed.calories,
    proteinG: seed.proteinG,
    carbsG: seed.carbsG,
    fatG: seed.fatG,
    workoutsPerWeek: seed.workoutsPerWeek,
    minSetsPerWeek: seed.minSetsPerWeek,
    maxSetsPerWeek: seed.maxSetsPerWeek,
    minRpe: seed.minRpe,
    maxRpe: seed.maxRpe,
    targetWeightKg: seed.targetWeightKg,
    weeklyWeightChangePercent: seed.weeklyWeightChangePercent,
    sleepHours: seed.sleepHours,
    createdAt: (validFrom ?? phase.startDate).add(const Duration(hours: 8)),
  );

  Future<void> _linkRoutines(
    PeriodizationPhase phase,
    _PhaseSeed seed,
    List<String> routineIds,
    DateTime createdAt,
  ) async {
    if (routineIds.isEmpty) return;
    if (seed.splitRoutines && routineIds.length > 1) {
      final split = phase.startDate.add(
        Duration(days: math.max(1, phase.totalDays ~/ 2)),
      );
      await _insertRoutineLink(
        phase,
        routineIds[0],
        phase.startDate,
        split.subtract(const Duration(days: 1)),
        createdAt,
        'strength',
      );
      await _insertRoutineLink(
        phase,
        routineIds[1],
        split,
        phase.endDate,
        createdAt,
        'running',
      );
      return;
    }
    final routineIndex = (seed.routineIndex ?? 0).clamp(
      0,
      routineIds.length - 1,
    );
    await _insertRoutineLink(
      phase,
      routineIds[routineIndex],
      phase.startDate,
      phase.endDate,
      createdAt,
      '$routineIndex',
    );
  }

  Future<void> _insertRoutineLink(
    PeriodizationPhase phase,
    String routineId,
    DateTime startsOn,
    DateTime endsOn,
    DateTime createdAt,
    String suffix,
  ) => context.database.insert('phase_routine_links', {
    'id': context.id('periodization_routine', '${phase.id}:$suffix'),
    'phase_id': phase.id,
    'routine_id': routineId,
    'starts_on': context.date(startsOn),
    'ends_on': context.date(endsOn),
    'created_at': createdAt.toIso8601String(),
  });

  Future<int> _insertCheckins(
    PeriodizationPhase phase,
    List<PeriodizationTarget> targets,
    DateTime today,
  ) async {
    var weekStart = _mondayOnOrAfter(phase.startDate);
    var count = 0;
    while (!weekStart.add(const Duration(days: 6)).isAfter(today) &&
        !weekStart.isAfter(phase.endDate)) {
      final target = targets.lastWhere(
        (candidate) => !candidate.validFrom.isAfter(weekStart),
        orElse: () => targets.first,
      );
      final plannedWorkouts = target.workoutsPerWeek ?? 4;
      final workouts = math.max(
        1,
        plannedWorkouts + context.random.nextInt(3) - 1,
      );
      final plannedSets = target.minSetsPerWeek ?? 30;
      final sets = math.max(8, plannedSets + context.random.nextInt(9) - 4);
      final adherence = context.jitter(91, 7).clamp(70, 100);
      final energy = context.jitter(4, .8).round().clamp(1, 5);
      final hunger = context.jitter(3, .9).round().clamp(1, 5);
      final recovery = context.jitter(4, .8).round().clamp(1, 5);
      final isAdjustment = phase.templateKey == 'cutting' && count == 1;
      final checkin = PeriodizationCheckin(
        id: context.id(
          'periodization_checkin',
          '${phase.id}:${context.date(weekStart)}',
        ),
        phaseId: phase.id,
        weekStart: weekStart,
        energy: energy,
        hunger: hunger,
        recovery: recovery,
        performance: energy >= 4 && recovery >= 4 ? 'improved' : 'stable',
        decision: isAdjustment
            ? PeriodizationDecision.adjust
            : PeriodizationDecision.maintain,
        notes: isAdjustment
            ? 'Fome aumentou no fim da semana; ajuste pequeno para sustentar o treino.'
            : _checkinNote(phase.templateKey, count),
        metricsSnapshot: {
          'start_date': context.date(weekStart),
          'end_date': context.date(weekStart.add(const Duration(days: 6))),
          'elapsed_days': 7,
          'workout_count': workouts,
          'completed_sets': sets,
          'volume': double.parse(
            context.jitter(10500 + count * 350, 900).toStringAsFixed(1),
          ),
          'planned_workouts': plannedWorkouts,
          'planned_sets_minimum': plannedSets,
          'workout_adherence_percent': workouts / plannedWorkouts * 100,
          'nutrition_days_logged': 6 + context.random.nextInt(2),
          'average_calories': target.calories == null
              ? null
              : double.parse(
                  context.jitter(target.calories!, 90).toStringAsFixed(1),
                ),
          'average_protein_g': target.proteinG == null
              ? null
              : double.parse(
                  context.jitter(target.proteinG!, 8).toStringAsFixed(1),
                ),
          'nutrition_adherence_percent': double.parse(
            adherence.toStringAsFixed(1),
          ),
          'average_sleep_hours': double.parse(
            context.jitter(target.sleepHours ?? 7.5, .35).toStringAsFixed(1),
          ),
          'sleep_days_logged': 7,
        },
        targetsSnapshot: target.toSnapshot(),
        createdAt: weekStart.add(const Duration(days: 6, hours: 20)),
      );
      await context.database.insert('periodization_checkins', checkin.toMap());
      count++;
      weekStart = weekStart.add(const Duration(days: 7));
    }
    return count;
  }

  String _checkinNote(String? templateKey, int week) => switch (templateKey) {
    'base' => 'Técnica estável e boa adaptação ao volume.',
    'intensification' =>
      week == 1
          ? 'Carga subiu bem; manter atenção à recuperação.'
          : 'Principais levantamentos evoluindo dentro do RPE planejado.',
    'peak' => 'Volume menor e sensação de força preservada.',
    'deload' => 'Fadiga caiu e o sono melhorou ao longo da semana.',
    'build' => 'Corridas consistentes, sem perda perceptível de força.',
    _ => 'Semana consistente e metas mantidas.',
  };

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime _mondayOnOrAfter(DateTime value) {
    final day = _day(value);
    final daysUntilMonday = (DateTime.monday - day.weekday) % 7;
    return day.add(Duration(days: daysUntilMonday));
  }

  static PeriodizationTarget _target({
    double? calories,
    double? protein,
    double? carbs,
    double? fat,
    int? workouts,
    int? setsMin,
    int? setsMax,
    double? rpeMin,
    double? rpeMax,
    double? weight,
    double? weeklyWeightChange,
    double? sleep,
  }) => PeriodizationTarget(
    id: '',
    phaseId: '',
    version: 0,
    validFrom: DateTime(2000),
    calories: calories,
    proteinG: protein,
    carbsG: carbs,
    fatG: fat,
    workoutsPerWeek: workouts,
    minSetsPerWeek: setsMin,
    maxSetsPerWeek: setsMax,
    minRpe: rpeMin,
    maxRpe: rpeMax,
    targetWeightKg: weight,
    weeklyWeightChangePercent: weeklyWeightChange,
    sleepHours: sleep,
    createdAt: DateTime(2000),
  );
}

class _PlanSeed {
  final String id;
  final String name;
  final DateTime startDate;
  final PeriodizationPlanStatus status;
  final String notes;
  final List<_PhaseSeed> phases;

  const _PlanSeed({
    required this.id,
    required this.name,
    required this.startDate,
    required this.status,
    required this.notes,
    required this.phases,
  });
}

class _PhaseSeed {
  final String key;
  final String name;
  final String templateKey;
  final int color;
  final DateTime startDate;
  final int days;
  final String intent;
  final PeriodizationTarget target;
  final PeriodizationTarget? revisedTarget;
  final int? revisionDay;
  final int? routineIndex;
  final bool splitRoutines;

  const _PhaseSeed({
    required this.key,
    required this.name,
    required this.templateKey,
    required this.color,
    required this.startDate,
    required this.days,
    required this.intent,
    required this.target,
    this.revisedTarget,
    this.revisionDay,
    this.routineIndex,
    this.splitRoutines = false,
  });

  DateTime get endDate => startDate.add(Duration(days: days - 1));
}
