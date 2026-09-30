import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_week_analytics.dart';
import 'package:workout_notes/widgets/ui/ui.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_format.dart';

/// Headline numbers of the selected period: volume with its trend against the
/// previous period, and workouts, sets, total time and average duration.
class StrengthPeriodHero extends StatelessWidget {
  final StrengthWeekAnalytics analytics;

  const StrengthPeriodHero({super.key, required this.analytics});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final totals = analytics.totals;
    final ratio = analytics.volumeRatioVsPreviousPeriod;
    final start = analytics.periodStart;
    final range = start == null
        ? null
        : '${DateFormat.MMMd(locale).format(start)} – '
              '${DateFormat.MMMd(locale).format(analytics.now)}';
    final volume = StrengthVolumeValue.of(totals.volumeKg);

    return AppHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconBadge(Icons.fitness_center),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  range ?? loc.runStatsPeriodAll,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: AppValueUnit(
                    value: RunFormatters.decimal(volume.value, volume.digits),
                    unit: volume.unit,
                    valueStyle: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1.0,
                    ),
                    unitStyle: theme.textTheme.titleMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (ratio != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: AppPill.trend(
                    context: context,
                    label:
                        '${ratio >= 0 ? '+' : '-'}'
                        '${(ratio.abs() * 100).round()}%',
                    positive: ratio >= 0,
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              analytics.hasPreviousPeriod
                  ? '${loc.strengthHomeStatVolume} · ${loc.runStatsVsPrevious}'
                  : loc.strengthHomeStatVolume,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: AppUi.divider(colors)),
          const SizedBox(height: 12),
          AppStatRow(
            children: [
              AppStatTile(
                icon: Icons.flag_outlined,
                color: colors.primary,
                label: loc.strengthHomeStatWorkouts,
                value: '${totals.sessions}',
              ),
              AppStatTile(
                icon: Icons.layers_outlined,
                color: colors.tertiary,
                label: loc.strengthHomeStatSets,
                value: '${totals.workingSets}',
              ),
              AppStatTile(
                icon: Icons.timer_outlined,
                color: colors.secondary,
                label: loc.strengthHomeStatTime,
                value: StrengthHomeFormat.duration(totals.durationSeconds),
              ),
              AppStatTile(
                icon: Icons.hourglass_bottom_rounded,
                color: colors.secondary,
                label: loc.strengthHomeStatAvgDurationShort,
                value: totals.sessions == 0
                    ? '--'
                    : StrengthHomeFormat.duration(totals.avgDurationSeconds),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            [
              loc.strengthHomeWorkoutsPerWeekValue(
                RunFormatters.decimal(analytics.avgWeeklySessions, 1),
              ),
              loc.strengthHomeVolumePerWeekValue(
                StrengthHomeFormat.volume(
                  analytics.periodWeekCount <= 0
                      ? 0
                      : totals.volumeKg / analytics.periodWeekCount,
                ),
              ),
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
