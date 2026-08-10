import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';

import 'nutrition_goal_suggest_sheet.dart';

/// Screen for managing the daily nutrition goal and the meal types
/// catalog (the sections rendered by the food diary).
///
/// The layout matches the rest of the app's settings surfaces: uppercase
/// section headers, rounded card groups and tap-to-edit value tiles that
/// open a focused bottom sheet. Saving is automatic per field so the
/// user never has to remember a final "Save" tap after editing the goal.
class NutritionSettingsScreen extends StatefulWidget {
  final NutritionRepository repository;

  const NutritionSettingsScreen({super.key, required this.repository});

  @override
  State<NutritionSettingsScreen> createState() =>
      _NutritionSettingsScreenState();
}

class _NutritionSettingsScreenState extends State<NutritionSettingsScreen> {
  final _bodyRepo = BodyMeasurementRepository();
  final _settingsRepo = SettingsRepository();

  bool _isLoading = true;
  NutritionGoal? _current;
  List<MealTypeDefinition> _mealTypes = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.repository.getActiveGoal(),
        widget.repository.getMealTypes(),
      ]);
      if (!mounted) return;
      setState(() {
        _current = results[0] as NutritionGoal?;
        _mealTypes = results[1] as List<MealTypeDefinition>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ===================================================================
  // Goal saving
  // ===================================================================

  Future<void> _saveGoalField({
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    String? successMessage,
  }) async {
    final loc = AppLocalizations.of(context)!;
    try {
      final goal = await widget.repository.saveGoal(
        calories: calories,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
      );
      if (!mounted) return;
      setState(() => _current = goal);
      if (successMessage != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    }
  }

  Future<void> _editNumericValue({
    required String title,
    required double? currentValue,
    required String unit,
    required ValueChanged<double?> onSubmit,
  }) async {
    final result = await _openNumberEditor(
      title: title,
      unit: unit,
      initial: currentValue,
    );
    if (result == _kUnchanged) return;
    // result is double? here (null = clear, value = set)
    onSubmit(result as double?);
  }

  Future<void> _clearGoal() async {
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
    setState(() => _current = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.nutritionSettingsCleared)));
  }

  // ===================================================================
  // Auto-suggest
  // ===================================================================

  Future<void> _openSuggestion() async {
    await NutritionGoalSuggestSheet.show(
      context,
      bodyRepo: _bodyRepo,
      settingsRepo: _settingsRepo,
      onApply: (calories, protein, carbs, fat) async {
        if (!mounted) return;
        await _saveGoalField(
          calories: calories,
          proteinG: protein,
          carbsG: carbs,
          fatG: fat,
          successMessage: AppLocalizations.of(context)!.nutritionSettingsGoalApplied,
        );
      },
    );
  }

  // ===================================================================
  // Meal types catalog
  // ===================================================================

  Future<void> _loadMealTypes() async {
    final types = await widget.repository.getMealTypes();
    if (!mounted) return;
    setState(() => _mealTypes = types);
  }

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

  Future<void> _openMealActions(MealTypeDefinition type, int index) async {
    final loc = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _MealActionsSheet(
        type: type,
        canMoveUp: index > 0,
        canMoveDown: index < _mealTypes.length - 1,
        onRename: () => _renameMealType(type),
        onDelete: () => _deleteMealType(type),
        onMoveUp: () => _moveMealType(type, -1),
        onMoveDown: () => _moveMealType(type, 1),
        titleOverride: loc.nutritionSettingsMealTypeActions,
      ),
    );
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

  // ===================================================================
  // Helpers
  // ===================================================================

  /// Sentinel returned by the number-editor bottom sheet when the user
  /// dismissed it without saving. Lets `_editNumericValue` tell the
  /// difference between "no change" and "user typed and saved".
  static const Object _kUnchanged = Object();

  Future<Object?> _openNumberEditor({
    required String title,
    required String unit,
    required double? initial,
  }) {
    return showModalBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _NumberEditorSheet(
        title: title,
        unit: unit,
        initial: initial,
      ),
    );
  }

  static String _formatNum(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  // ===================================================================
  // Build
  // ===================================================================

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          loc.nutritionSettingsTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _GoalPreviewCard(
                  calories: _current?.calories,
                  proteinG: _current?.proteinG,
                  carbsG: _current?.carbsG,
                  fatG: _current?.fatG,
                ),
                _SectionHeader(text: loc.nutritionSettingsSectionDaily),
                _SettingsCard(
                  children: [
                    _ValueTile(
                      icon: Icons.local_fire_department_outlined,
                      title: loc.nutritionGoalCalories,
                      subtitle: loc.nutritionSettingsCaloriesSubtitle,
                      value: _current?.calories,
                      formatValue: (v) =>
                          loc.nutritionConsumedKcal(_formatNum(v)),
                      notSetText: loc.nutritionSettingsNotSet,
                      onTap: () => _editNumericValue(
                        title: loc.nutritionSettingsEditCaloriesTitle,
                        currentValue: _current?.calories,
                        unit: 'kcal',
                        onSubmit: (v) => _saveGoalField(
                          calories: v,
                          proteinG: _current?.proteinG,
                          carbsG: _current?.carbsG,
                          fatG: _current?.fatG,
                          successMessage: loc.nutritionSettingsSaved,
                        ),
                      ),
                    ),
                    const _CardDivider(),
                    _ValueTile(
                      icon: Icons.fitness_center_outlined,
                      title: loc.nutritionProgressProtein,
                      subtitle: loc.nutritionSettingsProteinSubtitle,
                      value: _current?.proteinG,
                      formatValue: (v) =>
                          loc.nutritionSettingsGramsValue(_formatNum(v)),
                      notSetText: loc.nutritionSettingsNotSet,
                      onTap: () => _editNumericValue(
                        title: loc.nutritionSettingsEditProteinTitle,
                        currentValue: _current?.proteinG,
                        unit: 'g',
                        onSubmit: (v) => _saveGoalField(
                          calories: _current?.calories,
                          proteinG: v,
                          carbsG: _current?.carbsG,
                          fatG: _current?.fatG,
                          successMessage: loc.nutritionSettingsSaved,
                        ),
                      ),
                    ),
                    const _CardDivider(),
                    _ValueTile(
                      icon: Icons.grain_outlined,
                      title: loc.nutritionProgressCarbs,
                      subtitle: loc.nutritionSettingsCarbsSubtitle,
                      value: _current?.carbsG,
                      formatValue: (v) =>
                          loc.nutritionSettingsGramsValue(_formatNum(v)),
                      notSetText: loc.nutritionSettingsNotSet,
                      onTap: () => _editNumericValue(
                        title: loc.nutritionSettingsEditCarbsTitle,
                        currentValue: _current?.carbsG,
                        unit: 'g',
                        onSubmit: (v) => _saveGoalField(
                          calories: _current?.calories,
                          proteinG: _current?.proteinG,
                          carbsG: v,
                          fatG: _current?.fatG,
                          successMessage: loc.nutritionSettingsSaved,
                        ),
                      ),
                    ),
                    const _CardDivider(),
                    _ValueTile(
                      icon: Icons.opacity_outlined,
                      title: loc.nutritionProgressFat,
                      subtitle: loc.nutritionSettingsFatSubtitle,
                      value: _current?.fatG,
                      formatValue: (v) =>
                          loc.nutritionSettingsGramsValue(_formatNum(v)),
                      notSetText: loc.nutritionSettingsNotSet,
                      onTap: () => _editNumericValue(
                        title: loc.nutritionSettingsEditFatTitle,
                        currentValue: _current?.fatG,
                        unit: 'g',
                        onSubmit: (v) => _saveGoalField(
                          calories: _current?.calories,
                          proteinG: _current?.proteinG,
                          carbsG: _current?.carbsG,
                          fatG: v,
                          successMessage: loc.nutritionSettingsSaved,
                        ),
                      ),
                    ),
                  ],
                ),
                _SectionHeader(text: loc.nutritionSettingsSectionTools),
                _SettingsCard(
                  children: [
                    _LinkTile(
                      icon: Icons.calculate_outlined,
                      iconColor: theme.colorScheme.primary,
                      title: loc.nutritionSettingsSuggestSection,
                      subtitle: loc.nutritionSettingsSuggestBody,
                      onTap: _openSuggestion,
                    ),
                  ],
                ),
                _SectionHeader(text: loc.nutritionSettingsSectionMeals),
                _SettingsCard(
                  children: [
                    if (_mealTypes.isEmpty)
                      _EmptyHint(
                        icon: Icons.restaurant_outlined,
                        text: loc.nutritionSettingsMealTypeEmpty,
                      )
                    else
                      for (var i = 0; i < _mealTypes.length; i++) ...[
                        _MealTypeRow(
                          type: _mealTypes[i],
                          onTap: () => _openMealActions(_mealTypes[i], i),
                        ),
                        if (i < _mealTypes.length - 1) const _CardDivider(),
                      ],
                    if (_mealTypes.isNotEmpty) const _CardDivider(),
                    _LinkTile(
                      icon: Icons.add_circle_outline,
                      iconColor: theme.colorScheme.primary,
                      title: loc.nutritionAddMeal,
                      onTap: _addMealType,
                    ),
                  ],
                ),
                if (_current != null) ...[
                  _SectionHeader(text: loc.nutritionSettingsSectionDanger),
                  _SettingsCard(
                    children: [
                      _LinkTile(
                        icon: Icons.delete_outline,
                        iconColor: theme.colorScheme.error,
                        titleColor: theme.colorScheme.error,
                        title: loc.nutritionSettingsClear,
                        subtitle: loc.nutritionSettingsGoalRemoveSubtitle,
                        onTap: _clearGoal,
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}

// =====================================================================
// Shared visual primitives (mirrors the pattern from settings_screen.dart)
// =====================================================================

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      endIndent: 16,
      color: Theme.of(context).colorScheme.outlineVariant.withAlpha(60),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? titleColor;

  const _LinkTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = titleColor ?? theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (iconColor ?? theme.colorScheme.primary).withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: iconColor ?? theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: fg,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Row showing a value with a chevron. Tapping opens an editor. When
/// [value] is null the row reads "[notSetText]" in muted text so the
/// user immediately sees which fields still need attention.
class _ValueTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final double? value;
  final String Function(double) formatValue;
  final String notSetText;
  final VoidCallback onTap;

  const _ValueTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.formatValue,
    required this.notSetText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasValue = value != null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              hasValue ? formatValue(value!) : notSetText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: hasValue
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact row showing a configured meal type. Tap to open the actions
/// sheet (rename / delete / move).
class _MealTypeRow extends StatelessWidget {
  final MealTypeDefinition type;
  final VoidCallback onTap;

  const _MealTypeRow({required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.restaurant_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                type.displayName(loc),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.more_horiz,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline empty-state row used inside a card (no surrounding card).
class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Icon(
            icon,
            color: theme.colorScheme.onSurfaceVariant,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact summary card showing the calorie headline + macro split bars.
/// Replaces the previous full-size preview block so the screen starts
/// with a single dense overview instead of two stacked cards.
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
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
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
                size: 20,
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
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.pie_chart_outline_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    loc.nutritionSettingsPreviewLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (headline != null)
                Text(
                  loc.nutritionConsumedKcal(_formatNum(headline)),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
              if (macroTotal > 0) ...[
                const SizedBox(height: 12),
                _MacroBar(
                  label: loc.nutritionProgressProtein,
                  value: proteinKcal,
                  total: macroTotal,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(height: 6),
                _MacroBar(
                  label: loc.nutritionProgressCarbs,
                  value: carbsKcal,
                  total: macroTotal,
                  color: theme.colorScheme.secondary,
                ),
                const SizedBox(height: 6),
                _MacroBar(
                  label: loc.nutritionProgressFat,
                  value: fatKcal,
                  total: macroTotal,
                  color: theme.colorScheme.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _formatNum(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }
}

class _MacroBar extends StatelessWidget {
  final String label;
  final double value;
  final double total;
  final Color color;

  const _MacroBar({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = total > 0
        ? (value / total).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final percent = total > 0 ? '${((value / total) * 100).round()}%' : '—';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
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
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 4,
            backgroundColor: color.withAlpha(40),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// Bottom sheets
// =====================================================================

/// Bottom sheet used to edit one numeric goal value (calories, protein,
/// carbs or fat). Submitting an empty field is treated as "clear this
/// target" and resolves to null.
class _NumberEditorSheet extends StatefulWidget {
  final String title;
  final String unit;
  final double? initial;

  const _NumberEditorSheet({
    required this.title,
    required this.unit,
    required this.initial,
  });

  @override
  State<_NumberEditorSheet> createState() => _NumberEditorSheetState();
}

class _NumberEditorSheetState extends State<_NumberEditorSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial != null ? _format(widget.initial!) : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  void _submit() {
    final loc = AppLocalizations.of(context)!;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop(null);
      return;
    }
    final cleaned = text.replaceAll(',', '.');
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.nutritionInvalidNumber)),
      );
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      color: theme.colorScheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  hintText: loc.nutritionSettingsEditHint,
                  suffixText: widget.unit,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _submit,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(loc.nutritionSave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet that exposes the rename / move / delete actions for a
/// meal type. Replaces the inline row of action buttons previously used
/// in this screen.
class _MealActionsSheet extends StatelessWidget {
  final MealTypeDefinition type;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final String titleOverride;

  const _MealActionsSheet({
    required this.type,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onRename,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.titleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(
              children: [
                Icon(
                  Icons.restaurant_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.nutritionSettingsMealActionsTitle(
                      type.displayName(loc),
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                titleOverride,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          _ActionRow(
            icon: Icons.edit_outlined,
            label: loc.nutritionSettingsMealActionRename,
            onTap: () {
              Navigator.of(context).pop();
              onRename();
            },
          ),
          _ActionRow(
            icon: Icons.arrow_upward,
            label: loc.nutritionSettingsMealActionMoveUp,
            enabled: canMoveUp,
            onTap: () {
              Navigator.of(context).pop();
              onMoveUp();
            },
          ),
          _ActionRow(
            icon: Icons.arrow_downward,
            label: loc.nutritionSettingsMealActionMoveDown,
            enabled: canMoveDown,
            onTap: () {
              Navigator.of(context).pop();
              onMoveDown();
            },
          ),
          _ActionRow(
            icon: Icons.delete_outline,
            label: loc.nutritionSettingsMealActionDelete,
            destructive: true,
            onTap: () {
              Navigator.of(context).pop();
              onDelete();
            },
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool destructive;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = !enabled
        ? theme.colorScheme.outline
        : (destructive ? theme.colorScheme.error : theme.colorScheme.onSurface);
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge?.copyWith(color: color),
              ),
            ),
            if (!enabled)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '—',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
          ],
        ),
      ),
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