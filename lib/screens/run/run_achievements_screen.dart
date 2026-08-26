import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';
import 'package:workout_notes/widgets/run/run_achievements_section.dart';
import 'package:workout_notes/widgets/run/run_medal_badge.dart';

/// Complete, all-time personal-record board for GPS runs.
class RunAchievementsScreen extends StatefulWidget {
  const RunAchievementsScreen({super.key});

  @override
  State<RunAchievementsScreen> createState() => _RunAchievementsScreenState();
}

class _RunAchievementsScreenState extends State<RunAchievementsScreen> {
  final _repository = RunRepository();
  RunAchievementBoard _board = RunAchievementBoard.empty;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _repository.backfillMissingEfforts(limit: 60);
    final activities = await _repository.listActivities(limit: 500);
    if (!mounted) return;
    setState(() {
      _board = RunAchievementEngine.build(activities);
      _loading = false;
    });
  }

  Future<void> _openActivity(String activityId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(activityId: activityId),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(loc.runAchievementsTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _AchievementHero(board: _board),
                  const SizedBox(height: 28),
                  _SectionLabel(text: loc.runAchievementsRecords),
                  const SizedBox(height: 10),
                  for (
                    var index = 0;
                    index < _board.categories.length;
                    index++
                  ) ...[
                    _AchievementCategoryCard(
                          category: _board.categories[index],
                          onOpenActivity: _openActivity,
                        )
                        .animate()
                        .fadeIn(duration: 260.ms, delay: (index * 35).ms)
                        .slideY(begin: 0.025),
                    if (index < _board.categories.length - 1)
                      const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
    );
  }
}

class _AchievementHero extends StatelessWidget {
  final RunAchievementBoard board;

  const _AchievementHero({required this.board});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final unlocked = board.nonEmptyCategories.length;
    final total = board.categories.isEmpty
        ? RunAchievementKind.values.length
        : board.categories.length;
    final placements = <RunAchievementPlacement>[
      for (final category in board.categories) ...category.placements,
    ];
    final medalCounts = {
      for (final tier in RunMedalTier.values)
        tier: placements.where((item) => item.tier == tier).length,
    };

    return Container(
      key: const Key('run-achievements-hero'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer.withValues(alpha: 0.72),
            colors.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  Icons.emoji_events_rounded,
                  color: colors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.runAchievementsHeroTitle,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      loc.runAchievementsHeroSubtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$unlocked',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                  color: colors.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 5, bottom: 3),
                child: Text(
                  loc.runAchievementsProgress(total),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : unlocked / total,
              minHeight: 7,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (final tier in RunMedalTier.values) ...[
                Expanded(
                  child: _MedalCounter(
                    tier: tier,
                    count: medalCounts[tier]!,
                    label: _tierLabel(loc, tier),
                  ),
                ),
                if (tier != RunMedalTier.bronze) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MedalCounter extends StatelessWidget {
  final RunMedalTier tier;
  final int count;
  final String label;

  const _MedalCounter({
    required this.tier,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RunMedalDot(tier: tier, size: 21),
          const SizedBox(width: 7),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    height: 1,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
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

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AchievementCategoryCard extends StatelessWidget {
  final RunAchievementCategory category;
  final ValueChanged<String> onOpenActivity;

  const _AchievementCategoryCard({
    required this.category,
    required this.onOpenActivity,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final placements = category.placements;

    return Card(
      key: Key('run-achievement-${category.kind.name}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _iconFor(category.kind),
                    size: 21,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    runAchievementKindLabel(loc, category.kind),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (placements.isNotEmpty)
                  Text(
                    RunAchievementEngine.formatValue(
                      category.kind,
                      placements.first.value,
                    ),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w900,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            if (placements.isEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_open_rounded,
                      size: 18,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _unlockHint(loc, category.kind),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              const SizedBox(height: 12),
              Divider(
                height: 1,
                color: colors.outlineVariant.withValues(alpha: 0.45),
              ),
              for (var index = 0; index < placements.length; index++) ...[
                if (index > 0)
                  Divider(
                    height: 1,
                    indent: 36,
                    color: colors.outlineVariant.withValues(alpha: 0.35),
                  ),
                _PlacementRow(
                  placement: placements[index],
                  onTap: () => onOpenActivity(placements[index].activity.id),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PlacementRow extends StatelessWidget {
  final RunAchievementPlacement placement;
  final VoidCallback onTap;

  const _PlacementRow({required this.placement, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final activityTitle = placement.activity.title?.trim();
    final title = activityTitle == null || activityTitle.isEmpty
        ? loc.runDetailUntitled
        : activityTitle;
    final date = DateFormat.yMMMd(
      locale,
    ).format(placement.activity.startedAt.toLocal());

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            RunMedalDot(tier: placement.tier, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              RunAchievementEngine.formatValue(placement.kind, placement.value),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

String _tierLabel(AppLocalizations loc, RunMedalTier tier) => switch (tier) {
  RunMedalTier.gold => loc.runAchievementsGold,
  RunMedalTier.silver => loc.runAchievementsSilver,
  RunMedalTier.bronze => loc.runAchievementsBronze,
};

IconData _iconFor(RunAchievementKind kind) => switch (kind) {
  RunAchievementKind.longestDistance => Icons.route_rounded,
  RunAchievementKind.longestDuration => Icons.timer_outlined,
  RunAchievementKind.bestAvgPace => Icons.speed_rounded,
  RunAchievementKind.bestKmSplit => Icons.bolt_rounded,
  RunAchievementKind.bestEffort1k => Icons.looks_one_rounded,
  RunAchievementKind.bestEffort3k => Icons.filter_3_rounded,
  RunAchievementKind.bestEffort5k => Icons.filter_5_rounded,
  RunAchievementKind.bestEffort10k => Icons.directions_run_rounded,
  RunAchievementKind.bestEffortHalf => Icons.landscape_outlined,
  RunAchievementKind.bestEffortMarathon => Icons.emoji_events_outlined,
};

String _unlockHint(AppLocalizations loc, RunAchievementKind kind) {
  return switch (kind) {
    RunAchievementKind.longestDistance => loc.runAchievementsUnlockDistance,
    RunAchievementKind.longestDuration => loc.runAchievementsUnlockDuration,
    RunAchievementKind.bestAvgPace => loc.runAchievementsUnlockPace,
    RunAchievementKind.bestKmSplit => loc.runAchievementsUnlockGpsKilometer,
    RunAchievementKind.bestEffort1k => loc.runAchievementsUnlockEffort('1 km'),
    RunAchievementKind.bestEffort3k => loc.runAchievementsUnlockEffort('3 km'),
    RunAchievementKind.bestEffort5k => loc.runAchievementsUnlockEffort('5 km'),
    RunAchievementKind.bestEffort10k => loc.runAchievementsUnlockEffort(
      '10 km',
    ),
    RunAchievementKind.bestEffortHalf => loc.runAchievementsUnlockEffort(
      '21,1 km',
    ),
    RunAchievementKind.bestEffortMarathon => loc.runAchievementsUnlockEffort(
      '42,2 km',
    ),
  };
}
