import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/strength_routine_format.dart';
import 'package:workout_notes/utils/strength_routine_summary.dart';
import 'package:workout_notes/utils/workout_estimator.dart';
import 'package:workout_notes/widgets/strength/routines/routine_muscle_widgets.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Hero of the routine screen: description and the numbers that size the
/// routine (days, weekly sets, session time, volume) plus its muscle split.
class RoutineHero extends StatelessWidget {
  final RoutineSummary routine;

  const RoutineHero({super.key, required this.routine});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final muted = theme.colorScheme.onSurfaceVariant;
    final notes = routine.notes?.trim() ?? '';
    final duration = WorkoutEstimateCalculator.formatDuration(
      routine.averageSessionSeconds,
    );
    final volume = routine.weeklyVolumeKg;

    return AppHeroCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notes.isNotEmpty) ...[
            Text(
              notes,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 14),
          ],
          AppStatRow(
            children: [
              AppStatTile(
                icon: Icons.calendar_view_week_rounded,
                label: loc.routineStatDays,
                value: '${routine.dayCount}',
              ),
              AppStatTile(
                icon: Icons.stacked_bar_chart_rounded,
                label: loc.routineStatWeeklySets,
                value: '${routine.weeklySets}',
              ),
              AppStatTile(
                icon: Icons.timer_outlined,
                label: loc.routineStatSession,
                value: duration ?? '--',
              ),
              if (volume > 0)
                AppStatTile(
                  icon: Icons.scale_rounded,
                  label: loc.routineStatVolume,
                  value: StrengthRoutineFormat.volume(volume),
                  unit: 'kg',
                ),
            ],
          ),
          if (routine.muscles.isNotEmpty) ...[
            const SizedBox(height: 14),
            RoutineMuscleBar(muscles: routine.muscles, height: 8),
            const SizedBox(height: 8),
            RoutineMuscleChips(muscles: routine.muscles, max: 6),
          ],
        ],
      ),
    );
  }
}

/// A training day of the routine: name, sizing, muscles and a start button.
class RoutineDayCard extends StatelessWidget {
  final RoutineDaySummary day;
  final int index;
  final bool isNext;
  final VoidCallback onOpen;
  final VoidCallback onStart;

  const RoutineDayCard({
    super.key,
    required this.day,
    required this.index,
    required this.onOpen,
    required this.onStart,
    this.isNext = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    final duration = WorkoutEstimateCalculator.formatDuration(
      day.estimatedSeconds,
    );
    final name = day.name.isEmpty
        ? loc.routineDayDefaultName(index + 1)
        : day.name;

    return AppSectionCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${index + 1}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
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
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isNext) ...[
                      const SizedBox(width: 6),
                      AppPill(label: loc.routinesNextBadge),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                if (day.exerciseCount == 0)
                  Text(
                    loc.routineDayNoExercises,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                else ...[
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    children: [
                      RoutineInfoItem(
                        icon: Icons.fitness_center_rounded,
                        text: loc.routinesExercisesValue(day.exerciseCount),
                      ),
                      RoutineInfoItem(
                        icon: Icons.stacked_bar_chart_rounded,
                        text: loc.routinesSetsValue(day.workingSets),
                      ),
                      if (duration != null)
                        RoutineInfoItem(
                          icon: Icons.timer_outlined,
                          text: duration,
                        ),
                    ],
                  ),
                  if (day.muscles.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    RoutineMuscleChips(muscles: day.muscles, max: 3),
                  ],
                ],
              ],
            ),
          ),
          IconButton.filledTonal(
            tooltip: loc.routinesStartDay,
            onPressed: day.exerciseCount == 0 ? null : onStart,
            icon: const Icon(Icons.play_arrow_rounded),
          ),
        ],
      ),
    );
  }
}
