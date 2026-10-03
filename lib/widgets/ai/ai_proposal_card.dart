import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/widgets/ai/proposals/ai_proposal_format.dart';
import 'package:workout_notes/widgets/ai/proposals/body_goal_proposal_bodies.dart';
import 'package:workout_notes/widgets/ai/proposals/food_proposal_bodies.dart';
import 'package:workout_notes/widgets/ai/proposals/plan_proposal_bodies.dart';
import 'package:workout_notes/widgets/ai/proposals/routine_proposal_body.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// The card of one AI proposal: kind icon and title, status pill, the honest
/// preview of the change (by kind), warnings, and the approve / reject
/// buttons. It never changes data itself: [onApprove] and [onReject] do, and
/// the buttons stay disabled while either runs (and while [busy], the
/// orchestrator's own flag), so a double tap cannot apply twice.
///
/// When the change removes or replaces something the user must confirm it in a
/// dialog that names what goes away.
class AiProposalCard extends StatefulWidget {
  final AiProposal proposal;

  /// True while the app is applying a proposal of this conversation.
  final bool busy;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  /// True for kinds whose approval opens a form instead of applying (the
  /// button then says "Approve and review form"). Defaults to the kinds the
  /// app knows to be user-confirmed.
  final bool? opensForm;

  const AiProposalCard({
    required this.proposal,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    this.opensForm,
    super.key,
  });

  /// Kinds whose approval opens a pre-filled form.
  static const Set<String> formKinds = {'manual_food'};

  /// What would be removed or replaced by approving [preview]: the entries the
  /// confirmation dialog lists. Empty when approval needs no confirmation.
  static List<Map<String, dynamic>> destructiveItems(
    Map<String, dynamic> preview,
  ) => [...jsonMaps(preview['removals']), ...jsonMaps(preview['replacements'])];

  @override
  State<AiProposalCard> createState() => _AiProposalCardState();
}

enum _Phase { idle, confirming, applying }

class _AiProposalCardState extends State<AiProposalCard> {
  _Phase _phase = _Phase.idle;

  /// Buttons are locked while a confirmation is open, while applying and while
  /// the orchestrator is busy: a second tap can never start a second apply.
  bool get _locked => _phase != _Phase.idle || widget.busy;

  bool get _showBusy => _phase == _Phase.applying || widget.busy;

  bool get _opensForm =>
      widget.opensForm ??
      AiProposalCard.formKinds.contains(widget.proposal.kind);

  Future<void> _run(
    Future<void> Function() action, {
    _Phase phase = _Phase.applying,
  }) async {
    if (_locked) return;
    setState(() => _phase = phase);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _phase = _Phase.idle);
    }
  }

  Future<void> _approve() => _run(() async {
    final items = AiProposalCard.destructiveItems(widget.proposal.preview);
    if (items.isNotEmpty) {
      if (mounted) setState(() => _phase = _Phase.confirming);
      final confirmed = await _confirm(items);
      if (!confirmed || !mounted) return;
      setState(() => _phase = _Phase.applying);
    }
    await widget.onApprove();
  });

  Future<void> _reject() => _run(widget.onReject);

  Future<bool> _confirm(List<Map<String, dynamic>> items) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = AiProposalFormat(l10n);
    final removals = jsonMaps(widget.proposal.preview['removals']);
    final replacements = jsonMaps(widget.proposal.preview['replacements']);
    final names = <String>[];
    for (final removal in removals) {
      final type = removal['type'];
      if (type == 'day') {
        names.add('• ${removal['name']}');
      } else if (type == 'exercise') {
        final day = removal['day'] is String ? ' (${removal['day']})' : '';
        names.add('• ${fmt.exerciseName(removal)}$day');
      } else if (type == 'set') {
        names.add(
          '• ${fmt.exerciseName(removal)} (${l10n.aiProposalCountSets(1)})',
        );
      }
    }
    for (final replacement in replacements) {
      final from = jsonMap(replacement['from']);
      final to = jsonMap(replacement['to']);
      names.add('• ${fmt.exerciseName(from)} → ${fmt.exerciseName(to)}');
    }
    const maxListed = 8;
    final shown = names.take(maxListed).toList();
    if (names.length > maxListed) {
      shown.add(l10n.aiProposalScheduleMore(names.length - maxListed));
    }
    final message = [
      if (removals.isNotEmpty) l10n.aiProposalConfirmRemovals(removals.length),
      if (replacements.isNotEmpty)
        l10n.aiProposalConfirmReplacements(replacements.length),
      shown.join('\n'),
      l10n.aiProposalConfirmNoUndo,
    ].join('\n\n');
    return showConfirmDialog(
      context,
      title: l10n.aiProposalConfirmTitle,
      message: message,
      confirmLabel: l10n.aiProposalConfirmApply,
      cancelLabel: l10n.commonCancel,
      destructive: true,
      icon: Icons.warning_amber_rounded,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final fmt = AiProposalFormat(l10n);
    final proposal = widget.proposal;
    final preview = proposal.preview;
    final status = proposal.status;
    final pending = status == AiProposalStatus.awaiting;
    final tint = _tint(theme, status);
    final title = AiProposalText.title(l10n, proposal.kind, preview);
    final warnings = [
      for (final warning in jsonMaps(preview['warnings']))
        ?AiProposalText.warning(l10n, fmt, warning),
    ];
    final body = _body(preview);

    return Semantics(
      container: true,
      label: '$title: ${AiProposalText.status(l10n, status)}',
      child: Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: tint.withAlpha(160)),
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
                      color: tint.withAlpha(34),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      AiProposalText.icon(proposal.kind, preview),
                      color: tint,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  AppPill(
                    key: const Key('ai-proposal-status'),
                    label: AiProposalText.status(l10n, status),
                    color: tint,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _statusText(l10n, proposal),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (status == AiProposalStatus.stale ||
                  status == AiProposalStatus.failed) ...[
                const SizedBox(height: 8),
                AppBanner.warning(
                  AiProposalText.error(l10n, proposal.errorCode),
                  key: const Key('ai-proposal-error'),
                ),
              ],
              const SizedBox(height: 12),
              body,
              for (final warning in warnings) ...[
                const SizedBox(height: 8),
                AppBanner.warning(warning),
              ],
              if (pending) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const Key('ai-proposal-approve'),
                  onPressed: _locked ? null : _approve,
                  icon: _showBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(
                    _showBusy
                        ? l10n.aiProposalApplying
                        : _opensForm
                        ? l10n.aiProposalApproveForm
                        : l10n.aiProposalApprove,
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  key: const Key('ai-proposal-reject'),
                  onPressed: _locked ? null : _reject,
                  icon: const Icon(Icons.close_rounded),
                  label: Text(
                    _opensForm ? l10n.aiProposalDiscard : l10n.aiProposalReject,
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(Map<String, dynamic> preview) {
    final l10n = AppLocalizations.of(context)!;
    if (preview['v'] != kAiProposalPreviewVersion) {
      return Text(
        l10n.aiProposalUnknownBody,
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return switch (widget.proposal.kind) {
      'routine' => RoutineProposalBody(preview: preview),
      'manual_food' => ManualFoodProposalBody(preview: preview),
      'meal_log' => MealLogProposalBody(preview: preview),
      'body_measurement' => BodyMeasurementProposalBody(preview: preview),
      'goal' => GoalProposalBody(preview: preview),
      'nutrition_goal' => NutritionGoalProposalBody(preview: preview),
      'workout_schedule' => WorkoutScheduleProposalBody(preview: preview),
      'run_plan' => RunPlanProposalBody(preview: preview),
      _ => Text(
        l10n.aiProposalUnknownBody,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    };
  }

  String _statusText(AppLocalizations l10n, AiProposal proposal) =>
      switch (proposal.status) {
        AiProposalStatus.awaiting =>
          _opensForm
              ? l10n.aiProposalHintAwaitingForm
              : l10n.aiProposalHintAwaiting,
        AiProposalStatus.applied =>
          _opensForm
              ? l10n.aiProposalHintAppliedForm
              : l10n.aiProposalHintApplied,
        AiProposalStatus.rejected => l10n.aiProposalHintRejected,
        AiProposalStatus.expired => l10n.aiProposalHintExpired,
        AiProposalStatus.stale ||
        AiProposalStatus.failed => l10n.aiProposalHintNotApplied,
      };

  Color _tint(ThemeData theme, AiProposalStatus status) => switch (status) {
    AiProposalStatus.awaiting => theme.colorScheme.primary,
    AiProposalStatus.applied => Colors.green.shade700,
    AiProposalStatus.rejected ||
    AiProposalStatus.expired => theme.colorScheme.outline,
    AiProposalStatus.stale => Colors.orange.shade800,
    AiProposalStatus.failed => theme.colorScheme.error,
  };
}
