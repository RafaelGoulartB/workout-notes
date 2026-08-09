import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/widgets/form_section_card.dart';

import 'nutrition_goal_suggest_sheet.dart';

/// Screen for managing the daily nutrition goal and the meal types
/// catalog (the sections rendered by the food diary).
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
  List<MealTypeDefinition> _mealTypes = const [];

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
    try {
      final results = await Future.wait([
        widget.repository.getActiveGoal(),
        widget.repository.getMealTypes(),
      ]);
      final goal = results[0] as NutritionGoal?;
      if (!mounted) return;
      setState(() {
        _current = goal;
        _mealTypes = results[1] as List<MealTypeDefinition>;
        _isLoading = false;
        if (goal != null) {
          _caloriesController.text = _format(goal.calories);
          _proteinController.text = _format(goal.proteinG);
          _carbsController.text = _format(goal.carbsG);
          _fatController.text = _format(goal.fatG);
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
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

  // ===================================================================
  // Meal types catalog
  // ===================================================================

  Future<void> _addMealType() async {
    final loc = AppLocalizations.of(context)!;
    final name = await _promptMealTypeName(title: loc.nutritionNewMealTitle);
    if (name == null) return;
    if (!mounted) return;
    try {
      await widget.repository.createMealType(name);
      await _loadMealTypes();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionMealAdded)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    }
  }

  Future<void> _renameMealType(MealTypeDefinition type) async {
    final loc = AppLocalizations.of(context)!;
    final name = await _promptMealTypeName(
      title: loc.nutritionRenameMealTitle,
      initial: type.displayName(loc),
    );
    if (name == null) return;
    if (!mounted) return;
    try {
      await widget.repository.renameMealType(type.id, name);
      await _loadMealTypes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    }
  }

  Future<void> _deleteMealType(MealTypeDefinition type) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.nutritionDeleteMeal),
        content: Text(
          loc.nutritionMealTypeDeleteConfirm(type.displayName(loc)),
        ),
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
    if (confirmed != true) return;
    if (!mounted) return;
    try {
      await widget.repository.deleteMealType(type.id);
      await _loadMealTypes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    }
  }

  Future<void> _moveMealType(MealTypeDefinition type, int delta) async {
    final index = _mealTypes.indexWhere((t) => t.id == type.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= _mealTypes.length) return;
    final reordered = [..._mealTypes];
    final item = reordered.removeAt(index);
    reordered.insert(target, item);
    setState(() => _mealTypes = reordered);
    try {
      await widget.repository.reorderMealTypes(
        [for (final t in reordered) t.id],
      );
    } catch (_) {
      await _loadMealTypes();
    }
  }

  Future<void> _loadMealTypes() async {
    final types = await widget.repository.getMealTypes();
    if (!mounted) return;
    setState(() => _mealTypes = types);
  }

  Future<String?> _promptMealTypeName({
    required String title,
    String? initial,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _MealTypeNameDialog(title: title, initial: initial),
    );
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
                      Material(
                        color: theme.colorScheme.errorContainer.withAlpha(60),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        clipBehavior: Clip.antiAlias,
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
                    const SizedBox(height: 14),
                    FormSectionCard(
                      icon: Icons.restaurant_outlined,
                      title: loc.nutritionMealTypesTitle,
                      children: [
                        Text(
                          loc.nutritionMealTypesSubtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_mealTypes.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              loc.nutritionMealTypeEmpty,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        else
                          for (var i = 0; i < _mealTypes.length; i++)
                            _MealTypeTile(
                              type: _mealTypes[i],
                              canMoveUp: i > 0,
                              canMoveDown: i < _mealTypes.length - 1,
                              onMoveUp: () => _moveMealType(_mealTypes[i], -1),
                              onMoveDown: () =>
                                  _moveMealType(_mealTypes[i], 1),
                              onRename: () => _renameMealType(_mealTypes[i]),
                              onDelete: () => _deleteMealType(_mealTypes[i]),
                            ),
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          onPressed: _addMealType,
                          icon: const Icon(Icons.add),
                          label: Text(loc.nutritionAddMeal),
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

/// One row of the meal types catalog: name, reorder arrows, edit and
/// delete actions.
class _MealTypeTile extends StatelessWidget {
  final MealTypeDefinition type;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _MealTypeTile({
    required this.type,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: loc.nutritionMealTypeMoveUp,
          onPressed: canMoveUp ? onMoveUp : null,
          icon: const Icon(Icons.arrow_upward, size: 20),
        ),
        IconButton(
          tooltip: loc.nutritionMealTypeMoveDown,
          onPressed: canMoveDown ? onMoveDown : null,
          icon: const Icon(Icons.arrow_downward, size: 20),
        ),
        Expanded(
          child: Text(
            type.displayName(loc),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: loc.nutritionRenameMeal,
          onPressed: onRename,
          icon: const Icon(Icons.edit_outlined, size: 20),
        ),
        IconButton(
          tooltip: loc.nutritionDeleteMeal,
          onPressed: onDelete,
          icon: Icon(
            Icons.delete_outline,
            size: 20,
            color: theme.colorScheme.error,
          ),
        ),
      ],
    );
  }
}

/// Dialog for typing a meal type name. Owns its [TextEditingController]
/// so it is disposed only when the route is fully unmounted — disposing
/// it right after `showDialog` returns would run while the exit
/// animation still has the field attached and crash with a framework
/// assertion.
class _MealTypeNameDialog extends StatefulWidget {
  final String title;
  final String? initial;

  const _MealTypeNameDialog({required this.title, this.initial});

  @override
  State<_MealTypeNameDialog> createState() => _MealTypeNameDialogState();
}

class _MealTypeNameDialogState extends State<_MealTypeNameDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(
            labelText: loc.nutritionMealName,
            hintText: loc.nutritionMealNameHint,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          textInputAction: TextInputAction.done,
          validator: (value) =>
              (value == null || value.trim().isEmpty)
              ? loc.nutritionMealNameRequired
              : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(loc.nutritionCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(loc.nutritionSave),
        ),
      ],
    );
  }
}
