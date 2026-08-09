import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/utils/nutrition_goal_suggest.dart';

/// Bottom sheet that estimates daily calories and macros from the body
/// profile using the Mifflin-St Jeor equation. The profile is persisted
/// in `app_settings` under the `nutrition_profile_*` keys and the final
/// values are handed back to the caller via [onApply].
class NutritionGoalSuggestSheet extends StatefulWidget {
  final BodyMeasurementRepository bodyRepo;
  final SettingsRepository settingsRepo;
  final void Function(
    double calories,
    double proteinG,
    double carbsG,
    double fatG,
  ) onApply;

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
    required void Function(double, double, double, double) onApply,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => NutritionGoalSuggestSheet(
        bodyRepo: bodyRepo,
        settingsRepo: settingsRepo,
        onApply: onApply,
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

  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();

  bool _isLoading = true;
  bool _isMale = true;
  ActivityLevel _activity = ActivityLevel.moderate;
  NutritionObjective _objective = NutritionObjective.maintenance;
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

  void _recompute() {
    final age = _age;
    final height = _height;
    final weight = _weight;
    if (age == null || height == null || weight == null) {
      if (_suggestion != null) setState(() => _suggestion = null);
      return;
    }
    setState(() {
      _suggestion = suggestNutritionGoal(
        weightKg: weight,
        heightCm: height,
        ageYears: age.toInt(),
        isMale: _isMale,
        activity: _activity,
        objective: _objective,
      );
    });
  }

  Future<void> _apply() async {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    final loc = AppLocalizations.of(context)!;
    final settings = widget.settingsRepo;
    await settings.setSetting(_kSex, _isMale ? 'male' : 'female');
    await settings.setSetting(_kAge, _ageController.text.trim());
    await settings.setSetting(_kHeight, _heightController.text.trim());
    await settings.setSetting(_kWeight, _weightController.text.trim());
    await settings.setSetting(_kActivity, _activity.name);
    if (!mounted) return;
    widget.onApply(
      suggestion.calories,
      suggestion.proteinG,
      suggestion.carbsG,
      suggestion.fatG,
    );
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.nutritionSuggestApplied)),
    );
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

  static String _objectiveLabel(
    AppLocalizations loc,
    NutritionObjective objective,
  ) {
    switch (objective) {
      case NutritionObjective.cut:
        return loc.nutritionSuggestObjectiveCut;
      case NutritionObjective.maintenance:
        return loc.nutritionSuggestObjectiveMaintenance;
      case NutritionObjective.bulk:
        return loc.nutritionSuggestObjectiveBulk;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: _isLoading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    loc.nutritionSuggestTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    loc.nutritionSuggestSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(loc.nutritionSuggestSex,
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(
                        value: true,
                        label: Text(loc.nutritionSuggestSexMale),
                        icon: const Icon(Icons.male),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text(loc.nutritionSuggestSexFemale),
                        icon: const Icon(Icons.female),
                      ),
                    ],
                    selected: {_isMale},
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
                          label: loc.nutritionSuggestAge,
                          onChanged: (_) => _recompute(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SheetNumberField(
                          controller: _heightController,
                          label: loc.nutritionSuggestHeight,
                          onChanged: (_) => _recompute(),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SheetNumberField(
                          controller: _weightController,
                          label: loc.nutritionSuggestWeight,
                          onChanged: (_) => _recompute(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(loc.nutritionSuggestActivity,
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ActivityLevel>(
                    initialValue: _activity,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withAlpha(60),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
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
                  const SizedBox(height: 14),
                  Text(loc.nutritionSuggestObjective,
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  SegmentedButton<NutritionObjective>(
                    segments: [
                      for (final objective in NutritionObjective.values)
                        ButtonSegment(
                          value: objective,
                          label: Text(_objectiveLabel(loc, objective)),
                        ),
                    ],
                    selected: {_objective},
                    onSelectionChanged: (selection) {
                      setState(() => _objective = selection.first);
                      _recompute();
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_suggestion == null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest
                            .withAlpha(60),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              loc.nutritionSuggestNoProfile,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    _SuggestionPreviewCard(
                      suggestion: _suggestion!,
                      isMale: _isMale,
                      weightKg: _weight!,
                    ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _suggestion == null ? null : _apply,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(loc.nutritionSuggestApply),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _SuggestionPreviewCard extends StatelessWidget {
  final NutritionGoalSuggestion suggestion;
  final bool isMale;
  final double weightKg;

  const _SuggestionPreviewCard({
    required this.suggestion,
    required this.isMale,
    required this.weightKg,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
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
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calculate_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  loc.nutritionSuggestGoalPreview,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              loc.nutritionConsumedKcal(_format(suggestion.calories)),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${loc.nutritionSuggestBmr}: ${_format(suggestion.bmr)} kcal · '
              '${loc.nutritionSuggestTdee}: ${_format(suggestion.tdee)} kcal',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            _MacroRow(
              label: loc.nutritionProgressProtein,
              value: suggestion.proteinG,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(height: 6),
            _MacroRow(
              label: loc.nutritionProgressCarbs,
              value: suggestion.carbsG,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(height: 6),
            _MacroRow(
              label: loc.nutritionProgressFat,
              value: suggestion.fatG,
              color: theme.colorScheme.primary,
            ),
          ],
        ),
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

class _MacroRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _MacroRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Text(
          '${_format(value)} g',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
  final ValueChanged<String> onChanged;

  const _SheetNumberField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
      ],
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}
