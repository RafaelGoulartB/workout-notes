import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';

class SleepWeeklySummaryCard extends StatelessWidget {
  final SleepDashboardStats stats;
  final DateTime start;
  final DateTime end;

  const SleepWeeklySummaryCard({
    super.key,
    required this.stats,
    required this.start,
    required this.end,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final metrics = [
      (
        Icons.bedtime_outlined,
        loc.sleepAverageSleep,
        _formatMinutes(stats.average7Days?.round(), loc),
        null,
      ),
      (
        Icons.event_repeat_rounded,
        loc.sleepRegularity,
        stats.regularity7Days == null
            ? '--'
            : '${stats.regularity7Days!.round()}%',
        loc.sleepRegularityInfo,
      ),
      (
        Icons.speed_rounded,
        loc.sleepEfficiency,
        stats.efficiency7Days == null
            ? '--'
            : '${stats.efficiency7Days!.round()}%',
        null,
      ),
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    loc.sleepWeeklySummary,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Icon(Icons.calendar_view_week_rounded, color: colors.primary),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              _formatRange(start, end),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            Divider(height: 1, color: colors.outlineVariant),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var index = 0; index < metrics.length; index++) ...[
                  if (index > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetric(
                      context,
                      icon: metrics[index].$1,
                      label: metrics[index].$2,
                      value: metrics[index].$3,
                      tooltip: metrics[index].$4,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withAlpha(150),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                loc.sleepNightsRecorded(stats.recordedDays7Days, 7),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetric(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String? tooltip,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final content = Column(
      children: [
        Icon(icon, color: colors.primary, size: 22),
        const SizedBox(height: 8),
        Text(
          value,
          maxLines: 1,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.15,
          ),
        ),
      ],
    );
    if (tooltip == null) return content;
    return Tooltip(
      message: tooltip,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 5),
      child: Semantics(hint: tooltip, button: true, child: content),
    );
  }

  static String _formatRange(DateTime start, DateTime end) {
    final startText = DateFormat.MMMd(Intl.defaultLocale).format(start);
    final endText = DateFormat.yMMMd(Intl.defaultLocale).format(end);
    return '$startText - $endText';
  }

  static String _formatMinutes(int? minutes, AppLocalizations loc) {
    if (minutes == null) return '--';
    return loc.sleepDurationValue(minutes ~/ 60, minutes % 60);
  }
}
