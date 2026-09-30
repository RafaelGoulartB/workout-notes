import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/widgets/nutrition/progress/progress_shared.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

class MealDistributionCard extends StatelessWidget {
  final List<MealTypeCalories> distribution;

  const MealDistributionCard({super.key, required this.distribution});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (distribution.isEmpty) {
      return ProgressSectionCard(
        icon: Icons.restaurant_outlined,
        iconColor: theme.colorScheme.secondary,
        title: loc.nutritionBalanceMealDistribution,
        child: AppBanner.note(loc.nutritionBalanceMealEmpty),
      );
    }
    final total = distribution.fold<double>(0, (s, m) => s + m.totalCalories);
    final top = distribution.take(5).toList();
    final otherTotal =
        total - top.fold<double>(0, (s, m) => s + m.totalCalories);

    return ProgressSectionCard(
      icon: Icons.restaurant_outlined,
      iconColor: theme.colorScheme.secondary,
      title: loc.nutritionBalanceMealDistribution,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < top.length; i++)
            MealDistributionRow(rank: i + 1, entry: top[i], total: total),
          if (otherTotal > 0 && distribution.length > 5)
            MealDistributionRow(
              rank: top.length + 1,
              entry: MealTypeCalories(
                mealType: 'other',
                displayName: loc.nutritionBalanceOtherMeals,
                totalCalories: otherTotal,
                itemCount: 0,
              ),
              total: total,
            ),
        ],
      ),
    );
  }
}

class MealDistributionRow extends StatelessWidget {
  final int rank;
  final MealTypeCalories entry;
  final double total;

  const MealDistributionRow({
    super.key,
    required this.rank,
    required this.entry,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final percent = total == 0
        ? 0
        : ((entry.totalCalories / total) * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.displayName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${entry.totalCalories.round()} kcal · $percent%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : entry.totalCalories / total,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest
                        .withAlpha(100),
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              loc.nutritionItemCount(entry.itemCount),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class TopContributorsCard extends StatelessWidget {
  final List<CalorieContributor> contributors;
  final double totalConsumed;

  const TopContributorsCard({
    super.key,
    required this.contributors,
    required this.totalConsumed,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final top = contributors.take(8).toList();
    final hasData = top.isNotEmpty && totalConsumed > 0;
    final topShare = hasData
        ? top.fold<double>(0, (s, c) => s + c.totalCalories) / totalConsumed
        : 0.0;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const ValueKey('balance-top-contributors-tile'),
        initiallyExpanded: false,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          Icons.local_dining_outlined,
          color: theme.colorScheme.tertiary,
        ),
        title: Text(
          loc.nutritionBalanceTopContributors,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          hasData
              ? loc.nutritionBalanceTopShare(
                  top.length,
                  (topShare * 100).round(),
                )
              : loc.nutritionBalanceTopEmpty,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (!hasData)
            AppBanner.note(loc.nutritionBalanceTopEmpty)
          else
            Column(
              children: [
                for (var i = 0; i < top.length; i++)
                  ContributorRow(
                    rank: i + 1,
                    entry: top[i],
                    totalConsumed: totalConsumed,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class ContributorRow extends StatelessWidget {
  final int rank;
  final CalorieContributor entry;
  final double totalConsumed;

  const ContributorRow({
    super.key,
    required this.rank,
    required this.entry,
    required this.totalConsumed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final percent = totalConsumed == 0
        ? 0
        : ((entry.totalCalories / totalConsumed) * 100).round();
    final title = entry.brand == null || entry.brand!.isEmpty
        ? entry.name
        : '${entry.name} · ${entry.brand}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  loc.nutritionBalanceContributorMeta(
                    entry.totalCalories.round(),
                    entry.occurrences,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: totalConsumed == 0
                        ? 0
                        : entry.totalCalories / totalConsumed,
                    minHeight: 5,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest
                        .withAlpha(100),
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '$percent%',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
