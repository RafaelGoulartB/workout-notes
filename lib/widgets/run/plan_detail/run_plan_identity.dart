import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

/// One line of identity (goal, length), the race date with its countdown and
/// the notes. Deliberately not a card: a box around it only pushed the
/// training week further down.
class RunPlanIdentity extends StatelessWidget {
  final RunPlan plan;
  final DateTime today;

  const RunPlanIdentity({super.key, required this.plan, required this.today});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    final race = plan.raceDate;
    int? countdown;
    if (race != null) {
      final days = DateTime(
        race.year,
        race.month,
        race.day,
      ).difference(dayOf(today)).inDays;
      countdown = days < 0 ? null : days;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${RunPlanUi.goalLabel(loc, plan.goalKind)} · '
                  '${loc.runPlanWeeksValue(plan.weeks)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (race != null) ...[
            const SizedBox(height: 6),
            Text(
              countdown == null
                  ? DateFormat('d MMM y', Intl.defaultLocale).format(race)
                  : '${DateFormat('d MMM', Intl.defaultLocale).format(race)}'
                        ' · ${loc.runPlanRaceCountdown(countdown)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (plan.notes != null && plan.notes!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              plan.notes!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
