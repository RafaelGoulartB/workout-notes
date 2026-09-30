import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/body/body_stats_controller.dart';
import 'package:workout_notes/utils/body_progress_analytics.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';

/// Small coloured pill for deltas, paces and goal status. A null [positive]
/// renders the neutral variant.
class TrendPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool? positive;

  const TrendPill({
    super.key,
    required this.label,
    required this.icon,
    required this.positive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = switch (positive) {
      true => colors.primary,
      false => colors.error,
      null => colors.onSurfaceVariant,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed-width signed delta used by the monthly rows.
class DeltaBadge extends StatelessWidget {
  final String label;
  final bool? positive;

  const DeltaBadge({super.key, required this.label, required this.positive});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = switch (positive) {
      true => colors.primary,
      false => colors.error,
      null => colors.onSurfaceVariant,
    };

    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Start / now / target column under the goal progress bar.
class GoalAnchor extends StatelessWidget {
  final String label;
  final String value;
  final CrossAxisAlignment alignment;
  final bool emphasized;

  const GoalAnchor({
    super.key,
    required this.label,
    required this.value,
    required this.alignment,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Segmented pill row that swaps the chart shown in the trends card.
class ChartTabBar extends StatelessWidget {
  final BodyChartTab selected;
  final Map<BodyChartTab, String> labels;
  final ValueChanged<BodyChartTab> onChanged;

  const ChartTabBar({
    super.key,
    required this.selected,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final tab in BodyChartTab.values)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onChanged(tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: tab == selected
                        ? colors.primary.withAlpha(45)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      labels[tab] ?? '',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: tab == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: tab == selected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String bodyStatsShortDate(BuildContext context, DateTime d) =>
    DateFormat.MMMd(Localizations.localeOf(context).toString()).format(d);

String bodyStatsMonthLabel(BuildContext context, DateTime d) =>
    DateFormat.yMMM(Localizations.localeOf(context).toString()).format(d);

/// Uppercase tracked heading above each stats card.
class BodyStatsSectionHeader extends StatelessWidget {
  const BodyStatsSectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 0, 10),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Chips to switch between the measurement types that have data.
class BodyStatsTypeSelector extends StatelessWidget {
  const BodyStatsTypeSelector({super.key, required this.controller});

  final BodyStatsController controller;

  @override
  Widget build(BuildContext context) {
    // Types without data would render an empty screen, so they are dropped —
    // except the current selection, which must stay visible.
    final visible = controller.visibleTypes;
    if (visible.length < 2) return const SizedBox.shrink();
    final selectedType = controller.selectedType;

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final type = visible[i];
          final selected = type.id == selectedType;
          return ChoiceChip(
            avatar: Icon(
              type.icon,
              size: 16,
              color: selected ? type.color : Theme.of(context).hintColor,
            ),
            label: Text(typeName(type.id, context)),
            labelStyle: Theme.of(context).textTheme.labelMedium,
            showCheckmark: false,
            selected: selected,
            onSelected: (_) => selected ? null : controller.switchType(type.id),
          );
        },
      ),
    );
  }
}

/// Four period chips sharing one row.
class BodyStatsPeriodSelector extends StatelessWidget {
  const BodyStatsPeriodSelector({super.key, required this.controller});

  final BodyStatsController controller;

  static String _periodLabel(AppLocalizations loc, BodyStatsPeriod period) {
    return switch (period) {
      BodyStatsPeriod.weeks4 => loc.bodyStatsPeriod4Weeks,
      BodyStatsPeriod.weeks12 => loc.bodyStatsPeriod12Weeks,
      BodyStatsPeriod.weeks26 => loc.bodyStatsPeriod6Months,
      BodyStatsPeriod.all => loc.bodyStatsPeriodAll,
    };
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Row(
      children: [
        for (final period in BodyStatsPeriod.values) ...[
          if (period != BodyStatsPeriod.values.first) const SizedBox(width: 8),
          Expanded(
            child: ChoiceChip(
              // Four periods share the row, so labels scale down instead of
              // being clipped on narrow screens.
              label: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_periodLabel(loc, period), maxLines: 1),
                ),
              ),
              labelStyle: Theme.of(context).textTheme.labelMedium,
              labelPadding: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
              showCheckmark: false,
              selected: controller.period == period,
              onSelected: (_) => controller.setPeriod(period),
            ),
          ),
        ],
      ],
    );
  }
}
