import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/utils/nutrition_conversion.dart';

/// Bottom sheet that captures quantity, unit and (when needed) the
/// serving used. Previews the consumed values in real time and only
/// enables the save action when the conversion succeeds.
class FoodQuantitySheet extends StatefulWidget {
  final Food food;
  final FoodVariant primaryVariant;
  final List<FoodServing> servings;
  final MealLogItem? existing;

  const FoodQuantitySheet({
    super.key,
    required this.food,
    required this.primaryVariant,
    required this.servings,
    this.existing,
  });

  @override
  State<FoodQuantitySheet> createState() => _FoodQuantitySheetState();
}

class _FoodQuantitySheetState extends State<FoodQuantitySheet> {
  late TextEditingController _quantityController;
  String? _unit;
  FoodServing? _selectedServing;
  String? _errorText;
  NutritionValues? _preview;
  bool _isEstimated = false;
  bool _hasMissing = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.existing;
    if (initial != null) {
      _quantityController = TextEditingController(
        text: _formatForField(initial.quantity),
      );
      _unit = initial.unit;
    } else {
      _quantityController = TextEditingController(text: _defaultQuantityText());
    }
    _recomputeUnitAvailability();
    _restoreExistingServing(initial);
    _updatePreview();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  String _formatForField(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  String _defaultQuantityText() {
    final v = widget.primaryVariant.referenceAmount;
    return _formatForField(v);
  }

  void _recomputeUnitAvailability() {
    final available = _computeAvailableUnits();
    if (_unit == null || !available.contains(_unit)) {
      if (available.contains('g')) {
        _unit = 'g';
      } else if (available.contains('ml')) {
        _unit = 'ml';
      } else if (available.contains('serving')) {
        _unit = 'serving';
        _selectedServing = widget.servings.isEmpty
            ? null
            : widget.servings.first;
      } else if (available.contains('unit')) {
        _unit = 'unit';
        _selectedServing = null;
      } else {
        _unit = available.isEmpty ? null : available.first;
      }
    }
  }

  void _restoreExistingServing(MealLogItem? existing) {
    if (existing == null || _unit != 'serving' || widget.servings.isEmpty) {
      return;
    }
    final snapshot = existing.snapshot;
    _selectedServing = widget.servings.firstWhere(
      (serving) =>
          serving.gramsEquivalent == snapshot.gramsEquivalent &&
          serving.mlEquivalent == snapshot.mlEquivalent,
      orElse: () => widget.servings.first,
    );
  }

  /// Units the user can pick for this variant: the reference unit
  /// (g/ml when it normalizes to one, otherwise the free manual unit
  /// such as "fatia"), plus "porção" when servings are defined.
  Set<String> _computeAvailableUnits() {
    final available = <String>{};
    final ref = widget.primaryVariant.referenceUnit.trim();
    final normalizedRef = NutritionConversion.normalizeUnit(ref);
    if (normalizedRef == 'g') {
      available.add('g');
    } else if (normalizedRef == 'ml') {
      available.add('ml');
    } else if (normalizedRef == 'serving') {
      available.add('serving');
    } else if (normalizedRef == 'unit') {
      available.add('unit');
    } else if (ref.isNotEmpty) {
      // Free manual unit (e.g. "fatia"): the conversion supports a
      // direct unit == reference match, so surface the unit itself.
      available.add(ref);
    }
    if (widget.servings.isNotEmpty) {
      available.add('serving');
    }
    return available;
  }

  void _updatePreview() {
    final quantity = _parseQuantity(_quantityController.text);
    if (quantity == null || _unit == null) {
      setState(() {
        _preview = null;
        _errorText = quantity == null && _quantityController.text.isNotEmpty
            ? AppLocalizations.of(context)!.nutritionInvalidQuantity
            : null;
        _isEstimated = widget.primaryVariant.isEstimated;
        _hasMissing = widget.primaryVariant.values.hasMissingFields;
      });
      return;
    }
    final conversion = NutritionConversion(
      quantity: quantity,
      unit: _unit!,
      referenceAmount: widget.primaryVariant.referenceAmount,
      referenceUnit: widget.primaryVariant.referenceUnit,
      serving: _selectedServing,
    );
    try {
      final values = conversion.apply(widget.primaryVariant.values);
      setState(() {
        _preview = values;
        _errorText = null;
        _isEstimated = widget.primaryVariant.isEstimated;
        _hasMissing = values.hasMissingFields;
      });
    } on NutritionConversionException catch (e) {
      setState(() {
        _preview = null;
        _errorText = _humanizeError(e.code);
        _isEstimated = widget.primaryVariant.isEstimated;
        _hasMissing = widget.primaryVariant.values.hasMissingFields;
      });
    }
  }

  String _humanizeError(String code) {
    final loc = AppLocalizations.of(context)!;
    switch (code) {
      case 'quantity_must_be_positive':
      case 'reference_amount_must_be_positive':
        return loc.nutritionInvalidQuantity;
      case 'serving_equivalence_missing':
      case 'grams_equivalence_missing':
      case 'ml_equivalence_missing':
      case 'unsupported_unit_combination':
      case 'unsupported_reference_unit':
        return loc.nutritionInvalidQuantity;
      default:
        return loc.nutritionInvalidNumber;
    }
  }

  static double? _parseQuantity(String raw) {
    final cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null) return null;
    if (value <= 0) return null;
    if (value.isNaN || value.isInfinite) return null;
    return value;
  }

  void _onUnitChanged(String? value) {
    setState(() {
      _unit = value;
      if (value == 'serving' && widget.servings.isNotEmpty) {
        _selectedServing = widget.servings.first;
      } else if (value != 'serving') {
        _selectedServing = null;
      }
      // A number cannot be safely reinterpreted under another unit.
      // Reset every unit change to that unit's natural default.
      _quantityController.text = _defaultQuantityForUnit(value);
    });
    _updatePreview();
  }

  String _defaultQuantityForUnit(String? unit) {
    final normalizedReference = NutritionConversion.normalizeUnit(
      widget.primaryVariant.referenceUnit,
    );
    final isConvertedServing =
        unit == 'serving' && normalizedReference != 'serving';
    final isConvertedUnit = unit == 'unit' && normalizedReference != 'unit';
    return isConvertedServing || isConvertedUnit ? '1' : _defaultQuantityText();
  }

  void _onServingChanged(FoodServing? serving) {
    setState(() => _selectedServing = serving);
    _updatePreview();
  }

  void _save() {
    final quantity = _parseQuantity(_quantityController.text);
    if (quantity == null || _unit == null) {
      setState(
        () =>
            _errorText = AppLocalizations.of(context)!.nutritionInvalidQuantity,
      );
      return;
    }
    final conversion = NutritionConversion(
      quantity: quantity,
      unit: _unit!,
      referenceAmount: widget.primaryVariant.referenceAmount,
      referenceUnit: widget.primaryVariant.referenceUnit,
      serving: _selectedServing,
    );
    try {
      conversion.apply(widget.primaryVariant.values);
    } on NutritionConversionException {
      return;
    }
    Navigator.of(context).pop(
      NutritionQuantitySelection(
        food: widget.food,
        variant: widget.primaryVariant,
        conversion: conversion,
        availableServings: widget.servings,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 8, bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                widget.food.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (widget.food.brand != null && widget.food.brand!.isNotEmpty)
                Text(
                  widget.food.brand!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                loc.nutritionPer100g(
                  widget.primaryVariant.referenceAmount.toStringAsFixed(0),
                  widget.primaryVariant.referenceUnit,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _buildUnitChoices(loc),
              const SizedBox(height: 12),
              if (_unit == 'serving' && widget.servings.isNotEmpty) ...[
                _ServingDropdown(
                  servings: widget.servings,
                  selected: _selectedServing,
                  onChanged: _onServingChanged,
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: loc.nutritionQuantity,
                  errorText: _errorText,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => _updatePreview(),
              ),
              const SizedBox(height: 16),
              _PreviewCard(
                preview: _preview,
                isEstimated: _isEstimated,
                hasMissing: _hasMissing,
                loc: loc,
                theme: theme,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _preview == null ? null : _save,
                child: Text(loc.nutritionSave),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUnitChoices(AppLocalizations loc) {
    final available = _computeAvailableUnits();
    if (available.isEmpty) {
      return Text(
        loc.nutritionInvalidQuantity,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }
    return Wrap(
      spacing: 8,
      children: available.map((value) {
        return ChoiceChip(
          label: Text(_unitLabel(loc, value)),
          selected: _unit == value,
          onSelected: (selected) {
            if (selected) _onUnitChanged(value);
          },
        );
      }).toList(),
    );
  }

  String _unitLabel(AppLocalizations loc, String value) {
    switch (value) {
      case 'g':
        return loc.nutritionUnitGrams;
      case 'ml':
        return loc.nutritionUnitMilliliters;
      case 'serving':
        return loc.nutritionUnitServing;
      case 'unit':
        return loc.nutritionUnitUnit;
      default:
        return value;
    }
  }
}

class _ServingDropdown extends StatelessWidget {
  final List<FoodServing> servings;
  final FoodServing? selected;
  final ValueChanged<FoodServing?> onChanged;

  const _ServingDropdown({
    required this.servings,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return DropdownButtonFormField<FoodServing>(
      initialValue: selected,
      decoration: InputDecoration(
        labelText: loc.nutritionServingsAvailable,
        border: const OutlineInputBorder(),
      ),
      items: servings
          .map(
            (s) => DropdownMenuItem<FoodServing>(
              value: s,
              child: Text(_describe(s)),
            ),
          )
          .toList(),
      onChanged: onChanged,
    );
  }

  String _describe(FoodServing serving) {
    final qty = serving.quantity == serving.quantity.roundToDouble()
        ? serving.quantity.toStringAsFixed(0)
        : serving.quantity.toStringAsFixed(2);
    final base = '$qty ${serving.unit} · ${serving.label}';
    final extras = <String>[];
    if (serving.gramsEquivalent != null) {
      extras.add('${serving.gramsEquivalent!.toStringAsFixed(0)} g');
    }
    if (serving.mlEquivalent != null) {
      extras.add('${serving.mlEquivalent!.toStringAsFixed(0)} ml');
    }
    return extras.isEmpty ? base : '$base (${extras.join(', ')})';
  }
}

class _PreviewCard extends StatelessWidget {
  final NutritionValues? preview;
  final bool isEstimated;
  final bool hasMissing;
  final AppLocalizations loc;
  final ThemeData theme;

  const _PreviewCard({
    required this.preview,
    required this.isEstimated,
    required this.hasMissing,
    required this.loc,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.nutritionPreview,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (preview == null)
            Text(
              loc.nutritionInvalidQuantity,
              style: TextStyle(color: theme.colorScheme.error),
            )
          else ...[
            _previewLine(
              context,
              label: loc.nutritionGoalCalories,
              value: preview!.calories,
              suffix: 'kcal',
            ),
            _previewLine(
              context,
              label: loc.nutritionProgressProtein,
              value: preview!.proteinG,
              suffix: 'g',
            ),
            _previewLine(
              context,
              label: loc.nutritionProgressCarbs,
              value: preview!.carbsG,
              suffix: 'g',
            ),
            _previewLine(
              context,
              label: loc.nutritionProgressFat,
              value: preview!.fatG,
              suffix: 'g',
            ),
            if (hasMissing)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 16,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        loc.nutritionMissingValues,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (isEstimated)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.bolt_outlined,
                      size: 16,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        loc.nutritionEstimated,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _previewLine(
    BuildContext context, {
    required String label,
    required double? value,
    required String suffix,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value == null
                ? '—'
                : '${value.toStringAsFixed(value < 10 ? 2 : 1)} $suffix',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
