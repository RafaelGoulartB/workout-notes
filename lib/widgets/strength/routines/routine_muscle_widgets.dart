import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/utils/strength_routine_summary.dart';
import 'package:workout_notes/widgets/category_timeline_bar.dart';
import 'package:workout_notes/widgets/run/insights/run_insight_card.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Stacked bar with the share of working sets of each muscle group.
class RoutineMuscleBar extends StatelessWidget {
  final List<RoutineMuscleSets> muscles;
  final double height;

  const RoutineMuscleBar({super.key, required this.muscles, this.height = 6});

  @override
  Widget build(BuildContext context) => CategoryTimelineBar(
    height: height,
    segments: [for (final m in muscles) (color: Color(m.color), value: m.sets)],
  );
}

/// Compact chips ("dot + muscle") for the muscles a day or routine trains.
/// Shows at most [max] and folds the rest into a "+n" chip.
class RoutineMuscleChips extends StatelessWidget {
  final List<RoutineMuscleSets> muscles;
  final int max;
  final bool showSets;

  const RoutineMuscleChips({
    super.key,
    required this.muscles,
    this.max = 4,
    this.showSets = false,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final visible = muscles.take(max).toList();
    final hidden = muscles.length - visible.length;
    final muted = theme.colorScheme.onSurfaceVariant;
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final m in visible)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Color(m.color),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                showSets
                    ? '${ExerciseLocaleHelper.categoryName(loc, m.categoryRow)} ${m.sets}'
                    : ExerciseLocaleHelper.categoryName(loc, m.categoryRow),
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
            ],
          ),
        if (hidden > 0)
          Text(
            loc.routineDayMoreMuscles(hidden),
            style: theme.textTheme.labelSmall?.copyWith(
              color: muted,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}

/// Small icon + text pair used in routine and day summaries.
class RoutineInfoItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const RoutineInfoItem({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: muted),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

/// "Muscles per week": sets per muscle group against the recommended
/// 10-20 range, explained in the info sheet.
class RoutineWeeklyMusclesCard extends StatelessWidget {
  final List<RoutineMuscleSets> muscles;

  const RoutineWeeklyMusclesCard({super.key, required this.muscles});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scale = _scaleFor(muscles);
    return RunInsightCard(
      icon: Icons.accessibility_new_rounded,
      title: loc.routineMusclesTitle,
      subtitle: loc.routineMusclesSubtitle,
      info: loc.routineMusclesInfo,
      child: muscles.isEmpty
          ? RunInsightsNote(loc.routineMusclesEmpty)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in muscles)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _MuscleWeekRow(muscle: m, scale: scale),
                  ),
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 10,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withAlpha(45),
                        border: Border.all(
                          color: theme.colorScheme.primary.withAlpha(140),
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        loc.routineMusclesRecommended(
                          kRecommendedWeeklySetsMin,
                          kRecommendedWeeklySetsMax,
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  /// Bars share one scale so they are comparable; the recommended band always
  /// fits with some headroom.
  static double _scaleFor(List<RoutineMuscleSets> muscles) {
    final maxSets = muscles.fold<int>(0, (m, e) => e.sets > m ? e.sets : m);
    final base = kRecommendedWeeklySetsMax * 1.25;
    return (maxSets > base ? maxSets * 1.05 : base).toDouble();
  }
}

class _MuscleWeekRow extends StatelessWidget {
  final RoutineMuscleSets muscle;
  final double scale;

  const _MuscleWeekRow({required this.muscle, required this.scale});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final level = StrengthRoutineSummaryBuilder.levelFor(muscle.sets);
    final (levelLabel, levelColor) = switch (level) {
      WeeklySetsLevel.low => (loc.routineMusclesLow, scheme.tertiary),
      WeeklySetsLevel.inRange => (loc.routineMusclesInRange, scheme.primary),
      WeeklySetsLevel.high => (loc.routineMusclesHigh, scheme.error),
    };
    final color = Color(muscle.color);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                ExerciseLocaleHelper.categoryName(loc, muscle.categoryRow),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              levelLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: levelColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              loc.routinesSetsValue(muscle.sets),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: RunUi.tabular,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final bandLeft = width * kRecommendedWeeklySetsMin / scale;
            final bandRight = width * kRecommendedWeeklySetsMax / scale;
            final fill = (width * muscle.sets / scale).clamp(0.0, width);
            return SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withAlpha(140),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                  Positioned(
                    left: bandLeft,
                    width: bandRight - bandLeft,
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary.withAlpha(40),
                        border: Border.symmetric(
                          vertical: BorderSide(
                            color: scheme.primary.withAlpha(140),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 2,
                    bottom: 2,
                    width: fill,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
