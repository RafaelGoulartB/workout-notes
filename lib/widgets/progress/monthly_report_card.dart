import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/progress_helpers.dart';
import 'package:workout_notes/widgets/progress/progress_stat_cards.dart';

/// Monthly report summary card showing workout count, volume, sets, days,
/// average feeling, and comparison with last month.
class MonthlyReportCard extends StatelessWidget {
  final Map<String, dynamic>? report;
  final Map<String, dynamic>? comparison;

  const MonthlyReportCard({
    super.key,
    required this.report,
    required this.comparison,
  });

  @override
  Widget build(BuildContext context) {
    if (report == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final wc = report!['workout_count'] as int? ?? 0;
    final vol = (report!['total_volume'] as double?) ?? 0;
    final sets = report!['total_sets'] as int? ?? 0;
    final days = report!['days_with_workouts'] as int? ?? 0;
    final avgFeeling = report!['avg_feeling'] as double?;

    final comp = comparison;
    final deltaW = comp?['delta_workouts'] as int? ?? 0;
    final deltaV = (comp?['delta_volume'] as double?) ?? 0;

    final now = DateTime.now();
    final monthName = DateFormat('MMMM', Intl.defaultLocale).format(now);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(100),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.primaryContainer.withAlpha(120),
              theme.colorScheme.surface,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_graph,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  loc.progressMonthlyReport(monthName.toUpperCase()),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ProgressMiniStat(
                  icon: Icons.fitness_center,
                  label: loc.progressWorkouts,
                  value: '$wc',
                  color: theme.colorScheme.primary,
                  delta: deltaW,
                  theme: theme,
                ),
                const SizedBox(width: 8),
                ProgressMiniStat(
                  icon: Icons.auto_graph,
                  label: loc.commonVolume,
                  value: formatVolume(vol),
                  color: Colors.teal,
                  delta: deltaV.toInt(),
                  theme: theme,
                ),
                const SizedBox(width: 8),
                ProgressMiniStat(
                  icon: Icons.repeat,
                  label: loc.progressSets,
                  value: '$sets',
                  color: theme.colorScheme.secondary,
                  theme: theme,
                ),
                const SizedBox(width: 8),
                ProgressMiniStat(
                  icon: Icons.calendar_view_day,
                  label: loc.progressDays,
                  value: '$days',
                  color: Colors.blue,
                  theme: theme,
                ),
              ],
            ),
            if (avgFeeling != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.star, size: 14, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    loc.progressAverageFeeling(avgFeeling.toStringAsFixed(1)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (deltaW != 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: deltaW > 0
                            ? Colors.green.withAlpha(25)
                            : Colors.red.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            deltaW > 0
                                ? Icons.trending_up
                                : Icons.trending_down,
                            size: 14,
                            color: deltaW > 0 ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            loc.progressVsLastMonth(
                              '${deltaW > 0 ? '+' : ''}$deltaW',
                            ),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: deltaW > 0 ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
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
