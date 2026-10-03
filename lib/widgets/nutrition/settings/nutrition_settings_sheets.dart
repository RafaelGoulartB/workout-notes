import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/app_number_format.dart';
import 'package:workout_notes/utils/nutrition_goal_suggest.dart';

/// Bottom sheet used to edit one numeric goal value (calories, protein,
/// carbs or fat). Pops `(value,)` on save — an empty field saves `(null,)`,
/// meaning "clear this target" — and nothing when dismissed.
class NumberEditorSheet extends StatefulWidget {
  final String title;
  final String unit;
  final double? initial;

  const NumberEditorSheet({
    super.key,
    required this.title,
    required this.unit,
    required this.initial,
  });

  @override
  State<NumberEditorSheet> createState() => _NumberEditorSheetState();
}

class _NumberEditorSheetState extends State<NumberEditorSheet> {
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
    if (value == value.roundToDouble()) {
      return AppNumberFormat.decimal(value, 0);
    }
    return AppNumberFormat.decimal(value, 1);
  }

  void _submit() {
    final loc = AppLocalizations.of(context)!;
    final text = _controller.text.trim();
    if (text.isEmpty) {
      Navigator.of(context).pop<(double?,)>((null,));
      return;
    }
    final cleaned = text.replaceAll(',', '.');
    final parsed = double.tryParse(cleaned);
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionInvalidNumber)));
      return;
    }
    Navigator.of(context).pop<(double?,)>((parsed,));
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

/// Lightweight payload for the adjustment picker bottom sheet. The kind
/// is derived from the percent sign (negative = cut, zero = maintenance,
/// positive = bulk), so the two can never disagree.
class AdjustmentDraft {
  final double percent;
  const AdjustmentDraft({required this.percent});
}

/// Bottom sheet that defines the deficit/surplus adjustment applied to
/// the user's TDEE — this adjustment IS the daily calorie goal. The
/// preset buttons set the default percent for each kind and the field
/// accepts any signed value for fine-tuning (e.g. −15%).
class AdjustmentPickerSheet extends StatefulWidget {
  final double? tdee;
  final double initialPercent;

  const AdjustmentPickerSheet({
    super.key,
    required this.tdee,
    required this.initialPercent,
  });

  @override
  State<AdjustmentPickerSheet> createState() => _AdjustmentPickerSheetState();
}

class _AdjustmentPickerSheetState extends State<AdjustmentPickerSheet> {
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
    Navigator.of(context).pop(AdjustmentDraft(percent: _percent));
  }

  static String _formatPercentForEdit(double percent) {
    if (percent == percent.roundToDouble()) {
      return AppNumberFormat.decimal(percent, 0);
    }
    return AppNumberFormat.decimal(percent, 1);
  }

  static String _formatGoal(double value) {
    if (value == value.roundToDouble()) {
      return AppNumberFormat.decimal(value, 0);
    }
    return AppNumberFormat.decimal(value, 1);
  }

  static String _formatPercentLabel(double percent) {
    final rounded = percent.round();
    if (rounded > 0) return '+${AppNumberFormat.decimal(rounded, 0)}%';
    return '${AppNumberFormat.decimal(rounded, 0)}%';
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
                      child: AdjustmentOptionButton(
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

class AdjustmentOptionButton extends StatelessWidget {
  final NutritionObjective kind;
  final bool selected;
  final VoidCallback onTap;

  const AdjustmentOptionButton({
    super.key,
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
    if (rounded > 0) return '+${AppNumberFormat.decimal(rounded, 0)}%';
    return '${AppNumberFormat.decimal(rounded, 0)}%';
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
