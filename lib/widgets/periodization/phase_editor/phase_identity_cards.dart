import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/periodization/phase_editor_controller.dart';
import 'package:workout_notes/periodization/phase_kind.dart';
import 'package:workout_notes/periodization/phase_week_plan.dart';
import 'package:workout_notes/utils/periodization_palette.dart';
import 'package:workout_notes/widgets/periodization/planning_widgets.dart';

class PhaseIdentityCard extends StatelessWidget {
  final PhaseEditorController controller;

  const PhaseIdentityCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = controller.phase.startDate;
    final end = start.add(Duration(days: 7 * controller.weeks - 1));
    return PlanningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhaseAvatar(
                color: Color(controller.color),
                icon: controller.kind.icon,
                size: 48,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller.name,
                  onChanged: (_) => controller.touch(),
                  textCapitalization: TextCapitalization.sentences,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: InputDecoration(
                    hintText: loc.planningPhaseNameHint,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final kind in PhaseKind.values)
                ChoiceChip(
                  avatar: Icon(
                    kind.icon,
                    size: 16,
                    color: controller.kind == kind
                        ? scheme.onSecondaryContainer
                        : Color(kind.color),
                  ),
                  label: Text(kind.label(loc)),
                  selected: controller.kind == kind,
                  showCheckmark: false,
                  onSelected: (_) => controller.setKind(
                    kind,
                    labelOf: (value) => value.label(loc),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            controller.kind.description(loc),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (controller.kind == PhaseKind.custom) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                for (final color in kPeriodizationColors)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => controller.setColor(color),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Color(color),
                        child: controller.color == color
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const Divider(height: 28),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.planningDuration,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      planningDateRange(start, end),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PlanningStepper(
                value: loc.planningWeeksShort(controller.weeks),
                onDecrement:
                    controller.weeks > 1 &&
                        controller.weeks > controller.editableFrom + 1
                    ? () => controller.setWeeks(controller.weeks - 1)
                    : null,
                onIncrement: controller.weeks < 104
                    ? () => controller.setWeeks(controller.weeks + 1)
                    : null,
              ),
            ],
          ),
          if (controller.weeks != controller.phase.totalWeeks)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                loc.planningDurationShiftHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: controller.intent,
            onChanged: (_) => controller.touch(),
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: loc.planningPhaseGoal,
              hintText: loc.planningPhaseGoalHint,
              prefixIcon: const Icon(Icons.flag_outlined),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class PhaseTemplateWeekCard extends StatelessWidget {
  final PhaseEditorController controller;

  const PhaseTemplateWeekCard({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final week = controller.currentWeek ?? controller.editableFrom;
    final plan = controller.weekPlan(week.clamp(0, controller.weeks - 1));
    final average = PhaseWeekPlan.averageCalories(plan);
    final trainingDays = plan.where((day) => day.trainingDay).length;
    return PlanningCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TemplateWeekStrip(
            week: plan,
            accent: Color(controller.color),
            strengthLabels: controller.strengthSequence,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              PhaseWeekLegend(
                icon: Icons.fitness_center_rounded,
                label: loc.planningLegendStrength,
              ),
              PhaseWeekLegend(
                icon: Icons.directions_run_rounded,
                label: loc.planningLegendRun,
              ),
              PhaseWeekLegend(
                icon: Icons.remove_rounded,
                label: loc.planningLegendRest,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            trainingDays == 0
                ? loc.planningTemplateWeekEmpty
                : average == null
                ? loc.planningTrainingDaysCount(trainingDays)
                : loc.planningTemplateWeekSummary(
                    trainingDays,
                    planningKcal(average),
                  ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class PhaseWeekLegend extends StatelessWidget {
  final IconData icon;
  final String label;

  const PhaseWeekLegend({super.key, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
