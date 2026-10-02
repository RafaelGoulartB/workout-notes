import 'package:flutter/material.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/nutrition/nutrition_goal_suggest_sheet.dart';
import 'package:workout_notes/screens/nutrition/nutrition_settings_controller.dart';
import 'package:workout_notes/utils/nutrition_goal_suggest.dart';
import 'package:workout_notes/widgets/nutrition/settings/goal_preview_card.dart';
import 'package:workout_notes/widgets/nutrition/settings/meal_type_widgets.dart';
import 'package:workout_notes/widgets/nutrition/settings/nutrition_settings_sheets.dart';
import 'package:workout_notes/widgets/settings/settings.dart';
import 'package:workout_notes/widgets/ui/load_error_view.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

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
  final _bodyRepo = DatabaseHelper.instance.bodyMeasurementRepo;
  final _settingsRepo = DatabaseHelper.instance.settingsRepo;
  late final NutritionSettingsController _controller;

  NutritionGoal? get _current => _controller.current;

  @override
  void initState() {
    super.initState();
    _controller = NutritionSettingsController(repository: widget.repository);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      await _controller.saveGoalField(
        calories: calories,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        tdee: tdee,
        adjustmentKind: adjustmentKind,
        adjustmentPercent: adjustmentPercent,
      );
      if (!mounted) return;
      if (successMessage != null) showAppSnack(context, successMessage);
    } catch (e, stack) {
      debugPrint('nutrition_settings_screen: action failed: $e\n$stack');
      if (!mounted) return;
      showAppSnack(context, loc.commonSomethingWentWrong);
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
    if (result == null) return;
    onSubmit(result.$1);
  }

  Future<void> _clearGoal() async {
    final loc = AppLocalizations.of(context)!;
    final confirm = await showConfirmDialog(
      context,
      title: loc.nutritionSettingsClear,
      message: loc.nutritionSettingsClear,
      confirmLabel: loc.commonDelete,
      cancelLabel: loc.nutritionCancel,
      destructive: true,
    );
    if (confirm != true) return;
    await _controller.clearGoal();
    if (!mounted) return;
    showAppSnack(context, loc.nutritionSettingsCleared);
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
          successMessage: AppLocalizations.of(
            context,
          )!.nutritionSettingsGoalApplied,
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
    if (result == null) return;
    final newTdee = result.$1;
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
    final picked = await showModalBottomSheet<AdjustmentDraft>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => AdjustmentPickerSheet(
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
      await _controller.saveTdeeGoal(
        tdee: tdee,
        adjustmentKind: adjustmentKind,
        adjustmentPercent: adjustmentPercent,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
      );
      if (!mounted) return;
      if (successMessage != null) showAppSnack(context, successMessage);
    } catch (e, stack) {
      debugPrint('nutrition_settings_screen: action failed: $e\n$stack');
      if (!mounted) return;
      showAppSnack(context, loc.commonSomethingWentWrong);
    }
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
      await _controller.addMealType(name);
      if (!mounted) return;
      showAppSnack(context, loc.nutritionMealAdded);
    } catch (e, stack) {
      debugPrint('nutrition_settings_screen: action failed: $e\n$stack');
      if (!mounted) return;
      showAppSnack(context, loc.commonSomethingWentWrong);
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
      await _controller.renameMealType(type, name);
    } catch (e, stack) {
      debugPrint('nutrition_settings_screen: action failed: $e\n$stack');
      if (!mounted) return;
      showAppSnack(context, loc.commonSomethingWentWrong);
    }
  }

  Future<void> _deleteMealType(MealTypeDefinition type) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: loc.nutritionDeleteMeal,
      message: loc.nutritionMealTypeDeleteConfirm(type.displayName(loc)),
      confirmLabel: loc.commonDelete,
      cancelLabel: loc.nutritionCancel,
      destructive: true,
    );
    if (confirmed != true) return;
    if (!mounted) return;
    try {
      await _controller.deleteMealType(type);
    } catch (e, stack) {
      debugPrint('nutrition_settings_screen: action failed: $e\n$stack');
      if (!mounted) return;
      showAppSnack(context, loc.commonSomethingWentWrong);
    }
  }

  Future<void> _openMealActions(MealTypeDefinition type, int index) async {
    final loc = AppLocalizations.of(context)!;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => MealActionsSheet(
        type: type,
        canMoveUp: index > 0,
        canMoveDown: index < _controller.mealTypes.length - 1,
        onRename: () => _renameMealType(type),
        onDelete: () => _deleteMealType(type),
        onMoveUp: () => _controller.moveMealType(type, -1),
        onMoveDown: () => _controller.moveMealType(type, 1),
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
      builder: (ctx) => MealTypeNameDialog(title: title, initial: initial),
    );
  }

  // ===================================================================
  // Helpers
  // ===================================================================

  /// Resolves to null when the sheet is dismissed without saving, otherwise
  /// to `(value,)` where a null value clears the target.
  Future<(double?,)?> _openNumberEditor({
    required String title,
    required String unit,
    required double? initial,
  }) {
    return showModalBottomSheet<(double?,)>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) =>
          NumberEditorSheet(title: title, unit: unit, initial: initial),
    );
  }

  static String _formatNum(double value) =>
      NutritionSettingsController.formatNum(value);

  // ===================================================================
  // Build
  // ===================================================================

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: SettingsAppBar(title: loc.nutritionSettingsTitle),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          if (_controller.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_controller.loadFailed) {
            return LoadErrorView(onRetry: _controller.load);
          }
          final effective = _controller.effective;
          final mealTypes = _controller.mealTypes;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              GoalPreviewCard(
                label: effective.fromPlan
                    ? loc.nutritionSettingsBasePreviewLabel
                    : loc.nutritionSettingsPreviewLabel,
                tdee: _current?.tdee,
                adjustmentKind: _current?.adjustmentKind,
                adjustmentPercent: _current?.adjustmentPercent,
                calories: _current?.effectiveCalories,
                proteinG: _current?.proteinG,
                carbsG: _current?.carbsG,
                fatG: _current?.fatG,
              ),
              if (effective.fromPlan)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: PlanOverrideBanner(planInfo: effective),
                ),
              AppSectionHeader(loc.nutritionSettingsSectionDaily, padding: AppSectionHeader.compactPadding),
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
              AppSectionHeader(loc.nutritionSettingsSectionTools, padding: AppSectionHeader.compactPadding),
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
              AppSectionHeader(loc.nutritionSettingsSectionMeals, padding: AppSectionHeader.compactPadding),
              SettingsCard(
                children: [
                  if (mealTypes.isEmpty)
                    SettingsEmptyHint(
                      icon: Icons.restaurant_outlined,
                      text: loc.nutritionSettingsMealTypeEmpty,
                    )
                  else
                    for (var i = 0; i < mealTypes.length; i++) ...[
                      MealTypeRow(
                        type: mealTypes[i],
                        onTap: () => _openMealActions(mealTypes[i], i),
                      ),
                      if (i < mealTypes.length - 1) const SettingsCardDivider(),
                    ],
                  if (mealTypes.isNotEmpty) const SettingsCardDivider(),
                  SettingsLinkTile(
                    icon: Icons.add_circle_outline,
                    iconColor: theme.colorScheme.primary,
                    title: loc.nutritionAddMeal,
                    onTap: _addMealType,
                  ),
                ],
              ),
              if (_current != null) ...[
                AppSectionHeader(loc.nutritionSettingsSectionDanger, padding: AppSectionHeader.compactPadding),
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
          );
        },
      ),
    );
  }

  String _adjustmentSubtitle(AppLocalizations loc) {
    final current = _current;
    if (current == null) return loc.nutritionGoalAdjustmentNotSet;
    final kind = NutritionSettingsController.parseAdjustmentKind(
      current.adjustmentKind,
    );
    final percent = current.adjustmentPercent;
    final kindLabel = _adjustmentKindLabel(loc, kind);
    final percentLabel = percent == null
        ? ''
        : ' · ${NutritionSettingsController.formatPercent(percent)}';
    return '$kindLabel$percentLabel';
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
}
