import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'package:workout_notes/utils/nutrition_goal_suggest.dart';
import 'package:workout_notes/widgets/settings/settings.dart';

import 'nutrition_goal_suggest_sheet.dart';
import 'periodization_home_screen.dart';

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
  EffectiveNutritionGoal _effective = const EffectiveNutritionGoal();
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
        // Detects whether an active plan is overriding the settings goal.
        EffectiveNutritionGoalService.resolve(
          nutritionRepository: widget.repository,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _current = results[0] as NutritionGoal?;
        _mealTypes = results[1] as List<MealTypeDefinition>;
        _effective = results[2] as EffectiveNutritionGoal;
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
    double? tdee,
    String? adjustmentKind,
    double? adjustmentPercent,
    String? successMessage,
  }) async {
    final loc = AppLocalizations.of(context)!;
    try {
      final goal = await widget.repository.saveGoal(
        calories: calories,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        tdee: tdee,
        adjustmentKind: adjustmentKind,
        adjustmentPercent: adjustmentPercent,
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
      onApply: (suggestion) async {
        if (!mounted) return;
        // The suggest tool only computes the maintenance expenditure;
        // the deficit/surplus adjustment is owned by this screen, so the
        // current one is preserved (defaulting to maintenance).
        final current = _current;
        await _saveTdeeGoal(
          tdee: suggestion.tdee,
          adjustmentKind:
              current?.adjustmentKind ?? NutritionObjective.maintenance.name,
          adjustmentPercent: current?.adjustmentPercent ?? 0,
          proteinG: suggestion.proteinG,
          carbsG: suggestion.carbsG,
          fatG: suggestion.fatG,
          successMessage: AppLocalizations.of(context)!.nutritionSettingsGoalApplied,
        );
      },
    );
  }

  // ===================================================================
  // TDEE goal
  // ===================================================================

  Future<void> _editTdee({required double? currentTdee}) async {
    final loc = AppLocalizations.of(context)!;
    final result = await _openNumberEditor(
      title: loc.nutritionSettingsEditTdeeTitle,
      unit: 'kcal',
      initial: currentTdee,
    );
    if (result == _kUnchanged) return;
    final newTdee = result as double?;
    final current = _current;
    if (current != null) {
      await _saveTdeeGoal(
        tdee: newTdee,
        adjustmentKind: current.adjustmentKind,
        adjustmentPercent: current.adjustmentPercent,
        proteinG: current.proteinG,
        carbsG: current.carbsG,
        fatG: current.fatG,
        successMessage: loc.nutritionSettingsSaved,
      );
    } else if (newTdee != null) {
      await _saveTdeeGoal(
        tdee: newTdee,
        adjustmentKind: NutritionObjective.maintenance.name,
        adjustmentPercent: 0,
        successMessage: loc.nutritionSettingsSaved,
      );
    }
  }

  Future<void> _openAdjustmentPicker() async {
    final current = _current;
    if (current == null) return;
    final picked = await showModalBottomSheet<_AdjustmentDraft>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _AdjustmentPickerSheet(
        tdee: current.tdee,
        initialPercent: current.adjustmentPercent ?? 0,
      ),
    );
    if (picked == null || !mounted) return;
    await _saveTdeeGoal(
      tdee: current.tdee,
      adjustmentKind: NutritionAdjustment.kindForPercent(picked.percent).name,
      adjustmentPercent: picked.percent,
      proteinG: current.proteinG,
      carbsG: current.carbsG,
      fatG: current.fatG,
      successMessage: AppLocalizations.of(context)!.nutritionSettingsSaved,
    );
  }

  Future<void> _saveTdeeGoal({
    required double? tdee,
    required String? adjustmentKind,
    required double? adjustmentPercent,
    double? proteinG,
    double? carbsG,
    double? fatG,
    String? successMessage,
  }) async {
    final loc = AppLocalizations.of(context)!;
    try {
      // Carbohydrates always absorb the energy left by protein and fat,
      // so a TDEE or adjustment change re-derives them to keep the
      // macro split consistent with the goal.
      final goalKcal = (tdee != null && tdee > 0 && adjustmentPercent != null)
          ? tdee * (1 + adjustmentPercent / 100)
          : null;
      final resolvedCarbs = (goalKcal != null && proteinG != null && fatG != null)
          ? ((goalKcal - proteinG * 4 - fatG * 9) / 4)
                .clamp(0, double.infinity)
                .roundToDouble()
          : carbsG;
      final goal = await widget.repository.saveGoal(
        tdee: tdee,
        adjustmentKind: adjustmentKind,
        adjustmentPercent: adjustmentPercent,
        proteinG: proteinG,
        carbsG: resolvedCarbs,
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
      appBar: SettingsAppBar(title: loc.nutritionSettingsTitle),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _GoalPreviewCard(
                  tdee: _current?.tdee,
                  adjustmentKind: _current?.adjustmentKind,
                  adjustmentPercent: _current?.adjustmentPercent,
                  calories: _current?.effectiveCalories,
                  proteinG: _current?.proteinG,
                  carbsG: _current?.carbsG,
                  fatG: _current?.fatG,
                ),
                if (_effective.fromPlan)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 4),
                    child: _PlanOverrideBanner(planInfo: _effective),
                  ),
                SettingsSectionHeader(text: loc.nutritionSettingsSectionDaily),
                SettingsCard(
                  children: [
                    SettingsValueTile(
                      icon: Icons.local_fire_department_outlined,
                      title: loc.nutritionGoalTdee,
                      subtitle: loc.nutritionSettingsTdeeSubtitle,
                      value: _current?.tdee,
                      formatValue: (v) =>
                          loc.nutritionConsumedKcal(_formatNum(v)),
                      notSetText: loc.nutritionSettingsNotSet,
                      onTap: () => _editTdee(currentTdee: _current?.tdee),
                    ),
                    const SettingsCardDivider(),
                    SettingsValueTile(
                      icon: Icons.tune_rounded,
                      title: loc.nutritionGoalAdjustment,
                      subtitle: _adjustmentSubtitle(loc),
                      value: _current?.calories,
                      formatValue: (v) =>
                          loc.nutritionConsumedKcal(_formatNum(v)),
                      notSetText: loc.nutritionSettingsNotSet,
                      onTap: _openAdjustmentPicker,
                    ),
                    const SettingsCardDivider(),
                    SettingsValueTile(
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
                          tdee: _current?.tdee,
                          adjustmentKind: _current?.adjustmentKind,
                          adjustmentPercent: _current?.adjustmentPercent,
                          proteinG: v,
                          carbsG: _current?.carbsG,
                          fatG: _current?.fatG,
                          successMessage: loc.nutritionSettingsSaved,
                        ),
                      ),
                    ),
                    const SettingsCardDivider(),
                    SettingsValueTile(
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
                          tdee: _current?.tdee,
                          adjustmentKind: _current?.adjustmentKind,
                          adjustmentPercent: _current?.adjustmentPercent,
                          proteinG: _current?.proteinG,
                          carbsG: v,
                          fatG: _current?.fatG,
                          successMessage: loc.nutritionSettingsSaved,
                        ),
                      ),
                    ),
                    const SettingsCardDivider(),
                    SettingsValueTile(
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
                          tdee: _current?.tdee,
                          adjustmentKind: _current?.adjustmentKind,
                          adjustmentPercent: _current?.adjustmentPercent,
                          proteinG: _current?.proteinG,
                          carbsG: _current?.carbsG,
                          fatG: v,
                          successMessage: loc.nutritionSettingsSaved,
                        ),
                      ),
                    ),
                  ],
                ),
                SettingsSectionHeader(text: loc.nutritionSettingsSectionTools),
                SettingsCard(
                  children: [
                    SettingsLinkTile(
                      icon: Icons.calculate_outlined,
                      iconColor: theme.colorScheme.primary,
                      title: loc.nutritionSettingsSuggestSection,
                      subtitle: loc.nutritionSettingsSuggestBody,
                      onTap: _openSuggestion,
                    ),
                  ],
                ),
                SettingsSectionHeader(text: loc.nutritionSettingsSectionMeals),
                SettingsCard(
                  children: [
                    if (_mealTypes.isEmpty)
                      SettingsEmptyHint(
                        icon: Icons.restaurant_outlined,
                        text: loc.nutritionSettingsMealTypeEmpty,
                      )
                    else
                      for (var i = 0; i < _mealTypes.length; i++) ...[
                        _MealTypeRow(
                          type: _mealTypes[i],
                          onTap: () => _openMealActions(_mealTypes[i], i),
                        ),
                        if (i < _mealTypes.length - 1) const SettingsCardDivider(),
                      ],
                    if (_mealTypes.isNotEmpty) const SettingsCardDivider(),
                    SettingsLinkTile(
                      icon: Icons.add_circle_outline,
                      iconColor: theme.colorScheme.primary,
                      title: loc.nutritionAddMeal,
                      onTap: _addMealType,
                    ),
                  ],
                ),
                if (_current != null) ...[
                  SettingsSectionHeader(text: loc.nutritionSettingsSectionDanger),
                  SettingsCard(
                    children: [
                      SettingsLinkTile(
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

  String _adjustmentSubtitle(AppLocalizations loc) {
    final current = _current;
    if (current == null) return loc.nutritionGoalAdjustmentNotSet;
    final kind = _parseAdjustmentKind(current.adjustmentKind);
    final percent = current.adjustmentPercent;
    final kindLabel = _adjustmentKindLabel(loc, kind);
    final percentLabel = percent == null
        ? ''
        : ' · ${_formatPercent(percent)}';
    return '$kindLabel$percentLabel';
  }

  static NutritionObjective _parseAdjustmentKind(String? raw) {
    return NutritionObjective.values.firstWhere(
      (o) => o.name == raw,
      orElse: () => NutritionObjective.maintenance,
    );
  }

  static String _adjustmentKindLabel(
    AppLocalizations loc,
    NutritionObjective kind,
  ) {
    switch (kind) {
      case NutritionObjective.cut:
        return loc.nutritionSuggestObjectiveCut;
      case NutritionObjective.maintenance:
        return loc.nutritionSuggestObjectiveMaintenance;
      case NutritionObjective.bulk:
        return loc.nutritionSuggestObjectiveBulk;
    }
  }

  static String _formatPercent(double percent) {
    final rounded = percent.round();
    if (rounded > 0) return '+${rounded.toStringAsFixed(0)}%';
    return '${rounded.toStringAsFixed(0)}%';
  }
}

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

/// Compact summary card showing the calorie headline + macro split bars.
/// Replaces the previous full-size preview block so the screen starts
/// with a single dense overview instead of two stacked cards.
class _GoalPreviewCard extends StatelessWidget {
  final double? calories;
  final double? tdee;
  final double? adjustmentPercent;
  final String? adjustmentKind;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;

  const _GoalPreviewCard({
    this.calories,
    this.tdee,
    this.adjustmentPercent,
    this.adjustmentKind,
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
              if (headline != null) ...[
                Text(
                  loc.nutritionPreviewGoal(_formatNum(headline)),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              if (tdee != null)
                Text(
                  loc.nutritionPreviewTdee(_formatNum(tdee!)),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (tdee != null && adjustmentPercent != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _relationshipLabel(loc),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
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

  String _relationshipLabel(AppLocalizations loc) {
    final kind = NutritionObjective.values.firstWhere(
      (o) => o.name == adjustmentKind,
      orElse: () => NutritionObjective.maintenance,
    );
    final kindLabel = _kindLabel(loc, kind);
    final percent = adjustmentPercent!;
    final signed = percent == 0
        ? '0%'
        : (percent > 0 ? '+${percent.round()}%' : '${percent.round()}%');
    return loc.nutritionPreviewRelationship(kindLabel, signed);
  }

  static String _kindLabel(AppLocalizations loc, NutritionObjective kind) {
    switch (kind) {
      case NutritionObjective.cut:
        return loc.nutritionSuggestObjectiveCut;
      case NutritionObjective.maintenance:
        return loc.nutritionSuggestObjectiveMaintenance;
      case NutritionObjective.bulk:
        return loc.nutritionSuggestObjectiveBulk;
    }
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
          SettingsActionRow(
            icon: Icons.edit_outlined,
            label: loc.nutritionSettingsMealActionRename,
            onTap: () {
              Navigator.of(context).pop();
              onRename();
            },
          ),
          SettingsActionRow(
            icon: Icons.arrow_upward,
            label: loc.nutritionSettingsMealActionMoveUp,
            enabled: canMoveUp,
            onTap: () {
              Navigator.of(context).pop();
              onMoveUp();
            },
          ),
          SettingsActionRow(
            icon: Icons.arrow_downward,
            label: loc.nutritionSettingsMealActionMoveDown,
            enabled: canMoveDown,
            onTap: () {
              Navigator.of(context).pop();
              onMoveDown();
            },
          ),
          SettingsActionRow(
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

/// Lightweight payload for the adjustment picker bottom sheet. The kind
/// is derived from the percent sign (negative = cut, zero = maintenance,
/// positive = bulk), so the two can never disagree.
class _AdjustmentDraft {
  final double percent;
  const _AdjustmentDraft({required this.percent});
}

/// Bottom sheet that defines the deficit/surplus adjustment applied to
/// the user's TDEE — this adjustment IS the daily calorie goal. The
/// preset buttons set the default percent for each kind and the field
/// accepts any signed value for fine-tuning (e.g. −15%).
class _AdjustmentPickerSheet extends StatefulWidget {
  final double? tdee;
  final double initialPercent;

  const _AdjustmentPickerSheet({
    required this.tdee,
    required this.initialPercent,
  });

  @override
  State<_AdjustmentPickerSheet> createState() => _AdjustmentPickerSheetState();
}

class _AdjustmentPickerSheetState extends State<_AdjustmentPickerSheet> {
  late final TextEditingController _percentController;

  @override
  void initState() {
    super.initState();
    _percentController = TextEditingController(
      text: _formatPercentForEdit(widget.initialPercent),
    );
  }

  @override
  void dispose() {
    _percentController.dispose();
    super.dispose();
  }

  void _applyPreset(NutritionObjective kind) {
    setState(() {
      _percentController.text = _formatPercentForEdit(
        NutritionAdjustment.defaultsFor(kind).percent,
      );
    });
  }

  double get _percent {
    final raw = _percentController.text.trim().replaceAll(',', '.');
    return double.tryParse(raw) ?? 0;
  }

  double? get _previewGoal {
    final tdee = widget.tdee;
    if (tdee == null || tdee <= 0) return null;
    return tdee * (1 + _percent / 100);
  }

  void _submit() {
    Navigator.of(context).pop(_AdjustmentDraft(percent: _percent));
  }

  static String _formatPercentForEdit(double percent) {
    if (percent == percent.roundToDouble()) return percent.toStringAsFixed(0);
    return percent.toStringAsFixed(1);
  }

  static String _formatGoal(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  static String _formatPercentLabel(double percent) {
    final rounded = percent.round();
    if (rounded > 0) return '+${rounded.toStringAsFixed(0)}%';
    return '${rounded.toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final percent = _percent;
    final previewGoal = _previewGoal;
    final derivedKind = NutritionAdjustment.kindForPercent(percent);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
                      Icons.tune_rounded,
                      color: theme.colorScheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loc.nutritionSettingsAdjustmentTitle,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  for (final option in NutritionObjective.values) ...[
                    Expanded(
                      child: _AdjustmentOptionButton(
                        kind: option,
                        selected: derivedKind == option,
                        onTap: () => _applyPreset(option),
                      ),
                    ),
                    if (option != NutritionObjective.values.last)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _percentController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d\-.,]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: loc.nutritionSettingsAdjustmentPercent,
                  suffixText: '%',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
              ),
              if (previewGoal != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withAlpha(120),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          loc.nutritionGoalDerivedFromTdee(
                            _formatGoal(previewGoal),
                            _formatGoal(widget.tdee!),
                            _formatPercentLabel(percent),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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

class _AdjustmentOptionButton extends StatelessWidget {
  final NutritionObjective kind;
  final bool selected;
  final VoidCallback onTap;

  const _AdjustmentOptionButton({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  static String _label(AppLocalizations loc, NutritionObjective kind) {
    switch (kind) {
      case NutritionObjective.cut:
        return loc.nutritionSuggestObjectiveCut;
      case NutritionObjective.maintenance:
        return loc.nutritionSuggestObjectiveMaintenance;
      case NutritionObjective.bulk:
        return loc.nutritionSuggestObjectiveBulk;
    }
  }

  static String _defaultPercent(NutritionObjective kind) {
    final adjusted = NutritionAdjustment.defaultsFor(kind);
    final rounded = adjusted.percent.round();
    if (rounded > 0) return '+${rounded.toStringAsFixed(0)}%';
    return '${rounded.toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final fg = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withAlpha(70),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Column(
            children: [
              Text(
                _label(loc, kind),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                _defaultPercent(kind),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: fg.withAlpha(190),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner shown when an active periodization plan's current week is
/// overriding the goal configured here. Tapping opens the plan.
class _PlanOverrideBanner extends StatelessWidget {
  final EffectiveNutritionGoal planInfo;

  const _PlanOverrideBanner({required this.planInfo});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final phase = planInfo.phase!;
    final color = Color(phase.color);
    return Material(
      color: color.withAlpha(30),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const PeriodizationHomeScreen(),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Icon(Icons.event_note_rounded, size: 20, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  loc.nutritionSettingsPlanOverrideBanner(
                    phase.name,
                    planInfo.weekNumber ?? 1,
                    planInfo.totalWeeks ?? 1,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
