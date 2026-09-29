import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/services/strength_today_service.dart';
import 'package:workout_notes/widgets/ui/ui.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_format.dart';

/// "Today" card at the top of the gym hub: the routine day to train (with a
/// one-tap start), the workout already done, a rest day of the plan, or a
/// nudge to create a routine.
class StrengthTodayCard extends StatelessWidget {
  final StrengthTodayInfo info;
  final ValueChanged<StrengthRoutineDayInfo> onStartDay;
  final VoidCallback onBlankWorkout;
  final VoidCallback onOpenRoutines;
  final ValueChanged<String> onOpenWorkout;

  const StrengthTodayCard({
    super.key,
    required this.info,
    required this.onStartDay,
    required this.onBlankWorkout,
    required this.onOpenRoutines,
    required this.onOpenWorkout,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return AppSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTodayHeader(title: loc.strengthHomeTodayTitle),
          const SizedBox(height: 14),
          switch (info.status) {
            StrengthTodayStatus.planned => StrengthDayDetails(
              day: info.day!,
              caption: info.fromPlan
                  ? loc.strengthHomeTodayFromPlan
                  : loc.strengthHomeTodayFromRoutine,
              actionKey: const Key('strength-today-start'),
              actionLabel: loc.strengthHomeTodayStart,
              onAction: () => onStartDay(info.day!),
            ),
            StrengthTodayStatus.done => _Done(
              info: info,
              onOpenWorkout: onOpenWorkout,
              onStartNext: onStartDay,
            ),
            StrengthTodayStatus.rest => _Rest(
              info: info,
              onStartDay: onStartDay,
              onBlankWorkout: onBlankWorkout,
            ),
            StrengthTodayStatus.none => _NoRoutine(
              onOpenRoutines: onOpenRoutines,
              onBlankWorkout: onBlankWorkout,
            ),
          },
        ],
      ),
    );
  }
}

/// Day name, routine, exercise count, muscle chips and estimated time, with
/// an optional primary action.
class StrengthDayDetails extends StatelessWidget {
  final StrengthRoutineDayInfo day;
  final String? caption;
  final Key? actionKey;
  final String? actionLabel;
  final VoidCallback? onAction;

  const StrengthDayDetails({
    super.key,
    required this.day,
    this.caption,
    this.actionKey,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = day.dayName.trim().isNotEmpty ? day.dayName : day.routineName;
    final facts = <String>[
      if (day.dayName.trim().isNotEmpty && day.routineName.trim().isNotEmpty)
        day.routineName,
      loc.strengthHomeExercisesCount(day.exerciseCount),
      if (day.estimatedSeconds > 0)
        '~${StrengthHomeFormat.duration(day.estimatedSeconds)}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const AppIconBadge(Icons.fitness_center, size: 48, iconSize: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    facts.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (day.categories.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final category in day.categories.take(6))
                AppPill(
                  label: StrengthHomeFormat.categoryName(loc, category),
                  color: Color(category.color),
                ),
            ],
          ),
        ],
        if (onAction != null && actionLabel != null) ...[
          const SizedBox(height: 14),
          Divider(height: 1, color: AppUi.divider(colors)),
          const SizedBox(height: 12),
          AppTodayFooter(
            caption: caption,
            actionKey: actionKey,
            actionLabel: actionLabel!,
            onAction: onAction!,
          ),
        ] else if (caption != null) ...[
          const SizedBox(height: 8),
          Text(
            caption!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _Done extends StatelessWidget {
  final StrengthTodayInfo info;
  final ValueChanged<String> onOpenWorkout;
  final ValueChanged<StrengthRoutineDayInfo> onStartNext;

  const _Done({
    required this.info,
    required this.onOpenWorkout,
    required this.onStartNext,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final workout = info.doneWorkout!;
    final next = info.next;
    final name = workout.routineLabel ?? loc.strengthHomeFreeWorkout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppIconBadge(
              Icons.check_circle_rounded,
              color: colors.primary,
              size: 44,
              iconSize: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                loc.strengthHomeTodayDoneTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Material(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppUi.tileRadius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('strength-today-done-workout'),
            onTap: () => onOpenWorkout(workout.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            StrengthHomeFormat.volume(workout.volumeKg),
                            loc.strengthHomeSetsCount(workout.workingSets),
                            if (workout.durationSeconds > 0)
                              StrengthHomeFormat.duration(
                                workout.durationSeconds,
                              ),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (next != null) ...[
          const SizedBox(height: 12),
          _NextLine(
            label: loc.strengthHomeTodayNextUp,
            day: next,
            onTap: () => onStartNext(next),
          ),
        ],
      ],
    );
  }
}

class _NextLine extends StatelessWidget {
  final String label;
  final StrengthRoutineDayInfo day;
  final VoidCallback? onTap;

  const _NextLine({required this.label, required this.day, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final title = day.dayName.trim().isNotEmpty ? day.dayName : day.routineName;
    return Row(
      children: [
        Icon(Icons.arrow_forward_rounded, size: 16, color: colors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label: $title',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _Rest extends StatelessWidget {
  final StrengthTodayInfo info;
  final ValueChanged<StrengthRoutineDayInfo> onStartDay;
  final VoidCallback onBlankWorkout;

  const _Rest({
    required this.info,
    required this.onStartDay,
    required this.onBlankWorkout,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final next = info.next;
    final nextDate = info.nextDate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            AppIconBadge(
              Icons.self_improvement_rounded,
              color: colors.tertiary,
              size: 44,
              iconSize: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.strengthHomeTodayRestTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    loc.strengthHomeTodayRestSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (next != null) ...[
          const SizedBox(height: 12),
          _NextLine(
            label: nextDate == null
                ? loc.strengthHomeTodayNextUp
                : loc.strengthHomeTodayNextOn(
                    StrengthHomeFormat.dayLabel(context, nextDate),
                  ),
            day: next,
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const Key('strength-today-train-anyway'),
            onPressed: next == null ? onBlankWorkout : () => onStartDay(next),
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(loc.strengthHomeTodayTrainAnyway),
          ),
        ),
      ],
    );
  }
}

class _NoRoutine extends StatelessWidget {
  final VoidCallback onOpenRoutines;
  final VoidCallback onBlankWorkout;

  const _NoRoutine({
    required this.onOpenRoutines,
    required this.onBlankWorkout,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const AppIconBadge(
              Icons.event_note_outlined,
              size: 44,
              iconSize: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.strengthHomeTodayNoneTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    loc.strengthHomeTodayNoneSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const Key('strength-today-create-routine'),
          onPressed: onOpenRoutines,
          icon: const Icon(Icons.add_rounded),
          label: Text(loc.strengthHomeCreateRoutine),
        ),
        const SizedBox(height: 6),
        TextButton(
          key: const Key('strength-today-blank'),
          onPressed: onBlankWorkout,
          child: Text(loc.strengthHomeBlankWorkout),
        ),
      ],
    );
  }
}
