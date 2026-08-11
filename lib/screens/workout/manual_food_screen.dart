import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/ai_food_label_draft.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/food_serving.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/widgets/form_section_card.dart';

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
  final FoodWithDetails? existingFood;

  const ManualFoodScreen({
    super.key,
    required this.repository,
    this.source = FoodSource.manual,
    this.initial,
    this.existingFood,
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
  final _potassiumController = TextEditingController();
  final _calciumController = TextEditingController();
  final _ironController = TextEditingController();
  final _magnesiumController = TextEditingController();
  final _zincController = TextEditingController();
  final _vitaminAController = TextEditingController();
  final _vitaminCController = TextEditingController();
  final _vitaminDController = TextEditingController();
  final _vitaminB12Controller = TextEditingController();
  bool _isEstimated = false;
  final List<_ManualServingDraft> _servings = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingFood;
    if (existing != null) {
      _nameController.text = existing.food.name;
      if (existing.food.brand != null) {
        _brandController.text = existing.food.brand!;
      }
      if (existing.food.barcode != null) {
        _barcodeController.text = existing.food.barcode!;
      }
      final variant = existing.variants.isEmpty
          ? null
          : existing.variants.first;
      if (variant != null) {
        _referenceAmountController.text = _formatAmount(
          variant.referenceAmount,
        );
        _referenceUnitController.text = variant.referenceUnit;
        _fillNumber(_caloriesController, variant.values.calories);
        _fillNumber(_proteinController, variant.values.proteinG);
        _fillNumber(_carbsController, variant.values.carbsG);
        _fillNumber(_fatController, variant.values.fatG);
        _fillNumber(_fiberController, variant.values.fiberG);
        _fillNumber(_sugarsController, variant.values.sugarsG);
        _fillNumber(_sodiumController, variant.values.sodiumMg);
        _fillMicronutrients(variant.values);
        _isEstimated = variant.isEstimated;
        for (final serving
            in existing.servings[variant.id] ?? const <FoodServing>[]) {
          _servings.add(_servingDraftFromFoodServing(serving));
        }
      }
      return;
    }
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
    _fillMicronutrients(initial.values);
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
      _potassiumController,
      _calciumController,
      _ironController,
      _magnesiumController,
      _zincController,
      _vitaminAController,
      _vitaminCController,
      _vitaminDController,
      _vitaminB12Controller,
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
      final servingInputs = _servings
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
          .toList();
      final name = _nameController.text.trim();
      final brand = _nullableText(_brandController.text);
      final barcode = _nullableText(_barcodeController.text);
      final referenceAmount = _parseDouble(
        _referenceAmountController.text,
        100,
      )!;
      final referenceUnit = _referenceUnitController.text.trim().isEmpty
          ? 'g'
          : _referenceUnitController.text.trim();
      final referenceValues = NutritionValues(
        // Empty fields stay null ("unknown"), never 0: a blank
        // macro is different from a measured zero and must keep
        // flagging the food as incomplete in the UI.
        calories: _parseDouble(_caloriesController.text, null),
        proteinG: _parseDouble(_proteinController.text, null),
        carbsG: _parseDouble(_carbsController.text, null),
        fatG: _parseDouble(_fatController.text, null),
        fiberG: _parseDouble(_fiberController.text, null),
        sugarsG: _parseDouble(_sugarsController.text, null),
        sodiumMg: _parseDouble(_sodiumController.text, null),
        potassiumMg: _parseDouble(_potassiumController.text, null),
        calciumMg: _parseDouble(_calciumController.text, null),
        ironMg: _parseDouble(_ironController.text, null),
        magnesiumMg: _parseDouble(_magnesiumController.text, null),
        zincMg: _parseDouble(_zincController.text, null),
        vitaminAUg: _parseDouble(_vitaminAController.text, null),
        vitaminCMg: _parseDouble(_vitaminCController.text, null),
        vitaminDUg: _parseDouble(_vitaminDController.text, null),
        vitaminB12Ug: _parseDouble(_vitaminB12Controller.text, null),
      );
      final existing = widget.existingFood;
      final food = existing == null
          ? await widget.repository.createManualFood(
              name: name,
              brand: brand,
              barcode: barcode,
              source: widget.source,
              referenceAmount: referenceAmount,
              referenceUnit: referenceUnit,
              referenceValues: referenceValues,
              isEstimated: _isEstimated,
              servings: servingInputs,
            )
          : await widget.repository.updateManualFood(
              foodId: existing.food.id,
              name: name,
              brand: brand,
              barcode: barcode,
              referenceAmount: referenceAmount,
              referenceUnit: referenceUnit,
              referenceValues: referenceValues,
              isEstimated: _isEstimated,
              servings: servingInputs,
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

  void _fillMicronutrients(NutritionValues values) {
    _fillNumber(_potassiumController, values.potassiumMg);
    _fillNumber(_calciumController, values.calciumMg);
    _fillNumber(_ironController, values.ironMg);
    _fillNumber(_magnesiumController, values.magnesiumMg);
    _fillNumber(_zincController, values.zincMg);
    _fillNumber(_vitaminAController, values.vitaminAUg);
    _fillNumber(_vitaminCController, values.vitaminCMg);
    _fillNumber(_vitaminDController, values.vitaminDUg);
    _fillNumber(_vitaminB12Controller, values.vitaminB12Ug);
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

  static _ManualServingDraft _servingDraftFromFoodServing(FoodServing serving) {
    final draft = _ManualServingDraft();
    draft.labelController.text = serving.label;
    draft.quantityController.text = _formatAmount(serving.quantity);
    draft.unitController.text = serving.unit;
    if (serving.gramsEquivalent != null) {
      draft.gramsController.text = _formatAmount(serving.gramsEquivalent!);
    }
    if (serving.mlEquivalent != null) {
      draft.mlController.text = _formatAmount(serving.mlEquivalent!);
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
        title: Text(
          widget.existingFood == null
              ? loc.nutritionManualTitle
              : loc.nutritionManualEditTitle,
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(loc.nutritionSave),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              FormSectionCard(
                icon: Icons.fastfood_outlined,
                title: loc.nutritionManualSectionInfo,
                children: [
                  FormFieldLabel(text: loc.nutritionManualName),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _fieldDecoration(
                      hint: loc.nutritionManualNameHint,
                    ),
                    validator: _validateRequired,
                  ),
                  const SizedBox(height: 16),
                  FormFieldLabel(text: loc.nutritionManualBrand),
                  TextFormField(
                    controller: _brandController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _fieldDecoration(),
                  ),
                  const SizedBox(height: 16),
                  FormFieldLabel(text: loc.nutritionManualBarcode),
                  TextFormField(
                    controller: _barcodeController,
                    keyboardType: TextInputType.number,
                    decoration: _fieldDecoration(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FormSectionCard(
                icon: Icons.eco_outlined,
                title: loc.nutritionManualSectionMicronutrients,
                children: [
                  Text(
                    loc.nutritionManualMicronutrientsHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final row
                      in <
                        (
                          TextEditingController,
                          String,
                          TextEditingController,
                          String,
                        )
                      >[
                        (
                          _potassiumController,
                          loc.nutritionProgressPotassium,
                          _calciumController,
                          loc.nutritionProgressCalcium,
                        ),
                        (
                          _ironController,
                          loc.nutritionProgressIron,
                          _magnesiumController,
                          loc.nutritionProgressMagnesium,
                        ),
                        (
                          _zincController,
                          loc.nutritionProgressZinc,
                          _vitaminAController,
                          loc.nutritionProgressVitaminA,
                        ),
                        (
                          _vitaminCController,
                          loc.nutritionProgressVitaminC,
                          _vitaminDController,
                          loc.nutritionProgressVitaminD,
                        ),
                      ]) ...[
                    _MacroFieldRow(
                      children: [
                        _micronutrientField(row.$1, row.$2),
                        _micronutrientField(row.$3, row.$4),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  _micronutrientField(
                    _vitaminB12Controller,
                    loc.nutritionProgressVitaminB12,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FormSectionCard(
                icon: Icons.bar_chart_rounded,
                title: loc.nutritionManualSectionMacros,
                children: [
                  Text(
                    loc.nutritionManualReferenceHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: _NumberField(
                          controller: _referenceAmountController,
                          label: loc.nutritionManualReference,
                          validator: (v) =>
                              _validateNumber(v, allowZero: false),
                          allowDecimal: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NumberField(
                          controller: _referenceUnitController,
                          label: loc.nutritionUnit,
                          validator: _validateRequired,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _MacroFieldRow(
                    children: [
                      _NumberField(
                        controller: _caloriesController,
                        label: loc.nutritionManualCalories,
                        validator: _validateNumber,
                        allowDecimal: true,
                      ),
                      _NumberField(
                        controller: _proteinController,
                        label: loc.nutritionManualProtein,
                        validator: _validateNumber,
                        allowDecimal: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _MacroFieldRow(
                    children: [
                      _NumberField(
                        controller: _carbsController,
                        label: loc.nutritionManualCarbs,
                        validator: _validateNumber,
                        allowDecimal: true,
                      ),
                      _NumberField(
                        controller: _fatController,
                        label: loc.nutritionManualFat,
                        validator: _validateNumber,
                        allowDecimal: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _MacroFieldRow(
                    children: [
                      _NumberField(
                        controller: _fiberController,
                        label: loc.nutritionManualFiber,
                        validator: _validateNumber,
                        allowDecimal: true,
                        optional: true,
                      ),
                      _NumberField(
                        controller: _sugarsController,
                        label: loc.nutritionManualSugars,
                        validator: _validateNumber,
                        allowDecimal: true,
                        optional: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _NumberField(
                    controller: _sodiumController,
                    label: loc.nutritionManualSodium,
                    validator: _validateNumber,
                    allowDecimal: true,
                    optional: true,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withAlpha(60),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      type: MaterialType.transparency,
                      child: SwitchListTile(
                        value: _isEstimated,
                        onChanged: (v) => setState(() => _isEstimated = v),
                        title: Text(loc.nutritionManualIsEstimated),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FormSectionCard(
                icon: Icons.restaurant_menu_rounded,
                title: loc.nutritionServingsAvailable,
                children: [
                  Text(
                    loc.nutritionManualServingsHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_servings.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withAlpha(50),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withAlpha(80),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.lunch_dining_outlined,
                            size: 28,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            loc.nutritionManualServingsHint,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      children: List.generate(_servings.length, (i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ManualServingCard(
                            index: i,
                            draft: _servings[i],
                            onRemove: () => _removeServing(i),
                          ),
                        );
                      }),
                    ),
                  OutlinedButton.icon(
                    onPressed: _addServing,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(loc.nutritionManualAddServing),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(loc.nutritionSave),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({String? hint}) {
    final theme = Theme.of(context);
    return InputDecoration(
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
    );
  }

  Widget _micronutrientField(TextEditingController controller, String label) {
    final usesMicrograms =
        identical(controller, _vitaminAController) ||
        identical(controller, _vitaminDController) ||
        identical(controller, _vitaminB12Controller);
    return _NumberField(
      controller: controller,
      label: '$label (${usesMicrograms ? 'µg' : 'mg'})',
      validator: _validateNumber,
      allowDecimal: true,
      optional: true,
    );
  }
}

class _MacroFieldRow extends StatelessWidget {
  final List<Widget> children;

  const _MacroFieldRow({required this.children});

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

class _ManualServingCard extends StatelessWidget {
  final int index;
  final _ManualServingDraft draft;
  final VoidCallback onRemove;

  const _ManualServingCard({
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
