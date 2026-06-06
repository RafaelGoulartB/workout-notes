import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';

// ═══════════════════════════════════════════════════════════════════════
// BADGE WIDGETS (small inline labels)
// ═══════════════════════════════════════════════════════════════════════

/// Badge showing the time of day (e.g., morning, afternoon).
class TimeOfDayBadge extends StatelessWidget {
  final String tod;
  const TimeOfDayBadge({super.key, required this.tod});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = timeOfDayData(tod, context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.blueGrey),
          const SizedBox(width: 2),
          Text(label,
              style: TextStyle(fontSize: 9, color: Colors.blueGrey.shade700)),
        ],
      ),
    );
  }
}

/// Badge indicating the measurement was taken while fasting.
class FastedBadge extends StatelessWidget {
  const FastedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.nightlight_round,
              size: 10, color: Colors.deepPurple.shade400),
          const SizedBox(width: 2),
          Text(
            loc.bodyTrackerFasted,
            style: TextStyle(fontSize: 9, color: Colors.deepPurple.shade500),
          ),
        ],
      ),
    );
  }
}

/// Badge indicating left/right side for bilateral measurements.
class SideBadge extends StatelessWidget {
  final String side;
  const SideBadge({super.key, required this.side});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isLeft = side == 'left';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isLeft ? Colors.blue : Colors.red).withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLeft ? Icons.arrow_back : Icons.arrow_forward,
            size: 10,
            color: isLeft ? Colors.blue : Colors.red,
          ),
          const SizedBox(width: 2),
          Text(
            isLeft ? loc.bodyTrackerLeftAbbr : loc.bodyTrackerRightAbbr,
            style: TextStyle(
              fontSize: 9,
              color: (isLeft ? Colors.blue : Colors.red).shade700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// CHIP WIDGETS (for detail sheets)
// ═══════════════════════════════════════════════════════════════════════

/// Chip showing the time of day in a detail sheet.
class TimeOfDayChip extends StatelessWidget {
  final String tod;
  final ThemeData theme;
  const TimeOfDayChip({super.key, required this.tod, required this.theme});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = timeOfDayData(tod, context);
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: Colors.blueGrey.withAlpha(20),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

/// Chip indicating fasting status in a detail sheet.
class FastedChip extends StatelessWidget {
  final ThemeData theme;
  const FastedChip({super.key, required this.theme});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Chip(
      avatar: Icon(Icons.nightlight_round, size: 16, color: Colors.deepPurple),
      label: Text(loc.bodyTrackerFasting),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: Colors.deepPurple.withAlpha(20),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

/// Chip indicating left/right side in a detail sheet.
class SideChip extends StatelessWidget {
  final String side;
  final ThemeData theme;
  const SideChip({super.key, required this.side, required this.theme});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isLeft = side == 'left';
    final color = isLeft ? Colors.blue : Colors.red;
    return Chip(
      avatar: Icon(
        isLeft ? Icons.arrow_back : Icons.arrow_forward,
        size: 16,
        color: color,
      ),
      label: Text(isLeft ? loc.bodyTrackerLeft : loc.bodyTrackerRight),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: color.withAlpha(20),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SPEED DIAL
// ═══════════════════════════════════════════════════════════════════════

/// A single option in the floating action button speed dial.
class SpeedDialOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const SpeedDialOption({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: color,
          borderRadius: BorderRadius.circular(16),
          elevation: 4,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ],
    );
  }
}
