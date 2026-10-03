import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/ai/proposals/ai_proposal_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Preview of a `workout_schedule` proposal: schedule a routine day, move a
/// planned workout or copy a workout, with the exercises involved.
class WorkoutScheduleProposalBody extends StatelessWidget {
  final Map<String, dynamic> preview;

  const WorkoutScheduleProposalBody({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = AiProposalFormat(l10n);
    final theme = Theme.of(context);
    final action = preview['action'];
    final exercises = jsonMaps(preview['exercises']);
    final total =
        jsonNum(preview['exercise_count'])?.toInt() ?? exercises.length;
    final date = fmt.date(jsonText(preview['date']));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (action == 'schedule_routine_day')
          Text(
            l10n.aiProposalScheduleDay(
              jsonText(preview['routine']) ?? '',
              jsonText(preview['day']) ?? '',
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        if (action == 'move')
          Text(
            l10n.aiProposalScheduleMoveFromTo(
              fmt.date(jsonText(preview['from_date'])),
              date,
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              l10n.aiProposalScheduleOn(date),
              style: theme.textTheme.bodyMedium,
            ),
          ),
        if (action == 'copy')
          Text(
            l10n.aiProposalScheduleCopyHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [AppMetricChip(text: l10n.aiProposalCountExercises(total))],
        ),
        const SizedBox(height: 6),
        for (final exercise in exercises)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  Icons.fitness_center_rounded,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    fmt.exerciseName(exercise),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Text(
                  l10n.aiProposalCountSets(
                    jsonNum(exercise['sets'])?.toInt() ?? 0,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        if (total > exercises.length)
          Text(
            l10n.aiProposalScheduleMore(total - exercises.length),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// Preview of a `run_plan` proposal: a session moved to another weekday, or a
/// lighter week with the planned volume before and after.
class RunPlanProposalBody extends StatelessWidget {
  final Map<String, dynamic> preview;

  const RunPlanProposalBody({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = AiProposalFormat(l10n);
    final theme = Theme.of(context);
    final isScale = preview['action'] == 'scale_week';
    final header = l10n.aiProposalRunWeek(
      jsonText(preview['plan']) ?? '',
      jsonNum(preview['week'])?.toInt() ?? 0,
    );
    if (!isScale) {
      final session = jsonMap(preview['session']);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.aiProposalRunMoveFromTo(
              jsonText(session['name']) ?? '',
              fmt.weekday(jsonNum(preview['from_day'])?.toInt()),
              fmt.weekday(jsonNum(preview['to_day'])?.toInt()),
            ),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (jsonText(preview['date']) != null)
            Text(
              fmt.date(jsonText(preview['date'])),
              style: theme.textTheme.bodySmall,
            ),
          if (jsonNum(session['distance_m']) != null &&
              jsonNum(session['distance_m'])! > 0)
            Text(
              fmt.kmFromMeters(jsonNum(session['distance_m'])),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      );
    }
    final sessions = jsonMaps(preview['sessions']);
    final reason = jsonText(preview['reason']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          header,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.aiProposalRunWeekVolume(
            fmt.kmFromMeters(jsonNum(preview['before_m'])),
            fmt.kmFromMeters(jsonNum(preview['after_m'])),
          ),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        for (final session in sessions)
          if (jsonNum(session['before_m']) != jsonNum(session['after_m']))
            AiProposalChangeLine(
              icon: Icons.trending_down_rounded,
              color: theme.colorScheme.primary,
              text:
                  '${session['name']}: ${fmt.kmFromMeters(jsonNum(session['before_m']))} → ${fmt.kmFromMeters(jsonNum(session['after_m']))}',
            ),
        const SizedBox(height: 6),
        Text(
          l10n.aiProposalRunKeepShape,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (reason != null)
          Text(
            l10n.aiProposalRunReason(reason),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
