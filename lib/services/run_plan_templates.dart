import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';

/// A step described without ids — materialised by [RunPlanTemplates.create].
class RunPlanTemplateStep {
  final RunStepRole role;
  final RunIntervalMetric metric;
  final int value;
  final int? repeatGroup;
  final int repeatCount;
  final double? targetPaceMinSecPerKm;
  final double? targetPaceMaxSecPerKm;

  const RunPlanTemplateStep({
    required this.role,
    this.metric = RunIntervalMetric.distance,
    required this.value,
    this.repeatGroup,
    this.repeatCount = 1,
    this.targetPaceMinSecPerKm,
    this.targetPaceMaxSecPerKm,
  });
}

class RunPlanTemplateWorkout {
  final String name;
  final RunWorkoutKind kind;

  /// ISO weekday (1 = Monday … 7 = Sunday).
  final int dayOfWeek;
  final double? targetDistanceMeters;
  final int? targetDurationSeconds;
  final List<RunPlanTemplateStep> steps;

  const RunPlanTemplateWorkout({
    required this.name,
    required this.kind,
    required this.dayOfWeek,
    this.targetDistanceMeters,
    this.targetDurationSeconds,
    this.steps = const [],
  });
}

/// A ready-made plan the user can start from instead of an empty week.
class RunPlanTemplate {
  final String key;
  final RunPlanGoalKind goalKind;
  final int weeks;

  /// Sessions of the first week. Copied into every other week on creation, so
  /// the user gets a full plan to tweak instead of one filled week.
  final List<RunPlanTemplateWorkout> week;

  const RunPlanTemplate({
    required this.key,
    required this.goalKind,
    required this.weeks,
    required this.week,
  });
}

/// Seed templates. Paces are left open on easy volume (the user's easy pace is
/// personal) and only set on quality work, where a target is the point.
abstract final class RunPlanTemplates {
  static const base = RunPlanTemplate(
    key: 'base',
    goalKind: RunPlanGoalKind.base,
    weeks: 4,
    week: [
      RunPlanTemplateWorkout(
        name: 'Rodagem leve',
        kind: RunWorkoutKind.easy,
        dayOfWeek: 2,
        targetDistanceMeters: 5000,
      ),
      RunPlanTemplateWorkout(
        name: 'Rodagem leve',
        kind: RunWorkoutKind.easy,
        dayOfWeek: 4,
        targetDistanceMeters: 6000,
      ),
      RunPlanTemplateWorkout(
        name: 'Longão',
        kind: RunWorkoutKind.long,
        dayOfWeek: 7,
        targetDistanceMeters: 10000,
      ),
    ],
  );

  static const fiveK = RunPlanTemplate(
    key: '5k',
    goalKind: RunPlanGoalKind.fiveK,
    weeks: 8,
    week: [
      RunPlanTemplateWorkout(
        name: '8x400 m',
        kind: RunWorkoutKind.interval,
        dayOfWeek: 2,
        steps: [
          RunPlanTemplateStep(role: RunStepRole.warmup, value: 1500),
          RunPlanTemplateStep(
            role: RunStepRole.work,
            value: 400,
            repeatGroup: 1,
            repeatCount: 8,
            targetPaceMinSecPerKm: 225,
            targetPaceMaxSecPerKm: 240,
          ),
          RunPlanTemplateStep(
            role: RunStepRole.recovery,
            metric: RunIntervalMetric.time,
            value: 90,
            repeatGroup: 1,
            repeatCount: 8,
          ),
          RunPlanTemplateStep(role: RunStepRole.cooldown, value: 1000),
        ],
      ),
      RunPlanTemplateWorkout(
        name: 'Rodagem leve',
        kind: RunWorkoutKind.easy,
        dayOfWeek: 4,
        targetDistanceMeters: 6000,
      ),
      RunPlanTemplateWorkout(
        name: 'Longão',
        kind: RunWorkoutKind.long,
        dayOfWeek: 7,
        targetDistanceMeters: 10000,
      ),
    ],
  );

  static const tenK = RunPlanTemplate(
    key: '10k',
    goalKind: RunPlanGoalKind.tenK,
    weeks: 12,
    week: [
      RunPlanTemplateWorkout(
        name: '6x800 m',
        kind: RunWorkoutKind.interval,
        dayOfWeek: 2,
        steps: [
          RunPlanTemplateStep(role: RunStepRole.warmup, value: 2000),
          RunPlanTemplateStep(
            role: RunStepRole.work,
            value: 800,
            repeatGroup: 1,
            repeatCount: 6,
            targetPaceMinSecPerKm: 235,
            targetPaceMaxSecPerKm: 250,
          ),
          RunPlanTemplateStep(
            role: RunStepRole.recovery,
            metric: RunIntervalMetric.time,
            value: 120,
            repeatGroup: 1,
            repeatCount: 6,
          ),
          RunPlanTemplateStep(role: RunStepRole.cooldown, value: 1000),
        ],
      ),
      RunPlanTemplateWorkout(
        name: 'Rodagem leve',
        kind: RunWorkoutKind.easy,
        dayOfWeek: 3,
        targetDistanceMeters: 6000,
      ),
      RunPlanTemplateWorkout(
        name: 'Ritmo 20 min',
        kind: RunWorkoutKind.tempo,
        dayOfWeek: 5,
        steps: [
          RunPlanTemplateStep(role: RunStepRole.warmup, value: 1500),
          RunPlanTemplateStep(
            role: RunStepRole.steady,
            metric: RunIntervalMetric.time,
            value: 1200,
            targetPaceMinSecPerKm: 260,
            targetPaceMaxSecPerKm: 275,
          ),
          RunPlanTemplateStep(role: RunStepRole.cooldown, value: 1000),
        ],
      ),
      RunPlanTemplateWorkout(
        name: 'Longão',
        kind: RunWorkoutKind.long,
        dayOfWeek: 7,
        targetDistanceMeters: 14000,
      ),
    ],
  );

  static const half = RunPlanTemplate(
    key: 'half',
    goalKind: RunPlanGoalKind.half,
    weeks: 16,
    week: [
      RunPlanTemplateWorkout(
        name: '5x1000 m',
        kind: RunWorkoutKind.interval,
        dayOfWeek: 2,
        steps: [
          RunPlanTemplateStep(role: RunStepRole.warmup, value: 2000),
          RunPlanTemplateStep(
            role: RunStepRole.work,
            value: 1000,
            repeatGroup: 1,
            repeatCount: 5,
            targetPaceMinSecPerKm: 250,
            targetPaceMaxSecPerKm: 265,
          ),
          RunPlanTemplateStep(
            role: RunStepRole.recovery,
            metric: RunIntervalMetric.time,
            value: 150,
            repeatGroup: 1,
            repeatCount: 5,
          ),
          RunPlanTemplateStep(role: RunStepRole.cooldown, value: 1500),
        ],
      ),
      RunPlanTemplateWorkout(
        name: 'Rodagem leve',
        kind: RunWorkoutKind.easy,
        dayOfWeek: 3,
        targetDistanceMeters: 8000,
      ),
      RunPlanTemplateWorkout(
        name: 'Ritmo 30 min',
        kind: RunWorkoutKind.tempo,
        dayOfWeek: 5,
        steps: [
          RunPlanTemplateStep(role: RunStepRole.warmup, value: 2000),
          RunPlanTemplateStep(
            role: RunStepRole.steady,
            metric: RunIntervalMetric.time,
            value: 1800,
            targetPaceMinSecPerKm: 275,
            targetPaceMaxSecPerKm: 290,
          ),
          RunPlanTemplateStep(role: RunStepRole.cooldown, value: 1000),
        ],
      ),
      RunPlanTemplateWorkout(
        name: 'Longão',
        kind: RunWorkoutKind.long,
        dayOfWeek: 7,
        targetDistanceMeters: 20000,
      ),
    ],
  );

  static const maintenance = RunPlanTemplate(
    key: 'maintenance',
    goalKind: RunPlanGoalKind.maintenance,
    weeks: 1,
    week: [
      RunPlanTemplateWorkout(
        name: 'Fartlek 30 min',
        kind: RunWorkoutKind.fartlek,
        dayOfWeek: 3,
        steps: [
          RunPlanTemplateStep(role: RunStepRole.warmup, value: 1500),
          RunPlanTemplateStep(
            role: RunStepRole.work,
            metric: RunIntervalMetric.time,
            value: 60,
            repeatGroup: 1,
            repeatCount: 10,
          ),
          RunPlanTemplateStep(
            role: RunStepRole.recovery,
            metric: RunIntervalMetric.time,
            value: 60,
            repeatGroup: 1,
            repeatCount: 10,
          ),
          RunPlanTemplateStep(role: RunStepRole.cooldown, value: 1000),
        ],
      ),
      RunPlanTemplateWorkout(
        name: 'Longão',
        kind: RunWorkoutKind.long,
        dayOfWeek: 7,
        targetDistanceMeters: 12000,
      ),
    ],
  );

  static const all = <RunPlanTemplate>[
    base,
    fiveK,
    tenK,
    half,
    maintenance,
  ];

  static RunPlanTemplate? byKey(String key) {
    for (final template in all) {
      if (template.key == key) return template;
    }
    return null;
  }

  /// Creates a plan from [template], filling every week with its sessions.
  static Future<RunPlan> create(
    RunPlanRepository repository,
    RunPlanTemplate template, {
    required String name,
    DateTime? raceDate,
  }) async {
    final plan = await repository.createPlan(
      name: name,
      goalKind: template.goalKind,
      raceDate: raceDate,
      weeks: template.weeks,
    );
    for (final session in template.week) {
      final created = await repository.addWorkout(
        planId: plan.id,
        weekIndex: 0,
        name: session.name,
        kind: session.kind,
        dayOfWeek: session.dayOfWeek,
        targetDistanceMeters: session.targetDistanceMeters,
        targetDurationSeconds: session.targetDurationSeconds,
      );
      for (final step in session.steps) {
        await repository.addStep(
          workoutId: created.id,
          role: step.role,
          metric: step.metric,
          value: step.value,
          repeatGroup: step.repeatGroup,
          repeatCount: step.repeatCount,
          targetPaceMinSecPerKm: step.targetPaceMinSecPerKm,
          targetPaceMaxSecPerKm: step.targetPaceMaxSecPerKm,
        );
      }
    }
    if (template.weeks > 1) {
      await repository.copyWeek(
        plan.id,
        sourceWeek: 0,
        targetWeeks: {for (var i = 1; i < template.weeks; i++) i},
      );
    }
    return (await repository.getPlan(plan.id))!;
  }
}
