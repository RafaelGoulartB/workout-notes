import 'package:workout_notes/screens/workout/manual_food_controller.dart';
import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

class NutritionExpandableSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool initiallyExpanded;
  final List<Widget> children;

  const NutritionExpandableSection({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.initiallyExpanded,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        children: children,
      ),
    );
  }
}

class NutritionMacroFieldRow extends StatelessWidget {
  final List<Widget> children;

  const NutritionMacroFieldRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

class NutritionNumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;
  final bool allowDecimal;
  final bool optional;

  const NutritionNumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.validator,
    this.allowDecimal = false,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
      ),
      validator: (v) {
        if (optional && (v == null || v.trim().isEmpty)) return null;
        return validator(v);
      },
    );
  }
}

class ManualServingCard extends StatelessWidget {
  final int index;
  final ManualServingDraft draft;
  final VoidCallback onRemove;

  const ManualServingCard({
    super.key,
    required this.index,
    required this.draft,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 8, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${loc.nutritionServingsAvailable} ${index + 1}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: loc.commonDelete,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: theme.colorScheme.error.withAlpha(180),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              children: [
                TextFormField(
                  controller: draft.labelController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: loc.nutritionManualServingLabel,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withAlpha(60),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: draft.quantityController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: loc.nutritionQuantity,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withAlpha(60),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: draft.unitController,
                        textCapitalization: TextCapitalization.none,
                        decoration: InputDecoration(
                          labelText: loc.nutritionUnit,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withAlpha(60),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: draft.gramsController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: loc.nutritionManualServingGrams,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withAlpha(60),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: draft.mlController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: loc.nutritionUnitMilliliters,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withAlpha(60),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
