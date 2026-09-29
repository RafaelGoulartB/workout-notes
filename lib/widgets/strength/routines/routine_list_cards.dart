import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/strength_routine_format.dart';
import 'package:workout_notes/utils/strength_routine_summary.dart';
import 'package:workout_notes/utils/workout_estimator.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/strength/routines/routine_muscle_widgets.dart';

/// Callbacks shared by every routine card of the library.
class RoutineCardActions {
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

  const RoutineCardActions({
    required this.onOpen,
    required this.onDuplicate,
    required this.onDelete,
  });
}

/// Why a routine is highlighted as "in use".
enum RoutineInUseReason { planned, recent }

String _sessionText(AppLocalizations loc, RoutineSummary routine) {
  final duration = WorkoutEstimateCalculator.formatDuration(
    routine.averageSessionSeconds,
  );
  return duration == null ? '' : loc.routinesSessionValue(duration);
}

String _lastTrainedText(AppLocalizations loc, DateTime? date) => date == null
    ? loc.routinesNeverTrained
    : loc.routinesLastTrained(StrengthRoutineFormat.shortDate(date));

class RoutineCardMenu extends StatelessWidget {
  final RoutineCardActions actions;

  const RoutineCardMenu({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      tooltip: loc.commonMoreOptions,
      onSelected: (value) => switch (value) {
        'edit' => actions.onOpen(),
        'duplicate' => actions.onDuplicate(),
        'delete' => actions.onDelete(),
        _ => null,
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(value: 'edit', child: Text(loc.commonEdit)),
        PopupMenuItem(value: 'duplicate', child: Text(loc.routinesDuplicate)),
        PopupMenuItem(
          value: 'delete',
          child: Text(
            loc.commonDelete,
            style: TextStyle(color: Theme.of(ctx).colorScheme.error),
          ),
        ),
      ],
    );
  }
}

/// A routine of the library: name, description, key numbers, muscle split and
/// when it was last trained.
class RoutineLibraryCard extends StatelessWidget {
  final RoutineSummary routine;
  final RoutineCardActions actions;

  const RoutineLibraryCard({
    super.key,
    required this.routine,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final muted = theme.colorScheme.onSurfaceVariant;
    final notes = routine.notes?.trim() ?? '';
    final session = _sessionText(loc, routine);

    return RunSectionCard(
      onTap: actions.onOpen,
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  routine.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              RoutineCardMenu(actions: actions),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (notes.isNotEmpty) ...[
                  Text(
                    notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    RoutineInfoItem(
                      icon: Icons.calendar_view_week_rounded,
                      text: loc.routinesDaysValue(routine.dayCount),
                    ),
                    RoutineInfoItem(
                      icon: Icons.fitness_center_rounded,
                      text: loc.routinesExercisesValue(routine.exerciseCount),
                    ),
                    RoutineInfoItem(
                      icon: Icons.stacked_bar_chart_rounded,
                      text: loc.routinesSetsPerWeekValue(routine.weeklySets),
                    ),
                    if (session.isNotEmpty)
                      RoutineInfoItem(
                        icon: Icons.timer_outlined,
                        text: session,
                      ),
                  ],
                ),
                if (routine.muscles.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  RoutineMuscleBar(muscles: routine.muscles),
                  const SizedBox(height: 6),
                  RoutineMuscleChips(muscles: routine.muscles, max: 4),
                ],
                const SizedBox(height: 8),
                Text(
                  _lastTrainedText(loc, routine.lastTrainedAt),
                  style: theme.textTheme.labelSmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The routine being followed, pinned on top: key numbers plus every day as a
/// row with its own start button.
class RoutineInUseCard extends StatelessWidget {
  final RoutineSummary routine;
  final RoutineInUseReason reason;
  final RoutineCardActions actions;

  /// Day the periodization plan expects next, when it links this routine.
  final String? nextDayId;
  final void Function(RoutineDaySummary day) onStartDay;
  final void Function(RoutineDaySummary day) onOpenDay;

  const RoutineInUseCard({
    super.key,
    required this.routine,
    required this.reason,
    required this.actions,
    required this.onStartDay,
    required this.onOpenDay,
    this.nextDayId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    final notes = routine.notes?.trim() ?? '';
    final duration = WorkoutEstimateCalculator.formatDuration(
      routine.averageSessionSeconds,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(RunUi.heroRadius),
        onTap: actions.onOpen,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.primary.withAlpha(46),
                scheme.surfaceContainerLow,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(RunUi.heroRadius),
            border: Border.all(color: scheme.primary.withAlpha(90)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  RunPill(
                    icon: Icons.bolt_rounded,
                    label: loc.routinesInUseBadge,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reason == RoutineInUseReason.planned
                          ? loc.routinesInUsePlanned
                          : loc.routinesInUseRecent,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  RoutineCardMenu(actions: actions),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routine.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    RunStatRow(
                      children: [
                        RunStatTile(
                          label: loc.routineStatDays,
                          value: '${routine.dayCount}',
                        ),
                        RunStatTile(
                          label: loc.routineStatExercises,
                          value: '${routine.exerciseCount}',
                        ),
                        RunStatTile(
                          label: loc.routineStatWeeklySets,
                          value: '${routine.weeklySets}',
                        ),
                        RunStatTile(
                          label: loc.routineStatSession,
                          value: duration ?? '--',
                        ),
                      ],
                    ),
                    if (routine.muscles.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      RoutineMuscleBar(muscles: routine.muscles),
                      const SizedBox(height: 6),
                      RoutineMuscleChips(muscles: routine.muscles, max: 5),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _lastTrainedText(loc, routine.lastTrainedAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (routine.days.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Divider(height: 1, color: RunUi.divider(scheme)),
                ),
                for (final day in routine.days)
                  _InUseDayRow(
                    day: day,
                    isNext: day.id == nextDayId,
                    onStart: () => onStartDay(day),
                    onOpen: () => onOpenDay(day),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InUseDayRow extends StatelessWidget {
  final RoutineDaySummary day;
  final bool isNext;
  final VoidCallback onStart;
  final VoidCallback onOpen;

  const _InUseDayRow({
    required this.day,
    required this.isNext,
    required this.onStart,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final muted = theme.colorScheme.onSurfaceVariant;
    final duration = WorkoutEstimateCalculator.formatDuration(
      day.estimatedSeconds,
    );
    final subtitle = day.exerciseCount == 0
        ? loc.routineDayNoExercises
        : [
            loc.routinesExercisesValue(day.exerciseCount),
            loc.routinesSetsValue(day.workingSets),
            ?duration,
          ].join(' · ');

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 8, 4, 8),
        child: Row(
          children: [
            _DayDots(muscles: day.muscles),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          day.name.isEmpty
                              ? loc.routineDayDefaultName(day.orderIndex + 1)
                              : day.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isNext) ...[
                        const SizedBox(width: 6),
                        RunPill(label: loc.routinesNextBadge),
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
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
      ),
    );
  }
}

/// Up to three muscle-coloured dots stacked as a tiny day marker.
class _DayDots extends StatelessWidget {
  final List<RoutineMuscleSets> muscles;

  const _DayDots({required this.muscles});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = [for (final m in muscles.take(3)) Color(m.color)];
    return Container(
      width: 6,
      height: 36,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        color: colors.length == 1
            ? colors.first
            : (colors.isEmpty ? scheme.outlineVariant : null),
        gradient: colors.length > 1
            ? LinearGradient(
                colors: colors,
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : null,
      ),
    );
  }
}
