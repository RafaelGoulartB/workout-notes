import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/macro_calculator.dart';

/// Shared nutrition target inputs: total calories, protein and fat in g/kg
/// and the reference weight used to convert ratios into grams. Carbohydrates
/// are computed from the remaining calories and shown as a live preview —
/// nothing is stored until the caller saves the resolved grams.
///
/// The controllers are owned by the parent (form/wizard); call [parseField]
/// to read them and [breakdownOf] to resolve the computed macros.
class NutritionTargetFields extends StatelessWidget {
  final TextEditingController calories;
  final TextEditingController proteinPerKg;
  final TextEditingController fatPerKg;
  final TextEditingController referenceWeight;
  final bool enabled;
  final VoidCallback? onChanged;

  const NutritionTargetFields({
    super.key,
    required this.calories,
    required this.proteinPerKg,
    required this.fatPerKg,
    required this.referenceWeight,
    this.enabled = true,
    this.onChanged,
  });

  static double? parseField(TextEditingController controller) =>
      _parse(controller.text);

  static double? _parse(String raw) {
    final cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  static MacroBreakdown? breakdownOf({
    required TextEditingController calories,
    required TextEditingController proteinPerKg,
    required TextEditingController fatPerKg,
    required TextEditingController referenceWeight,
  }) {
    final kcal = parseField(calories);
    final protein = parseField(proteinPerKg);
    final fat = parseField(fatPerKg);
    final weight = parseField(referenceWeight);
    if (kcal == null || protein == null || fat == null || weight == null) {
      return null;
    }
    return computeMacros(
      calories: kcal,
      proteinPerKg: protein,
      fatPerKg: fat,
      weightKg: weight,
    );
  }

  MacroBreakdown? get _breakdown {
    if (!enabled) return null;
    return breakdownOf(
      calories: calories,
      proteinPerKg: proteinPerKg,
      fatPerKg: fatPerKg,
      referenceWeight: referenceWeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final breakdown = _breakdown;
    final hasRatioInputs =
        calories.text.trim().isNotEmpty ||
        proteinPerKg.text.trim().isNotEmpty ||
        fatPerKg.text.trim().isNotEmpty;
    final hasWeight = parseField(referenceWeight) != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 560
                ? (constraints.maxWidth - 10) / 2
                : constraints.maxWidth;
            Widget field(
              TextEditingController controller,
              String label,
              String unit,
            ) => SizedBox(
              width: width,
              child: TextField(
                controller: controller,
                enabled: enabled,
                onChanged: (_) => onChanged?.call(),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [FilteringTextInputFormatter.allow(
                  RegExp(r'[\d.,]'),
                )],
                decoration: InputDecoration(
                  labelText: label,
                  suffixText: unit,
                  filled: true,
                  fillColor:
                      theme.colorScheme.surfaceContainerLowest,
                ),
              ),
            );

            return Wrap(
              spacing: 10,
              runSpacing: 12,
              children: [
                field(calories, loc.periodizationCaloriesPerDay, 'kcal'),
                field(
                  referenceWeight,
                  loc.periodizationReferenceWeight,
                  'kg',
                ),
                field(proteinPerKg, loc.periodizationProteinPerKg, 'g/kg'),
                field(fatPerKg, loc.periodizationFatPerKg, 'g/kg'),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        if (breakdown != null) ...[
          if (breakdown.energyConflict)
            _ConflictBanner(loc.nutritionSuggestMacroEnergyError)
          else
            _MacroPreview(breakdown: breakdown),
        ] else if (hasRatioInputs && !hasWeight)
          _Hint(
            icon: Icons.monitor_weight_outlined,
            text: loc.periodizationNoReferenceWeight,
          )
        else
          _Hint(
            icon: Icons.info_outline_rounded,
            text: loc.nutritionSuggestCarbsRemainder,
          ),
      ],
    );
  }
}

class _MacroPreview extends StatelessWidget {
  final MacroBreakdown breakdown;

  const _MacroPreview({required this.breakdown});

  static const _proteinColor = Color(0xFF4F8EF7);
  static const _carbsColor = Color(0xFFF5B942);
  static const _fatColor = Color(0xFF9B6BE8);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final totalKcal =
        breakdown.proteinKcal + breakdown.fatKcal + breakdown.carbsKcal;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(90),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.periodizationMacroPreview,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _MacroValue(
                  label: loc.nutritionProgressProtein,
                  value: '${breakdown.proteinRounded} g',
                  color: _proteinColor,
                ),
              ),
              Expanded(
                child: _MacroValue(
                  label: loc.periodizationCarbsRemainder,
                  value: '${breakdown.carbsRounded} g',
                  color: _carbsColor,
                ),
              ),
              Expanded(
                child: _MacroValue(
                  label: loc.nutritionProgressFat,
                  value: '${breakdown.fatRounded} g',
                  color: _fatColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (totalKcal > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 8,
                child: Row(
                  children: [
                    Expanded(
                      flex: breakdown.proteinKcal,
                      child: Container(color: _proteinColor),
                    ),
                    Expanded(
                      flex: breakdown.fatKcal,
                      child: Container(color: _fatColor),
                    ),
                    Expanded(
                      flex: breakdown.carbsKcal,
                      child: Container(color: _carbsColor),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MacroValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MacroValue({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ConflictBanner extends StatelessWidget {
  final String message;

  const _ConflictBanner(this.message);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withAlpha(120),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 19,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Hint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
