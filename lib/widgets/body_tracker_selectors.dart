import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

/// Dropdown selector for time of day (used in add-measurement sheet).
class TimeOfDaySelector extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const TimeOfDaySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: loc.bodyTrackerTimeOfDay,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        isDense: true,
      ),
      items: [
        DropdownMenuItem(value: null, child: Text(loc.bodyTrackerNotInformed)),
        DropdownMenuItem(
          value: 'morning',
          child: Text('\u{1F305} ${loc.bodyTrackerMorning}'),
        ),
        DropdownMenuItem(
          value: 'afternoon',
          child: Text('\u{2600}\u{FE0F} ${loc.bodyTrackerAfternoon}'),
        ),
        DropdownMenuItem(
          value: 'evening',
          child: Text('\u{1F306} ${loc.bodyTrackerEvening}'),
        ),
        DropdownMenuItem(
          value: 'night',
          child: Text('\u{1F319} ${loc.bodyTrackerNight}'),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

/// Row of selectable time-of-day options (used in quick-measure sheet).
class QuickTimeOfDaySelector extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const QuickTimeOfDaySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final options = [
      (null, loc.commonAll, Icons.all_inclusive),
      ('morning', loc.bodyTrackerMorning, Icons.wb_sunny),
      ('afternoon', loc.bodyTrackerAfternoon, Icons.wb_cloudy),
      ('evening', loc.bodyTrackerEvening, Icons.nights_stay),
    ];

    return Row(
      children: options.map((opt) {
        final isSelected = value == opt.$1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onChanged(opt.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant.withAlpha(60),
                  ),
                  color: isSelected
                      ? theme.colorScheme.primary.withAlpha(18)
                      : null,
                ),
                child: Column(
                  children: [
                    Icon(
                      opt.$3,
                      size: 16,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      opt.$2,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Selector for left/right side on bilateral measurements.
class SideSelector extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const SideSelector({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onChanged('left'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: value == 'left'
                      ? Colors.blue.withAlpha(120)
                      : theme.colorScheme.outlineVariant.withAlpha(60),
                ),
                color: value == 'left' ? Colors.blue.withAlpha(15) : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.arrow_back, size: 16, color: Colors.blue),
                  const SizedBox(width: 6),
                  Text(
                    loc.bodyTrackerLeft,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onChanged('right'),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: value == 'right'
                      ? Colors.red.withAlpha(120)
                      : theme.colorScheme.outlineVariant.withAlpha(60),
                ),
                color: value == 'right' ? Colors.red.withAlpha(15) : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.arrow_forward, size: 16, color: Colors.red),
                  const SizedBox(width: 6),
                  Text(
                    loc.bodyTrackerRight,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
