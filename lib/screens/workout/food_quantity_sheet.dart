import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/food_variant.dart';
import 'package:workout_notes/models/nutrition/meal_log_item.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/utils/nutrition_conversion.dart';

/// Helper to present the quantity modal for [food]. Returns the
/// user's selection or null when dismissed.
Future<NutritionQuantitySelection?> showFoodQuantitySheet({
  required BuildContext context,
  required Food food,
  required FoodVariant? primaryVariant,
  required List<FoodServing> servings,
  MealLogItem? existing,
  VoidCallback? onRemove,
}) async {
  if (primaryVariant == null) {
    return null;
  }
  return showModalBottomSheet<NutritionQuantitySelection>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return FoodQuantitySheet(
        food: food,
        primaryVariant: primaryVariant,
        servings: servings,
        existing: existing,
        onRemove: onRemove,
      );
    },
  );
}

/// Bottom sheet that captures quantity, unit and (when needed) the
/// serving used. Previews the consumed values in real time and only
/// enables the save action when the conversion succeeds.
class FoodQuantitySheet extends StatefulWidget {
  final Food food;
  final FoodVariant primaryVariant;
  final List<FoodServing> servings;
  final MealLogItem? existing;
  final VoidCallback? onRemove;

  const FoodQuantitySheet({
    super.key,
    required this.food,
    required this.primaryVariant,
    required this.servings,
    this.existing,
    this.onRemove,
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
    final previous = _unit;
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
    if (_unit != null && _unit != previous) {
      _quantityController.text = _defaultQuantityForUnit(_unit);
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
      });
    } on NutritionConversionException catch (e) {
      setState(() {
        _preview = null;
        _errorText = _humanizeError(e.code);
        _isEstimated = widget.primaryVariant.isEstimated;
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
        return loc.nutritionServingEquivalenceMissing;
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
    setState(() {
      _selectedServing = serving;
      _quantityController.text = _formatForField(serving?.quantity ?? 1);
    });
    _updatePreview();
  }

  void _onQuantityChanged(String raw) {
    _updatePreview();
  }

  void _adjustQuantity(double delta) {
    final current = _parseQuantity(_quantityController.text) ?? 0;
    final next = (current + delta).clamp(0.0, double.infinity);
    _quantityController.text = _formatForField(next);
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

  void _remove() {
    final onRemove = widget.onRemove;
    if (onRemove == null) return;
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => onRemove());
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
              _Header(
                name: widget.food.name,
                brand: widget.food.brand,
                perLabel: loc.nutritionPer100g(
                  widget.primaryVariant.referenceAmount.toStringAsFixed(0),
                  widget.primaryVariant.referenceUnit,
                ),
              ),
              const SizedBox(height: 18),
              _buildUnitChoices(loc),
              if (_unit == 'serving' && widget.servings.isNotEmpty) ...[
                const SizedBox(height: 14),
                _ServingQuickPicks(
                  servings: widget.servings,
                  referenceUnit: widget.primaryVariant.referenceUnit,
                  selected: _selectedServing,
                  onTap: _onServingChanged,
                ),
              ],
              const SizedBox(height: 16),
              _PreviewSection(
                preview: _preview,
                isEstimated: _isEstimated,
                loc: loc,
                theme: theme,
              ),
              const SizedBox(height: 14),
              _QuantityField(
                controller: _quantityController,
                errorText: _errorText,
                onChanged: _onQuantityChanged,
                onIncrement: () => _adjustQuantity(1),
                onDecrement: () => _adjustQuantity(-1),
                canDecrement:
                    (_parseQuantity(_quantityController.text) ?? 0) > 0,
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _preview == null ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(loc.nutritionSave),
              ),
              if (widget.onRemove != null) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const ValueKey('food-quantity-remove'),
                  onPressed: _remove,
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(loc.nutritionDeleteItem),
                ),
              ],
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
    final entries =
        available
            .map(
              (value) =>
                  _SegmentUnitEntry.fromValue(value, _unitLabel(loc, value)),
            )
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return _UnitSegmentedControl(
      entries: entries,
      selected: _unit,
      onChanged: _onUnitChanged,
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

/// Light header: food name, optional brand, "per X" hint. No
/// background — the modal already provides a surface.
class _Header extends StatelessWidget {
  final String name;
  final String? brand;
  final String perLabel;

  const _Header({
    required this.name,
    required this.brand,
    required this.perLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        if (brand != null && brand!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            brand!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          perLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Per-unit entry used to render the segmented unit picker. The
/// label is the localized unit name (kept in sync with the rest of
/// the app's copy); the icon is a small visual cue so the user can
/// scan the control quickly.
class _SegmentUnitEntry {
  final String value;
  final String label;
  final IconData icon;
  final int sortOrder;

  const _SegmentUnitEntry(this.value, this.label, this.icon, this.sortOrder);

  factory _SegmentUnitEntry.fromValue(String value, String label) {
    switch (value) {
      case 'g':
        return _SegmentUnitEntry(value, label, Icons.scale_outlined, 0);
      case 'ml':
        return _SegmentUnitEntry(value, label, Icons.local_drink_outlined, 1);
      case 'serving':
        return _SegmentUnitEntry(value, label, Icons.restaurant_outlined, 2);
      case 'unit':
        return _SegmentUnitEntry(value, label, Icons.circle_outlined, 3);
      default:
        return _SegmentUnitEntry(value, label, Icons.circle_outlined, 9);
    }
  }
}

/// A single-row segmented control for unit selection. Uses a subtle
/// filled background (surfaceContainerLow) so it reads as a control,
/// not as a stack of colorful chips.
class _UnitSegmentedControl extends StatelessWidget {
  final List<_SegmentUnitEntry> entries;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _UnitSegmentedControl({
    required this.entries,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _SegmentButton(
                entry: entries[i],
                selected: entries[i].value == selected,
                onTap: () => onChanged(entries[i].value),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final _SegmentUnitEntry entry;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = selected ? theme.colorScheme.surface : Colors.transparent;
    final fg = selected
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(
                    color: theme.colorScheme.outlineVariant.withAlpha(140),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(entry.icon, size: 15, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  entry.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick-pick chips for the available servings. Tapping a chip
/// switches the selected serving and updates the quantity field
/// with the serving's natural amount. Servings without an
/// equivalence for the current reference unit are rendered in a
/// muted state and are not selectable.
class _ServingQuickPicks extends StatelessWidget {
  final List<FoodServing> servings;
  final String referenceUnit;
  final FoodServing? selected;
  final ValueChanged<FoodServing?> onTap;

  const _ServingQuickPicks({
    required this.servings,
    required this.referenceUnit,
    required this.selected,
    required this.onTap,
  });

  bool _isConvertible(FoodServing s) {
    final ref = NutritionConversion.normalizeUnit(referenceUnit);
    if (ref == 'g') {
      if (s.hasGramConversion) return true;
      return NutritionConversion.inferEquivalenceFromLabel(s.label, 'g') !=
          null;
    }
    if (ref == 'ml') {
      if (s.hasMlConversion) return true;
      return NutritionConversion.inferEquivalenceFromLabel(s.label, 'ml') !=
          null;
    }
    return s.hasGramConversion || s.hasMlConversion;
  }

  String? _equivalenceLabel(FoodServing s) {
    final ref = NutritionConversion.normalizeUnit(referenceUnit);
    if (ref == 'g' && s.gramsEquivalent != null) {
      return '${_formatGrams(s.gramsEquivalent!)} g';
    }
    if (ref == 'ml' && s.mlEquivalent != null) {
      return '${_formatGrams(s.mlEquivalent!)} ml';
    }
    if (s.gramsEquivalent != null) {
      return '${_formatGrams(s.gramsEquivalent!)} g';
    }
    if (s.mlEquivalent != null) {
      return '${_formatGrams(s.mlEquivalent!)} ml';
    }
    final inferred = NutritionConversion.inferEquivalenceFromLabel(
      s.label,
      ref,
    );
    if (inferred != null) {
      return '~${_formatGrams(inferred)} $ref';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: servings.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = servings[i];
          final isSelected = s.id == selected?.id;
          final isConvertible = _isConvertible(s);
          final equivalence = _equivalenceLabel(s);
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isConvertible ? () => onTap(s) : null,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary.withAlpha(28)
                      : theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary.withAlpha(140)
                        : theme.colorScheme.outlineVariant.withAlpha(
                            isConvertible ? 80 : 40,
                          ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      s.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: isSelected
                            ? theme.colorScheme.primary
                            : (isConvertible
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant
                                        .withAlpha(140)),
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                    if (equivalence != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? theme.colorScheme.primary.withAlpha(160)
                              : theme.colorScheme.onSurfaceVariant.withAlpha(
                                  120,
                                ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        equivalence,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isSelected
                              ? theme.colorScheme.primary.withAlpha(220)
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatGrams(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}

/// Quantity input with subtle +/- stepper buttons on each side. The
/// stepper adapts: integer units increment by 1; units below 10
/// (small quantities) increment by 0.5 to keep the UX precise.
class _QuantityField extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final bool canDecrement;

  const _QuantityField({
    required this.controller,
    required this.errorText,
    required this.onChanged,
    required this.onIncrement,
    required this.onDecrement,
    required this.canDecrement,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        children: [
          _StepperButton(
            icon: Icons.remove_rounded,
            onTap: canDecrement ? onDecrement : null,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                errorText: errorText,
                errorMaxLines: 1,
              ),
              onChanged: onChanged,
            ),
          ),
          _StepperButton(icon: Icons.add_rounded, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    final fg = enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant.withAlpha(120);
    return Material(
      color: enabled
          ? theme.colorScheme.surface
          : theme.colorScheme.surface.withAlpha(120),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withAlpha(80),
            ),
          ),
          child: Icon(icon, size: 20, color: fg),
        ),
      ),
    );
  }
}

/// Inline preview section. No background card — the hero calorie
/// number is the focal point, and the macros sit in a tight,
/// right-aligned column.
class _PreviewSection extends StatelessWidget {
  final NutritionValues? preview;
  final bool isEstimated;
  final AppLocalizations loc;
  final ThemeData theme;

  const _PreviewSection({
    required this.preview,
    required this.isEstimated,
    required this.loc,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    if (preview == null) {
      return Text(
        loc.nutritionInvalidQuantity,
        style: TextStyle(color: theme.colorScheme.error),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                loc.nutritionPreview,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (isEstimated) ...[
                _InlineBadge(
                  icon: Icons.bolt_outlined,
                  label: loc.nutritionEstimated,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatCalories(preview!.calories),
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 36,
                  height: 1.0,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'kcal',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MacroPill(
                  label: loc.nutritionProgressProtein,
                  value: _formatMacro(preview!.proteinG),
                  color: _proteinMacroColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MacroPill(
                  label: loc.nutritionProgressCarbs,
                  value: _formatMacro(preview!.carbsG),
                  color: _carbMacroColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MacroPill(
                  label: loc.nutritionProgressFat,
                  value: _formatMacro(preview!.fatG),
                  color: _fatMacroColor,
                ),
              ),
            ],
          ),
          if (preview!.hasFatBreakdown) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (preview!.saturatedFatG != null)
                  _FatDetailChip(
                    label: loc.nutritionFatSaturated,
                    value: _formatMacro(preview!.saturatedFatG),
                  ),
                if (preview!.monounsaturatedFatG != null)
                  _FatDetailChip(
                    label: loc.nutritionFatMonounsaturated,
                    value: _formatMacro(preview!.monounsaturatedFatG),
                  ),
                if (preview!.polyunsaturatedFatG != null)
                  _FatDetailChip(
                    label: loc.nutritionFatPolyunsaturated,
                    value: _formatMacro(preview!.polyunsaturatedFatG),
                  ),
                if (preview!.transFatG != null)
                  _FatDetailChip(
                    label: loc.nutritionFatTrans,
                    value: _formatMacro(preview!.transFatG),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _formatCalories(double? value) {
    if (value == null) return '—';
    if (value < 10) return value.toStringAsFixed(1);
    return value.toStringAsFixed(0);
  }

  static String _formatMacro(double? value) {
    if (value == null) return '— g';
    if (value < 10) return '${value.toStringAsFixed(1)} g';
    return '${value.toStringAsFixed(0)} g';
  }
}

const Color _carbMacroColor = Color(0xFF20A39E);
const Color _proteinMacroColor = Color(0xFFF29E38);
const Color _fatMacroColor = Color(0xFF8E44AD);

class _FatDetailChip extends StatelessWidget {
  final String label;
  final String value;

  const _FatDetailChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${label.replaceAll(' (g)', '')}: $value',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _MacroPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MacroPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
                height: 1.0,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Container(
          height: 3,
          decoration: BoxDecoration(
            color: color.withAlpha(45),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: 0.4,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InlineBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiary.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.tertiary),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.tertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
