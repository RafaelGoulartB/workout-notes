import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/utils/exercise_equipment.dart';
import 'package:workout_notes/utils/strength_exercise_library.dart';
import 'package:workout_notes/utils/strength_routine_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Icon that hints at what an exercise records (weight, distance, time...).
IconData exerciseTypeIcon(String? type) {
  switch (type) {
    case 'distanceTime':
    case 'distanceOnly':
      return Icons.straighten_rounded;
    case 'weightDistance':
    case 'weightOnly':
      return Icons.monitor_weight_rounded;
    case 'weightTime':
    case 'timeOnly':
      return Icons.timer_rounded;
    case 'repsDistance':
    case 'repsOnly':
      return Icons.repeat_rounded;
    case 'repsTime':
    case 'weightReps':
    default:
      return Icons.fitness_center_rounded;
  }
}

String exerciseSortLabel(AppLocalizations loc, ExerciseLibrarySort sort) =>
    switch (sort) {
      ExerciseLibrarySort.az => loc.exerciseLibrarySortAz,
      ExerciseLibrarySort.recent => loc.exerciseLibrarySortRecent,
      ExerciseLibrarySort.mostTrained => loc.exerciseLibrarySortMostTrained,
    };

/// Search field plus favorites / muscle-group chips, pinned above the list.
class ExerciseLibraryFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final List<Map<String, dynamic>> categories;
  final String? selectedCategoryId;
  final ValueChanged<String?> onCategoryChanged;
  final bool favoritesOnly;
  final ValueChanged<bool> onFavoritesChanged;

  const ExerciseLibraryFilterBar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.categories,
    required this.selectedCategoryId,
    required this.onCategoryChanged,
    required this.favoritesOnly,
    required this.onFavoritesChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: loc.exerciseLibrarySearch,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: ListenableBuilder(
                listenable: searchController,
                builder: (context, _) => searchController.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: loc.commonClearSearch,
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged('');
                        },
                      ),
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: scheme.surfaceContainerHighest.withAlpha(90),
            ),
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            children: [
              FilterChip(
                avatar: Icon(
                  favoritesOnly ? Icons.star_rounded : Icons.star_outline,
                  size: 18,
                  color: favoritesOnly
                      ? Colors.amber.shade700
                      : scheme.onSurfaceVariant,
                ),
                label: Text(loc.exerciseLibraryFavorites),
                selected: favoritesOnly,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: onFavoritesChanged,
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(loc.exerciseLibraryAll),
                selected: selectedCategoryId == null,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onCategoryChanged(null),
              ),
              for (final cat in categories) ...[
                const SizedBox(width: 8),
                _CategoryChip(
                  category: cat,
                  selected: selectedCategoryId == cat['id'],
                  onSelected: () => onCategoryChanged(
                    selectedCategoryId == cat['id']
                        ? null
                        : cat['id'] as String,
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

class _CategoryChip extends StatelessWidget {
  final Map<String, dynamic> category;
  final bool selected;
  final VoidCallback onSelected;

  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final color = Color(category['color'] as int? ?? 0xFF757575);
    return FilterChip(
      avatar: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      label: Text(ExerciseLocaleHelper.categoryName(loc, category)),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      selectedColor: color.withAlpha(50),
      side: selected ? BorderSide(color: color.withAlpha(160)) : null,
      onSelected: (_) => onSelected(),
    );
  }
}

/// "12 exercises" + sort menu shown at the top of the list.
class ExerciseLibraryListHeader extends StatelessWidget {
  final int count;
  final ExerciseLibrarySort sort;
  final ValueChanged<ExerciseLibrarySort> onSortChanged;

  const ExerciseLibraryListHeader({
    super.key,
    required this.count,
    required this.sort,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              loc.exerciseLibraryCountValue(count),
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          PopupMenuButton<ExerciseLibrarySort>(
            tooltip: loc.exerciseLibrarySort,
            initialValue: sort,
            onSelected: onSortChanged,
            itemBuilder: (ctx) => [
              for (final value in ExerciseLibrarySort.values)
                PopupMenuItem(
                  value: value,
                  child: Text(exerciseSortLabel(loc, value)),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.sort_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    exerciseSortLabel(loc, sort),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Muscle-group header of a section of the "All" view.
class ExerciseLibrarySectionHeader extends StatelessWidget {
  final Map<String, dynamic> category;
  final int count;

  const ExerciseLibrarySectionHeader({
    super.key,
    required this.category,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final color = Color(category['color'] as int? ?? 0xFF757575);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ExerciseLocaleHelper.categoryName(loc, category).toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            '$count',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: AppUi.tabular,
            ),
          ),
        ],
      ),
    );
  }
}

/// A dense exercise row: muscle-colored badge, name, equipment / last trained
/// and best e1RM, with the favorite star.
class ExerciseLibraryRow extends StatelessWidget {
  final ExerciseLibraryEntry entry;

  /// Show the muscle group in the subtitle (flat lists; sections already say it).
  final bool showCategory;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  const ExerciseLibraryRow({
    super.key,
    required this.entry,
    required this.showCategory,
    required this.onTap,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final row = entry.row;
    final color = Color(row['category_color'] as int? ?? 0xFF757575);
    final equipment = ExerciseEquipment.label(loc, row['equipment'] as String?);
    final lastDate = entry.lastDate;
    final subtitle = [
      if (showCategory) ExerciseLocaleHelper.categoryName(loc, row),
      if (equipment.isNotEmpty) equipment,
      if (lastDate != null)
        loc.exerciseLibraryLastTrained(
          StrengthRoutineFormat.shortDate(lastDate),
        ),
    ].join(' · ');
    final e1rm = entry.bestE1rm;
    final isFavorite = entry.isFavorite;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withAlpha(36),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                exerciseTypeIcon(row['type'] as String?),
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (e1rm != null) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: loc.exerciseLibraryBestE1rm(
                  StrengthRoutineFormat.kg(e1rm),
                ),
                child: Text(
                  '${StrengthRoutineFormat.kg(e1rm)} kg',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: AppUi.tabular,
                  ),
                ),
              ),
            ],
            IconButton(
              tooltip: isFavorite
                  ? loc.exerciseLibraryFavoriteRemove
                  : loc.exerciseLibraryFavoriteAdd,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              padding: EdgeInsets.zero,
              icon: Icon(
                isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 22,
                color: isFavorite
                    ? Colors.amber.shade600
                    : scheme.onSurfaceVariant.withAlpha(120),
              ),
              onPressed: onToggleFavorite,
            ),
          ],
        ),
      ),
    );
  }
}
