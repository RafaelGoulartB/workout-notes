import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/strength_history_repository.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_workout_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Month section header: month name on the left, totals on the right.
class StrengthHistoryMonthHeader extends StatelessWidget {
  final DateTime month;
  final StrengthHistoryTotals? totals;

  const StrengthHistoryMonthHeader({
    super.key,
    required this.month,
    this.totals,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final label = DateFormat.yMMMM(locale).format(month);
    final totals = this.totals;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              toBeginningOfSentenceCase(label, locale) ?? label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          if (totals != null)
            Text(
              loc.strengthHistoryMonthTotals(
                totals.count,
                StrengthWorkoutFormat.volume(totals.volume),
              ),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: AppUi.tabular,
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact workout row: routine day, date, duration, volume, muscle chips,
/// feeling and record badge.
class StrengthHistoryRow extends StatelessWidget {
  final StrengthHistoryWorkout workout;
  final VoidCallback onTap;

  const StrengthHistoryRow({
    super.key,
    required this.workout,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();

    final started = workout.startedAt;
    final datePart = DateFormat('EEE, d MMM', locale).format(workout.day);
    final caption = [
      started == null
          ? datePart
          : '$datePart · ${DateFormat('HH:mm', locale).format(started)}',
      if (workout.durationSeconds > 0)
        RunFormatters.durationHoursMinutes(workout.durationSeconds),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppUi.tileRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppIconBadge(
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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          workout.title ??
                              _muscleLabel(loc, workout) ??
                              loc.strengthHistoryFreeWorkout,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (workout.recordCount > 0) ...[
                        const SizedBox(width: 8),
                        _RecordBadge(count: workout.recordCount),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (workout.muscles.isNotEmpty ||
                      workout.feelingRating > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: _MuscleChips(muscles: workout.muscles)),
                        if (workout.feelingRating > 0)
                          _FeelingStars(rating: workout.feelingRating),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  StrengthWorkoutFormat.volume(workout.volume),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: AppUi.tabular,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  loc.strengthHistorySets(workout.workingSets),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: AppUi.tabular,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordBadge extends StatelessWidget {
  final int count;

  const _RecordBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final tint = Theme.of(context).colorScheme.tertiary;
    return Semantics(
      label: loc.strengthHistoryRecordsBadge(count),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.emoji_events_rounded, size: 15, color: tint),
          if (count > 1) ...[
            const SizedBox(width: 2),
            Text(
              '$count',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: tint,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Up to three muscle groups as dot + name, `+N` for the rest.
class _MuscleChips extends StatelessWidget {
  final List<StrengthMuscleShare> muscles;

  const _MuscleChips({required this.muscles});

  static const _maxChips = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final shown = muscles.take(_maxChips).toList();
    final extra = muscles.length - shown.length;
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        for (final muscle in shown)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: muscle.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                ExerciseLocaleHelper.categoryName(loc, muscle.categoryRow),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        if (extra > 0)
          Text(
            '+$extra',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

class _FeelingStars extends StatelessWidget {
  final int rating;

  const _FeelingStars({required this.rating});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 13,
            color: i <= rating ? colors.tertiary : colors.outlineVariant,
          ),
      ],
    );
  }
}

/// "Costas · Bíceps" for workouts without a routine day: the two muscle
/// groups with the most working sets.
String? _muscleLabel(AppLocalizations loc, StrengthHistoryWorkout workout) {
  if (workout.muscles.isEmpty) return null;
  final sorted = [...workout.muscles]
    ..sort((a, b) => b.workingSets.compareTo(a.workingSets));
  return sorted
      .take(2)
      .map(
        (m) => ExerciseLocaleHelper.categoryName(loc, {
          'name': m.name,
          'locale_key': m.localeKey,
          'category_id': m.categoryId,
        }),
      )
      .join(' · ');
}
