import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan_template.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_controller.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_warnings.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_widgets.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_strength_planner.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/run/run_plan_volume_sparkline.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Step 4: name, coach warnings, volume curve and a week-by-week browser.
class RunPlanWizardPreviewStep extends StatelessWidget {
  final RunPlanWizardController controller;
  final RunPlanOutline? outline;
  final ValueChanged<RunPlanTemplate> onSwitchTemplate;

  const RunPlanWizardPreviewStep({
    super.key,
    required this.controller,
    required this.outline,
    required this.onSwitchTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final outline = this.outline;
    final total = outline?.schedule.length ?? 0;
    final weekIndex = total == 0
        ? 0
        : controller.previewWeek.clamp(0, total - 1);
    final week = [...?(total == 0 ? null : outline!.schedule[weekIndex])]
      ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
    final weekOutline = total == 0 ? null : outline!.weeks[weekIndex];
    bool hasRace(int w) =>
        w >= 0 &&
        w < total &&
        outline!.schedule[w].any((s) => s.kind == RunWorkoutKind.race);
    final strengthDays = !controller.includeStrength || total == 0
        ? const <int>[]
        : RunStrengthPlanner.daysFor(
            [
              for (final s in week)
                (
                  day: s.dayOfWeek,
                  kind: s.kind,
                  km: (s.targetDistanceMeters ?? 0) / 1000,
                ),
            ],
            raceWeek: hasRace(weekIndex),
            weekBeforeRace: hasRace(weekIndex + 1),
          );
    final easyPace = outline?.paceRamp.pacesAt(weekIndex)?.easySecPerKm;
    final summary = <String>[
      if (outline != null && outline.peakWeeklyKm > 0)
        loc.runPlanCustomizePreviewPeak(wizardKm(outline.peakWeeklyKm)),
      if (outline != null && outline.peakLongKm > 0)
        loc.runPlanCustomizePreviewLong(wizardKm(outline.peakLongKm)),
      if (outline?.raceWeekNumber != null)
        loc.runPlanCustomizePreviewRaceWeek(outline!.raceWeekNumber!),
      if (outline?.startWeek != null)
        loc.runPlanCustomizeStartsOn(wizardDate(context, outline!.startWeek!)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RunPlanWizardStepTitle(
          loc.runPlanCustomizePreviewTitle,
          help: controller.isRunWalk
              ? loc.runPlanCustomizePreviewHelpRunWalk
              : controller.isMaintain
              ? loc.runPlanCustomizePreviewHelpMaintain
              : loc.runPlanCustomizePreviewHelp,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: controller.nameCtl,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: loc.runPlanName,
            hintText: loc.runPlanNameHint,
            helperText: loc.runPlanWizardNameHelp,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => controller.markChanged(),
        ),
        RunPlanWizardWarnings(
          controller: controller,
          outline: outline,
          full: true,
          onSwitchTemplate: onSwitchTemplate,
        ),
        if (outline != null && outline.hasVolumeCurve) ...[
          const SizedBox(height: 16),
          RunPlanVolumeSparkline(
            weeks: outline.weeks,
            selected: weekIndex,
            onSelect: controller.setPreviewWeek,
          ),
        ],
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(summary.join(' · '), style: theme.textTheme.titleSmall),
        ],
        if (week.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: weekIndex > 0
                    ? () => controller.setPreviewWeek(weekIndex - 1)
                    : null,
              ),
              Expanded(
                child: Text(
                  [
                    loc.runPlanCustomizeWeekOf(weekIndex + 1, total),
                    if (weekOutline != null && !controller.isRunWalk)
                      RunPlanVolumeSparkline.phaseLabel(loc, weekOutline.phase),
                    if (weekOutline != null && weekOutline.weekKm >= 1)
                      '${wizardKm(weekOutline.weekKm)} km',
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: weekIndex < total - 1
                    ? () => controller.setPreviewWeek(weekIndex + 1)
                    : null,
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        for (final session in week)
          _PreviewCard(
            child: ListTile(
              leading: Icon(
                RunPlanUi.kindIcon(session.kind),
                color: RunPlanUi.kindColor(theme.colorScheme, session.kind),
              ),
              title: Text(session.name),
              subtitle: Text(
                [
                  RunPlanUi.weekdayLabel(loc, session.dayOfWeek),
                  RunPlanUi.kindLabel(loc, session.kind),
                  if (session.targetDistanceMeters != null)
                    RunPlanUi.distanceLabel(session.targetDistanceMeters!),
                  if (RunPlanComposer.estimateDurationSeconds(
                        session,
                        easySecPerKm: easyPace,
                      )
                      case final seconds?)
                    loc.runPlanCustomizeDuration((seconds / 60).round()),
                  if (session.targetPaceSecPerKm != null)
                    '${RunPlanUi.paceLabel(session.targetPaceSecPerKm)}/km',
                ].join(' · '),
              ),
            ),
          ),
        if (strengthDays.isNotEmpty)
          _PreviewCard(
            child: ListTile(
              leading: Icon(
                Icons.fitness_center_rounded,
                color: theme.colorScheme.secondary,
              ),
              title: Text(
                loc.runPlanCustomizeStrengthDays(
                  strengthDays
                      .map((d) => RunPlanUi.weekdayLabel(loc, d))
                      .join(', '),
                ),
              ),
              subtitle: Text(loc.runPlanCustomizeStrengthHelp),
            ),
          ),
      ],
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final Widget child;

  const _PreviewCard({required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: RunSectionCard(padding: EdgeInsets.zero, child: child),
  );
}
