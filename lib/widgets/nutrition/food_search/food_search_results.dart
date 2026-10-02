import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/food_search_result.dart';
import 'package:workout_notes/models/nutrition/saved_meal.dart';
import 'package:workout_notes/screens/nutrition/food_search_controller.dart';
import 'package:workout_notes/widgets/nutrition/food_search/food_search_cards.dart';
import 'package:workout_notes/widgets/nutrition/food_search/food_search_headers.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Scrollable body of the food search: the favorites / suggestions / history
/// sections while the field is empty, and the local + remote result lists
/// (with their status banners) once the user types.
class FoodSearchResultsView extends StatelessWidget {
  const FoodSearchResultsView({
    super.key,
    required this.controller,
    required this.mealLabel,
    required this.onSelectFood,
    required this.onLogSavedMeal,
  });

  final FoodSearchController controller;

  /// Display name of the meal the search is bound to.
  final String mealLabel;
  final ValueChanged<FoodSearchResult> onSelectFood;
  final ValueChanged<SavedMealWithItems> onLogSavedMeal;

  Widget _foodList(
    List<FoodSearchResult> items, {
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 12),
    bool favoritable = true,
  }) {
    return SliverPadding(
      padding: padding,
      sliver: SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 6),
        itemBuilder: (_, index) => FoodCard(
          result: items[index],
          onSelected: () => onSelectFood(items[index]),
          onToggleFavorite: favoritable
              ? () => controller.toggleFavorite(items[index])
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final query = controller.query;
    final localResults = controller.localResults;
    final remoteResults = controller.remoteResults;
    final remoteError = controller.remoteError;
    final isSearchingRemote = controller.isSearchingRemote;
    final showQueryTooShort = controller.showQueryTooShort;
    final hasAny = localResults.isNotEmpty || remoteResults.isNotEmpty;
    final hasRemoteBanner = remoteError != null || isSearchingRemote;

    // Before the user types: favorites, meal-specific suggestions and
    // recents take over the empty state.
    if (query.isEmpty && !showQueryTooShort) {
      final sections = controller.emptyQuerySections;
      final showFavorites = sections.favorites.isNotEmpty;
      final showMeal = sections.mealSuggestions.isNotEmpty;
      final showRecents = sections.recents.isNotEmpty;
      final showAllFoods = sections.allFoods.isNotEmpty;
      final showSavedMeals = sections.showSavedMeals;
      final savedMeals = controller.savedMeals;
      return CustomScrollView(
        slivers: [
          if (showFavorites) ...[
            SliverToBoxAdapter(
              child: AppSectionHeader(
                loc.nutritionSearchFavorites,
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              ),
            ),
            _foodList(sections.favorites),
          ],
          if (showMeal) ...[
            SliverToBoxAdapter(
              child: AppSectionHeader(
                loc.nutritionSearchSuggestedFor(mealLabel),
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              ),
            ),
            _foodList(sections.mealSuggestions),
          ],
          if (showRecents) ...[
            SliverToBoxAdapter(
              child: FoodSearchHistoryHeader(
                title: loc.nutritionSearchHistory,
                sortLabel: loc.nutritionSearchMostRecent,
              ),
            ),
            _foodList(
              sections.recents,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            ),
          ],
          if (showAllFoods) ...[
            SliverToBoxAdapter(
              child: AppSectionHeader(
                loc.nutritionSearchMyFoods,
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              ),
            ),
            _foodList(
              sections.allFoods,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            ),
          ],
          if (showSavedMeals) ...[
            SliverToBoxAdapter(
              child: AppSectionHeader(
                loc.nutritionSavedMeals,
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              sliver: SliverList.separated(
                itemCount: savedMeals.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, index) => SavedMealCard(
                  meal: savedMeals[index],
                  isLogging: controller.isLoggingMeal,
                  onSelected: () => onLogSavedMeal(savedMeals[index]),
                ),
              ),
            ),
          ],
          if (!sections.hasSuggestions && !controller.suggestionsLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        showSavedMeals
                            ? Icons.restaurant_menu_outlined
                            : Icons.restaurant_menu_rounded,
                        size: 80,
                        color: theme.colorScheme.primary.withAlpha(80),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        showSavedMeals
                            ? loc.nutritionSavedMealsEmptyTitle
                            : loc.nutritionSearchEmpty,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        showSavedMeals
                            ? loc.nutritionSavedMealsEmptySubtitle
                            : loc.nutritionSearchEmptyHint,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return CustomScrollView(
      slivers: [
        if (remoteError?.code == 'rate_limited')
          SliverToBoxAdapter(
            child: FoodSearchInfoBanner(
              icon: Icons.hourglass_top,
              text: loc.nutritionRateLimited,
            ),
          )
        else if (remoteError != null)
          SliverToBoxAdapter(
            child: FoodSearchInfoBanner(
              icon: Icons.error_outline,
              text: loc.nutritionSearchUnavailable,
            ),
          )
        else if (isSearchingRemote)
          SliverToBoxAdapter(
            child: FoodSearchInfoBanner(
              icon: Icons.cloud_sync_outlined,
              text: loc.nutritionSearchLoading,
            ),
          ),
        if (localResults.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: AppSectionHeader(
              loc.nutritionSearchLocalResults,
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
            ),
          ),
          _foodList(localResults),
        ],
        if (remoteResults.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: AppSectionHeader(
              loc.nutritionSearchRemoteResults,
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
            ),
          ),
          _foodList(
            remoteResults,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            favoritable: false,
          ),
        ],
        if (!hasAny && !hasRemoteBanner && !showQueryTooShort)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.restaurant_menu_rounded,
                      size: 80,
                      color: theme.colorScheme.primary.withAlpha(80),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      loc.nutritionSearchEmpty,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      loc.nutritionSearchEmptyHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (hasAny) const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}
