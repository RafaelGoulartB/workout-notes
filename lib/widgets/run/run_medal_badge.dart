import 'package:flutter/material.dart';
import 'package:workout_notes/models/run_achievement.dart';

abstract final class RunMedalColors {
  static const gold = Color(0xFFD4AF37);
  static const silver = Color(0xFF9E9E9E);
  static const bronze = Color(0xFFCD7F32);

  static Color forTier(RunMedalTier tier) => switch (tier) {
        RunMedalTier.gold => gold,
        RunMedalTier.silver => silver,
        RunMedalTier.bronze => bronze,
      };
}

/// Compact circular medal (gold / silver / bronze).
class RunMedalDot extends StatelessWidget {
  final RunMedalTier tier;
  final double size;

  const RunMedalDot({
    super.key,
    required this.tier,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final color = RunMedalColors.forTier(tier);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.35)!,
            color,
            Color.lerp(color, Colors.black, 0.18)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        '${tier.place}',
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.55,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

/// Medal + short category label chip for list / detail.
class RunMedalBadge extends StatelessWidget {
  final RunMedalTier tier;
  final String label;
  final bool compact;

  const RunMedalBadge({
    super.key,
    required this.tier,
    required this.label,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = RunMedalColors.forTier(tier);
    return Container(
      padding: EdgeInsets.fromLTRB(
        compact ? 5 : 6,
        compact ? 3 : 4,
        compact ? 7 : 8,
        compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RunMedalDot(tier: tier, size: compact ? 14 : 16),
          SizedBox(width: compact ? 4 : 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 10 : 11,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wrap of medals for a run card; collapses extras into +N.
class RunMedalBadgeRow extends StatelessWidget {
  final List<RunAchievementPlacement> placements;
  final String Function(RunAchievementKind kind) labelFor;
  final int maxVisible;

  const RunMedalBadgeRow({
    super.key,
    required this.placements,
    required this.labelFor,
    this.maxVisible = 3,
  });

  @override
  Widget build(BuildContext context) {
    if (placements.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final visible = placements.take(maxVisible).toList();
    final overflow = placements.length - visible.length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final p in visible)
          RunMedalBadge(
            tier: p.tier,
            label: labelFor(p.kind),
            compact: true,
          ),
        if (overflow > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '+$overflow',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}
