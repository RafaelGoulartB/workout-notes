import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan_template.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_controller.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_widgets.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Coach warnings for the current step. Days step: only the schedule smell;
/// preview step: everything, so the athlete sees it right before creating.
class RunPlanWizardWarnings extends StatelessWidget {
  final RunPlanWizardController controller;
  final RunPlanOutline? outline;
  final bool full;

  /// Opens [template] in a fresh wizard (a "try a shorter goal" action).
  final ValueChanged<RunPlanTemplate> onSwitchTemplate;

  const RunPlanWizardWarnings({
    super.key,
    required this.controller,
    required this.outline,
    required this.full,
    required this.onSwitchTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final readiness = outline?.readiness;
    if (readiness == null) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final template = controller.template;
    final isPt = controller.isPt;
    final messages = <String>[];
    final actions = <(String, VoidCallback)>[];
    void action(String label, VoidCallback onTap) {
      if (actions.every((a) => a.$1 != label)) actions.add((label, onTap));
    }

    if (readiness.consecutiveDays) {
      messages.add(loc.runPlanCustomizeWarnConsecutiveDays);
    }
    if (full && readiness.raceTooSoon) {
      messages.add(
        loc.runPlanCustomizeWarnRaceTooSoon(
          readiness.weeksToRace ?? 0,
          readiness.minWeeks,
        ),
      );
      action(loc.runPlanCustomizeActionPickDate, () => controller.goToStep(0));
    }
    if (full && readiness.baselineZero) {
      messages.add(loc.runPlanCustomizeWarnZeroBaseline);
      action(
        loc.runPlanCustomizeActionStartRunning,
        () => onSwitchTemplate(RunPlanTemplates.runWalk),
      );
    }
    if (full && readiness.volumeGap) {
      messages.add(
        loc.runPlanCustomizeWarnVolumeGap(
          wizardKm(readiness.startWeeklyKm),
          wizardKm(readiness.currentWeeklyKm ?? 0),
        ),
      );
    }
    if (full && readiness.thinSessions) {
      messages.add(loc.runPlanCustomizeWarnThinSessions);
    }
    if (full && (readiness.volumeGap || readiness.thinSessions)) {
      if (controller.sessions > 3 &&
          template.allowedSessionsPerWeek.contains(3)) {
        action(
          loc.runPlanCustomizeActionThreeDays,
          () => controller.setSessions(3),
        );
      }
      if (readiness.volumeGap &&
          controller.intensity != RunPlanIntensity.conservative) {
        action(
          loc.runPlanCustomizeActionConservative,
          () => controller.setIntensity(RunPlanIntensity.conservative),
        );
      }
    }
    if (full && readiness.timeCapDistanceGap) {
      messages.add(
        loc.runPlanCustomizeWarnTimeCapGap(
          wizardKm(readiness.longRunCapKm),
          wizardKm(readiness.requiredLongKm),
        ),
      );
    } else if (full && readiness.longRunShort) {
      messages.add(
        loc.runPlanCustomizeWarnLongRunShort(
          wizardKm(readiness.peakLongKm),
          wizardKm(readiness.requiredLongKm),
        ),
      );
    }
    if (full && (readiness.longRunShort || readiness.baselineZero)) {
      final shorter = RunPlanTemplates.shorterGoal(template);
      if (shorter != null && shorter.key != RunPlanTemplates.runWalk.key) {
        action(
          loc.runPlanCustomizeActionTryPlan(shorter.title(isPt)),
          () => onSwitchTemplate(shorter),
        );
      }
    }
    if (full && readiness.needsHillAccess) {
      messages.add(loc.runPlanCustomizeWarnNeedsHills);
      final threshold = RunPlanTemplates.thresholdBlock;
      action(
        loc.runPlanCustomizeActionTryPlan(threshold.title(isPt)),
        () => onSwitchTemplate(threshold),
      );
    }
    if (messages.isEmpty) return const SizedBox.shrink();

    final scheme = theme.colorScheme;
    final blocking = full && !readiness.canCreate;
    final background = blocking
        ? scheme.errorContainer
        : scheme.tertiaryContainer;
    final foreground = blocking
        ? scheme.onErrorContainer
        : scheme.onTertiaryContainer;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppSectionCard(
        color: background,
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: foreground),
                const SizedBox(width: 8),
                Text(
                  loc.runPlanCustomizeWarnTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foreground,
                  ),
                ),
              ],
            ),
            for (final message in messages) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(color: foreground),
              ),
            ],
            if (blocking) ...[
              const SizedBox(height: 8),
              Text(
                loc.runPlanCustomizeBlocked,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (label, onTap) in actions)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: foreground,
                        side: BorderSide(color: foreground),
                      ),
                      onPressed: onTap,
                      child: Text(label),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
