import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/strength_history_repository.dart';
import 'package:workout_notes/widgets/strength/history/strength_menu_chip.dart';

String strengthHistoryPeriodLabel(
  AppLocalizations loc,
  StrengthHistoryPeriod period,
) => switch (period) {
  StrengthHistoryPeriod.all => loc.strengthHistoryPeriodAll,
  StrengthHistoryPeriod.last30Days => loc.strengthHistoryPeriod30,
  StrengthHistoryPeriod.last90Days => loc.strengthHistoryPeriod90,
  StrengthHistoryPeriod.thisYear => loc.strengthHistoryPeriodYear,
};

/// Search field plus a horizontally scrolling row of filter chips (routine,
/// period, muscle group).
class StrengthHistoryFilterBar extends StatelessWidget {
  final StrengthHistoryFilter filter;
  final TextEditingController searchController;
  final List<StrengthRoutineOption> routines;
  final List<StrengthCategoryOption> categories;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<StrengthHistoryFilter> onChanged;

  const StrengthHistoryFilterBar({
    super.key,
    required this.filter,
    required this.searchController,
    required this.routines,
    required this.categories,
    required this.onQueryChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;

    String routineLabel = loc.strengthHistoryFilterRoutine;
    for (final routine in routines) {
      if (routine.id == filter.routineId) routineLabel = routine.name;
    }
    String muscleLabel = loc.strengthHistoryFilterMuscle;
    for (final category in categories) {
      if (category.id == filter.categoryId) {
        muscleLabel = ExerciseLocaleHelper.categoryName(
          loc,
          category.categoryRow,
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            key: const ValueKey('strengthHistorySearch'),
            controller: searchController,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: loc.strengthHistorySearchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: loc.commonClearSearch,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        searchController.clear();
                        onQueryChanged('');
                      },
                    ),
              isDense: true,
              filled: true,
              fillColor: colors.surfaceContainerHighest.withAlpha(90),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              if (routines.isNotEmpty) ...[
                StrengthMenuChip<String>(
                  key: const ValueKey('strengthHistoryRoutine'),
                  icon: Icons.event_note_rounded,
                  label: routineLabel,
                  active: filter.routineId != null,
                  selected: filter.routineId ?? '',
                  options: [
                    StrengthMenuOption(
                      '',
                      loc.strengthHistoryFilterAllRoutines,
                    ),
                    for (final routine in routines)
                      StrengthMenuOption(routine.id, routine.name),
                  ],
                  onSelected: (id) => onChanged(
                    id.isEmpty
                        ? filter.copyWith(clearRoutine: true)
                        : filter.copyWith(routineId: id),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              StrengthMenuChip<StrengthHistoryPeriod>(
                key: const ValueKey('strengthHistoryPeriod'),
                icon: Icons.calendar_month_outlined,
                label: filter.period == StrengthHistoryPeriod.all
                    ? loc.strengthHistoryFilterPeriod
                    : strengthHistoryPeriodLabel(loc, filter.period),
                active: filter.period != StrengthHistoryPeriod.all,
                selected: filter.period,
                options: [
                  for (final period in StrengthHistoryPeriod.values)
                    StrengthMenuOption(
                      period,
                      strengthHistoryPeriodLabel(loc, period),
                    ),
                ],
                onSelected: (period) =>
                    onChanged(filter.copyWith(period: period)),
              ),
              if (categories.isNotEmpty) ...[
                const SizedBox(width: 8),
                StrengthMenuChip<String>(
                  key: const ValueKey('strengthHistoryMuscle'),
                  icon: Icons.accessibility_new_rounded,
                  label: muscleLabel,
                  active: filter.categoryId != null,
                  selected: filter.categoryId ?? '',
                  options: [
                    StrengthMenuOption('', loc.strengthHistoryFilterAllMuscles),
                    for (final category in categories)
                      StrengthMenuOption(
                        category.id,
                        ExerciseLocaleHelper.categoryName(
                          loc,
                          category.categoryRow,
                        ),
                      ),
                  ],
                  onSelected: (id) => onChanged(
                    id.isEmpty
                        ? filter.copyWith(clearCategory: true)
                        : filter.copyWith(categoryId: id),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
