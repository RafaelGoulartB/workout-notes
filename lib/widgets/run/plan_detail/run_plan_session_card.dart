import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/services/run_plan_week_view.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// One planned session inside the training week.
///
/// A single badge tells where it stands (done / missed / skipped); a planned
/// session that is due today (or next) carries a direct "Start" button.
class RunPlanSessionCard extends StatelessWidget {
  final RunPlanSessionView view;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback? onMove;
  final VoidCallback onDelete;

  /// Starts the run for this session; only set on today's / the next one.
  final VoidCallback? onStart;

  /// Opens the recorded run of a done session.
  final VoidCallback? onOpenRun;

  const RunPlanSessionCard({
    super.key,
    required this.view,
    required this.onTap,
    required this.onEdit,
    required this.onDuplicate,
    required this.onDelete,
    this.onMove,
    this.onStart,
    this.onOpenRun,
  });

  RunPlanWorkout get workout => view.workout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    final color = RunPlanUi.kindColor(scheme, workout.kind);
    final outline = RunPlanUi.stepsOutline(loc, workout);
    final estimate = RunPlanUi.estimatedTotalSeconds(workout);
    final done = view.state == RunSessionState.done;
    final ledger = view.ledger;

    final summary = [
      RunPlanUi.kindLabel(loc, workout.kind),
      RunPlanUi.sessionSummary(loc, workout),
      if (estimate > 0) '~${RunPlanUi.durationRoughLabel(estimate)}',
    ].where((part) => part.isNotEmpty).join(' · ');

    // What was actually run, replacing nothing: the plan line stays.
    String? actual;
    if (done && ledger?.actualDistanceMeters != null) {
      actual = loc.runPlanDetailCompletedRunLine(
        RunFormatters.distanceWithUnit(ledger!.actualDistanceMeters!),
        RunFormatters.paceWithUnit(ledger.actualPaceSecPerKm),
      );
    }

    return Material(
      color: done
          ? scheme.tertiaryContainer.withAlpha(70)
          : scheme.surfaceContainerHighest.withAlpha(70),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: view.state == RunSessionState.missed
            ? BorderSide(color: scheme.error.withAlpha(90))
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  RunIconBadge(
                    RunPlanUi.kindIcon(workout.kind),
                    color: color,
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workout.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          summary,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _StateBadge(state: view.state, onTap: onOpenRun),
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    padding: EdgeInsets.zero,
                    onSelected: (value) => switch (value) {
                      'edit' => onEdit(),
                      'duplicate' => onDuplicate(),
                      'move' => onMove?.call(),
                      'delete' => onDelete(),
                      _ => null,
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(loc.runPlanDetailEditSession),
                      ),
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Text(loc.runPlanSessionDuplicate),
                      ),
                      if (onMove != null)
                        PopupMenuItem(
                          value: 'move',
                          child: Text(loc.runPlanSessionMove),
                        ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(loc.runWorkoutDelete),
                      ),
                    ],
                  ),
                ],
              ),
              // The intensity profile only says something for structured
              // sessions; a continuous run would just be a flat grey bar.
              if (workout.hasSteps) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: RunWorkoutProfileBar(workout: workout, height: 8),
                ),
              ],
              if (outline.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    outline,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              if (actual != null) ...[
                const SizedBox(height: 6),
                Text(
                  actual,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.tertiary,
                    fontWeight: FontWeight.w700,
                    fontFeatures: RunUi.tabular,
                  ),
                ),
              ],
              if (onStart != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: ValueKey('run-plan-start-${workout.id}'),
                      onPressed: onStart,
                      icon: const Icon(Icons.play_arrow_rounded, size: 20),
                      label: Text(loc.runPlanDetailStart),
                    ),
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

/// The single status badge of a session; nothing for a plain planned one.
class _StateBadge extends StatelessWidget {
  final RunSessionState state;
  final VoidCallback? onTap;

  const _StateBadge({required this.state, this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final pill = switch (state) {
      RunSessionState.planned => null,
      RunSessionState.done => RunPill(
        icon: Icons.check_circle_rounded,
        label: loc.runPlanSessionCompleted,
        color: scheme.tertiary,
      ),
      RunSessionState.missed => RunPill(
        icon: Icons.error_outline_rounded,
        label: loc.runPlanDetailMissed,
        color: scheme.error,
      ),
      RunSessionState.skipped => RunPill(
        icon: Icons.skip_next_rounded,
        label: loc.runPlanSessionSkipped,
        color: scheme.onSurfaceVariant,
      ),
    };
    if (pill == null) return const SizedBox.shrink();
    final child = Padding(
      padding: const EdgeInsets.only(right: 2),
      child: pill,
    );
    if (onTap == null || state != RunSessionState.done) return child;
    return Tooltip(
      message: loc.runPlanDetailViewRun,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: child,
      ),
    );
  }
}
