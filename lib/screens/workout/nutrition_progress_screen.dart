import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/nutrition_progress.dart';
import 'package:workout_notes/screens/workout/nutrition_progress_controller.dart';
import 'package:workout_notes/widgets/nutrition/progress/average_nutrients_card.dart';
import 'package:workout_notes/widgets/nutrition/progress/macro_balance_card.dart';
import 'package:workout_notes/widgets/nutrition/progress/meal_and_contributors_cards.dart';
import 'package:workout_notes/widgets/nutrition/progress/rolling_average_card.dart';
import 'package:workout_notes/widgets/nutrition/progress/week_sequence_card.dart';

/// Calorie-tracking analytics. The whole screen is purpose-built for
/// the "am I in a surplus or a deficit?" question that drives weight
/// change: it surfaces the net balance for the selected window, the
/// distribution of days across the three bands, the rolling 7-day
/// average against the goal, where the calories are coming from
/// (per meal and per food), and how the macros stack up against the
/// target. Analytics follow navigable calendar weeks and months.
class NutritionProgressScreen extends StatefulWidget {
  const NutritionProgressScreen({super.key});

  @override
  State<NutritionProgressScreen> createState() =>
      _NutritionProgressScreenState();
}

class _NutritionProgressScreenState extends State<NutritionProgressScreen>
    with SingleTickerProviderStateMixin {
  final NutritionProgressController _controller = NutritionProgressController();
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _tabController.addListener(_onTabChanged);
    _controller.load();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    _controller.setPeriod(
      _tabController.index == 0 ? BalancePeriod.week : BalancePeriod.month,
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                IconButton(
                  key: const ValueKey('balance-previous-period'),
                  tooltip: loc.nutritionBalancePreviousPeriod,
                  onPressed: () => c.movePeriod(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    c.periodLabel(loc),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('balance-next-period'),
                  tooltip: loc.nutritionBalanceNextPeriod,
                  onPressed: !c.canMoveNext ? null : () => c.movePeriod(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            bottom: TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: loc.nutritionBalanceLast7Days),
                Tab(text: loc.nutritionBalanceLast30Days),
              ],
            ),
          ),
          body: c.isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: c.load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: [
                      WeekSequenceCard(
                        dailies: c.dailies,
                        goal: c.goal?.calories,
                        balance: c.balance,
                        period: c.period,
                      ),
                      const SizedBox(height: 12),
                      RollingAverageCard(
                        spots: c.rollingSpots,
                        goal: c.rollingGoal,
                        windowDays: c.periodDays,
                        startDate: c.periodStart,
                      ),
                      const SizedBox(height: 12),
                      MacroBalanceCard(summary: c.macros, goal: c.goal),
                      const SizedBox(height: 12),
                      MealDistributionCard(distribution: c.mealDistribution),
                      const SizedBox(height: 12),
                      AverageNutrientsCard(
                        key: ValueKey(
                          'average-nutrients-${c.period.name}-${c.nutrientViewVersion}',
                        ),
                        expanded: c.nutrientsExpanded,
                        loading: c.isLoadingNutrients,
                        loadFailed: c.nutrientLoadFailed,
                        averages: c.nutrientAverages,
                        goal: c.goal,
                        onExpansionChanged: c.toggleNutrients,
                      ),
                      const SizedBox(height: 12),
                      TopContributorsCard(
                        contributors: c.contributors,
                        totalConsumed: c.balance?.totalConsumed ?? 0,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
