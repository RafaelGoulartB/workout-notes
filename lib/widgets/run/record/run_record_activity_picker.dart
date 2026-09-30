import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';

IconData runActivityIcon(CardioActivityType type) => switch (type) {
  CardioActivityType.running => Icons.directions_run_rounded,
  CardioActivityType.treadmill => Icons.speed_rounded,
  CardioActivityType.stationaryBike => Icons.pedal_bike_rounded,
};

String runActivityName(AppLocalizations loc, CardioActivityType type) =>
    switch (type) {
      CardioActivityType.running => loc.cardioActivityRunning,
      CardioActivityType.treadmill => loc.runTreadmillPickerTitle,
      CardioActivityType.stationaryBike => loc.cardioActivityStationaryBike,
    };

String runActivitySubtitle(AppLocalizations loc, CardioActivityType type) =>
    switch (type) {
      CardioActivityType.running => loc.cardioActivityRunningSubtitle,
      CardioActivityType.treadmill => loc.runTreadmillPickerSubtitle,
      CardioActivityType.stationaryBike =>
        loc.cardioActivityStationaryBikeSubtitle,
    };

/// Compact selector for the exercise type (run, treadmill, stationary bike).
/// Tapping opens a bottom sheet; [onChanged] null locks it.
class RunActivityTypeSelector extends StatelessWidget {
  final CardioActivityType value;
  final ValueChanged<CardioActivityType>? onChanged;

  /// Types offered in the picker (all of them by default). A run with an
  /// attached workout can be outdoors or on the treadmill, never on the bike.
  final List<CardioActivityType> allowed;

  const RunActivityTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.allowed = CardioActivityType.values,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('cardio-activity-selector'),
        onTap: onChanged == null ? null : () => _openPicker(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(
                runActivityIcon(value),
                size: 21,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.cardioActivityPickerLabel.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      runActivityName(loc, value),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (onChanged != null)
                Icon(
                  Icons.unfold_more_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final loc = AppLocalizations.of(context)!;
    final selected = await showModalBottomSheet<CardioActivityType>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.cardioActivityPickerTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              for (final type in allowed) ...[
                _ActivityChoiceTile(
                  icon: runActivityIcon(type),
                  title: runActivityName(loc, type),
                  subtitle: runActivitySubtitle(loc, type),
                  selected: value == type,
                  onTap: () => Navigator.pop(context, type),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
    if (selected != null && selected != value) onChanged?.call(selected);
  }
}

class _ActivityChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ActivityChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: selected ? const Icon(Icons.check_circle_rounded) : null,
      ),
    );
  }
}
