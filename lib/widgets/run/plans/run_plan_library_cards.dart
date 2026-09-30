import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/services/run_plan_week_view.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Callbacks shared by every plan card of the library.
class RunPlanCardActions {
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback onToggleArchive;
  final VoidCallback onDelete;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;

  const RunPlanCardActions({
    required this.onOpen,
    required this.onDuplicate,
    required this.onToggleArchive,
    required this.onDelete,
    required this.onActivate,
    required this.onDeactivate,
  });
}

String _subtitle(AppLocalizations loc, RunPlan plan) => [
  RunPlanUi.goalLabel(loc, plan.goalKind),
  loc.runPlanWeeksValue(plan.weeks),
  if (plan.raceDate != null)
    DateFormat('d MMM y', Intl.defaultLocale).format(plan.raceDate!),
].join(' · ');

/// Days from today to the race, or null when the race has passed / is unset.
int? _raceCountdown(DateTime? raceDate, DateTime today) {
  if (raceDate == null) return null;
  final days = DateTime(
    raceDate.year,
    raceDate.month,
    raceDate.day,
  ).difference(dayOf(today)).inDays;
  return days < 0 ? null : days;
}

/// A plan of the library. The one action that matters (follow) is a button;
/// the rest lives in the overflow menu.
class RunPlanLibraryCard extends StatelessWidget {
  final RunPlan plan;
  final RunPlanProgress progress;

  /// Driven by a periodization phase: no activation of its own.
  final bool linkedToPlanning;
  final RunPlanCardActions actions;
  final DateTime today;

  const RunPlanLibraryCard({
    super.key,
    required this.plan,
    required this.progress,
    required this.linkedToPlanning,
    required this.actions,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;

    var total = 0.0;
    for (var week = 0; week < plan.weeks; week++) {
      total += plan.weeklyDistanceMeters(week);
    }
    final averageVolume = plan.weeks == 0 ? 0.0 : total / plan.weeks;
    final sessionsPerWeek = plan.weeks == 0
        ? 0
        : (plan.workouts.length / plan.weeks).round();
    final countdown = _raceCountdown(plan.raceDate, today);
    final canFollow =
        !plan.isArchived && !plan.isActivated && !linkedToPlanning;

    return Opacity(
      opacity: plan.isArchived ? 0.6 : 1,
      child: AppSectionCard(
        onTap: actions.onOpen,
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(
              plan: plan,
              subtitle: _subtitle(loc, plan),
              badge: _badgeFor(context),
              menu: RunPlanCardMenu(
                plan: plan,
                linkedToPlanning: linkedToPlanning,
                actions: actions,
              ),
            ),
            if (total > 0) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        loc.runPlanWeeklyVolumeTitle.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .8,
                        ),
                      ),
                    ),
                    Text(
                      loc.runPlanWeekSummary(
                        RunPlanUi.kmValue(averageVolume),
                        sessionsPerWeek,
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: RunPlanVolumeBars(plan: plan, height: 26),
              ),
            ],
            if (progress.hasProgress) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: RunPlanProgressLine(progress: progress),
              ),
            ],
            if (countdown != null || canFollow) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  children: [
                    if (countdown != null)
                      Flexible(
                        child: AppPill(
                          icon: Icons.flag_outlined,
                          label: loc.runPlanRaceCountdown(countdown),
                        ),
                      ),
                    const Spacer(),
                    if (canFollow)
                      FilledButton.tonalIcon(
                        onPressed: actions.onActivate,
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: Text(loc.runPlansFollow),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget? _badgeFor(BuildContext context) {
    if (progress.isComplete) {
      return _CompletedBadge(
        completionCount: plan.completionCount < 1 ? 1 : plan.completionCount,
      );
    }
    if (plan.isArchived) {
      return Icon(
        Icons.inventory_2_outlined,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    if (linkedToPlanning) {
      return AppPill(
        icon: Icons.route_rounded,
        label: AppLocalizations.of(context)!.periodizationTitle.toUpperCase(),
      );
    }
    return null;
  }
}

/// The plan being followed, pinned on top of the library: where the athlete
/// is in it, what is next and a direct "Start".
class RunPlanFollowedCard extends StatelessWidget {
  final RunPlan plan;
  final RunPlanProgress progress;
  final bool linkedToPlanning;
  final RunPlanCardActions actions;
  final DateTime today;

  /// Today's or the next session, when there is one.
  final RunPlanSessionView? next;
  final VoidCallback? onStartNext;

  const RunPlanFollowedCard({
    super.key,
    required this.plan,
    required this.progress,
    required this.linkedToPlanning,
    required this.actions,
    required this.today,
    required this.next,
    required this.onStartNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    final finished = plan.isFinishedOn(today);
    final complete = progress.isComplete;
    final week = plan.activeWeekIndexOn(today);

    // One status only: a plan is completed, ended by date or being followed.
    final Widget badge;
    if (complete) {
      badge = _CompletedBadge(
        completionCount: plan.completionCount < 1 ? 1 : plan.completionCount,
      );
    } else if (finished) {
      badge = AppPill(
        icon: Icons.flag_circle_outlined,
        label: loc.runPlansEndedBadge,
        color: scheme.onSurfaceVariant,
      );
    } else if (linkedToPlanning) {
      badge = AppPill(
        icon: Icons.route_rounded,
        label: loc.periodizationTitle.toUpperCase(),
      );
    } else {
      badge = AppPill(
        icon: Icons.play_circle_outline,
        label: loc.runPlanActiveBadge,
      );
    }

    final String status;
    if (complete) {
      status = loc.runPlanCompletedHelp;
    } else if (finished) {
      // The "ended" badge and the progress bar below already say it all.
      status = '';
    } else if (week != null) {
      status = loc.runPlanCurrentWeek(week + 1, plan.weeks);
    } else if (linkedToPlanning) {
      status = loc.runPlansPlanningLinked;
    } else if (plan.activatedAt != null && plan.activatedAt!.isAfter(today)) {
      status = loc.runPlanStartsOn(
        DateFormat('d MMM', Intl.defaultLocale).format(plan.activatedAt!),
      );
    } else {
      status = '';
    }

    return AppSectionCard(
      onTap: actions.onOpen,
      color: scheme.primary.withAlpha(14),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            plan: plan,
            subtitle: _subtitle(loc, plan),
            badge: badge,
            menu: RunPlanCardMenu(
              plan: plan,
              linkedToPlanning: linkedToPlanning,
              actions: actions,
            ),
          ),
          if (status.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                status,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
          if (progress.totalSessions > 0) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: RunPlanProgressLine(progress: progress),
            ),
          ],
          if (!finished && !complete && !linkedToPlanning) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _NextSessionRow(
                next: next,
                today: today,
                onStart: onStartNext,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NextSessionRow extends StatelessWidget {
  final RunPlanSessionView? next;
  final DateTime today;
  final VoidCallback? onStart;

  const _NextSessionRow({
    required this.next,
    required this.today,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    final view = next;
    if (view == null) {
      return Text(
        loc.runPlansNoPendingSession,
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    final locale = Localizations.localeOf(context).toString();
    final day = view.isToday(today)
        ? loc.runPlanDetailToday
        : DateFormat('EEE d/M', locale).format(view.date!);
    return Row(
      children: [
        AppIconBadge(
          RunPlanUi.kindIcon(view.workout.kind),
          color: RunPlanUi.kindColor(scheme, view.workout.kind),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            loc.runPlansNextSession(day, view.workout.name),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (onStart != null)
          FilledButton.icon(
            key: const ValueKey('run-plans-start-next'),
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow_rounded, size: 20),
            label: Text(loc.runPlanDetailStart),
          ),
      ],
    );
  }
}

class _CardHeader extends StatelessWidget {
  final RunPlan plan;
  final String subtitle;
  final Widget? badge;
  final Widget menu;

  const _CardHeader({
    required this.plan,
    required this.subtitle,
    required this.badge,
    required this.menu,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        AppIconBadge(
          Icons.route_outlined,
          color: scheme.secondary,
          size: 42,
          iconSize: 22,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                plan.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (badge != null)
          Padding(padding: const EdgeInsets.only(left: 4), child: badge),
        menu,
      ],
    );
  }
}

/// Overflow menu: everything except the primary action of the card.
class RunPlanCardMenu extends StatelessWidget {
  final RunPlan plan;
  final bool linkedToPlanning;
  final RunPlanCardActions actions;

  const RunPlanCardMenu({
    super.key,
    required this.plan,
    required this.linkedToPlanning,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return PopupMenuButton<String>(
      tooltip: loc.runPlansMoreActions,
      onSelected: (value) => switch (value) {
        'activate' => actions.onActivate(),
        'deactivate' => actions.onDeactivate(),
        'duplicate' => actions.onDuplicate(),
        'archive' => actions.onToggleArchive(),
        'delete' => actions.onDelete(),
        _ => null,
      },
      itemBuilder: (ctx) => [
        if (!plan.isArchived && !linkedToPlanning)
          PopupMenuItem(
            value: plan.isActivated ? 'deactivate' : 'activate',
            child: Text(
              plan.isActivated ? loc.runPlanDeactivate : loc.runPlanActivate,
            ),
          ),
        PopupMenuItem(value: 'duplicate', child: Text(loc.runPlansDuplicate)),
        PopupMenuItem(
          value: 'archive',
          child: Text(
            plan.isArchived ? loc.runPlansUnarchive : loc.runPlansArchive,
          ),
        ),
        PopupMenuItem(value: 'delete', child: Text(loc.runPlansDelete)),
      ],
    );
  }
}

/// Sessions done against the total, as a bar with its label.
class RunPlanProgressLine extends StatelessWidget {
  final RunPlanProgress progress;

  const RunPlanProgressLine({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 6,
              color: scheme.primary,
              backgroundColor: scheme.primary.withAlpha(30),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          loc.runPlanProgressValue(
            progress.completedSessions,
            progress.totalSessions,
          ),
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (progress.skippedSessions > 0) ...[
          const SizedBox(width: 8),
          Text(
            loc.runPlanSkippedCount(progress.skippedSessions),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _CompletedBadge extends StatelessWidget {
  final int completionCount;

  const _CompletedBadge({required this.completionCount});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final repeated = completionCount > 1;
    return Tooltip(
      message: repeated
          ? '${loc.runPlanCompletedBadge} · ${completionCount}x'
          : loc.runPlanCompletedBadge,
      child: Semantics(
        label: repeated
            ? '${loc.runPlanCompletedBadge}, ${completionCount}x'
            : loc.runPlanCompletedBadge,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: repeated ? 7 : 6,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: scheme.primary.withAlpha(30),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                size: 14,
                color: scheme.primary,
              ),
              if (repeated) ...[
                const SizedBox(width: 3),
                Text(
                  '${completionCount}x',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
