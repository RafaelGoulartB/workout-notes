import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/services/run_today_service.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// "Today" card at the top of the running home: what the plan expects today
/// (with a one-tap start), what was already run, a rest day, or a nudge to
/// pick a plan.
class RunTodayCard extends StatelessWidget {
  final RunTodayInfo info;
  final VoidCallback onStartSession;
  final VoidCallback onFreeRun;
  final VoidCallback onOpenPlans;
  final ValueChanged<String> onOpenRun;

  const RunTodayCard({
    super.key,
    required this.info,
    required this.onStartSession,
    required this.onFreeRun,
    required this.onOpenPlans,
    required this.onOpenRun,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return RunSoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RunTodayHeader(title: loc.runHomeTodayTitle),
          const SizedBox(height: 14),
          switch (info.status) {
            RunTodayStatus.planned => _Planned(
              info: info,
              onStart: onStartSession,
            ),
            RunTodayStatus.done => _Done(info: info, onOpenRun: onOpenRun),
            RunTodayStatus.rest => _Rest(info: info),
            RunTodayStatus.none => _NoPlan(
              onOpenPlans: onOpenPlans,
              onFreeRun: onFreeRun,
            ),
          },
        ],
      ),
    );
  }
}

/// Distance and duration of a planned session, `8 km · 45 min`.
String _sessionFacts(RunPlanWorkout workout) {
  final distance = workout.plannedDistanceMeters;
  final seconds = workout.plannedDurationSeconds;
  final parts = <String>[
    if (distance > 0) RunPlanUi.distanceLabel(distance),
    if (seconds > 0) RunPlanUi.durationRoughLabel(seconds),
  ];
  return parts.join(' · ');
}

class _Planned extends StatelessWidget {
  final RunTodayInfo info;
  final VoidCallback onStart;

  const _Planned({required this.info, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final session = info.session!;
    final workout = session.workout;
    final tint = RunPlanUi.kindColor(colors, workout.kind);
    final facts = _sessionFacts(workout);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            RunIconBadge(
              RunPlanUi.kindIcon(workout.kind),
              color: tint,
              size: 48,
              iconSize: 26,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    workout.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      RunPlanUi.kindLabel(loc, workout.kind),
                      if (facts.isNotEmpty) facts,
                    ].join(' · '),
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
        Divider(height: 1, color: RunUi.divider(colors)),
        const SizedBox(height: 12),
        RunTodayFooter(
          caption: session.planName == null
              ? null
              : loc.runHomeTodayFromPlan(session.planName!),
          captionIcon: Icons.route_rounded,
          actionKey: const Key('run-today-start'),
          actionLabel: loc.strengthHomeTodayStart,
          onAction: onStart,
        ),
      ],
    );
  }
}

class _Done extends StatelessWidget {
  final RunTodayInfo info;
  final ValueChanged<String> onOpenRun;

  const _Done({required this.info, required this.onOpenRun});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final activity = info.doneActivity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            RunIconBadge(
              Icons.check_circle_rounded,
              color: colors.primary,
              size: 44,
              iconSize: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                info.session != null
                    ? loc.runHomeTodayDoneTitle
                    : loc.runHomeTodayDoneFree,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        if (activity != null) ...[
          const SizedBox(height: 10),
          _DoneRun(activity: activity, onTap: () => onOpenRun(activity.id)),
        ],
        if (info.next != null) ...[
          const SizedBox(height: 10),
          _NextSession(session: info.next!),
        ],
      ],
    );
  }
}

class _DoneRun extends StatelessWidget {
  final RunActivity activity;
  final VoidCallback onTap;

  const _DoneRun({required this.activity, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final seconds = activity.movingTimeSeconds > 0
        ? activity.movingTimeSeconds
        : activity.durationSeconds;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RunUi.tileRadius),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(RunUi.tileRadius),
        ),
        child: Row(
          children: [
            Expanded(
              child: RunValueUnit(
                value: RunFormatters.distanceKm(activity.distanceMeters),
                unit: 'km',
                valueStyle: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              '${RunFormatters.durationHoursMinutes(seconds)} · '
              '${RunFormatters.paceWithUnit(activity.avgPaceSecPerKm)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontFeatures: RunUi.tabular,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: loc.runHomeTodayOpenRun,
              child: Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Rest extends StatelessWidget {
  final RunTodayInfo info;

  const _Rest({required this.info});

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
            RunIconBadge(
              Icons.self_improvement,
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
                    loc.runHomeTodayRestTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    loc.runHomeTodayRestSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (info.next != null) ...[
          const SizedBox(height: 12),
          _NextSession(session: info.next!),
        ],
      ],
    );
  }
}

/// `Next session` row: weekday, name and distance of the following session.
class _NextSession extends StatelessWidget {
  final RunPlannedSession session;

  const _NextSession({required this.session});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final day = DateFormat.EEEE(
      Localizations.localeOf(context).toString(),
    ).format(session.date);
    final dayLabel = toBeginningOfSentenceCase(day);
    final distance = session.workout.plannedDistanceMeters;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(RunUi.tileRadius),
      ),
      child: Row(
        children: [
          Icon(
            RunPlanUi.kindIcon(session.workout.kind),
            size: 18,
            color: RunPlanUi.kindColor(colors, session.workout.kind),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.runHomeTodayNextLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                Text(
                  distance > 0
                      ? loc.runHomeTodayNextValue(
                          dayLabel,
                          session.workout.name,
                          RunPlanUi.distanceLabel(distance),
                        )
                      : loc.runHomeTodayNextValueNoDistance(
                          dayLabel,
                          session.workout.name,
                        ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoPlan extends StatelessWidget {
  final VoidCallback onOpenPlans;
  final VoidCallback onFreeRun;

  const _NoPlan({required this.onOpenPlans, required this.onFreeRun});

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
            const RunIconBadge(Icons.route_outlined, size: 44, iconSize: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.runHomeTodayNoneTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loc.runHomeTodayNoneSubtitle,
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
        Row(
          children: [
            Expanded(
              child: FilledButton(
                key: const Key('run-today-choose-plan'),
                onPressed: onOpenPlans,
                child: Text(loc.runHomeTodayNoneCta),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: onFreeRun,
                child: Text(loc.runHomeTodayFreeRun),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
