import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan_template.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_controller.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_warnings.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_widgets.dart';
import 'package:workout_notes/services/run_plan_composer.dart';

/// Step 1: sessions per week, which days, long-run day, plan length, race date.
class RunPlanWizardDaysStep extends StatelessWidget {
  final RunPlanWizardController controller;
  final RunPlanOutline? outline;
  final ValueChanged<RunPlanTemplate> onSwitchTemplate;

  const RunPlanWizardDaysStep({
    super.key,
    required this.controller,
    required this.outline,
    required this.onSwitchTemplate,
  });

  List<String> _weekdayLabels(AppLocalizations loc) => [
    loc.runPlanCustomizeWeekdayMon,
    loc.runPlanCustomizeWeekdayTue,
    loc.runPlanCustomizeWeekdayWed,
    loc.runPlanCustomizeWeekdayThu,
    loc.runPlanCustomizeWeekdayFri,
    loc.runPlanCustomizeWeekdaySat,
    loc.runPlanCustomizeWeekdaySun,
  ];

  String? _raceNote(AppLocalizations loc, BuildContext context) {
    final readiness = outline?.readiness;
    final current = outline;
    if (!controller.hasRace ||
        controller.raceDate == null ||
        readiness == null ||
        current == null) {
      return null;
    }
    final weeksToRace = readiness.weeksToRace;
    final plannedWeeks = current.schedule.length;
    if (readiness.raceTooSoon) {
      return loc.runPlanCustomizeWarnRaceTooSoon(
        weeksToRace ?? 0,
        readiness.minWeeks,
      );
    }
    if (weeksToRace != null && weeksToRace < controller.template.weeks) {
      return loc.runPlanCustomizeRaceCompressed(plannedWeeks);
    }
    if (current.startWeek != null) {
      return loc.runPlanCustomizeRaceStartsLater(
        plannedWeeks,
        wizardDate(context, current.startWeek!),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final labels = _weekdayLabels(loc);
    final template = controller.template;
    final muted = wizardMutedStyle(theme);
    final raceNote = _raceNote(loc, context);
    final sortedDays = controller.days.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RunPlanWizardStepTitle(
          loc.runPlanCustomizeDaysTitle,
          help: loc.runPlanCustomizeDaysHelp,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final n in template.allowedSessionsPerWeek)
              ChoiceChip(
                label: Text(loc.runPlanCustomizeSessions(n)),
                selected: controller.sessions == n,
                onSelected: (_) => controller.setSessions(n),
              ),
          ],
        ),
        const SizedBox(height: 24),
        RunPlanWizardSubtitle(
          loc.runPlanCustomizePickDays(controller.sessions),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var d = 1; d <= 7; d++)
              FilterChip(
                label: Text(labels[d - 1]),
                selected: controller.days.contains(d),
                onSelected: (selected) {
                  if (!controller.toggleDay(d, selected)) {
                    // Silently swapping a day the athlete picked earlier was
                    // confusing; say what to do instead.
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            loc.runPlanCustomizeDaysFull(controller.sessions),
                          ),
                        ),
                      );
                  }
                },
              ),
          ],
        ),
        if (!controller.daysValid) ...[
          const SizedBox(height: 12),
          Text(
            loc.runPlanCustomizePickDays(controller.sessions),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (!controller.isRunWalk && controller.daysValid) ...[
          const SizedBox(height: 24),
          RunPlanWizardSubtitle(loc.runPlanCustomizeLongRunDay),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: Text(loc.runPlanCustomizeLongRunAuto),
                selected: controller.longRunDay == null,
                onSelected: (_) => controller.setLongRunDay(null),
              ),
              for (final d in sortedDays)
                ChoiceChip(
                  label: Text(labels[d - 1]),
                  selected: controller.longRunDay == d,
                  onSelected: (_) => controller.setLongRunDay(d),
                ),
            ],
          ),
        ],
        if (template.selectableWeeks) ...[
          const SizedBox(height: 24),
          RunPlanWizardSubtitle(loc.runPlanCustomizeWeeksTitle),
          const SizedBox(height: 8),
          Text(loc.runPlanCustomizeWeeksHelp, style: muted),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in template.allowedWeeks)
                ChoiceChip(
                  label: Text(loc.runPlanWeeksValue(n)),
                  selected: controller.weeks == n,
                  onSelected: (_) => controller.setWeeks(n),
                ),
            ],
          ),
        ],
        RunPlanWizardWarnings(
          controller: controller,
          outline: outline,
          full: false,
          onSwitchTemplate: onSwitchTemplate,
        ),
        if (controller.hasRace) ...[
          const SizedBox(height: 24),
          _RaceDateTile(controller: controller),
          if (raceNote != null)
            Text(
              raceNote,
              style: outline?.readiness.raceTooSoon ?? false
                  ? theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    )
                  : muted,
            ),
        ],
      ],
    );
  }
}

class _RaceDateTile extends StatelessWidget {
  final RunPlanWizardController controller;

  const _RaceDateTile({required this.controller});

  Future<void> _pick(BuildContext context) async {
    final today = controller.today;
    final picked = await showDatePicker(
      context: context,
      initialDate:
          controller.raceDate ??
          today.add(Duration(days: 7 * controller.template.weeks)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 800)),
    );
    if (picked != null) controller.setRaceDate(picked);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final raceDate = controller.raceDate;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(loc.runPlanCustomizeRaceDate),
      subtitle: Text(
        raceDate == null
            ? loc.runPlanRaceDateNone
            : wizardDate(context, raceDate),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (raceDate != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => controller.setRaceDate(null),
            ),
          IconButton(
            icon: Icon(
              raceDate == null ? Icons.event_outlined : Icons.event_available,
            ),
            onPressed: () => _pick(context),
          ),
        ],
      ),
    );
  }
}
