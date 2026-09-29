import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/periodization/phase_week_plan.dart';

/// One phase in a plan's ordered, back-to-back schedule as edited by the
/// plan editor. Phases are chained: each starts the day after the previous
/// one ends, so only the length in [weeks] is edited.
class PhaseScheduleEntry {
  /// Existing phase id, or null for a phase added in the editor.
  final String? id;
  final String name;
  final String templateKey;
  final int color;
  final String? intent;
  final int weeks;

  /// Target stored as version 1 when a NEW phase is created. Ignored for
  /// existing phases, whose targets move with them.
  final PeriodizationTarget? seedTarget;

  const PhaseScheduleEntry({
    this.id,
    required this.name,
    required this.templateKey,
    required this.color,
    this.intent,
    required this.weeks,
    this.seedTarget,
  });

  PhaseScheduleEntry copyWith({
    String? name,
    String? templateKey,
    int? color,
    int? weeks,
  }) => PhaseScheduleEntry(
    id: id,
    name: name ?? this.name,
    templateKey: templateKey ?? this.templateKey,
    color: color ?? this.color,
    intent: intent,
    weeks: weeks ?? this.weeks,
    seedTarget: seedTarget,
  );
}

/// What the active plan expects on one date: the phase and week, the target
/// in effect and the template-week day it falls on.
class PeriodizationDayPlan {
  final PeriodizationPhase phase;
  final PeriodizationTarget? target;

  /// 1-based phase week of the date.
  final int weekNumber;
  final int totalWeeks;

  /// The template week the date belongs to (Monday → Sunday).
  final List<PlannedWeekday> week;

  /// Linked running plan, when the target links one.
  final RunPlan? runPlan;

  /// Zero-based running-plan week the date maps onto.
  final int? runPlanWeek;
  final DateTime date;

  const PeriodizationDayPlan({
    required this.phase,
    required this.target,
    required this.weekNumber,
    required this.totalWeeks,
    required this.week,
    required this.date,
    this.runPlan,
    this.runPlanWeek,
  });

  PlannedWeekday get day => week[date.weekday - 1];

  /// True/false when the template week says whether the date is a training
  /// day; null when the target has no template week.
  bool? get trainingDay =>
      week.any((day) => day.trainingDay) ? day.trainingDay : null;
}
