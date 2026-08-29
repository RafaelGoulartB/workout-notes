import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_routine_proposal.dart';

class AiRoutineProposalCard extends StatefulWidget {
  final AiRoutineProposal proposal;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  final VoidCallback? onViewRoutine;
  final Future<void> Function()? onRetrySummary;

  const AiRoutineProposalCard({
    super.key,
    required this.proposal,
    required this.onApprove,
    required this.onReject,
    this.onViewRoutine,
    this.onRetrySummary,
  });

  @override
  State<AiRoutineProposalCard> createState() => _AiRoutineProposalCardState();
}

class _AiRoutineProposalCardState extends State<AiRoutineProposalCard> {
  bool _expanded = false;

  Future<void> _approve() async {
    if (widget.proposal.hasRemovals) {
      final l10n = AppLocalizations.of(context)!;
      final count =
          ((widget.proposal.diff['removed'] as Map?)?['total'] as num? ?? 0)
              .toInt();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.aiRoutineProposalConfirmTitle),
          content: Text(l10n.aiRoutineProposalConfirmBody(count)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.aiRoutineProposalConfirmApply),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await widget.onApprove();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final proposal = widget.proposal;
    final pending = proposal.status == AiRoutineProposalStatus.awaitingApproval;
    final applying = proposal.status == AiRoutineProposalStatus.applying;
    final colors = _statusColors(theme, proposal.status);
    final diff = proposal.diff;
    final before = (diff['before'] as Map?) ?? const {};
    final after = (diff['after'] as Map?) ?? const {};
    final added = (diff['added'] as Map?) ?? const {};

    return Semantics(
      container: true,
      label:
          '${proposal.action == AiRoutineProposalAction.create ? l10n.aiRoutineProposalCreate : l10n.aiRoutineProposalUpdate}: ${proposal.routineName}',
      child: Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.$1.withAlpha(160)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: colors.$1.withAlpha(34),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      proposal.action == AiRoutineProposalAction.create
                          ? Icons.playlist_add_rounded
                          : Icons.edit_note_rounded,
                      color: colors.$1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          proposal.action == AiRoutineProposalAction.create
                              ? l10n.aiRoutineProposalCreate
                              : l10n.aiRoutineProposalUpdate,
                          style: theme.textTheme.labelLarge,
                        ),
                        Text(
                          proposal.routineName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(
                    label: _statusLabel(l10n, proposal.status),
                    color: colors.$1,
                    foreground: colors.$2,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _statusBody(l10n, proposal),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    icon: Icons.calendar_view_week_rounded,
                    value: '${after['days'] ?? 0}',
                    label: l10n.commonDays,
                  ),
                  _MetricChip(
                    icon: Icons.fitness_center_rounded,
                    value: '${after['exercises'] ?? 0}',
                    label: l10n.commonExercises,
                  ),
                  _MetricChip(
                    icon: Icons.repeat_rounded,
                    value: '${after['sets'] ?? 0}',
                    label: l10n.commonSets,
                  ),
                ],
              ),
              if (proposal.hasRemovals) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.aiRoutineProposalRemovalWarning(
                            ((diff['removed'] as Map?)?['total'] as num? ?? 0)
                                .toInt(),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
                label: Text(
                  _expanded
                      ? l10n.aiRoutineProposalHideDetails
                      : l10n.aiRoutineProposalDetails,
                ),
              ),
              if (_expanded)
                _Details(
                  proposal: proposal,
                  before: before,
                  after: after,
                  added: added,
                  l10n: l10n,
                ),
              if (pending || applying) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: applying ? null : _approve,
                  icon: applying
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(l10n.aiRoutineProposalApprove),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: applying ? null : _reject,
                  icon: const Icon(Icons.close_rounded),
                  label: Text(l10n.aiRoutineProposalReject),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ],
              if (proposal.status == AiRoutineProposalStatus.applied) ...[
                const SizedBox(height: 8),
                if (widget.onViewRoutine != null)
                  OutlinedButton.icon(
                    onPressed: widget.onViewRoutine,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(l10n.aiRoutineProposalView),
                  ),
                if (widget.onRetrySummary != null)
                  TextButton(
                    onPressed: widget.onRetrySummary,
                    child: Text(l10n.aiRoutineProposalRetrySummary),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _reject() async => widget.onReject();

  (Color, Color) _statusColors(
    ThemeData theme,
    AiRoutineProposalStatus status,
  ) => switch (status) {
    AiRoutineProposalStatus.awaitingApproval => (
      theme.colorScheme.primary,
      theme.colorScheme.onPrimary,
    ),
    AiRoutineProposalStatus.applying => (
      theme.colorScheme.secondary,
      theme.colorScheme.onSecondary,
    ),
    AiRoutineProposalStatus.applied => (Colors.green.shade700, Colors.white),
    AiRoutineProposalStatus.rejected => (
      theme.colorScheme.outline,
      theme.colorScheme.onSurface,
    ),
    AiRoutineProposalStatus.stale || AiRoutineProposalStatus.failed => (
      theme.colorScheme.error,
      theme.colorScheme.onError,
    ),
  };

  String _statusLabel(AppLocalizations l, AiRoutineProposalStatus status) =>
      switch (status) {
        AiRoutineProposalStatus.awaitingApproval => l.aiRoutineProposalAwaiting,
        AiRoutineProposalStatus.applying => l.aiRoutineProposalApplying,
        AiRoutineProposalStatus.applied => l.aiRoutineProposalApplied,
        AiRoutineProposalStatus.rejected => l.aiRoutineProposalRejected,
        AiRoutineProposalStatus.stale => l.aiRoutineProposalStale,
        AiRoutineProposalStatus.failed => l.aiRoutineProposalFailed,
      };

  String _statusBody(AppLocalizations l, AiRoutineProposal proposal) =>
      switch (proposal.status) {
        AiRoutineProposalStatus.awaitingApproval => l.aiRoutineProposalPreview,
        AiRoutineProposalStatus.applying => l.aiChatApplyingProposal,
        AiRoutineProposalStatus.applied => l.aiRoutineProposalAppliedBody,
        AiRoutineProposalStatus.rejected => l.aiRoutineProposalRejectedBody,
        AiRoutineProposalStatus.stale => l.aiRoutineProposalStaleBody,
        AiRoutineProposalStatus.failed =>
          proposal.errorMessage ?? l.aiChatErrorGeneric,
      };
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color foreground;
  const _StatusChip({
    required this.label,
    required this.color,
    required this.foreground,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: foreground,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  const _MetricChip({
    required this.icon,
    required this.value,
    required this.label,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15),
        const SizedBox(width: 4),
        Text('$value $label', style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );
}

class _Details extends StatelessWidget {
  final AiRoutineProposal proposal;
  final Map before;
  final Map after;
  final Map added;
  final AppLocalizations l10n;
  const _Details({
    required this.proposal,
    required this.before,
    required this.after,
    required this.added,
    required this.l10n,
  });
  @override
  Widget build(BuildContext context) {
    final days = proposal.target['days'] as List? ?? const [];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.aiRoutineProposalChanges,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          Text(
            '${l10n.aiRoutineProposalAdded}: ${l10n.aiRoutineProposalAddedSummary((added['days'] as num?)?.toInt() ?? 0, (added['exercises'] as num?)?.toInt() ?? 0, (added['sets'] as num?)?.toInt() ?? 0)}',
          ),
          if (proposal.hasRemovals)
            Text(
              '${l10n.aiRoutineProposalRemoved}: ${(proposal.diff['removed'] as Map?)?['total'] ?? 0}',
            ),
          const Divider(height: 20),
          ...days.map((rawDay) {
            final day = (rawDay as Map).cast<String, dynamic>();
            final exercises = day['exercises'] as List? ?? const [];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    day['name'] as String? ?? l10n.commonDay,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  ...exercises.map((rawExercise) {
                    final e = (rawExercise as Map).cast<String, dynamic>();
                    return Padding(
                      padding: const EdgeInsets.only(left: 8, top: 3),
                      child: Text(
                        '• ${l10n.aiRoutineProposalExerciseSummary('${e['exercise_name'] ?? e['exercise_id']}', (e['sets'] as List? ?? const []).length, e['rest_time_seconds'] == null ? '' : ' · ${e['rest_time_seconds']}s')}',
                      ),
                    );
                  }),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
