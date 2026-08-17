import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/utils/nutrition_goal_suggest.dart';

/// Callback invoked when the user applies the suggestion. The
/// suggestion always carries the maintenance expenditure (TDEE) and
/// its macro split; the deficit/surplus adjustment is configured
/// separately in the nutrition settings.
typedef NutritionGoalApplyCallback =
    void Function(NutritionGoalSuggestion suggestion);

/// Bottom sheet that estimates the maintenance daily calories (TDEE)
/// and macros from the body profile using the Mifflin-St Jeor equation.
/// The profile is persisted in `app_settings` under the
/// `nutrition_profile_*` keys and the final values are handed back to
/// the caller via [onApply].
class NutritionGoalSuggestSheet extends StatefulWidget {
  final BodyMeasurementRepository bodyRepo;
  final SettingsRepository settingsRepo;
  final NutritionGoalApplyCallback onApply;

  const NutritionGoalSuggestSheet({
    super.key,
    required this.bodyRepo,
    required this.settingsRepo,
    required this.onApply,
  });

  static Future<void> show(
    BuildContext context, {
    required BodyMeasurementRepository bodyRepo,
    required SettingsRepository settingsRepo,
    required NutritionGoalApplyCallback onApply,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.9,
        child: NutritionGoalSuggestSheet(
          bodyRepo: bodyRepo,
          settingsRepo: settingsRepo,
          onApply: onApply,
        ),
      ),
    );
  }

  @override
  State<NutritionGoalSuggestSheet> createState() =>
      _NutritionGoalSuggestSheetState();
}

class _NutritionGoalSuggestSheetState extends State<NutritionGoalSuggestSheet> {
  static const _kSex = 'nutrition_profile_sex';
  static const _kAge = 'nutrition_profile_age';
  static const _kHeight = 'nutrition_profile_height_cm';
  static const _kWeight = 'nutrition_profile_weight_kg';
  static const _kActivity = 'nutrition_profile_activity';
  static const _kMacroProtein = 'nutrition_profile_macro_protein_g_kg';
  static const _kMacroFat = 'nutrition_profile_macro_fat_g_kg';
  // Pre-objective-removal sheet stored one ratio pair per objective; the
  // maintenance pair is the closest ancestor of the single ratio pair.
  static const _kLegacyMacroProtein =
      'nutrition_profile_macro_maintenance_protein_g_kg';
  static const _kLegacyMacroFat =
      'nutrition_profile_macro_maintenance_fat_g_kg';

  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _MacroRatioControllers _macroControllers =
      _MacroRatioControllers.defaults();

  bool _isLoading = true;
  bool _isMale = true;
  ActivityLevel _activity = ActivityLevel.moderate;
  NutritionGoalSuggestion? _suggestion;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _macroControllers.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final results = await Future.wait([
        widget.bodyRepo.getLatestWeightKg(),
        widget.settingsRepo.getSetting(_kSex),
        widget.settingsRepo.getSetting(_kAge),
        widget.settingsRepo.getSetting(_kHeight),
        widget.settingsRepo.getSetting(_kWeight),
        widget.settingsRepo.getSetting(_kActivity),
        widget.settingsRepo.getSetting(_kMacroProtein),
        widget.settingsRepo.getSetting(_kMacroFat),
        widget.settingsRepo.getSetting(_kLegacyMacroProtein),
        widget.settingsRepo.getSetting(_kLegacyMacroFat),
      ]);
      final latestWeight = results[0] as double?;
      final sex = results[1] as String?;
      final age = results[2] as String?;
      final height = results[3] as String?;
      final savedWeight = results[4] as String?;
      final activity = results[5] as String?;
      if (!mounted) return;
      setState(() {
        _isMale = sex == null || sex == 'male';
        _ageController.text = age ?? '';
        _heightController.text = height ?? '';
        // The live body measurement wins over the saved profile value.
        _weightController.text =
            (latestWeight ?? double.tryParse(savedWeight ?? ''))?.toString() ??
            '';
        _activity = ActivityLevel.values.firstWhere(
          (a) => a.name == activity,
          orElse: () => ActivityLevel.moderate,
        );
        final protein = (results[6] as String?) ?? results[8] as String?;
        final fat = (results[7] as String?) ?? results[9] as String?;
        if (_parseNum(protein ?? '') != null) {
          _macroControllers.protein.text = protein!;
        }
        if (_parseNum(fat ?? '') != null) {
          _macroControllers.fat.text = fat!;
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
    _recompute();
  }

  double? get _age => _parseInt(_ageController.text);
  double? get _height => _parseNum(_heightController.text);
  double? get _weight => _parseNum(_weightController.text);

  NutritionMacroRatios? get _ratios {
    final protein = _parseNum(_macroControllers.protein.text);
    final fat = _parseNum(_macroControllers.fat.text);
    if (protein == null || fat == null) return null;
    return NutritionMacroRatios(proteinPerKg: protein, fatPerKg: fat);
  }

  bool get _hasCompleteProfile =>
      _age != null && _height != null && _weight != null;

  bool get _allRatiosValid => _ratios != null;

  bool get _hasMacroEnergyConflict {
    final age = _age;
    final height = _height;
    final weight = _weight;
    final ratios = _ratios;
    if (age == null || height == null || weight == null || ratios == null) {
      return false;
    }
    final suggestion = suggestNutritionGoal(
      weightKg: weight,
      heightCm: height,
      ageYears: age.toInt(),
      isMale: _isMale,
      activity: _activity,
      macroRatios: ratios,
    );
    return suggestion.proteinG * 4 + suggestion.fatG * 9 > suggestion.calories;
  }

  void _recompute() {
    final age = _age;
    final height = _height;
    final weight = _weight;
    final ratios = _ratios;
    if (age == null || height == null || weight == null || ratios == null) {
      setState(() => _suggestion = null);
      return;
    }
    setState(() {
      _suggestion = suggestNutritionGoal(
        weightKg: weight,
        heightCm: height,
        ageYears: age.toInt(),
        isMale: _isMale,
        activity: _activity,
        macroRatios: ratios,
      );
    });
  }

  void _restoreCurrentMacroDefaults() {
    final defaults = NutritionMacroRatios.defaults;
    _macroControllers.protein.text = _formatRatio(defaults.proteinPerKg);
    _macroControllers.fat.text = _formatRatio(defaults.fatPerKg);
    _recompute();
  }

  Future<void> _apply() async {
    final suggestion = _suggestion;
    final ratios = _ratios;
    if (suggestion == null || ratios == null || _hasMacroEnergyConflict) {
      return;
    }
    final loc = AppLocalizations.of(context)!;
    final settings = widget.settingsRepo;
    await settings.setSetting(_kSex, _isMale ? 'male' : 'female');
    await settings.setSetting(_kAge, _ageController.text.trim());
    await settings.setSetting(_kHeight, _heightController.text.trim());
    await settings.setSetting(_kWeight, _weightController.text.trim());
    await settings.setSetting(_kActivity, _activity.name);
    await settings.setSetting(
      _kMacroProtein,
      ratios.proteinPerKg.toString(),
    );
    await settings.setSetting(
      _kMacroFat,
      ratios.fatPerKg.toString(),
    );
    if (!mounted) return;
    widget.onApply(suggestion);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.nutritionSuggestApplied)));
  }

  static double? _parseNum(String raw) {
    final cleaned = raw.trim().replaceAll(',', '.');
    final value = double.tryParse(cleaned);
    if (value == null || value.isNaN || value.isInfinite || value <= 0) {
      return null;
    }
    return value;
  }

  static double? _parseInt(String raw) {
    final value = _parseNum(raw);
    if (value == null) return null;
    return value >= 1 ? value : null;
  }

  static String _formatRatio(double value) => value.toStringAsFixed(1);

  static String _activityLabel(AppLocalizations loc, ActivityLevel level) {
    switch (level) {
      case ActivityLevel.sedentary:
        return loc.nutritionSuggestActivitySedentary;
      case ActivityLevel.light:
        return loc.nutritionSuggestActivityLight;
      case ActivityLevel.moderate:
        return loc.nutritionSuggestActivityModerate;
      case ActivityLevel.active:
        return loc.nutritionSuggestActivityActive;
      case ActivityLevel.veryActive:
        return loc.nutritionSuggestActivityVeryActive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final canApply =
        _suggestion != null && _allRatiosValid && !_hasMacroEnergyConflict;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 12, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.nutritionSuggestTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      loc.nutritionSuggestSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              18,
              16,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SectionLabel(
                  icon: Icons.person_outline_rounded,
                  label: loc.nutritionSuggestProfileSection,
                ),
                const SizedBox(height: 8),
                _SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        loc.nutritionSuggestSex,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(
                            value: true,
                            label: Text(loc.nutritionSuggestSexMale),
                            icon: const Icon(Icons.male_rounded),
                          ),
                          ButtonSegment(
                            value: false,
                            label: Text(loc.nutritionSuggestSexFemale),
                            icon: const Icon(Icons.female_rounded),
                          ),
                        ],
                        selected: {_isMale},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) {
                          setState(() => _isMale = selection.first);
                          _recompute();
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _SheetNumberField(
                              controller: _ageController,
                              label: loc.nutritionSuggestAgeShort,
                              suffix: loc.nutritionSuggestYearsUnit,
                              onChanged: (_) => _recompute(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SheetNumberField(
                              controller: _heightController,
                              label: loc.nutritionSuggestHeightShort,
                              suffix: 'cm',
                              onChanged: (_) => _recompute(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SheetNumberField(
                              controller: _weightController,
                              label: loc.nutritionSuggestWeightShort,
                              suffix: 'kg',
                              onChanged: (_) => _recompute(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _SectionLabel(
                  icon: Icons.flag_outlined,
                  label: loc.nutritionSuggestPlanSection,
                ),
                const SizedBox(height: 8),
                _SurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        loc.nutritionSuggestActivity,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 7),
                      DropdownButtonFormField<ActivityLevel>(
                        initialValue: _activity,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.directions_run_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withAlpha(75),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        items: [
                          for (final level in ActivityLevel.values)
                            DropdownMenuItem(
                              value: level,
                              child: Text(_activityLabel(loc, level)),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _activity = value);
                          _recompute();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _MacroConfigurationCard(
                  controllers: _macroControllers,
                  onChanged: _recompute,
                  onRestore: _restoreCurrentMacroDefaults,
                ),
                if (!_allRatiosValid || _hasMacroEnergyConflict) ...[
                  const SizedBox(height: 8),
                  _InlineWarning(
                    message: !_allRatiosValid
                        ? loc.nutritionSuggestInvalidMacros
                        : loc.nutritionSuggestMacroEnergyError,
                  ),
                ],
                const SizedBox(height: 20),
                if (_suggestion == null && !_hasCompleteProfile)
                  _InlineInfo(message: loc.nutritionSuggestNoProfile)
                else if (_suggestion != null)
                  _SuggestionPreviewCard(suggestion: _suggestion!),
              ],
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            12 + MediaQuery.paddingOf(context).bottom,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withAlpha(20),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: FilledButton.icon(
            onPressed: canApply ? _apply : null,
            icon: const Icon(Icons.check_rounded),
            label: Text(loc.nutritionSuggestApply),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 7),
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  final Widget child;

  const _SurfaceCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _MacroRatioControllers {
  final TextEditingController protein;
  final TextEditingController fat;

  _MacroRatioControllers({required this.protein, required this.fat});

  factory _MacroRatioControllers.defaults() {
    final defaults = NutritionMacroRatios.defaults;
    return _MacroRatioControllers(
      protein: TextEditingController(
        text: defaults.proteinPerKg.toStringAsFixed(1),
      ),
      fat: TextEditingController(text: defaults.fatPerKg.toStringAsFixed(1)),
    );
  }

  void dispose() {
    protein.dispose();
    fat.dispose();
  }
}

class _MacroConfigurationCard extends StatelessWidget {
  final _MacroRatioControllers controllers;
  final VoidCallback onChanged;
  final VoidCallback onRestore;

  const _MacroConfigurationCard({
    required this.controllers,
    required this.onChanged,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return _SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  size: 19,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.nutritionSuggestMacroSettings,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      loc.nutritionSuggestMacroSettingsSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: loc.nutritionSuggestRestoreDefaults,
                onPressed: onRestore,
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MacroRatioField(
                  controller: controllers.protein,
                  label: loc.nutritionSuggestProteinPerKg,
                  icon: Icons.fitness_center_rounded,
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _MacroRatioField(
                  controller: controllers.fat,
                  label: loc.nutritionSuggestFatPerKg,
                  icon: Icons.water_drop_outlined,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(70),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 17,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.nutritionSuggestCarbsRemainder,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MacroRatioField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final VoidCallback onChanged;

  const _MacroRatioField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        suffixText: 'g/kg',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 14,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _InlineWarning extends StatelessWidget {
  final String message;

  const _InlineWarning({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineInfo extends StatelessWidget {
  final String message;

  const _InlineInfo({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withAlpha(100),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 19,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _SuggestionPreviewCard extends StatelessWidget {
  final NutritionGoalSuggestion suggestion;

  const _SuggestionPreviewCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withAlpha(170),
            theme.colorScheme.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.primary.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_graph_rounded,
                size: 19,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                loc.nutritionSuggestGoalPreview,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            loc.nutritionConsumedKcal(_format(suggestion.tdee)),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.7,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            loc.nutritionSuggestTdeeSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${loc.nutritionSuggestBmr}: ${_format(suggestion.bmr)} kcal',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _MacroStat(
                  label: loc.nutritionProgressProtein,
                  value: suggestion.proteinG,
                  color: theme.colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MacroStat(
                  label: loc.nutritionProgressCarbs,
                  value: suggestion.carbsG,
                  color: theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MacroStat(
                  label: loc.nutritionProgressFat,
                  value: suggestion.fatG,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}

class _MacroStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _MacroStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(180),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_format(value)} g',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}

class _SheetNumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String suffix;
  final ValueChanged<String> onChanged;

  const _SheetNumberField({
    required this.controller,
    required this.label,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }
}
