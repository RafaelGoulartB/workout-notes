import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/services/run_plan_week_view.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Where a plan stands, in one honest card: following, not following,
/// finished by date, fully completed or driven by a periodization phase.
///
/// Exactly one state is shown, so "Following" and "Completed" can never
/// appear together.
class RunPlanStatusCard extends StatelessWidget {
  final RunPlan plan;
  final RunPlanProgress progress;
  final bool viaPlanning;
  final DateTime today;

  /// Today's or the next session of a followed plan.
  final RunPlanSessionView? next;

  /// Follow / stop following. Null when a periodization phase owns the plan.
  final VoidCallback? onToggle;
  final VoidCallback? onReset;
  final VoidCallback? onChooseNext;
  final VoidCallback? onClose;
  final VoidCallback? onOpenNext;
  final List<RunPlanTemplate> nextTemplates;
  final ValueChanged<RunPlanTemplate>? onStartTemplate;

  const RunPlanStatusCard({
    super.key,
    required this.plan,
    required this.progress,
    required this.viaPlanning,
    required this.today,
    this.next,
    this.onToggle,
    this.onReset,
    this.onChooseNext,
    this.onClose,
    this.onOpenNext,
    this.nextTemplates = const [],
    this.onStartTemplate,
  });

  @override
  Widget build(BuildContext context) {
    if (viaPlanning) return _buildLinked(context);
    if (progress.isComplete) return _buildComplete(context);
    if (plan.isFinishedOn(today)) return _buildFinished(context);
    if (plan.isActivated) return _buildFollowing(context);
    return _buildIdle(context);
  }

  // --- states ---------------------------------------------------------------

  Widget _buildLinked(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return _Frame(
      tint: Theme.of(context).colorScheme.primary,
      icon: Icons.route_rounded,
      title: loc.runPlanActiveVia,
      body: loc.runPlanActiveViaHelp,
      progress: progress,
    );
  }

  Widget _buildComplete(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return _Frame(
      tint: scheme.tertiary,
      filled: true,
      icon: Icons.workspace_premium_rounded,
      title: loc.runPlanCompletedBadge,
      body: loc.runPlanCompletedHelp,
      progress: progress,
      actions: [
        if (onChooseNext != null)
          FilledButton.tonalIcon(
            onPressed: onChooseNext,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(loc.runPlanDetailChooseNext),
          ),
        if (onClose != null)
          TextButton(
            onPressed: onClose,
            child: Text(loc.runPlanDetailCloseFinished),
          ),
      ],
      footer: _templates(context, headline: false),
    );
  }

  Widget _buildFinished(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final percent = progress.totalSessions < 1
        ? 0
        : (progress.completedSessions * 100 / progress.totalSessions).round();
    final raced = plan.workouts.any((w) => w.kind == RunWorkoutKind.race);
    return _Frame(
      tint: scheme.onSurfaceVariant,
      icon: Icons.flag_circle_outlined,
      title: loc.runPlanDetailFinishedTitle,
      body: loc.runPlanDetailFinishedSummary(
        progress.completedSessions,
        progress.totalSessions,
        percent,
      ),
      extra: raced ? loc.runPlanFinishedRecovery : null,
      progress: progress,
      // The summary line already states "2 of 18 sessions (11%)".
      showProgressLabel: false,
      actions: [
        if (onReset != null)
          FilledButton.tonalIcon(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: Text(loc.runPlanDetailRestart),
          ),
        if (onChooseNext != null)
          OutlinedButton(
            onPressed: onChooseNext,
            child: Text(loc.runPlanDetailChooseNext),
          ),
        if (onClose != null)
          TextButton(
            onPressed: onClose,
            child: Text(loc.runPlanDetailCloseFinished),
          ),
      ],
      footer: _templates(context, headline: true),
    );
  }

  Widget _buildFollowing(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final week = plan.activeWeekIndexOn(today);
    final title = week != null
        ? loc.runPlanDetailFollowingWeek(week + 1, plan.weeks)
        : loc.runPlanActiveBadge;
    final startsLater =
        plan.activatedAt != null && plan.activatedAt!.isAfter(today);
    return _Frame(
      tint: scheme.primary,
      icon: Icons.play_circle_outline,
      title: title,
      body: startsLater
          ? loc.runPlanStartsOn(
              MaterialLocalizations.of(
                context,
              ).formatMediumDate(plan.activatedAt!),
            )
          : null,
      progress: progress,
      headerActions: [
        if (onReset != null)
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt_rounded, size: 17),
            label: Text(loc.runPlanResetShort),
          ),
        if (onToggle != null)
          TextButton(
            onPressed: onToggle,
            child: Text(loc.runPlanUnfollowShort),
          ),
      ],
      footer: next == null ? null : _nextRow(context),
    );
  }

  Widget _buildIdle(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return _Frame(
      tint: scheme.onSurfaceVariant,
      icon: Icons.flag_outlined,
      title: progress.hasProgress
          ? loc.runPlanPausedBadge
          : loc.runPlanNotFollowing,
      body: loc.runPlanActivateHint,
      progress: progress.hasProgress ? progress : null,
      headerActions: [
        if (onReset != null)
          TextButton.icon(
            onPressed: onReset,
            icon: const Icon(Icons.restart_alt_rounded, size: 17),
            label: Text(loc.runPlanResetShort),
          ),
        if (onToggle != null)
          FilledButton.tonalIcon(
            onPressed: onToggle,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(loc.runPlanFollowShort),
          ),
      ],
    );
  }

  // --- pieces ---------------------------------------------------------------

  Widget _nextRow(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final view = next!;
    final locale = Localizations.localeOf(context).toString();
    final isToday = view.isToday(today);
    final day = isToday
        ? loc.runPlanDetailToday
        : DateFormat('EEE d/M', locale).format(view.date!);
    return InkWell(
      onTap: onOpenNext,
      borderRadius: BorderRadius.circular(RunUi.tileRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.event_rounded,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${loc.runPlanDetailNextLabel}  ',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    TextSpan(
                      text: loc.runPlanDetailNextValue(day, view.workout.name),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget? _templates(BuildContext context, {required bool headline}) {
    if (nextTemplates.isEmpty || onStartTemplate == null) return null;
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isPt = Localizations.localeOf(context).languageCode == 'pt';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (headline)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Text(
              loc.runPlanFinishedNext.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final template in nextTemplates)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text(template.title(isPt)),
              subtitle: Text(template.prerequisite(isPt)),
              trailing: const Icon(Icons.arrow_forward),
              onTap: () => onStartTemplate!(template),
            ),
          ),
      ],
    );
  }
}

/// Shared chrome of every status: tinted card, icon + title row, optional
/// body, progress bar and actions.
class _Frame extends StatelessWidget {
  final Color tint;
  final bool filled;
  final IconData icon;
  final String title;
  final String? body;
  final String? extra;
  final RunPlanProgress? progress;
  final bool showProgressLabel;
  final List<Widget> headerActions;
  final List<Widget> actions;
  final Widget? footer;

  const _Frame({
    required this.tint,
    required this.icon,
    required this.title,
    this.filled = false,
    this.body,
    this.extra,
    this.progress,
    this.showProgressLabel = true,
    this.headerActions = const [],
    this.actions = const [],
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = this.progress;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: filled
            ? tint.withAlpha(40)
            : tint == scheme.primary
            ? tint.withAlpha(16)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(RunUi.cardRadius),
        border: Border.all(
          color: tint == scheme.onSurfaceVariant
              ? scheme.outlineVariant.withAlpha(90)
              : tint.withAlpha(90),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: tint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: tint,
                  ),
                ),
              ),
              ...headerActions,
            ],
          ),
          if (body != null) ...[
            const SizedBox(height: 4),
            Text(
              body!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (extra != null) ...[
            const SizedBox(height: 4),
            Text(extra!, style: theme.textTheme.bodySmall),
          ],
          if (progress != null && progress.totalSessions > 0) ...[
            const SizedBox(height: 10),
            Row(
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
                if (showProgressLabel) ...[
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
                ],
              ],
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: actions),
          ],
          if (footer != null) ...[const SizedBox(height: 4), footer!],
        ],
      ),
    );
  }
}
