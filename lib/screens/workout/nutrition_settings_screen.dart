import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';

/// Screen for managing the user-defined daily nutrition goal.
class NutritionSettingsScreen extends StatefulWidget {
  final NutritionRepository repository;

  const NutritionSettingsScreen({super.key, required this.repository});

  @override
  State<NutritionSettingsScreen> createState() =>
      _NutritionSettingsScreenState();
}

class _NutritionSettingsScreenState extends State<NutritionSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  NutritionGoal? _current;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final goal = await widget.repository.getActiveGoal();
    if (!mounted) return;
    setState(() {
      _current = goal;
      _isLoading = false;
      if (goal != null) {
        _caloriesController.text = _format(goal.calories);
        _proteinController.text = _format(goal.proteinG);
        _carbsController.text = _format(goal.carbsG);
        _fatController.text = _format(goal.fatG);
      }
    });
  }

  String _format(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  String? _validateNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final cleaned = value.trim().replaceAll(',', '.');
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return AppLocalizations.of(context)!.nutritionInvalidNumber;
    }
    if (parsed < 0) {
      return AppLocalizations.of(context)!.nutritionInvalidNumber;
    }
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    final loc = AppLocalizations.of(context)!;
    try {
      final goal = await widget.repository.saveGoal(
        calories: _parseValue(_caloriesController.text),
        proteinG: _parseValue(_proteinController.text),
        carbsG: _parseValue(_carbsController.text),
        fatG: _parseValue(_fatController.text),
      );
      if (!mounted) return;
      setState(() => _current = goal);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionSettingsSaved)));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _clear() async {
    final loc = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.nutritionSettingsClear),
        content: Text(loc.nutritionSettingsClear),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.nutritionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.commonDelete),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.repository.clearActiveGoal();
    if (!mounted) return;
    setState(() {
      _current = null;
      _caloriesController.clear();
      _proteinController.clear();
      _carbsController.clear();
      _fatController.clear();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.nutritionSettingsCleared)));
  }

  static double? _parseValue(String raw) {
    final cleaned = raw.trim().replaceAll(',', '.');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    if (value == null || value.isNaN || value.isInfinite) return null;
    if (value <= 0) return null;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.nutritionSettingsTitle),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: Text(loc.nutritionSettingsSave),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Text(
                      loc.nutritionSettingsSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _NumberField(
                      controller: _caloriesController,
                      label: loc.nutritionSettingsCalories,
                      validator: _validateNumber,
                    ),
                    const SizedBox(height: 12),
                    _NumberField(
                      controller: _proteinController,
                      label: loc.nutritionSettingsProtein,
                      validator: _validateNumber,
                    ),
                    const SizedBox(height: 12),
                    _NumberField(
                      controller: _carbsController,
                      label: loc.nutritionSettingsCarbs,
                      validator: _validateNumber,
                    ),
                    const SizedBox(height: 12),
                    _NumberField(
                      controller: _fatController,
                      label: loc.nutritionSettingsFat,
                      validator: _validateNumber,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loc.nutritionSettingsEmpty,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (_current != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isSaving ? null : _clear,
                        icon: const Icon(Icons.delete_outline),
                        label: Text(loc.nutritionSettingsClear),
                      ),
                    ],
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

  const _NumberField({
    required this.controller,
    required this.label,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
  }
}
