import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/widgets/form_section_card.dart';

import 'nutrition_goal_suggest_sheet.dart';

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
  final _bodyRepo = BodyMeasurementRepository();
  final _settingsRepo = SettingsRepository();
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

  /// Opens the Mifflin-St Jeor suggestion sheet and fills the goal
  /// fields with its result when the user applies it.
  Future<void> _openSuggestion() async {
    await NutritionGoalSuggestSheet.show(
      context,
      bodyRepo: _bodyRepo,
      settingsRepo: _settingsRepo,
      onApply: (calories, protein, carbs, fat) {
        if (!mounted) return;
        setState(() {
          _caloriesController.text = _format(calories);
          _proteinController.text = _format(protein);
          _carbsController.text = _format(carbs);
          _fatController.text = _format(fat);
        });
      },
    );
  }

  Future<void> _clear() async {    final loc = AppLocalizations.of(context)!;
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

  /// Live values read from the form while editing, used by the
  /// preview card.
  double? get _calories => _parseValue(_caloriesController.text);
  double? get _protein => _parseValue(_proteinController.text);
  double? get _carbs => _parseValue(_carbsController.text);
  double? get _fat => _parseValue(_fatController.text);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.nutritionSettingsTitle),
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
                : Text(loc.nutritionSettingsSave),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  children: [
                    _GoalHeaderCard(
                      subtitle: loc.nutritionSettingsSubtitle,
                    ),
                    const SizedBox(height: 14),
                    _GoalPreviewCard(
                      calories: _calories,
                      proteinG: _protein,
                      carbsG: _carbs,
                      fatG: _fat,
                    ),
                    const SizedBox(height: 14),
                    FormSectionCard(
                      icon: Icons.tune_rounded,
                      title: loc.nutritionSettingsSectionTarget,
                      children: [
                        _NumberField(
                          controller: _caloriesController,
                          label: loc.nutritionSettingsCalories,
                          validator: _validateNumber,
                          prefix: 'kcal',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        _NumberField(
                          controller: _proteinController,
                          label: loc.nutritionSettingsProtein,
                          validator: _validateNumber,
                          prefix: 'g',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        _NumberField(
                          controller: _carbsController,
                          label: loc.nutritionSettingsCarbs,
                          validator: _validateNumber,
                          prefix: 'g',
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        _NumberField(
                          controller: _fatController,
                          label: loc.nutritionSettingsFat,
                          validator: _validateNumber,
                          prefix: 'g',
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    FormSectionCard(
                      icon: Icons.calculate_outlined,
                      title: loc.nutritionSettingsSuggestSection,
                      children: [
                        Text(
                          loc.nutritionSettingsSuggestBody,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _isSaving ? null : _openSuggestion,
                          icon: const Icon(Icons.trending_up_rounded),
                          label: Text(loc.nutritionSettingsSuggestButton),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_current != null)
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer.withAlpha(60),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ListTile(
                          leading: Icon(
                            Icons.delete_outline,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          title: Text(
                            loc.nutritionSettingsClear,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: _isSaving ? null : _clear,
                        ),
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
            label: Text(loc.nutritionSettingsSave),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoalHeaderCard extends StatelessWidget {
  final String subtitle;

  const _GoalHeaderCard({required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(90),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.flag_outlined,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live preview of the goal being typed: headline calories and the
/// macro energy split (protein/carbs/fat at 4/4/9 kcal per gram).
class _GoalPreviewCard extends StatelessWidget {
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;

  const _GoalPreviewCard({
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final proteinKcal = (proteinG ?? 0) * 4;
    final carbsKcal = (carbsG ?? 0) * 4;
    final fatKcal = (fatG ?? 0) * 9;
    final macroTotal = proteinKcal + carbsKcal + fatKcal;
    final headline = calories ?? (macroTotal > 0 ? macroTotal : null);
    final hasAny =
        headline != null || proteinG != null || carbsG != null || fatG != null;

    if (!hasAny) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.pie_chart_outline_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                loc.nutritionSettingsEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.pie_chart_outline_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  loc.nutritionPreview,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  loc.nutritionConsumedKcal(_format(headline)),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (macroTotal > 0 && calories == null) ...[
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      loc.nutritionSettingsFromMacros,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _MacroSplitBar(
              label: loc.nutritionProgressProtein,
              valueKcal: proteinKcal,
              totalKcal: macroTotal,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(height: 8),
            _MacroSplitBar(
              label: loc.nutritionProgressCarbs,
              valueKcal: carbsKcal,
              totalKcal: macroTotal,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 8),
            _MacroSplitBar(
              label: loc.nutritionProgressFat,
              valueKcal: fatKcal,
              totalKcal: macroTotal,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }

  static String _format(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}

class _MacroSplitBar extends StatelessWidget {
  final String label;
  final double valueKcal;
  final double totalKcal;
  final Color color;

  const _MacroSplitBar({
    required this.label,
    required this.valueKcal,
    required this.totalKcal,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = totalKcal > 0
        ? (valueKcal / totalKcal).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final percent =
        totalKcal > 0 ? '${((valueKcal / totalKcal) * 100).round()}%' : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              percent,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: color.withAlpha(40),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?) validator;
  final String? prefix;
  final ValueChanged<String>? onChanged;

  const _NumberField({
    required this.controller,
    required this.label,
    required this.validator,
    this.prefix,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: prefix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
      ),
      validator: validator,
      onChanged: onChanged,
    );
  }
}
