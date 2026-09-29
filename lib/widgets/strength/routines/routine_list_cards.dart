import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/strength_routine_format.dart';
import 'package:workout_notes/utils/strength_routine_summary.dart';
import 'package:workout_notes/utils/workout_estimator.dart';
import 'package:workout_notes/widgets/ui/ui.dart';
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

/// "3 dias · 17 exercícios · 26 séries/semana · 28 min".
String _metaLine(AppLocalizations loc, RoutineSummary routine) => [
  loc.routinesDaysValue(routine.dayCount),
  loc.routinesExercisesValue(routine.exerciseCount),
  loc.routinesSetsPerWeekValue(routine.weeklySets),
  ?WorkoutEstimateCalculator.formatDuration(routine.averageSessionSeconds),
].join(' · ');

/// Other routines of the library, listed in one card.
class RoutineLibraryList extends StatelessWidget {
  final List<RoutineSummary> routines;
  final RoutineCardActions Function(RoutineSummary routine) actionsFor;

  const RoutineLibraryList({
    super.key,
    required this.routines,
    required this.actionsFor,
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
      child: AppDividedList(
        children: [
          for (final routine in routines)
            RoutineLibraryRow(routine: routine, actions: actionsFor(routine)),
        ],
      ),
    );
  }
}

/// A routine of the library: name, one line of notes, key numbers, muscle
/// split and when it was last trained.
class RoutineLibraryRow extends StatelessWidget {
  final RoutineSummary routine;
  final RoutineCardActions actions;

  const RoutineLibraryRow({
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

    return InkWell(
      onTap: actions.onOpen,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 0, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    routine.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (notes.isNotEmpty)
                    Text(
                      notes,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _metaLine(loc, routine),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (routine.muscles.isNotEmpty)
                        RoutineMuscleChips(muscles: routine.muscles, max: 3),
                      Text(
                        _lastTrainedText(loc, routine.lastTrainedAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            RoutineCardMenu(actions: actions),
          ],
        ),
      ),
    );
  }
}

/// The routine being followed, pinned on top: one summary line, the muscle
/// split and every day as a compact row with its own start button (the next
/// day stands out).
class RoutineInUseCard extends StatelessWidget {
  final RoutineSummary routine;
  final RoutineCardActions actions;

  /// Day the periodization plan expects next, when it links this routine.
  final String? nextDayId;
  final void Function(RoutineDaySummary day) onStartDay;
  final void Function(RoutineDaySummary day) onOpenDay;

  const RoutineInUseCard({
    super.key,
    required this.routine,
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

    return AppSectionCard(
      onTap: actions.onOpen,
      padding: const EdgeInsets.fromLTRB(16, 10, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      routine.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _metaLine(loc, routine),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      _lastTrainedText(loc, routine.lastTrainedAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              RoutineCardMenu(actions: actions),
            ],
          ),
          if (routine.muscles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: RoutineMuscleChips(muscles: routine.muscles, max: 5),
            ),
          ],
          if (routine.days.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Divider(height: 1, color: AppUi.divider(scheme)),
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
        padding: const EdgeInsets.fromLTRB(0, 6, 12, 6),
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
                        AppPill(label: loc.routinesNextBadge),
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
            if (isNext)
              IconButton.filled(
                tooltip: loc.routinesStartDay,
                visualDensity: VisualDensity.compact,
                onPressed: day.exerciseCount == 0 ? null : onStart,
                icon: const Icon(Icons.play_arrow_rounded),
              )
            else
              IconButton.filledTonal(
                tooltip: loc.routinesStartDay,
                visualDensity: VisualDensity.compact,
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
      width: 4,
      height: 30,
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
