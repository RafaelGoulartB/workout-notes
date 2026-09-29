import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/widgets/sleep/sleep_ui.dart';

/// Headline card of the sleep tab, laid out like the nutrition day summary:
/// how long the latest night was, how much of the goal that is, its time
/// window, a goal progress bar and the supporting numbers. Tapping opens the
/// night detail.
class SleepLastNightCard extends StatelessWidget {
  final SleepEntry entry;
  final SleepMonitorSession? session;
  final int goalMinutes;
  final VoidCallback onTap;

  const SleepLastNightCard({
    super.key,
    required this.entry,
    required this.goalMinutes,
    required this.onTap,
    this.session,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final slept = entry.effectiveSleepMinutes;
    final ratio = goalMinutes <= 0 ? 0.0 : slept / goalMinutes;
    final reached = slept >= goalMinutes;
    final window = SleepUi.window(entry.bedtimeMinutes, entry.wakeTimeMinutes);
    final hasStages =
        session != null &&
        session!.analysisStatus == SleepMonitorSession.analysisAvailable &&
        ((session!.sleepingMinutes ?? 0) + (session!.deepSleepMinutes ?? 0)) >
            0;

    return Semantics(
      container: true,
      button: true,
      label:
          '${loc.sleepLastNight}: ${SleepUi.duration(loc, slept)}, '
          '${reached ? loc.sleepGoalReached : loc.sleepGoalMissed}',
      child: SleepCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SleepCardHeader(
              icon: Icons.bedtime_rounded,
              title: loc.sleepLastNight,
              subtitle: '· ${SleepUi.weekdayDayMonth(entry.date)}',
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: SleepBigDuration(minutes: slept)),
                const SizedBox(width: 8),
                SleepHeadlinePercent(
                  value: '${(ratio * 100).round()}%',
                  caption: loc.sleepOfGoal,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              reached
                  ? loc.sleepGoalReached
                  : loc.sleepGoalShortBy(
                      SleepUi.duration(loc, goalMinutes - slept),
                    ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            if (window != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: SleepBadge(icon: Icons.nightlight_round, label: window),
              ),
            ],
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio.clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: colors.surfaceContainerHighest,
                color: colors.primary,
              ),
            ),
            if (hasStages) ...[
              const SizedBox(height: 14),
              SleepStageBar(session: session!, height: 6),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                runSpacing: 4,
                children: [
                  _StageAmount(
                    color: SleepUi.awake,
                    label: loc.sleepStageAwake,
                    minutes: session!.awakeMinutes,
                  ),
                  _StageAmount(
                    color: SleepUi.sleeping,
                    label: loc.sleepStageSleeping,
                    minutes: session!.sleepingMinutes,
                  ),
                  _StageAmount(
                    color: SleepUi.deep,
                    label: loc.sleepStageDeepShort,
                    minutes: session!.deepSleepMinutes,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            SleepStatRow(
              children: [
                SleepStat(
                  value: entry.efficiency == null
                      ? '--'
                      : '${entry.efficiency!.round()}%',
                  label: loc.sleepEfficiency,
                  progress: entry.efficiency == null
                      ? 0
                      : entry.efficiency! / 100,
                  color: SleepUi.efficiencyColor(colors, entry.efficiency),
                ),
                SleepStat(
                  value: SleepUi.duration(loc, entry.timeInBedMinutes),
                  label: loc.sleepMetricTimeInBed,
                  progress: entry.timeInBedMinutes == null
                      ? 0
                      : entry.timeInBedMinutes! / goalMinutes,
                  color: colors.secondary,
                ),
                SleepStat(
                  value: SleepUi.duration(loc, goalMinutes),
                  label: loc.sleepGoalTarget,
                  progress: ratio,
                  color: colors.tertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StageAmount extends StatelessWidget {
  final Color color;
  final String label;
  final int? minutes;

  const _StageAmount({
    required this.color,
    required this.label,
    required this.minutes,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label ${SleepUi.duration(loc, minutes ?? 0)}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
