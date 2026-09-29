import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_controller.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_widgets.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

/// Step 3: recent race time, goal time and the resulting pace preview.
class RunPlanWizardPaceStep extends StatelessWidget {
  final RunPlanWizardController controller;
  final RunPlanOutline? outline;

  const RunPlanWizardPaceStep({
    super.key,
    required this.controller,
    required this.outline,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = wizardMutedStyle(theme);
    final distances = <(String, double)>[
      for (final meters in RunPlanWizardController.standardDistances)
        (controller.distanceName(loc, meters), meters),
    ];
    final suggested = controller.history?.suggestedRace;
    final current = controller.currentDistanceMeters;
    final nearest = distances.reduce(
      (a, b) => (a.$2 - current).abs() < (b.$2 - current).abs() ? a : b,
    );
    final goalDistance = controller.goalDistance;
    final ramp = outline?.paceRamp;
    final start = ramp?.pacesAt(0);
    final end = ramp?.targetPaces;
    final plannedWeeks = outline?.schedule.length ?? controller.template.weeks;
    final projected = goalDistance == null
        ? null
        : ramp?.projectedSeconds(goalDistance);
    final assessment =
        outline?.readiness.goalAssessment ?? RunPlanGoalAssessment.none;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RunPlanWizardStepTitle(
          loc.runPlanCustomizePaceTitle,
          help: loc.runPlanCustomizePaceHelp,
        ),
        const SizedBox(height: 20),
        RunPlanWizardSubtitle(loc.runPlanCustomizeCurrentTitle),
        const SizedBox(height: 4),
        Text(loc.runPlanCustomizeCurrentHelp, style: muted),
        if (suggested != null) ...[
          const SizedBox(height: 4),
          Text(
            loc.runPlanCustomizePaceFromRun(
              RunPlanUi.distanceLabel(suggested.distanceMeters),
              RunFormatters.duration(suggested.timeSeconds),
            ),
            style: muted,
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in distances)
              ChoiceChip(
                label: Text(entry.$1),
                selected: (nearest.$2 - entry.$2).abs() < 1,
                onSelected: (_) => controller.setCurrentDistance(entry.$2),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _TimeField(
          controller: controller,
          field: controller.currentCtl,
          seconds: controller.currentSeconds,
        ),
        if (goalDistance != null && !controller.isMaintain) ...[
          const SizedBox(height: 24),
          RunPlanWizardSubtitle(
            loc.runPlanCustomizeGoalTitle(
              controller.distanceName(loc, goalDistance),
            ),
          ),
          const SizedBox(height: 4),
          Text(loc.runPlanCustomizeGoalHelp, style: muted),
          const SizedBox(height: 12),
          _TimeField(
            controller: controller,
            field: controller.goalCtl,
            seconds: controller.goalSeconds,
          ),
          if (controller.goalCalibration != null &&
              controller.currentCalibration == null) ...[
            const SizedBox(height: 8),
            Text(loc.runPlanCustomizeGoalOnlyNote, style: muted),
          ],
        ],
        if (start != null) ...[
          const SizedBox(height: 20),
          Text(
            loc.runPlanCustomizePacePreview(
              RunPlanUi.paceLabel(start.easySecPerKm),
              RunPlanUi.paceLabel(start.tempoSecPerKm),
              RunPlanUi.paceLabel(start.intervalSecPerKm),
            ),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (end != null &&
              (end.tempoSecPerKm - start.tempoSecPerKm).abs() >= 1) ...[
            const SizedBox(height: 4),
            Text(
              loc.runPlanCustomizePaceEndPreview(
                RunPlanUi.paceLabel(end.tempoSecPerKm),
                RunPlanUi.paceLabel(end.intervalSecPerKm),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (projected != null) ...[
            const SizedBox(height: 12),
            RunPlanWizardGoalFeedback(
              assessment: assessment,
              message: switch (assessment) {
                RunPlanGoalAssessment.realistic =>
                  loc.runPlanCustomizeGoalRealistic(plannedWeeks),
                RunPlanGoalAssessment.ambitious =>
                  loc.runPlanCustomizeGoalAmbitious(
                    RunFormatters.duration(projected),
                  ),
                RunPlanGoalAssessment.unrealistic =>
                  loc.runPlanCustomizeGoalUnrealistic(
                    plannedWeeks,
                    RunFormatters.duration(projected),
                  ),
                RunPlanGoalAssessment.none => loc.runPlanCustomizeProjection(
                  RunFormatters.duration(projected),
                ),
              },
            ),
          ],
          const SizedBox(height: 8),
          Text(loc.runPlanCustomizePaceEstimateNote, style: muted),
        ],
      ],
    );
  }
}

class _TimeField extends StatelessWidget {
  final RunPlanWizardController controller;
  final TextEditingController field;
  final int? seconds;

  const _TimeField({
    required this.controller,
    required this.field,
    required this.seconds,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return TextField(
      controller: field,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: loc.runPlanCustomizePaceTime,
        hintText: loc.runPlanCustomizePaceTimeHint,
        errorText: seconds != null && seconds! < 0
            ? loc.runPlanCustomizeTimeInvalid
            : null,
        border: const OutlineInputBorder(),
      ),
      onChanged: (_) => controller.markChanged(),
    );
  }
}
