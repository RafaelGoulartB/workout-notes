import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/widgets/goals/goal_progress_ring.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/sleep/sleep_ui.dart';

/// Headline card of the sleep tab: how long the latest night was against the
/// personal goal, its time window, stage split (when measured) and the key
/// supporting numbers. Tapping opens the night detail.
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
    final accent = reached ? colors.primary : colors.tertiary;
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(RunUi.heroRadius),
          child: RunHeroCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      loc.sleepLastNight.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        ' · ${SleepUi.weekdayDayMonth(entry.date)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onSurfaceVariant,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    GoalProgressRing(
                      percent: ratio,
                      color: accent,
                      trackColor: accent.withAlpha(35),
                      size: 88,
                      strokeWidth: 8,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${(ratio * 100).round().clamp(0, 999)}%',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontFeatures: RunUi.tabular,
                            ),
                          ),
                          Text(
                            loc.sleepOfGoal,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              SleepUi.duration(loc, slept),
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                fontFeatures: RunUi.tabular,
                              ),
                            ),
                          ),
                          if (window != null) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.bedtime_outlined,
                                  size: 15,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  window,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    fontFeatures: RunUi.tabular,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          RunPill(
                            icon: reached
                                ? Icons.check_rounded
                                : Icons.flag_outlined,
                            color: accent,
                            label: reached
                                ? loc.sleepGoalReached
                                : loc.sleepGoalShortBy(
                                    SleepUi.duration(loc, goalMinutes - slept),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (hasStages) ...[
                  const SizedBox(height: 16),
                  SleepStageBar(session: session!, height: 8),
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
                RunStatRow(
                  children: [
                    RunStatTile(
                      icon: Icons.speed_rounded,
                      color: SleepUi.efficiencyColor(colors, entry.efficiency),
                      label: loc.sleepEfficiency,
                      value: entry.efficiency == null
                          ? '--'
                          : '${entry.efficiency!.round()}%',
                    ),
                    RunStatTile(
                      icon: Icons.hotel_rounded,
                      label: loc.sleepMetricTimeInBed,
                      value: SleepUi.duration(loc, entry.timeInBedMinutes),
                    ),
                    RunStatTile(
                      icon: Icons.flag_outlined,
                      label: loc.sleepGoalTarget,
                      value: SleepUi.duration(loc, goalMinutes),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
