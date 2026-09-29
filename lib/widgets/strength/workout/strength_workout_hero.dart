import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/strength_history_repository.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_workout_format.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Headline of a workout: routine day, date and time, the three key numbers,
/// feeling / RPE / density chips and the notes.
class StrengthWorkoutHero extends StatelessWidget {
  final StrengthWorkoutDetail detail;

  const StrengthWorkoutHero({super.key, required this.detail});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final workout = detail.workout;
    final stats = detail.stats;

    final start = DateTime.tryParse(workout['start_time'] as String? ?? '');
    final end = DateTime.tryParse(workout['end_time'] as String? ?? '');
    final day =
        DateTime.tryParse(workout['date'] as String? ?? '') ??
        start ??
        DateTime.now();
    final isActive = end == null;
    final clock = DateFormat('HH:mm', locale);
    final date = DateFormat.yMMMMEEEEd(locale).format(day);
    final dateLine = [
      toBeginningOfSentenceCase(date, locale),
      if (start != null && end != null)
        '${clock.format(start)} – ${clock.format(end)}'
      else if (start != null)
        clock.format(start),
    ].join(' · ');

    final title = detail.title ?? loc.strengthHistoryFreeWorkout;
    final routine = detail.routineName?.trim();
    final subtitle =
        routine != null &&
            routine.isNotEmpty &&
            detail.dayName?.trim().isNotEmpty == true &&
            routine != title
        ? routine
        : null;

    final duration = (workout['duration_seconds'] as num?)?.toInt() ?? 0;
    final feeling = (workout['feeling_rating'] as num?)?.toInt() ?? 0;
    final comment = (workout['comment'] as String?)?.trim();
    final density = stats?.densityKgPerMinute;
    final calories = stats?.estimatedCalories;
    final avgRpe = stats?.averageRpe;

    final chips = <Widget>[
      if (isActive)
        RunPill(
          label: loc.workoutHomeOngoing,
          icon: Icons.play_circle_outline_rounded,
          color: colors.primary,
        ),
      if (feeling > 0)
        RunPill(
          label: '${loc.workoutDetailFeeling} $feeling/5',
          icon: Icons.star_rounded,
          color: colors.tertiary,
        ),
      if (avgRpe != null)
        RunPill(
          label:
              '${loc.workoutStatsAverageRpe} ${RunFormatters.decimal(avgRpe, 1)}',
          icon: Icons.speed_rounded,
          color: colors.secondary,
        ),
      if (density != null)
        RunPill(
          label:
              '${loc.workoutStatsDensity} ${RunFormatters.decimal(density, density >= 10 ? 0 : 1)} ${loc.workoutStatsKgPerMin}',
          icon: Icons.bolt_rounded,
          color: colors.secondary,
        ),
      if (calories != null && calories > 0)
        RunPill(
          label: '${calories.round()} kcal',
          icon: Icons.local_fire_department_rounded,
          color: colors.secondary,
        ),
    ];

    return RunHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RunIconBadge(
                Icons.fitness_center_rounded,
                size: 44,
                iconSize: 22,
                color: colors.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      dateLine,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RunStatRow(
            children: [
              RunStatTile(
                icon: Icons.schedule_rounded,
                label: loc.activeWorkoutTimerDuration,
                value: duration > 0
                    ? RunFormatters.durationHoursMinutes(duration)
                    : '--',
              ),
              RunStatTile(
                icon: Icons.monitor_weight_outlined,
                label: loc.commonVolume,
                value: StrengthWorkoutFormat.volume(stats?.totalVolume ?? 0),
              ),
              RunStatTile(
                icon: Icons.repeat_rounded,
                label: loc.workoutDetailWorkingSets,
                value: '${stats?.completedSets ?? 0}',
                unit: stats == null || stats.totalSets == stats.completedSets
                    ? null
                    : '/${stats.totalSets}',
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withAlpha(110),
                borderRadius: BorderRadius.circular(RunUi.tileRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.workoutDetailNotes,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(comment, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
