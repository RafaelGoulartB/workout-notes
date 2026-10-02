import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/periodization/phase_kind.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/utils/app_number_format.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/periodization/planning_widgets.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// A plan with its phases and, per phase, the target that best describes it
/// (today's for the running phase, the first week's for future phases, the
/// last week's for finished ones) — what the overview cards summarize.
class PlanOverviewData {
  final PeriodizationPlan plan;
  final List<PeriodizationPhase> phases;
  final Map<String, PeriodizationTarget?> targets;
  final Map<String, String> routineNames;
  final Map<String, String> runPlanNames;

  const PlanOverviewData({
    required this.plan,
    required this.phases,
    required this.targets,
    required this.routineNames,
    required this.runPlanNames,
  });

  static Future<PlanOverviewData> load(
    PeriodizationRepository repository,
    PeriodizationPlan plan, {
    DateTime? today,
  }) async {
    final now = today ?? DateTime.now();
    final day = dayOf(now);
    final phases = await repository.getPhases(plan.id);
    final targets = await Future.wait([
      for (final phase in phases)
        repository.getEffectiveTarget(
          phase.id,
          date: phase.contains(day)
              ? day
              : phase.endDate.isBefore(day)
              ? phase.endDate
              : phase.startDate,
        ),
    ]);
    final routines = await DatabaseHelper.instance.routineRepo.getRoutines();
    final runPlans = await DatabaseHelper.instance.runPlanRepo.listPlans(
      includeArchived: true,
    );
    return PlanOverviewData(
      plan: plan,
      phases: phases,
      targets: {
        for (var i = 0; i < phases.length; i++) phases[i].id: targets[i],
      },
      routineNames: {
        for (final row in routines)
          row['id'] as String: row['name'] as String? ?? '',
      },
      runPlanNames: {for (final plan in runPlans) plan.id: plan.name},
    );
  }

  PeriodizationPhase? phaseOn(DateTime date) =>
      phases.where((phase) => phase.contains(date)).firstOrNull;
}

/// The plan header: name, where today falls, the roadmap and a menu.
class PlanHeaderCard extends StatelessWidget {
  final PlanOverviewData data;
  final DateTime today;
  final Widget? menu;
  final ValueChanged<PeriodizationPhase>? onPhaseTap;

  const PlanHeaderCard({
    super.key,
    required this.data,
    required this.today,
    this.menu,
    this.onPhaseTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final plan = data.plan;
    final phases = data.phases;
    final start = phases.isEmpty ? plan.startDate : phases.first.startDate;
    final end = phases.isEmpty ? plan.endDate : phases.last.endDate;
    final totalWeeks = ((end.difference(start).inDays + 1) / 7).ceil();
    final String status;
    if (today.isBefore(start)) {
      status = loc.planningPlanStartsOn(
        DateFormat('d MMM', Intl.defaultLocale).format(start),
      );
    } else if (today.isAfter(end)) {
      status = loc.planningPlanFinished;
    } else {
      status = loc.planningPlanWeekOf(
        today.difference(start).inDays ~/ 7 + 1,
        totalWeeks,
      );
    }
    return PlanningCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$status · ${loc.planningEndsOn(DateFormat('d MMM y', Intl.defaultLocale).format(end))}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ?menu,
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PlanRoadmap(
              phases: phases,
              today: today,
              onPhaseTap: onPhaseTap,
            ),
          ),
        ],
      ),
    );
  }
}

/// One phase in the plan list: identity, status and a line of pills that
/// says what the phase plans (calories, routine, running, weight).
class PhaseSummaryCard extends StatelessWidget {
  final PeriodizationPhase phase;
  final PeriodizationTarget? target;
  final PlanOverviewData data;
  final DateTime today;
  final VoidCallback onTap;

  const PhaseSummaryCard({
    super.key,
    required this.phase,
    required this.target,
    required this.data,
    required this.today,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = Color(phase.color);
    final current = phase.contains(today);
    final done = phase.endDate.isBefore(today);
    final target = this.target;
    final pills = <Widget>[
      if (target?.calories != null)
        PlanningPill(
          icon: Icons.local_fire_department_outlined,
          label: target!.hasRestDayNutrition
              ? '${planningKcal(target.calories)}/${planningKcal(target.restCalories)}'
              : '${planningKcal(target.calories)} kcal',
        ),
      if (target?.proteinG != null)
        PlanningPill(
          icon: Icons.egg_alt_outlined,
          label: '${target!.proteinG!.round()} g P',
        ),
      if (target != null && target.strengthDays.isNotEmpty)
        PlanningPill(
          icon: Icons.fitness_center_rounded,
          label: loc.planningTimesPerWeek(target.strengthDays.length),
        ),
      for (final id in target?.routineIds ?? const <String>[])
        if (data.routineNames[id] case final name?)
          PlanningPill(icon: Icons.repeat_rounded, label: name),
      for (final id in target?.runPlanIds ?? const <String>[])
        if (data.runPlanNames[id] case final name?)
          PlanningPill(icon: Icons.directions_run_rounded, label: name),
      if (target != null &&
          target.runPlanIds.isEmpty &&
          target.runDays.isNotEmpty)
        PlanningPill(
          icon: Icons.directions_run_rounded,
          label: loc.planningTimesPerWeek(target.runDays.length),
        ),
      if (target?.weeklyWeightChangePercent case final rate?)
        if (rate != 0)
          PlanningPill(
            icon: rate < 0
                ? Icons.south_east_rounded
                : Icons.north_east_rounded,
            label: loc.planningWeightRatePerWeek(
              '${rate > 0 ? '+' : '−'}'
              '${AppNumberFormat.decimal(rate.abs(), 2, trimZeros: true)}%',
            ),
          ),
    ];
    return Opacity(
      opacity: done ? 0.7 : 1,
      child: PlanningCard(
        onTap: onTap,
        borderColor: current ? color.withAlpha(160) : null,
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                PhaseAvatar.of(phase),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        phase.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${planningDateRange(phase.startDate, phase.endDate)} · '
                        '${loc.planningWeeksShort(phase.totalWeeks)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AppPill(
                  label: phaseStatusLabel(loc, phase, today),
                  icon: done ? Icons.check_rounded : null,
                  iconSize: 12,
                  color: current
                      ? color
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  background:
                      (current
                              ? color
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest)
                          .withAlpha(current ? 40 : 140),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  fontWeight: FontWeight.w800,
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            if (current) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: phase.progressAt(today).toDouble(),
                  minHeight: 4,
                  color: color,
                  backgroundColor: color.withAlpha(40),
                ),
              ),
            ],
            if (pills.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: pills),
            ] else if (!done) ...[
              const SizedBox(height: 10),
              Text(
                loc.planningPhaseNoTargets,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Ready-made plan shapes in two columns; each card grows with its text so
/// nothing clips at large font sizes.
class BlueprintGrid extends StatelessWidget {
  final PlanBlueprint? selected;
  final ValueChanged<PlanBlueprint> onTap;

  const BlueprintGrid({super.key, this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const blueprints = PlanBlueprint.values;
    return Column(
      children: [
        for (var i = 0; i < blueprints.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _card(context, blueprints[i])),
                  const SizedBox(width: 8),
                  Expanded(
                    child: i + 1 < blueprints.length
                        ? _card(context, blueprints[i + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _card(BuildContext context, PlanBlueprint blueprint) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isSelected = blueprint == selected;
    return PlanningCard(
      key: Key('blueprint-${blueprint.name}'),
      padding: const EdgeInsets.all(12),
      color: isSelected
          ? scheme.primaryContainer.withAlpha(120)
          : scheme.surfaceContainerHighest.withAlpha(90),
      borderColor: isSelected ? scheme.primary : null,
      onTap: () => onTap(blueprint),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(blueprint.icon, size: 20, color: scheme.primary),
          const SizedBox(height: 8),
          Text(
            blueprint.label(loc),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            blueprint.summary(loc),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
