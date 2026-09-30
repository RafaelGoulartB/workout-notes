import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/services/run_plan_adaptation.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

/// The weekly review's suggestion: what happened, what changes, and the
/// choice to apply it or keep the plan as it is.
class RunPlanAdaptationCard extends StatelessWidget {
  final RunPlan plan;
  final RunPlanAdaptationProposal proposal;
  final bool busy;
  final VoidCallback onApply;
  final VoidCallback onKeep;
  final VoidCallback onReturnPlan;

  const RunPlanAdaptationCard({
    super.key,
    required this.plan,
    required this.proposal,
    required this.busy,
    required this.onApply,
    required this.onKeep,
    required this.onReturnPlan,
  });

  static String _km(double km) => km < 0.05
      ? '0'
      : km >= 10
      ? RunFormatters.decimal(km, 0)
      : RunPlanUi.kmValue(km * 1000);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final last = proposal.lastWeek;
    final title = switch (proposal.adjustment) {
      RunPlanAdjustment.hold
          when last?.fatigued == true && last?.outcome == RunWeekOutcome.full =>
        loc.runPlanAdaptTitleFatigue,
      RunPlanAdjustment.hold => loc.runPlanAdaptTitleHold,
      RunPlanAdjustment.stepBack => loc.runPlanAdaptTitleStepBack,
      RunPlanAdjustment.rebuild => loc.runPlanAdaptTitleRebuild(
        proposal.missedWeeks,
      ),
      RunPlanAdjustment.none => loc.runPlanAdaptTitlePace,
    };
    final lines = <String>[];
    if (last != null && proposal.adjustment != RunPlanAdjustment.none) {
      lines.add(
        loc.runPlanAdaptLastWeek(
          _km(last.doneKm),
          _km(last.plannedKm),
          (last.adherence * 100).round(),
          last.doneSessions,
          last.plannedSessions,
        ),
      );
      if (last.easyRpe != null && last.easyRpe! >= 6.5) {
        lines.add(
          loc.runPlanAdaptEasyRpe(RunFormatters.decimal(last.easyRpe!)),
        );
      }
      if (last.maxedOutRuns >= 2) {
        lines.add(loc.runPlanAdaptMaxedOut(last.maxedOutRuns));
      }
    }
    final baseline = proposal.baselineKm;
    final before = proposal.fromWeek < plan.weeks
        ? plan.weeklyDistanceMeters(proposal.fromWeek) / 1000
        : 0.0;
    if (baseline != null && before > 0 && (before - baseline).abs() >= 1) {
      lines.add(loc.runPlanAdaptVolume(_km(baseline), _km(before)));
    }
    final configured = plan.config != null && plan.templateKey != null;
    if (configured && proposal.adjustment != RunPlanAdjustment.none) {
      if (plan.raceDate != null) {
        lines.add(
          loc.runPlanAdaptRaceKept(
            DateFormat('d MMM', Intl.defaultLocale).format(plan.raceDate!),
          ),
        );
      } else if (proposal.remainingWeeks != null) {
        final extra = proposal.fromWeek + proposal.remainingWeeks! - plan.weeks;
        if (extra > 0) lines.add(loc.runPlanAdaptExtends(extra));
      }
    }
    if (proposal.changesPace && configured) {
      final before = RunPaceCalculator.fromVdot(proposal.expectedVdot!);
      final after = RunPaceCalculator.fromVdot(proposal.newVdot!);
      final direction = proposal.pacesUp
          ? loc.runPlanAdaptFitter
          : loc.runPlanAdaptSlower;
      final a = RunPlanUi.paceLabel(before.intervalSecPerKm);
      final b = RunPlanUi.paceLabel(after.intervalSecPerKm);
      lines.add(switch (proposal.paceSource) {
        RunFitnessSource.test ||
        RunFitnessSource.race => loc.runPlanAdaptPaceTest(direction, a, b),
        RunFitnessSource.bestEffort => loc.runPlanAdaptPaceEffort(
          direction,
          a,
          b,
        ),
        _ => loc.runPlanAdaptPaceWorkouts(direction, a, b),
      });
    }
    if (!configured) lines.add(loc.runPlanAdaptNoConfig);
    if (proposal.suggestReturnPlan) lines.add(loc.runPlanAdaptReturnHint);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withAlpha(120),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.secondary.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 18, color: scheme.secondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (proposal.suggestReturnPlan)
                OutlinedButton(
                  onPressed: busy ? null : onReturnPlan,
                  child: Text(loc.runPlanAdaptOpenReturn),
                ),
              TextButton(
                onPressed: busy ? null : onKeep,
                child: Text(loc.runPlanAdaptKeep),
              ),
              FilledButton(
                onPressed: busy ? null : onApply,
                child: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(loc.runPlanAdaptApply),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
