import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/periodization/nutrition_target_input.dart';
import 'package:workout_notes/utils/macro_calculator.dart';

/// Shared nutrition target inputs for a phase week.
///
/// * **Daily expenditure (TDEE)** is read from the app settings and is
///   not editable here; the field is rendered as a read-only tile.
/// * **Deficit / Surplus** is a signed kcal input applied on top of the
///   TDEE. The day goal shown below is `TDEE ± adjustment`.
/// * **Reference weight**, **Protein (g/kg)** and **Fat (g/kg)** are the
///   same inputs used before; protein and fat are always side-by-side.
///
/// Carbohydrates are computed from the remaining calories and shown as
/// a live preview — nothing is stored until the caller saves the
/// resolved grams.
///
/// The controllers are owned by the parent (form/wizard); call
/// [parseField] to read them and [breakdownOf] to resolve the computed
/// macros.
class NutritionTargetFields extends StatelessWidget {
  final double? tdee;

  final TextEditingController adjustment;
  final TextEditingController proteinPerKg;
  final TextEditingController fatPerKg;
  final TextEditingController referenceWeight;
  final bool enabled;
  final VoidCallback? onChanged;

  const NutritionTargetFields({
    super.key,
    required this.tdee,
    required this.adjustment,
    required this.proteinPerKg,
    required this.fatPerKg,
    required this.referenceWeight,
    this.enabled = true,
    this.onChanged,
  });

  static double? parseField(TextEditingController controller) =>
      NutritionTargetInput.parse(controller.text);

  static double? parseSignedField(TextEditingController controller) =>
      NutritionTargetInput.parse(controller.text, allowSigned: true);

  static MacroBreakdown? breakdownOf({
    required double? tdee,
    required TextEditingController adjustment,
    required TextEditingController proteinPerKg,
    required TextEditingController fatPerKg,
    required TextEditingController referenceWeight,
  }) => NutritionTargetInput.fromControllers({
    'tdee': _TextEditingControllerAdapter(tdee),
    'adjustment': adjustment,
    'proteinPerKg': proteinPerKg,
    'fatPerKg': fatPerKg,
    'refWeight': referenceWeight,
  }).resolve();

  MacroBreakdown? get _breakdown {
    if (!enabled) return null;
    return breakdownOf(
      tdee: tdee,
      adjustment: adjustment,
      proteinPerKg: proteinPerKg,
      fatPerKg: fatPerKg,
      referenceWeight: referenceWeight,
    );
  }

  double? get _adjustmentKcal => parseSignedField(adjustment);
  double? get _resolvedGoal {
    if (tdee == null) return null;
    final adjustment = _adjustmentKcal ?? 0;
    return tdee! + adjustment;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final breakdown = _breakdown;
    final resolvedGoal = _resolvedGoal;
    final hasTdee = tdee != null;
    final hasRatioInputs =
        adjustment.text.trim().isNotEmpty ||
        proteinPerKg.text.trim().isNotEmpty ||
        fatPerKg.text.trim().isNotEmpty;
    final hasWeight = parseField(referenceWeight) != null;

    if (!hasTdee) {
      return _TdeeMissingBanner(message: loc.periodizationTdeeMissing);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TdeeReadOnlyTile(value: tdee!, help: loc.periodizationTdeeFromSettingsHelp),
        const SizedBox(height: 12),
        TextField(
          controller: adjustment,
          enabled: enabled,
          onChanged: (_) => onChanged?.call(),
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d\-.,]')),
          ],
          decoration: InputDecoration(
            labelText: loc.periodizationAdjustmentKcal,
            helperText: loc.periodizationAdjustmentKcalHelp,
            suffixText: 'kcal',
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerLowest,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: referenceWeight,
          enabled: enabled,
          onChanged: (_) => onChanged?.call(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.,]'))],
          decoration: InputDecoration(
            labelText: loc.periodizationReferenceWeight,
            suffixText: 'kg',
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerLowest,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: proteinPerKg,
                enabled: enabled,
                onChanged: (_) => onChanged?.call(),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                decoration: InputDecoration(
                  labelText: loc.periodizationProteinPerKg,
                  suffixText: 'g/kg',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerLowest,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: fatPerKg,
                enabled: enabled,
                onChanged: (_) => onChanged?.call(),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                ],
                decoration: InputDecoration(
                  labelText: loc.periodizationFatPerKg,
                  suffixText: 'g/kg',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerLowest,
                ),
              ),
            ),
          ],
        ),
        if (resolvedGoal != null) ...[
          const SizedBox(height: 14),
          _MacroPreviewCard(
            tdee: tdee!,
            adjustmentKcal: _adjustmentKcal,
            goal: resolvedGoal,
            breakdown: breakdown,
          ),
        ] else if (hasRatioInputs && !hasWeight) ...[
          const SizedBox(height: 14),
          _Hint(
            icon: Icons.monitor_weight_outlined,
            text: loc.periodizationNoReferenceWeight,
          ),
        ],
      ],
    );
  }
}

/// Read-only tile showing the daily expenditure pulled from the app
/// settings. The field is intentionally non-interactive: the editor
/// only renders the live value so the user knows where the kcal goal
/// comes from.
class _TdeeReadOnlyTile extends StatelessWidget {
  final double value;
  final String help;

  const _TdeeReadOnlyTile({required this.value, required this.help});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final formatted = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(120),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.local_fire_department_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.periodizationTdeeFromSettings,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  help,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatted,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'kcal',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Banner that shows the resolved daily kcal goal together with the
/// TDEE ± adjustment breakdown that produces it. Acts as the live
/// preview of the phase weekly target.
/// Card that shows the resolved daily kcal goal together with the
/// TDEE ± adjustment breakdown that produces it, and (when the inputs
/// are sufficient) the protein/carbs/fat split underneath. Both live
/// in the same surface so the user sees the goal + macros without
/// bouncing between two cards.
class _MacroPreviewCard extends StatelessWidget {
  static const _proteinColor = Color(0xFF4F8EF7);
  static const _carbsColor = Color(0xFFF5B942);
  static const _fatColor = Color(0xFF9B6BE8);

  final double tdee;
  final double? adjustmentKcal;
  final double goal;
  final MacroBreakdown? breakdown;

  const _MacroPreviewCard({
    required this.tdee,
    required this.adjustmentKcal,
    required this.goal,
    required this.breakdown,
  });

  static String _formatKcal(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  static String _formatSigned(AppLocalizations loc, double value) {
    if (value > 0) {
      return loc.periodizationGoalSignedPlus(_formatKcal(value));
    }
    if (value < 0) return _formatKcal(value);
    return '±0';
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final adjustment = adjustmentKcal ?? 0;
    final hasAdjustment = adjustment != 0;
    final breakdown = this.breakdown;
    final hasBreakdown = breakdown != null;
    final totalKcal = hasBreakdown
        ? breakdown.proteinKcal + breakdown.fatKcal + breakdown.carbsKcal
        : 0;
    final isConflict = hasBreakdown && breakdown.energyConflict;
    final goalTextColor = theme.colorScheme.onPrimaryContainer;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withAlpha(120),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.periodizationDailyGoal(_formatKcal(goal)),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: goalTextColor,
            ),
          ),
          if (hasAdjustment) ...[
            const SizedBox(height: 4),
            Text(
              loc.periodizationGoalBreakdown(
                _formatKcal(tdee),
                _formatSigned(loc, adjustment),
              ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: goalTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else
            Text(
              loc.periodizationAdjustmentKcalNotSet,
              style: theme.textTheme.bodySmall?.copyWith(
                color: goalTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (isConflict) ...[
            const SizedBox(height: 12),
            _ConflictBanner(loc.nutritionSuggestMacroEnergyError),
          ] else if (hasBreakdown) ...[
            const SizedBox(height: 12),
            Divider(
              height: 1,
              thickness: 1,
              color: goalTextColor.withAlpha(35),
            ),
            const SizedBox(height: 12),
            Text(
              loc.periodizationMacroPreview,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MacroValue(
                    label: loc.nutritionProgressProtein,
                    value: '${breakdown.proteinRounded} g',
                    color: _proteinColor,
                  ),
                ),
                Expanded(
                  child: _MacroValue(
                    label: loc.periodizationCarbsRemainder,
                    value: '${breakdown.carbsRounded} g',
                    color: _carbsColor,
                  ),
                ),
                Expanded(
                  child: _MacroValue(
                    label: loc.nutritionProgressFat,
                    value: '${breakdown.fatRounded} g',
                    color: _fatColor,
                  ),
                ),
              ],
            ),
            if (totalKcal > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      Expanded(
                        flex: breakdown.proteinKcal,
                        child: Container(color: _proteinColor),
                      ),
                      Expanded(
                        flex: breakdown.fatKcal,
                        child: Container(color: _fatColor),
                      ),
                      Expanded(
                        flex: breakdown.carbsKcal,
                        child: Container(color: _carbsColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TdeeMissingBanner extends StatelessWidget {
  final String message;
  const _TdeeMissingBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withAlpha(140),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 19,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Adapter that lets us feed the TDEE (a non-editable value) into the
/// [NutritionTargetInput.fromControllers] helper without spinning up a
/// throwaway controller.
class _TextEditingControllerAdapter extends TextEditingController {
  _TextEditingControllerAdapter(double? value)
      : super(text: value == null ? '' : value.toString());

  @override
  set value(TextEditingValue newValue) {
    // The TDEE is read-only; ignore external mutations.
  }
}

class _MacroValue extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MacroValue({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
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
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ConflictBanner extends StatelessWidget {
  final String message;

  const _ConflictBanner(this.message);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withAlpha(120),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 19,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _Hint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}