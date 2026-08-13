import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/nutrition/ai_manual_food_proposal.dart';
import '../../models/nutrition/nutrition_values.dart';

class AiManualFoodProposalCard extends StatefulWidget {
  final AiManualFoodProposal proposal;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  const AiManualFoodProposalCard({
    super.key,
    required this.proposal,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<AiManualFoodProposalCard> createState() =>
      _AiManualFoodProposalCardState();
}

class _AiManualFoodProposalCardState extends State<AiManualFoodProposalCard> {
  bool _expanded = false;
  bool _opening = false;

  Future<void> _approve() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onApprove();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final proposal = widget.proposal;
    final draft = proposal.draft;
    final pending =
        proposal.status == AiManualFoodProposalStatus.awaitingApproval;
    final statusColor = switch (proposal.status) {
      AiManualFoodProposalStatus.awaitingApproval => theme.colorScheme.primary,
      AiManualFoodProposalStatus.created => Colors.green.shade700,
      AiManualFoodProposalStatus.rejected => theme.colorScheme.outline,
    };

    return Semantics(
      container: true,
      label: '${l10n.aiFoodProposalTitle}: ${draft.name}',
      child: Card(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: statusColor.withAlpha(150)),
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
                      color: statusColor.withAlpha(34),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.restaurant_menu_rounded,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.aiFoodProposalTitle,
                          style: theme.textTheme.labelLarge,
                        ),
                        Text(
                          draft.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (draft.brand != null)
                          Text(
                            draft.brand!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _StatusChip(
                    label: switch (proposal.status) {
                      AiManualFoodProposalStatus.awaitingApproval =>
                        l10n.aiFoodProposalAwaiting,
                      AiManualFoodProposalStatus.created =>
                        l10n.aiFoodProposalCreated,
                      AiManualFoodProposalStatus.rejected =>
                        l10n.aiFoodProposalRejected,
                    },
                    color: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                switch (proposal.status) {
                  AiManualFoodProposalStatus.awaitingApproval =>
                    l10n.aiFoodProposalPreview,
                  AiManualFoodProposalStatus.created =>
                    l10n.aiFoodProposalCreatedBody,
                  AiManualFoodProposalStatus.rejected =>
                    l10n.aiFoodProposalRejectedBody,
                },
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.aiFoodProposalReference(
                  _format(draft.referenceAmount),
                  draft.referenceUnit,
                ),
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    label: l10n.nutritionProgressCalories,
                    value: _value(draft.values.calories, 'kcal'),
                  ),
                  _MetricChip(
                    label: l10n.nutritionProgressProtein,
                    value: _value(draft.values.proteinG, 'g'),
                  ),
                  _MetricChip(
                    label: l10n.nutritionProgressCarbs,
                    value: _value(draft.values.carbsG, 'g'),
                  ),
                  _MetricChip(
                    label: l10n.nutritionProgressFat,
                    value: _value(draft.values.fatG, 'g'),
                  ),
                ],
              ),
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
                      ? l10n.aiFoodProposalHideDetails
                      : l10n.aiFoodProposalDetails,
                ),
              ),
              if (_expanded) _Details(proposal: proposal),
              if (pending) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _opening ? null : _approve,
                  icon: _opening
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(l10n.aiFoodProposalApprove),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _opening ? null : widget.onReject,
                  icon: const Icon(Icons.close_rounded),
                  label: Text(l10n.aiFoodProposalReject),
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
}

class _Details extends StatelessWidget {
  final AiManualFoodProposal proposal;

  const _Details({required this.proposal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final values = proposal.draft.values;
    final nutrients = _nutrients(l10n, values);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.aiFoodProposalEstimated,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (proposal.notes != null) ...[
            const SizedBox(height: 10),
            Text(
              l10n.aiFoodProposalNotes,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(proposal.notes!, style: theme.textTheme.bodySmall),
          ],
          if (nutrients.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final nutrient in nutrients)
                  _MetricChip(label: nutrient.$1, value: nutrient.$2),
              ],
            ),
          ],
          if (proposal.draft.servings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.aiFoodProposalServings,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            for (final serving in proposal.draft.servings)
              Text(
                '• ${serving.label}: ${_format(serving.quantity)} ${serving.unit}'
                '${serving.gramsEquivalent == null ? '' : ' (${_format(serving.gramsEquivalent!)} g)'}'
                '${serving.mlEquivalent == null ? '' : ' (${_format(serving.mlEquivalent!)} ml)'}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ],
      ),
    );
  }

  List<(String, String)> _nutrients(
    AppLocalizations l10n,
    NutritionValues values,
  ) => [
    if (values.saturatedFatG != null)
      (l10n.nutritionFatSaturated, _value(values.saturatedFatG, 'g')),
    if (values.monounsaturatedFatG != null)
      (
        l10n.nutritionFatMonounsaturated,
        _value(values.monounsaturatedFatG, 'g'),
      ),
    if (values.polyunsaturatedFatG != null)
      (
        l10n.nutritionFatPolyunsaturated,
        _value(values.polyunsaturatedFatG, 'g'),
      ),
    if (values.transFatG != null)
      (l10n.nutritionFatTrans, _value(values.transFatG, 'g')),
    if (values.fiberG != null)
      (l10n.nutritionProgressFiber, _value(values.fiberG, 'g')),
    if (values.sugarsG != null)
      (l10n.nutritionProgressSugars, _value(values.sugarsG, 'g')),
    if (values.sodiumMg != null)
      (l10n.nutritionProgressSodium, _value(values.sodiumMg, 'mg')),
    if (values.potassiumMg != null)
      (l10n.nutritionProgressPotassium, _value(values.potassiumMg, 'mg')),
    if (values.calciumMg != null)
      (l10n.nutritionProgressCalcium, _value(values.calciumMg, 'mg')),
    if (values.ironMg != null)
      (l10n.nutritionProgressIron, _value(values.ironMg, 'mg')),
    if (values.magnesiumMg != null)
      (l10n.nutritionProgressMagnesium, _value(values.magnesiumMg, 'mg')),
    if (values.zincMg != null)
      (l10n.nutritionProgressZinc, _value(values.zincMg, 'mg')),
    if (values.vitaminAUg != null)
      (l10n.nutritionProgressVitaminA, _value(values.vitaminAUg, 'µg')),
    if (values.vitaminCMg != null)
      (l10n.nutritionProgressVitaminC, _value(values.vitaminCMg, 'mg')),
    if (values.vitaminDUg != null)
      (l10n.nutritionProgressVitaminD, _value(values.vitaminDUg, 'µg')),
    if (values.vitaminB12Ug != null)
      (l10n.nutritionProgressVitaminB12, _value(values.vitaminB12Ug, 'µg')),
  ];
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;

  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text('$label: $value', style: theme.textTheme.labelMedium),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withAlpha(28),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

String _value(double? value, String unit) =>
    value == null ? '—' : '${_format(value)} $unit';

String _format(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(1);
