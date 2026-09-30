import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/models/sleep_night_summary.dart';
import 'package:workout_notes/widgets/ui/ui.dart';
import 'package:workout_notes/widgets/sleep/sleep_ui.dart';

/// One night in the sleep history: date badge, duration, time window, the
/// stage split when measured, and efficiency on the right.
class SleepHistoryRow extends StatelessWidget {
  final SleepEntry entry;
  final SleepNightSummary? summary;
  final int goalMinutes;
  final VoidCallback onTap;

  const SleepHistoryRow({
    super.key,
    required this.entry,
    required this.goalMinutes,
    required this.onTap,
    this.summary,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final slept = entry.effectiveSleepMinutes;
    final window = SleepUi.window(entry.bedtimeMinutes, entry.wakeTimeMinutes);
    final subtitle = [
      ?window,
      if (entry.timeInBedMinutes != null)
        '${loc.sleepInBedShort} ${SleepUi.duration(loc, entry.timeInBedMinutes)}',
    ].join(' · ');
    final session = summary?.session;
    final efficiency = entry.efficiency;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            SleepDateBadge(date: entry.date),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        SleepUi.duration(loc, slept),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontFeatures: AppUi.tabular,
                        ),
                      ),
                      if (slept >= goalMinutes) ...[
                        const SizedBox(width: 6),
                        Icon(
                          Icons.check_circle_rounded,
                          size: 15,
                          color: colors.primary,
                        ),
                      ],
                    ],
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: AppUi.tabular,
                      ),
                    ),
                  if ((summary?.hasStages ?? false) && session != null) ...[
                    const SizedBox(height: 6),
                    SleepStageBar(session: session, height: 5),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (efficiency != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${efficiency.round()}%',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: SleepUi.efficiencyColor(colors, efficiency),
                      fontFeatures: AppUi.tabular,
                    ),
                  ),
                  Text(
                    loc.sleepEfficiencyShort,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
