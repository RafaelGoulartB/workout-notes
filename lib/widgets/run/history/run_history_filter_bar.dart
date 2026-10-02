import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_activity_filter.dart';

String runHistoryTypeLabel(AppLocalizations loc, RunHistoryType type) =>
    switch (type) {
      RunHistoryType.all => loc.runHistoryFilterAll,
      RunHistoryType.run => loc.runHistoryFilterRun,
      RunHistoryType.treadmill => loc.runHistoryFilterTreadmill,
      RunHistoryType.bike => loc.runHistoryFilterBike,
    };

String runHistoryPeriodLabel(AppLocalizations loc, RunHistoryPeriod period) =>
    switch (period) {
      RunHistoryPeriod.all => loc.runHistoryPeriodAll,
      RunHistoryPeriod.last30Days => loc.runHistoryPeriod30,
      RunHistoryPeriod.last90Days => loc.runHistoryPeriod90,
      RunHistoryPeriod.thisYear => loc.runHistoryPeriodYear,
    };

String runHistoryDistanceLabel(
  AppLocalizations loc,
  RunHistoryDistance distance,
) => switch (distance) {
  RunHistoryDistance.any => loc.runHistoryDistanceAny,
  RunHistoryDistance.under5 => loc.runHistoryDistanceUnder5,
  RunHistoryDistance.from5to10 => loc.runHistoryDistance5to10,
  RunHistoryDistance.over10 => loc.runHistoryDistanceOver10,
};

/// Search field plus a horizontally scrolling row of filter chips.
class RunHistoryFilterBar extends StatelessWidget {
  final RunHistoryFilter filter;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<RunHistoryFilter> onChanged;

  const RunHistoryFilterBar({
    super.key,
    required this.filter,
    required this.searchController,
    required this.onQueryChanged,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            controller: searchController,
            onChanged: onQueryChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: loc.runHistorySearchHint,
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
              for (final type in RunHistoryType.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('runHistoryType_${type.name}'),
                    label: Text(runHistoryTypeLabel(loc, type)),
                    selected: filter.type == type,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onChanged(filter.copyWith(type: type)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  key: const ValueKey('runHistoryPlanOnly'),
                  label: Text(loc.runHistoryFilterPlanOnly),
                  selected: filter.onlyPlan,
                  showCheckmark: false,
                  avatar: const Icon(Icons.event_note_rounded, size: 16),
                  visualDensity: VisualDensity.compact,
                  onSelected: (value) =>
                      onChanged(filter.copyWith(onlyPlan: value)),
                ),
              ),
              _MenuChip<RunHistoryPeriod>(
                key: const ValueKey('runHistoryPeriod'),
                icon: Icons.calendar_month_outlined,
                label: filter.period == RunHistoryPeriod.all
                    ? loc.runHistoryFilterPeriod
                    : runHistoryPeriodLabel(loc, filter.period),
                active: filter.period != RunHistoryPeriod.all,
                values: RunHistoryPeriod.values,
                selected: filter.period,
                labelOf: (v) => runHistoryPeriodLabel(loc, v),
                onSelected: (v) => onChanged(filter.copyWith(period: v)),
              ),
              const SizedBox(width: 8),
              _MenuChip<RunHistoryDistance>(
                key: const ValueKey('runHistoryDistance'),
                icon: Icons.straighten_rounded,
                label: filter.distance == RunHistoryDistance.any
                    ? loc.runHistoryFilterDistance
                    : runHistoryDistanceLabel(loc, filter.distance),
                active: filter.distance != RunHistoryDistance.any,
                values: RunHistoryDistance.values,
                selected: filter.distance,
                labelOf: (v) => runHistoryDistanceLabel(loc, v),
                onSelected: (v) => onChanged(filter.copyWith(distance: v)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Chip that opens a single-choice popup menu.
class _MenuChip<T> extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  const _MenuChip({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = active ? colors.onSecondaryContainer : null;
    return PopupMenuButton<T>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final value in values)
          CheckedPopupMenuItem<T>(
            value: value,
            checked: value == selected,
            child: Text(labelOf(value)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? colors.secondaryContainer : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? Colors.transparent : colors.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: foreground),
            const SizedBox(width: 6),
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(color: foreground),
            ),
            Icon(Icons.arrow_drop_down_rounded, size: 18, color: foreground),
          ],
        ),
      ),
    );
  }
}
