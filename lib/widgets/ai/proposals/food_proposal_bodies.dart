import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/ai/proposals/ai_proposal_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Preview of a `manual_food` proposal: the draft the manual food form will be
/// pre-filled with. Values are estimates until the user saves the form.
class ManualFoodProposalBody extends StatefulWidget {
  final Map<String, dynamic> preview;

  const ManualFoodProposalBody({super.key, required this.preview});

  @override
  State<ManualFoodProposalBody> createState() => _ManualFoodProposalBodyState();
}

class _ManualFoodProposalBodyState extends State<ManualFoodProposalBody> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = AiProposalFormat(l10n);
    final theme = Theme.of(context);
    final preview = widget.preview;
    final values = jsonMap(preview['values']);
    final reference = jsonMap(preview['reference']);
    final servings = jsonMaps(preview['servings']);
    final brand = jsonText(preview['brand']);
    final notes = jsonText(preview['notes']);
    final extras = _extras(l10n, fmt, values);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          jsonText(preview['name']) ?? '',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (brand != null)
          Text(
            brand,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          l10n.aiFoodProposalReference(
            fmt.number(jsonNum(reference['amount'])),
            jsonText(reference['unit']) ?? '',
          ),
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        if (values.isEmpty)
          Text(l10n.aiProposalFoodNoValues, style: theme.textTheme.bodySmall)
        else
          AiProposalMacroChips(values: values),
        if (extras.isNotEmpty || servings.isNotEmpty || notes != null)
          TextButton.icon(
            key: const Key('ai-proposal-food-details'),
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            ),
            label: Text(
              _expanded
                  ? l10n.aiFoodProposalHideDetails
                  : l10n.aiFoodProposalDetails,
            ),
          ),
        if (_expanded)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.aiFoodProposalEstimated,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (notes != null) ...[
                  AiProposalSectionLabel(l10n.aiFoodProposalNotes),
                  Text(notes, style: theme.textTheme.bodySmall),
                ],
                if (extras.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final (label, value) in extras)
                        AppMetricChip(text: '$label: $value'),
                    ],
                  ),
                ],
                if (servings.isNotEmpty) ...[
                  AiProposalSectionLabel(l10n.aiFoodProposalServings),
                  for (final serving in servings)
                    Text(
                      '• ${serving['label']}: '
                      '${fmt.number(jsonNum(serving['quantity']))} '
                      '${serving['unit']}'
                      '${serving['grams_equivalent'] == null ? '' : ' (${fmt.grams(jsonNum(serving['grams_equivalent']))})'}'
                      '${serving['ml_equivalent'] == null ? '' : ' (${fmt.withUnit(jsonNum(serving['ml_equivalent']), 'ml')})'}',
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// The secondary nutrients, in display order, that the draft carries.
  static List<(String, String)> _extras(
    AppLocalizations l10n,
    AiProposalFormat fmt,
    Map<String, dynamic> values,
  ) {
    final rows = <(String, String, String)>[
      ('saturated_fat_g', l10n.nutritionFatSaturated, 'g'),
      ('monounsaturated_fat_g', l10n.nutritionFatMonounsaturated, 'g'),
      ('polyunsaturated_fat_g', l10n.nutritionFatPolyunsaturated, 'g'),
      ('trans_fat_g', l10n.nutritionFatTrans, 'g'),
      ('fiber_g', l10n.nutritionProgressFiber, 'g'),
      ('sugars_g', l10n.nutritionProgressSugars, 'g'),
      ('sodium_mg', l10n.nutritionProgressSodium, 'mg'),
      ('potassium_mg', l10n.nutritionProgressPotassium, 'mg'),
      ('calcium_mg', l10n.nutritionProgressCalcium, 'mg'),
      ('iron_mg', l10n.nutritionProgressIron, 'mg'),
      ('magnesium_mg', l10n.nutritionProgressMagnesium, 'mg'),
      ('zinc_mg', l10n.nutritionProgressZinc, 'mg'),
      ('vitamin_a_ug', l10n.nutritionProgressVitaminA, 'µg'),
      ('vitamin_c_mg', l10n.nutritionProgressVitaminC, 'mg'),
      ('vitamin_d_ug', l10n.nutritionProgressVitaminD, 'µg'),
      ('vitamin_b12_ug', l10n.nutritionProgressVitaminB12, 'µg'),
    ];
    return [
      for (final (key, label, unit) in rows)
        if (jsonNum(values[key]) != null)
          (label, fmt.withUnit(jsonNum(values[key]), unit)),
    ];
  }
}

/// Preview of a `meal_log` proposal: what lands in which meal of which day,
/// per item and in total, with the effect on the day.
class MealLogProposalBody extends StatelessWidget {
  final Map<String, dynamic> preview;

  const MealLogProposalBody({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = AiProposalFormat(l10n);
    final theme = Theme.of(context);
    final items = jsonMaps(preview['items']);
    final totals = jsonMap(preview['totals']);
    final day = jsonMap(preview['day']);
    final before = jsonNum(day['before_kcal'])?.toInt();
    final after = jsonNum(day['after_kcal'])?.toInt();
    final goal = jsonNum(day['goal_kcal'])?.toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.aiProposalMealLogTarget(
            fmt.mealLabel(
              jsonText(preview['meal_type']),
              jsonText(preview['meal_name']),
            ),
            fmt.date(jsonText(preview['date'])),
          ),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        for (final item in items) _ItemRow(item: item, fmt: fmt),
        const Divider(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.aiProposalMealLogTotal,
                style: theme.textTheme.labelLarge,
              ),
            ),
            Text(
              fmt.kcal(jsonNum(totals['calories'])),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        AiProposalMacroChips(values: {...totals}..remove('calories')),
        if (before != null && after != null) ...[
          const SizedBox(height: 6),
          Text(
            goal == null
                ? l10n.aiProposalMealLogDay(before, after)
                : l10n.aiProposalMealLogDayGoal(before, after, goal),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (jsonTrue(totals['incomplete']))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              l10n.aiProposalMealLogIncomplete,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final AiProposalFormat fmt;

  const _ItemRow({required this.item, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final l10n = fmt.l10n;
    final theme = Theme.of(context);
    final isSaved = item['kind'] == 'saved_meal';
    final serving = jsonMap(item['serving']);
    final detail = isSaved
        ? '${l10n.aiProposalMealLogSavedMeal} · ${l10n.aiProposalMealLogIngredients(item['ingredients'] is List ? (item['ingredients'] as List).length : 0)}'
        : '${fmt.number(jsonNum(item['quantity']))} '
              '${serving['label'] != null ? '× ${serving['label']}' : item['unit'] ?? ''}';
    final macros = [
      if (jsonNum(item['protein_g']) != null)
        '${l10n.nutritionProgressProtein.characters.first} ${fmt.number(jsonNum(item['protein_g']))}',
      if (jsonNum(item['carbs_g']) != null)
        '${l10n.nutritionProgressCarbs.characters.first} ${fmt.number(jsonNum(item['carbs_g']))}',
      if (jsonNum(item['fat_g']) != null)
        '${l10n.nutritionProgressFat.characters.first} ${fmt.number(jsonNum(item['fat_g']))}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isSaved ? Icons.menu_book_rounded : Icons.restaurant_rounded,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  jsonText(item['name']) ?? '',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  [
                    detail,
                    if (jsonText(item['brand']) != null) item['brand'],
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (macros.isNotEmpty)
                  Text(
                    macros,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                jsonTrue(item['incomplete']) &&
                        jsonNum(item['calories']) == null
                    ? '—'
                    : fmt.kcal(jsonNum(item['calories'])),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (jsonTrue(item['estimated']))
                Text(
                  l10n.aiProposalMealLogEstimated,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
