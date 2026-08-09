import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/ai_food_label_draft.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';

/// Form for adding a new food manually to the local cache. The new
/// food is persisted via [NutritionRepository.createManualFood] and
/// popped to the caller so the search screen can hand it off to the
/// quantity sheet.
///
/// When [initial] is provided (AI label extraction), the form is
/// pre-filled so the user can review and correct the parsed values
/// before saving. [source] is recorded as the food's origin.
class ManualFoodScreen extends StatefulWidget {
  final NutritionRepository repository;
  final String source;
  final AiFoodLabelDraft? initial;

  const ManualFoodScreen({
    super.key,
    required this.repository,
    this.source = FoodSource.manual,
    this.initial,
  });

  @override
  State<ManualFoodScreen> createState() => _ManualFoodScreenState();
}

class _ManualFoodScreenState extends State<ManualFoodScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _referenceAmountController = TextEditingController(text: '100');
  final _referenceUnitController = TextEditingController(text: 'g');
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();
  final _fiberController = TextEditingController();
  final _sugarsController = TextEditingController();
  final _sodiumController = TextEditingController();
  bool _isEstimated = false;
  final List<_ManualServingDraft> _servings = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    _nameController.text = initial.name;
    if (initial.brand != null) _brandController.text = initial.brand!;
    if (initial.barcode != null) _barcodeController.text = initial.barcode!;
    _referenceAmountController.text = _formatAmount(initial.referenceAmount);
    _referenceUnitController.text = initial.referenceUnit;
    _fillNumber(_caloriesController, initial.values.calories);
    _fillNumber(_proteinController, initial.values.proteinG);
    _fillNumber(_carbsController, initial.values.carbsG);
    _fillNumber(_fatController, initial.values.fatG);
    _fillNumber(_fiberController, initial.values.fiberG);
    _fillNumber(_sugarsController, initial.values.sugarsG);
    _fillNumber(_sodiumController, initial.values.sodiumMg);
    _isEstimated = true;
    for (final serving in initial.servings) {
      _servings.add(_servingDraftFrom(serving));
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _brandController,
      _barcodeController,
      _referenceAmountController,
      _referenceUnitController,
      _caloriesController,
      _proteinController,
      _carbsController,
      _fatController,
      _fiberController,
      _sugarsController,
      _sodiumController,
    ]) {
      c.dispose();
    }
    for (final s in _servings) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    try {
      final food = await widget.repository.createManualFood(
        name: _nameController.text.trim(),
        brand: _nullableText(_brandController.text),
        barcode: _nullableText(_barcodeController.text),
        source: widget.source,
        referenceAmount: _parseDouble(_referenceAmountController.text, 100)!,
        referenceUnit: _referenceUnitController.text.trim().isEmpty
            ? 'g'
            : _referenceUnitController.text.trim(),
        referenceValues: NutritionValues(
          calories: _parseDouble(_caloriesController.text, 0),
          proteinG: _parseDouble(_proteinController.text, 0),
          carbsG: _parseDouble(_carbsController.text, 0),
          fatG: _parseDouble(_fatController.text, 0),
          fiberG: _parseDouble(_fiberController.text, null),
          sugarsG: _parseDouble(_sugarsController.text, null),
          sodiumMg: _parseDouble(_sodiumController.text, null),
        ),
        isEstimated: _isEstimated,
        servings: _servings
            .where((s) => s.labelController.text.trim().isNotEmpty)
            .map(
              (s) => ManualServingInput(
                label: s.labelController.text.trim(),
                quantity: _parseDouble(s.quantityController.text, 1) ?? 1,
                unit: s.unitController.text.trim().isEmpty
                    ? 'g'
                    : s.unitController.text.trim(),
                gramsEquivalent: _parseDouble(s.gramsController.text, null),
                mlEquivalent: _parseDouble(s.mlController.text, null),
              ),
            )
            .toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(food);
    } catch (e) {
      if (!mounted) return;
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  static double? _parseDouble(String raw, double? fallback) {
    final cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return fallback;
    final value = double.tryParse(cleaned);
    if (value == null || value.isNaN || value.isInfinite) return fallback;
    if (value < 0) return null;
    return value;
  }

  static String? _nullableText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _addServing() {
    setState(() {
      _servings.add(_ManualServingDraft());
    });
  }

  static String _formatAmount(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  static void _fillNumber(TextEditingController controller, double? value) {
    if (value == null) return;
    controller.text = _formatAmount(value);
  }

  static _ManualServingDraft _servingDraftFrom(
    AiFoodLabelServingDraft serving,
  ) {
    final draft = _ManualServingDraft();
    draft.labelController.text = serving.label;
    draft.quantityController.text = _formatAmount(serving.quantity);
    draft.unitController.text = serving.unit;
    if (serving.gramsEquivalent != null) {
      draft.gramsController.text = _formatAmount(serving.gramsEquivalent!);
    }
    return draft;
  }

  void _removeServing(int index) {
    setState(() {
      _servings.removeAt(index).dispose();
    });
  }

  String? _validateRequired(String? value) {
    if (value == null || value.trim().isEmpty) {
      return AppLocalizations.of(context)!.nutritionFieldRequired;
    }
    return null;
  }

  String? _validateNumber(String? value, {bool allowZero = true}) {
    final loc = AppLocalizations.of(context)!;
    if (value == null || value.trim().isEmpty) return null;
    final cleaned = value.trim().replaceAll(',', '.');
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return loc.nutritionInvalidNumber;
    }
    if (!allowZero && parsed <= 0) {
      return loc.nutritionInvalidQuantity;
    }
    if (parsed < 0) {
      return loc.nutritionInvalidNumber;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.nutritionManualTitle),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(loc.nutritionSave),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: loc.nutritionManualName,
                  hintText: loc.nutritionManualNameHint,
                  border: const OutlineInputBorder(),
                ),
                validator: _validateRequired,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _brandController,
                decoration: InputDecoration(
                  labelText: loc.nutritionManualBrand,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _barcodeController,
                decoration: InputDecoration(
                  labelText: loc.nutritionManualBarcode,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _referenceAmountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: loc.nutritionManualReference,
                        hintText: loc.nutritionManualReferenceHint,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => _validateNumber(v, allowZero: false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _referenceUnitController,
                      decoration: InputDecoration(
                        labelText: loc.nutritionUnit,
                        border: const OutlineInputBorder(),
                      ),
                      validator: _validateRequired,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _caloriesController,
                label: loc.nutritionManualCalories,
                validator: _validateNumber,
                allowDecimal: true,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _proteinController,
                label: loc.nutritionManualProtein,
                validator: _validateNumber,
                allowDecimal: true,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _carbsController,
                label: loc.nutritionManualCarbs,
                validator: _validateNumber,
                allowDecimal: true,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _fatController,
                label: loc.nutritionManualFat,
                validator: _validateNumber,
                allowDecimal: true,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _fiberController,
                label: loc.nutritionManualFiber,
                validator: _validateNumber,
                allowDecimal: true,
                optional: true,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _sugarsController,
                label: loc.nutritionManualSugars,
                validator: _validateNumber,
                allowDecimal: true,
                optional: true,
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _sodiumController,
                label: loc.nutritionManualSodium,
                validator: _validateNumber,
                allowDecimal: true,
                optional: true,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _isEstimated,
                onChanged: (v) => setState(() => _isEstimated = v),
                title: Text(loc.nutritionManualIsEstimated),
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(height: 32),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      loc.nutritionServingsAvailable,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addServing,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(loc.nutritionManualAddServing),
                  ),
                ],
              ),
              if (_servings.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    loc.nutritionSettingsEmpty,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                Column(
                  children: List.generate(_servings.length, (i) {
                    return _ManualServingRow(
                      draft: _servings[i],
                      onRemove: () => _removeServing(i),
                    );
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;
  final bool allowDecimal;
  final bool optional;

  const _NumberField({
    required this.controller,
    required this.label,
    required this.validator,
    this.allowDecimal = false,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: allowDecimal),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (v) {
        if (optional && (v == null || v.trim().isEmpty)) return null;
        return validator(v);
      },
    );
  }
}

class _ManualServingDraft {
  final TextEditingController labelController = TextEditingController();
  final TextEditingController quantityController = TextEditingController(
    text: '1',
  );
  final TextEditingController unitController = TextEditingController();
  final TextEditingController gramsController = TextEditingController();
  final TextEditingController mlController = TextEditingController();

  void dispose() {
    labelController.dispose();
    quantityController.dispose();
    unitController.dispose();
    gramsController.dispose();
    mlController.dispose();
  }
}

class _ManualServingRow extends StatelessWidget {
  final _ManualServingDraft draft;
  final VoidCallback onRemove;

  const _ManualServingRow({required this.draft, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          TextFormField(
            controller: draft.labelController,
            decoration: InputDecoration(
              labelText: loc.nutritionManualServingLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: draft.quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: loc.nutritionQuantity,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: draft.unitController,
                  decoration: InputDecoration(
                    labelText: loc.nutritionUnit,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: draft.gramsController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: loc.nutritionManualServingGrams,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
