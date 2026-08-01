import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';

/// Compact dashboard section inspired by the reference sleep-goal summary.
///
/// It only renders metrics that are actually present in [entry] or [stats].
/// Missing values stay as `--` instead of being inferred from a different
/// measurement.
class SleepGoalMetricsCard extends StatelessWidget {
  const SleepGoalMetricsCard({
    super.key,
    required this.entry,
    required this.stats,
    required this.goalMinutes,
  });

  final SleepEntry entry;
  final SleepDashboardStats stats;
  final int goalMinutes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final sleptMinutes =
        entry.actualSleepMinutes ??
        entry.estimatedSleepMinutes ??
        entry.sleepMinutes;
    final reached = sleptMinutes >= goalMinutes;
    final status = reached ? loc.sleepGoalReached : loc.sleepGoalMissed;
    final statusColor = reached ? colors.primary : colors.tertiary;

    return Semantics(
      container: true,
      label: '${loc.sleepGoalTitle}: $status',
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colors.outlineVariant.withAlpha(80),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.track_changes_rounded, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${loc.sleepGoalTitle}: $status',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${loc.sleepGoalTarget}: ${_formatDuration(goalMinutes, loc)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Tooltip(
                    message: loc.sleepGoalInfo,
                    child: Icon(
                      Icons.help_outline_rounded,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final metrics = [
                    _MetricData(
                      icon: Icons.bedtime_rounded,
                      label: loc.sleepMetricSleep,
                      value: _formatDuration(sleptMinutes, loc),
                    ),
                    _MetricData(
                      icon: Icons.speed_rounded,
                      label: loc.sleepEfficiency,
                      value: _formatPercent(entry.efficiency),
                    ),
                    _MetricData(
                      icon: Icons.bar_chart_rounded,
                      label: loc.sleepRegularity,
                      value: _formatPercent(stats.regularity7Days),
                    ),
                    _MetricData(
                      icon: Icons.hotel_rounded,
                      label: loc.sleepMetricTimeInBed,
                      value: _formatDuration(entry.timeInBedMinutes, loc),
                    ),
                    _MetricData(
                      icon: Icons.nightlight_round,
                      label: loc.sleepBedtime,
                      value: _formatClock(entry.bedtimeMinutes),
                    ),
                    _MetricData(
                      icon: Icons.wb_sunny_outlined,
                      label: loc.sleepWakeTime,
                      value: _formatClock(entry.wakeTimeMinutes),
                    ),
                  ];
                  final columns = constraints.maxWidth < 300 ? 1 : 2;
                  return GridView.builder(
                    itemCount: metrics.length,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 10,
                      mainAxisExtent: 48,
                    ),
                    itemBuilder: (context, index) =>
                        _MetricTile(data: metrics[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(int? minutes, AppLocalizations loc) {
    if (minutes == null) return '--';
    return loc.sleepDurationValue(minutes ~/ 60, minutes % 60);
  }

  static String _formatPercent(double? value) {
    if (value == null) return '--';
    return '${value.round()}%';
  }

  static String _formatClock(int? minutes) {
    if (minutes == null) return '--';
    final hour = (minutes ~/ 60) % 24;
    return '${hour.toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  }
}

class _MetricData {
  const _MetricData({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Icon(data.icon, size: 22, color: colors.primary),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                data.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
